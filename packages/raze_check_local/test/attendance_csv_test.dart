import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_local/raze_check_local.dart';

void main() {
  test('CSV escapes quotes, multiline text and formula leading cells', () {
    expect(AttendanceCsv.cell('a,"b"\nc'), '"a,""b""\nc"');
    for (final prefix in ['=', '+', '-', '@', '\t', '\r']) {
      expect(AttendanceCsv.cell('${prefix}SUM(A1)'), '"\'${prefix}SUM(A1)"');
    }
    expect(AttendanceCsv.cell('plain'), '"plain"');
  });
}
