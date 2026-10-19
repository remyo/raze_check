import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/check_matchers.dart';
import 'support/fake_clock.dart';
import 'support/memory_key_store.dart';
import 'support/temp_paths.dart';

class SealGatedKeys extends MemoryKeyStore {
  final reached = Completer<void>();
  final release = Completer<void>();
  bool _gated = false;
  @override
  Future<Uint8List?> read(String id) async {
    if (id == 'vault:installation-catalog' &&
        values.containsKey(id) &&
        !_gated) {
      _gated = true;
      reached.complete();
      await release.future;
    }
    return super.read(id);
  }
}

class ReplacementGatedWriter implements CatalogStagingWriter {
  bool armed = false;
  final reached = Completer<void>();
  final release = Completer<void>();
  File? staged;
  @override
  Future<void> write(File file, Uint8List sealed) async {
    await const FileCatalogStagingWriter().write(file, sealed);
    if (armed) {
      staged = file;
      reached.complete();
      await release.future;
    }
  }
}

void main() {
  const secret = 'a long safe passphrase';
  test(
    'lock during catalog seal rejects setup without publishing a profile',
    () async {
      final paths = await tempPaths();
      addTearDown(() => paths.root.delete(recursive: true));
      final keys = SealGatedKeys();
      final identity = LocalIdentityService(
        keys: keys,
        catalog: ProfileCatalog(paths: paths, keys: keys),
        clock: FakeClock(),
        ids: SecureIds(),
      );
      final pending = identity.createProfile('Canceled Alice', secret);
      await keys.reached.future;
      identity.lock();
      keys.release.complete();
      await expectLater(pending, throwsCheckError(CheckError.locked));
      expect(await identity.profiles(), isEmpty);
      expect(await paths.catalog.exists(), isFalse);
      expect(keys.values.keys, ['vault:installation-catalog']);
      expect(await paths.root.list().length, 0);
    },
  );
  test(
    'lock while staged catalog replacement waits preserves existing profile and keys',
    () async {
      final paths = await tempPaths();
      addTearDown(() => paths.root.delete(recursive: true));
      final keys = MemoryKeyStore();
      final writer = ReplacementGatedWriter();
      final identity = LocalIdentityService(
        keys: keys,
        catalog: ProfileCatalog(
          paths: paths,
          keys: keys,
          stagingWriter: writer,
        ),
        clock: FakeClock(),
        ids: SecureIds(),
      );
      final alice = await identity.createProfile('Alice', secret);
      final person = identity.requireActor(alice).personId;
      final originalCatalog = await paths.catalog.readAsBytes();
      final originalKeys = {
        for (final entry in keys.values.entries)
          entry.key: Uint8List.fromList(entry.value),
      };
      writer.armed = true;
      final pending = identity.createProfile('Canceled Bob', secret);
      await writer.reached.future;
      expect(await writer.staged!.exists(), isTrue);
      expect(await paths.catalog.readAsBytes(), originalCatalog);
      identity.lock();
      writer.release.complete();
      await expectLater(pending, throwsCheckError(CheckError.locked));
      expect(await paths.catalog.readAsBytes(), originalCatalog);
      expect((await identity.profiles()).single.personId, person);
      expect(keys.values, originalKeys);
      expect(await writer.staged!.exists(), isFalse);
      expect(
        () => identity.requireActor(alice),
        throwsCheckError(CheckError.locked),
      );
      final unlocked = await identity.unlock(person, secret);
      expect(identity.requireActor(unlocked).personId, person);
    },
  );
}
