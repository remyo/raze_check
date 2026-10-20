import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'support/dashboard_fixture.dart';

void main() {
  testWidgets(
    'report form stays scrollable above keyboard and generates real own snapshot',
    (tester) async {
      final f = (await tester.runAsync(dashboardFixture))!;
      addTearDown(() async {
        await tester.runAsync(f.pair.dispose);
      });
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: CheckTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 260),
              ),
              child: child!,
            ),
            home: AttendanceReportScreen(
              services: featureServices(f.pair.staff),
              session: f.pair.staff.session,
              company: f.pair.company,
              canExport: false,
              personalAllowed: true,
            ),
          ),
        );
      });
      await tester.enterText(
        find.widgetWithText(TextField, 'Start date (YYYY-MM-DD)'),
        '2026-10-19',
      );
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'End date (YYYY-MM-DD)'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'End date (YYYY-MM-DD)'),
        '2026-10-19',
      );
      await tester.ensureVisible(find.text('Generate report'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Generate report'));
        await tester.pump();
      });
      await settleFeature(tester);
      expect(find.textContaining('2 records'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Share CSV'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Share CSV'));
        await tester.pump();
      });
      await settleFeature(tester);
      expect(find.textContaining('Sharing did not confirm'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'End date (YYYY-MM-DD)'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'End date (YYYY-MM-DD)'),
        '2026-10-20',
      );
      await tester.pump();
      expect(find.text('Share CSV'), findsNothing);

      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
