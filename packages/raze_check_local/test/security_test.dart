import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/check_matchers.dart';
import 'support/fake_clock.dart';
import 'support/memory_key_store.dart';
import 'support/temp_paths.dart';

class ForgedSession implements SessionHandle {}

class CollisionIds implements IdGenerator {
  CollisionIds(this.person);
  final String person;
  int calls = 0;
  @override
  String next() => calls++ == 0 ? person : SecureIds().next();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppPaths paths;
  late MemoryKeyStore store;
  late FakeClock clock;
  late LocalIdentityService identity;
  LocalIdentityService service() => LocalIdentityService(
    keys: store,
    catalog: ProfileCatalog(paths: paths, keys: store),
    clock: clock,
    ids: SecureIds(),
  );
  setUp(() async {
    paths = await tempPaths();
    store = MemoryKeyStore();
    clock = FakeClock();
    identity = service();
  });
  tearDown(() async => paths.root.delete(recursive: true));
  const pass = 'twelve safe words 🌱';
  test(
    'profile survives new service and wrong passphrase grants no session',
    () async {
      final session = await identity.createProfile('Alice Private', pass);
      final actor = identity.requireActor(session);
      identity.lock();
      identity = service();
      final profiles = await identity.profiles();
      expect(profiles.single.personId, actor.personId);
      await expectLater(
        identity.unlock(actor.personId, 'incorrect password'),
        throwsCheckError(CheckError.wrongSecret),
      );
      final unlocked = await identity.unlock(actor.personId, pass);
      expect(identity.requireActor(unlocked).personId, actor.personId);
      expect(
        utf8.decode(await paths.catalog.readAsBytes(), allowMalformed: true),
        isNot(contains('Alice Private')),
      );
    },
  );
  test(
    'only live exact handles authorize and idle timeout cannot be revived',
    () async {
      final session = await identity.createProfile('Alice', pass);
      expect(
        () => identity.requireActor(ForgedSession()),
        throwsCheckError(CheckError.locked),
      );
      expect(
        () => service().requireActor(session),
        throwsCheckError(CheckError.locked),
      );
      clock.advance(const Duration(minutes: 4));
      identity.recordActivity(session);
      clock.advance(const Duration(minutes: 4));
      identity.recordActivity(session);
      clock.advance(const Duration(minutes: 5));
      expect(
        () => identity.requireActor(session),
        throwsCheckError(CheckError.locked),
      );
      clock.now = DateTime.utc(2026, 10, 19);
      expect(
        () => identity.requireActor(session),
        throwsCheckError(CheckError.locked),
      );
    },
  );
  test(
    'authorization checks do not extend idle time; successful activity does',
    () async {
      final session = await identity.createProfile('Alice', pass);
      clock.advance(const Duration(minutes: 4));
      identity.requireActor(session);
      expect(identity.remainingIdleTime(session), const Duration(minutes: 1));
      identity.recordActivity(session);
      expect(identity.remainingIdleTime(session), const Duration(minutes: 5));
      clock.advance(const Duration(minutes: 5));
      expect(
        () => identity.recordActivity(session),
        throwsCheckError(CheckError.locked),
      );
    },
  );
  test('lock invalidates old handles even after unlock', () async {
    final session = await identity.createProfile('Alice', pass);
    final id = identity.requireActor(session).personId;
    identity.lock();
    final next = await identity.unlock(id, pass);
    expect(
      () => identity.requireActor(session),
      throwsCheckError(CheckError.locked),
    );
    expect(identity.requireActor(next).personId, id);
  });
  test(
    'invalid setup persists nothing and failed storage creates no active profile',
    () async {
      await expectLater(
        identity.createProfile(' ', pass),
        throwsCheckError(CheckError.malformed),
      );
      await expectLater(
        identity.createProfile('Alice', 'short'),
        throwsCheckError(CheckError.wrongSecret),
      );
      expect(await identity.profiles(), isEmpty);
      store.failWrites = true;
      await expectLater(
        identity.createProfile('Alice', pass),
        throwsCheckError(CheckError.storageFailure),
      );
      store.failWrites = false;
      expect(await service().profiles(), isEmpty);
    },
  );
  test(
    'missing catalog key over encrypted data requires recovery without replacement',
    () async {
      await identity.createProfile('Alice', pass);
      final before = await paths.catalog.readAsBytes();
      store.values.clear();
      await expectLater(
        service().profiles(),
        throwsCheckError(CheckError.recoveryRequired),
      );
      expect(store.values, isEmpty);
      expect(await paths.catalog.readAsBytes(), before);
    },
  );
  test('missing person key never silently replaces it', () async {
    final session = await identity.createProfile('Alice', pass);
    final actor = identity.requireActor(session);
    identity.lock();
    store.values.remove('vault:${actor.personId}');
    await expectLater(
      identity.unlock(actor.personId, pass),
      throwsCheckError(CheckError.recoveryRequired),
    );
    expect(store.values.containsKey('vault:${actor.personId}'), isFalse);
  });
  test(
    'AES-GCM authenticates scope record revision ciphertext and nonce',
    () async {
      final vault = VaultKeys(store);
      await vault.create('A');
      await vault.create('B');
      expect(store.values['vault:A'], isNot(store.values['vault:B']));
      // Aliasing keys isolates scope authentication from key routing: omitting
      // scope from AAD must fail this test even with otherwise valid ciphertext.
      store.values['vault:B'] = Uint8List.fromList(store.values['vault:A']!);
      final cipher = AesPayloadCipher(vault);
      final data = Uint8List.fromList(utf8.encode('private attendance'));
      final sealed = await cipher.seal(
        scopeId: 'A',
        recordId: 'r1',
        revision: 1,
        plain: data,
      );
      expect(
        await cipher.open(
          scopeId: 'A',
          recordId: 'r1',
          revision: 1,
          sealed: sealed,
        ),
        data,
      );
      for (final context in [('B', 'r1', 1), ('A', 'r2', 1), ('A', 'r1', 2)]) {
        await expectLater(
          cipher.open(
            scopeId: context.$1,
            recordId: context.$2,
            revision: context.$3,
            sealed: sealed,
          ),
          throwsCheckError(CheckError.invalidSignature),
        );
      }
      for (final index in [1, 13, sealed.length - 1]) {
        final modified = Uint8List.fromList(sealed);
        modified[index] ^= 1;
        await expectLater(
          cipher.open(
            scopeId: 'A',
            recordId: 'r1',
            revision: 1,
            sealed: modified,
          ),
          throwsCheckError(CheckError.invalidSignature),
        );
      }
      final nonces = <String>{};
      for (var i = 0; i < 100; i++) {
        final bytes = await cipher.seal(
          scopeId: 'A',
          recordId: 'r1',
          revision: 1,
          plain: data,
        );
        nonces.add(base64.encode(bytes.sublist(1, 13)));
      }
      expect(nonces, hasLength(100));
      store.values.remove('vault:A');
      await expectLater(
        cipher.open(scopeId: 'A', recordId: 'r1', revision: 1, sealed: sealed),
        throwsCheckError(CheckError.recoveryRequired),
      );
      expect(store.values.containsKey('vault:A'), isFalse);
    },
  );
  test('signatures survive relaunch and reject modified bytes', () async {
    final session = await identity.createProfile('Alice', pass);
    final actor = identity.requireActor(session);
    final keyService = LocalKeyService(store);
    final bytes = Uint8List.fromList([1, 2, 3]);
    final signature = await keyService.sign(bytes, actor.signingKeyId);
    expect(
      await LocalKeyService(store).verify(bytes, signature, actor.publicKey),
      isTrue,
    );
    expect(
      await keyService.verify(
        Uint8List.fromList([1, 2, 4]),
        signature,
        actor.publicKey,
      ),
      isFalse,
    );
    store.values.remove(actor.signingKeyId);
    expect(await keyService.verify(bytes, signature, actor.publicKey), isTrue);
    await expectLater(
      keyService.sign(bytes, actor.signingKeyId),
      throwsCheckError(CheckError.recoveryRequired),
    );
  });
  test('catalog corruption is typed and never overwritten', () async {
    await identity.createProfile('Alice', pass);
    final bytes = await paths.catalog.readAsBytes();
    bytes[20] ^= 1;
    await paths.catalog.writeAsBytes(bytes, flush: true);
    await expectLater(
      service().profiles(),
      throwsCheckError(CheckError.invalidSignature),
    );
    expect(await paths.catalog.readAsBytes(), bytes);
    expect(await Directory(paths.root.path).list().length, 1);
  });
  test(
    'failed provisioning with colliding ID cannot erase existing credentials',
    () async {
      final session = await identity.createProfile('Alice', pass);
      final person = identity.requireActor(session).personId;
      identity.lock();
      final collision = LocalIdentityService(
        keys: store,
        catalog: ProfileCatalog(paths: paths, keys: store),
        clock: clock,
        ids: CollisionIds(person),
      );
      await expectLater(
        collision.createProfile('Bob', pass),
        throwsCheckError(CheckError.invalidTransition),
      );
      final restored = await identity.unlock(person, pass);
      expect(identity.requireActor(restored).personId, person);
    },
  );
  test(
    'locking during setup cancels authorization before any profile commit',
    () async {
      final pending = identity.createProfile('Alice', pass);
      identity.lock();
      await expectLater(pending, throwsCheckError(CheckError.locked));
      expect(await identity.profiles(), isEmpty);
      expect(store.values, isEmpty);
    },
  );
  test('locking during unlock cannot issue a late active handle', () async {
    final session = await identity.createProfile('Alice', pass);
    final person = identity.requireActor(session).personId;
    identity.lock();
    final pending = identity.unlock(person, pass);
    identity.lock();
    await expectLater(pending, throwsCheckError(CheckError.locked));
    expect(
      () => identity.requireActor(session),
      throwsCheckError(CheckError.locked),
    );
  });

  test(
    'Android secure storage never resets all keys on read failure',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      Map<dynamic, dynamic>? options;
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            options = (call.arguments as Map)['options'] as Map;
            throw PlatformException(code: 'keyUnavailable');
          });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await expectLater(
        OsSecureKeyStore().read('vault:A'),
        throwsCheckError(CheckError.storageFailure),
      );
      expect(options!['resetOnError'], 'false');
      expect(methods, ['read']);
    },
  );
  test(
    'two service instances cannot race provisioning over one catalog',
    () async {
      final pending = identity.createProfile('Alice', pass);
      await expectLater(
        service().createProfile('Bob', pass),
        throwsCheckError(CheckError.invalidTransition),
      );
      final session = await pending;
      expect(
        (await identity.profiles()).single.personId,
        identity.requireActor(session).personId,
      );
    },
  );
}
