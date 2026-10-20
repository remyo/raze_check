import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'support/dashboard_fixture.dart';

void main() {
  testWidgets(
    'owner repairs only an overlong legacy name through company tools',
    (tester) async {
      final f = (await tester.runAsync(dashboardFixture))!;
      final d = f.pair.manager;
      await tester.runAsync(() async {
        final old = (await d.storage.repo.read(
          f.pair.companyId,
          f.pair.companyId,
        ))!;
        final legacy = StoredRecord(
          old.id,
          old.companyId,
          old.kind,
          old.revision + 1,
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({...f.pair.company.toJson(), 'name': 'L' * 121}),
            ),
          ),
        );
        await d.storage.repo.commit(
          f.pair.context('legacy-name'),
          requestDigest: Uint8List(32),
          build: (_) async => Mutation([legacy], [], [], legacy),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: RazeCheckFeature(
              services: featureServices(d),
              initialCompanyId: f.pair.companyId,
              host: CheckFeatureHost(onExit: () {}),
            ),
          ),
        );
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.pair.dispose);
      });
      await unlockFeature(tester, 'Owner');
      await settleFeature(tester, until: 'A clear view');
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correct company name'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save corrected name'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Repaired company');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save corrected name'));
        await tester.pump();
      });
      await settleFeature(tester);
      await tester.runAsync(() async {
        expect(
          (await d.companies.readCompany(
            tester
                .widget<CompanyWorkspace>(find.byType(CompanyWorkspace))
                .session,
            f.pair.companyId,
          ))!.name,
          'Repaired company',
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('Correct company name'), findsNothing);
      expect(find.text('Repaired company'), findsWidgets);
    },
  );
}
