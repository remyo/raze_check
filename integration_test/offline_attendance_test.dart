import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../packages/raze_check_local/test/support/acceptance_scenarios.dart';
import 'support/native_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real OS keys and persisted offline invitation receipt review correction reopen',
    (tester) async {
      final devices = await nativeAcceptanceDevices(['manager', 'staff']);
      try {
        await offlineAcceptance(devices[0], devices[1]);
      } finally {
        await closeNativeAcceptance(devices);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
