import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../packages/raze_check_local/test/support/acceptance_scenarios.dart';
import 'support/native_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native archive fsync authenticated owner recovery and scoped authorized queries',
    (tester) async {
      final devices = await nativeAcceptanceDevices([
        'manager',
        'staff',
        'recovered',
      ]);
      try {
        await recoveryAcceptance(devices[0], devices[1], devices[2]);
      } finally {
        await closeNativeAcceptance(devices);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
