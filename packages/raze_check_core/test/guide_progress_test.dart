import 'package:raze_check_core/raze_check_core.dart';
import 'package:test/test.dart';

GuideProgress entry() => GuideProgress(
  guideId: 'attendance',
  variantId: 'worker',
  contentRevision: 1,
);
void main() {
  test('snapshot copies entries and exposes an immutable list', () {
    final entries = [entry()];
    final snapshot = GuideProgressSnapshot(entries: entries);
    entries.clear();
    expect(snapshot.entries, hasLength(1));
    expect(() => snapshot.entries.clear(), throwsUnsupportedError);
    expect(snapshot.entries.single.stepId, isNull);
    expect(snapshot.welcomeDismissed, isFalse);
    expect(snapshot.entries.single.viewed, isFalse);
  });
  test('duplicate guide variant keys are rejected', () {
    expect(
      () => GuideProgressSnapshot(entries: [entry(), entry()]),
      throwsArgumentError,
    );
  });
}
