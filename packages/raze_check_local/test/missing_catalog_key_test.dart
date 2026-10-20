import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/acceptance_device.dart';
import 'support/memory_key_store.dart';

void main() {
  test(
    'restored encrypted catalog without its device key fails closed without replacing bytes',
    () async {
      final root = await acceptanceDirectory('missing-key');
      final keys = MemoryKeyStore(),
          device = AcceptanceDevice(AppPaths(root), MemoryKeyStore());
      // The fixture's real encrypted catalog and signing credentials are retained.
      await device.open();
      addTearDown(() async {
        await device.close();
        await root.delete(recursive: true);
      });
      final before = await device.paths.catalog.readAsBytes();
      final catalog = ProfileCatalog(paths: device.paths, keys: keys);
      await expectLater(
        catalog.read(),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.recoveryRequired,
          ),
        ),
      );
      await expectLater(
        catalog.write([]),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.recoveryRequired,
          ),
        ),
      );
      expect(await device.paths.catalog.readAsBytes(), orderedEquals(before));
      expect(
        keys.values,
        isEmpty,
        reason:
            'Never generate replacement key over existing encrypted catalog',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
