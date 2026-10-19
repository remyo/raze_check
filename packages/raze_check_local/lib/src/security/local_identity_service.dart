import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'local_key_service.dart';
import 'profile_catalog.dart';
import 'secure_key_store.dart';

// KDF runs in a worker isolate: never lower the work factor to keep UI responsive.
Future<Uint8List> _verifier(String passphrase, Uint8List salt) =>
    Isolate.run(() async {
      final kdf = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 600000,
        bits: 256,
      ).toSync();
      return Uint8List.fromList(
        await (await kdf.deriveKey(
          secretKey: SecretKey(utf8.encode(passphrase)),
          nonce: salt,
        )).extractBytes(),
      );
    });

final class _LocalSession implements SessionHandle {
  _LocalSession(this.actor, this.lastActivity);
  final ActorIdentity actor;
  DateTime lastActivity;
}

/// Serializes identity mutations and issues non-serializable live capabilities.
final class LocalIdentityService implements IdentityService {
  LocalIdentityService({
    required this.keys,
    required this.catalog,
    required this.clock,
    required this.ids,
  });
  final SecureKeyStore keys;
  final ProfileCatalog catalog;
  final CheckClock clock;
  final IdGenerator ids;
  final _live = Map<SessionHandle, _LocalSession>.identity();
  int _epoch = 0;
  static final _mutatingCatalogs = <String>{};
  @override
  Future<List<LocalProfile>> profiles() => catalog.read();
  @override
  void lock() {
    _live.clear();
    _epoch++;
  }

  @override
  ActorIdentity requireActor(SessionHandle session) {
    final active = _live[session];
    final now = clock.nowUtc();
    if (active == null) throw const CheckException(CheckError.locked);
    final idle = now.difference(active.lastActivity);
    if (idle.isNegative || idle >= const Duration(minutes: 5)) {
      lock();
      throw const CheckException(CheckError.locked);
    }
    active.lastActivity = now;
    return active.actor;
  }

  SessionHandle _issue(LocalProfile p, int epoch) {
    if (_epoch != epoch) throw const CheckException(CheckError.locked);
    _live.clear();
    final s = _LocalSession(
      ActorIdentity(
        personId: p.personId,
        installationId: p.installationId,
        signingKeyId: p.signingKeyId,
        publicKey: Uint8List.fromList(p.publicKey),
      ),
      clock.nowUtc(),
    );
    _live[s] = s;
    return s;
  }

  Future<T> _exclusive<T>(Future<T> Function(int epoch) action) async {
    final catalogPath = catalog.paths.root.absolute.uri
        .normalizePath()
        .toFilePath();
    if (!_mutatingCatalogs.add(catalogPath)) {
      throw const CheckException(CheckError.invalidTransition);
    }
    final epoch = _epoch;
    try {
      return await action(epoch);
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    } finally {
      _mutatingCatalogs.remove(catalogPath);
    }
  }

  @override
  Future<SessionHandle> createProfile(
    String name,
    String passphrase,
  ) => _exclusive((epoch) async {
    if (name.trim().isEmpty || name.runes.length > 100) {
      throw const CheckException(CheckError.malformed);
    }
    if (passphrase.runes.length < 12) {
      throw const CheckException(CheckError.wrongSecret);
    }
    final profiles = await catalog.read();
    final person = ids.next();
    final installation = ids.next();
    final signing = 'signing:${ids.next()}';
    final allocated = <String>[];
    // Refuse collisions before provisioning, and never clean up foreign keys.
    for (final id in ['vault:$person', signing, 'credential:$person']) {
      if (await keys.read(id) != null) {
        throw const CheckException(CheckError.invalidTransition);
      }
    }
    var committed = false;
    try {
      final salt = secureRandomBytes(16);
      final derived = await _verifier(passphrase, salt);
      if (_epoch != epoch) throw const CheckException(CheckError.locked);
      allocated.add('vault:$person');
      await VaultKeys(keys).create(person);
      allocated.add(signing);
      final public = await LocalKeyService(keys).create(signing);
      allocated.add('credential:$person');
      await keys.write(
        'credential:$person',
        Uint8List.fromList([1, ...salt, ...derived]),
      );
      final profile = LocalProfile(
        personId: person,
        displayName: name.trim(),
        installationId: installation,
        signingKeyId: signing,
        publicKey: public,
      );
      if (_epoch != epoch) throw const CheckException(CheckError.locked);
      SessionHandle? publishedSession;
      await catalog.write(
        [...profiles, profile],
        beforePublish: () {
          if (_epoch != epoch) throw const CheckException(CheckError.locked);
        },
        onPublished: () {
          committed = true;
          publishedSession = _issue(profile, epoch);
        },
      );
      // Publication already succeeded. A later lock invalidates this issued
      // handle, but must not turn the durable create into a rejected operation.
      return publishedSession!;
    } finally {
      if (!committed) {
        for (final id in allocated) {
          await keys.delete(id);
        }
      }
    }
  });
  @override
  Future<SessionHandle> unlock(
    String personId,
    String passphrase,
  ) => _exclusive((epoch) async {
    final profiles = await catalog.read();
    final matches = profiles.where((p) => p.personId == personId);
    if (matches.length != 1) {
      throw const CheckException(CheckError.unauthorized);
    }
    final credential = await keys.read('credential:$personId');
    if (credential == null || credential.length != 49) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    if (credential[0] != 1) {
      throw const CheckException(CheckError.unsupportedVersion);
    }
    final derived = await _verifier(
      passphrase,
      Uint8List.fromList(credential.sublist(1, 17)),
    );
    var difference = 0;
    for (var i = 0; i < 32; i++) {
      difference |= derived[i] ^ credential[i + 17];
    }
    if (difference != 0) throw const CheckException(CheckError.wrongSecret);
    await VaultKeys(keys).require(personId);
    // Prove signing credentials are present and correspond to catalog history.
    final probe = Uint8List.fromList(utf8.encode('RAZE_CHECK_UNLOCK_V1'));
    final keyService = LocalKeyService(keys);
    final signature = await keyService.sign(probe, matches.single.signingKeyId);
    if (!await keyService.verify(probe, signature, matches.single.publicKey)) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    return _issue(matches.single, epoch);
  });
}
