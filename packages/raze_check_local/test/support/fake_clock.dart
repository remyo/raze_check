import 'package:raze_check_core/raze_check_core.dart';

class FakeClock implements CheckClock {
  DateTime now = DateTime.utc(2026, 10, 19);
  @override
  DateTime nowUtc() => now;
  void advance(Duration by) => now = now.add(by);
}
