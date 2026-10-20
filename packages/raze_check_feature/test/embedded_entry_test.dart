import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'support/dashboard_fixture.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';

void main() {
  testWidgets(
    'independent host preserves theme, navigation, company switch and lock boundaries',
    (tester) async {
      final f = (await tester.runAsync(dashboardFixture))!;
      final d = f.pair.manager;
      await tester.runAsync(() async {
        await d.companies.createCompany(
          d.session,
          const CompanyDraft('Second synthetic company', 'Europe/London'),
          'second',
        );
      });
      final services = featureServices(d);
      var exits = 0;
      final routes = <String>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.pair.dispose);
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'HostTypeface'),
            home: RazeCheckFeature(
              services: services,
              initialCompanyId: f.pair.companyId,
              host: CheckFeatureHost(
                onExit: () => exits++,
                themeBuilder: (context, _) => Theme.of(context),
                navigate: (context, page, name) async {
                  routes.add(name);
                  await Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => page));
                },
              ),
            ),
          ),
        );
      });
      await unlockFeature(tester, 'Owner');
      await settleFeature(tester, until: 'A clear view');
      expect(find.textContaining('Offline company'), findsWidgets);
      expect(find.textContaining('Management'), findsWidgets);
      expect(
        Theme.of(
          tester.element(find.byType(ManagerHomeScreen)),
        ).textTheme.bodyMedium!.fontFamily,
        'HostTypeface',
      );
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Overview'));
        await tester.pump();
      });
      await settleFeature(tester, until: 'A clear view');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Attendance report'));
        await tester.pump();
      });
      await settleFeature(tester);
      expect(routes, contains('attendance-report'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('company-switcher')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Second synthetic company').last);
        await tester.pump();
      });
      await settleFeature(tester);
      expect(find.textContaining('Offline company'), findsNothing);
      expect(find.textContaining('Second synthetic company'), findsWidgets);
      await tester.tap(find.text('Lock'));
      await settleFeature(tester, until: 'Unlock Owner');
      expect(find.byType(ManagerHomeScreen), findsNothing);
      expect(find.textContaining('Second synthetic company'), findsNothing);
      await unlockFeature(tester, 'Owner');
      await tester.tap(find.byTooltip('Exit Raze Check'));
      expect(exits, 1);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    },
  );
  testWidgets(
    'unsupported initial company is rejected before any records display',
    (tester) async {
      final f = (await tester.runAsync(dashboardFixture))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.pair.dispose);
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: RazeCheckFeature(
              services: featureServices(f.pair.staff),
              initialCompanyId: 'not-authorized',
              host: CheckFeatureHost(onExit: () {}),
            ),
          ),
        );
      });
      await unlockFeature(tester, 'Staff');
      expect(
        find.textContaining('Requested company access was rejected'),
        findsOneWidget,
      );
      expect(find.byType(StaffHomeScreen), findsNothing);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    },
  );
  testWidgets('fresh staff can reach invitation join from the real entry', (
    tester,
  ) async {
    final pair = (await tester.runAsync(TwoDeviceFixture.create))!;
    addTearDown(() async {
      await tester.runAsync(pair.dispose);
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: RazeCheckFeature(
            services: featureServices(pair.staff),
            host: CheckFeatureHost(onExit: () {}),
          ),
        ),
      );
    });
    await unlockFeature(tester, 'Staff');
    await settleFeature(tester, until: 'Join company');
    await tester.runAsync(() async {
      await tester.tap(find.text('Join company'));
      await tester.pump();
    });
    await settleFeature(tester);
    expect(find.text('Read invitation'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
