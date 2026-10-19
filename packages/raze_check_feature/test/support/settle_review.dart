import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keep real database futures running until the rendered busy state clears.
/// A fixed sleep followed by fake-time settling can starve pending real I/O.
Future<void> settleReview(WidgetTester tester) async {
  await tester.runAsync(() async {
    // A tap/rebuild may have scheduled busy without rendering that frame yet.
    await tester.pump();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
  expect(
    find.byType(LinearProgressIndicator),
    findsNothing,
    reason: 'Review database work must finish within 10 real seconds',
  );
  await tester.pumpAndSettle();
}
