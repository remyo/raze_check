import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../packages/raze_check_local/test/support/acceptance_device.dart';
import 'support/native_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'missing OS catalog key preserves encrypted bytes and reports explicit recovery required',
    (tester) async {
      final devices = await nativeAcceptanceDevices(['missing-catalog-key']);
      final device = devices.single;
      try {
        final before = await device.paths.catalog.readAsBytes();
        device.identity.lock();
        await device.keys.delete('vault:installation-catalog');
        await expectLater(
          device.identity.profiles(),
          throwsA(
            isA<CheckException>().having(
              (e) => e.code,
              'code',
              CheckError.recoveryRequired,
            ),
          ),
        );
        await expectLater(
          device.identity.createProfile(
            'Must not overwrite',
            acceptancePassword,
          ),
          throwsA(
            isA<CheckException>().having(
              (e) => e.code,
              'code',
              CheckError.recoveryRequired,
            ),
          ),
        );
        expect(await device.paths.catalog.readAsBytes(), orderedEquals(before));
        expect(await device.keys.read('vault:installation-catalog'), isNull);
      } finally {
        await closeNativeAcceptance(devices);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  testWidgets(
    'OS secure storage persists random key across adapter instances and isolates namespace',
    (tester) async {
      final prefix = 'acceptance:${SecureIds().next()}:secure',
          keys = NamespacedKeys(OsSecureKeyStore(), prefix);
      final original = secureRandomBytes(32);
      expect(await keys.read('probe'), isNull);
      await keys.write('probe', original);
      final reopened = NamespacedKeys(OsSecureKeyStore(), prefix);
      expect(await reopened.read('probe'), orderedEquals(original));
      expect(
        await NamespacedKeys(OsSecureKeyStore(), '$prefix:other').read('probe'),
        isNull,
      );
      await keys.delete('probe');
      expect(await reopened.read('probe'), isNull);
      // Adapter reopening alone is not OS-process-death/uninstall evidence.
    },
  );
}
