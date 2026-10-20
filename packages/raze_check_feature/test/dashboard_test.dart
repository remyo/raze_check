import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'support/dashboard_fixture.dart';

void main() {
  testWidgets('dashboard uses saved and returned real receipt state', (
    tester,
  ) async {
    final f = (await tester.runAsync(dashboardFixture))!;
    addTearDown(() async {
      await tester.runAsync(f.pair.dispose);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: CheckTheme.light(),
        home: Scaffold(
          body: StaffHomeScreen(
            overview: f.staff,
            onCapture: () {},
            onAttendance: () {},
          ),
        ),
      ),
    );
    expect(find.text('Saved on this device'), findsOneWidget);
    expect(find.text('Awaiting review'), findsOneWidget);
    expect(find.text('Absent'), findsNothing);
    expect(find.text('Salary'), findsNothing);
    expect(find.textContaining('Offline company'), findsWidgets);
    expect(find.textContaining('Staff'), findsWidgets);
    await tester.pumpWidget(
      MaterialApp(
        theme: CheckTheme.dark(),
        home: Scaffold(
          body: ManagerHomeScreen(overview: f.manager, onAttendance: () {}),
        ),
      ),
    );
    expect(find.byKey(const Key('last-received')), findsOneWidget);
    expect(find.textContaining('2026-10-19 09:00 Asia/Tokyo'), findsOneWidget);
  });
}
