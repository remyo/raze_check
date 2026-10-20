import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'support/dashboard_fixture.dart';

void main() {
  testWidgets(
    'return from recovery refreshes real backup age without changing company',
    (tester) async {
      final f = (await tester.runAsync(dashboardFixture))!;
      addTearDown(() async {
        await tester.pump();
        await tester.runAsync(
          () => f.pair.dispose().timeout(const Duration(seconds: 15)),
        );
      });
      final services = featureServices(f.pair.manager);
      await tester.runAsync(() async {
        await f.pair.manager.companies.createCompany(
          f.pair.manager.session,
          const CompanyDraft('Second synthetic company', 'Europe/London'),
          'second-backup-company',
        );
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: RazeCheckFeature(
              services: services,
              initialCompanyId: f.pair.companyId,
              host: CheckFeatureHost(
                onExit: () {},
                navigate: (context, page, name) async {
                  expect(name, 'recovery');
                  final session = tester
                      .widget<CompanyWorkspace>(find.byType(CompanyWorkspace))
                      .session;
                  await services.backups.create(
                    session,
                    CompanyScope(f.pair.companyId),
                    'a strong archive passphrase',
                  );
                },
              ),
            ),
          ),
        );
      });
      await unlockFeature(tester, 'Owner');
      await settleFeature(tester, until: 'Company attendance');
      await tester.runAsync(() async {
        await tester.tap(find.text('Backup / recovery'));
        await tester.pump();
      });
      await settleFeature(tester, until: 'Company backup');
      expect(find.textContaining('Company backup'), findsOneWidget);
      expect(
        find.textContaining('external copy not confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('Offline company'), findsOneWidget);
      final staleRefresh = tester
          .state<CompanyWorkspaceState>(find.byType(CompanyWorkspace))
          .prepareRecoveryRefresh();
      await tester.tap(find.byKey(const Key('company-switcher')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Second synthetic company').last);
        await tester.pump();
      });
      await settleFeature(tester, until: 'another company');
      staleRefresh();
      await settleFeature(tester);
      expect(find.textContaining('Company backup'), findsNothing);
      expect(find.textContaining('another company'), findsOneWidget);
      expect(find.textContaining('Second synthetic company'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Lock'));
        await tester.pump();
      });
      await settleFeature(tester, until: 'Unlock Owner');
      staleRefresh();
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    },
  );
}
