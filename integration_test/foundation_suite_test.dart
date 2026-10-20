// One exact compiled entrypoint for prebuilt iOS execution with local signing.
// Process-kill and operator-led native routes remain separate explicit gates.
import 'offline_attendance_test.dart' as offline;
import 'recovery_test.dart' as recovery;
import 'secure_storage_test.dart' as secure;
import 'qr_transfer_test.dart' as qr;
import 'native_matrix_test.dart' as matrix;

void main() {
  offline.main();
  recovery.main();
  secure.main();
  qr.main();
  matrix.main();
}
