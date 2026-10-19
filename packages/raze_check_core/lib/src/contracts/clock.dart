/// Supplies UTC instants; deterministic clocks can be injected by callers.
abstract interface class CheckClock {
  DateTime nowUtc();
}

final class SystemCheckClock implements CheckClock {
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}
