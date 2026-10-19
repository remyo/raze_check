import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check/main.dart' as app;
import 'package:timezone/timezone.dart' as tz;

void main() {
  testWidgets(
    'startup identifies Raze Check and reports unconfigured services',
    (tester) async {
      app.main();
      await tester.pumpAndSettle();

      expect(find.text('Raze Check'), findsOneWidget);
      expect(
        find.text('Local services are not configured yet.'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsOneWidget);
      expect(tz.getLocation('Asia/Tokyo').name, 'Asia/Tokyo');
    },
  );
}
