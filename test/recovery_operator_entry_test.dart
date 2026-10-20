@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check/app/check_app.dart';
import 'package:raze_check/app/local_composition.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../packages/raze_check_local/test/support/fake_clock.dart';
import '../packages/raze_check_local/test/support/memory_key_store.dart';
import '../packages/raze_check_local/test/support/temp_paths.dart';

Future<void> settleIo(WidgetTester tester) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (i > 2 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.text('Unlocking…').evaluate().isEmpty) {
        break;
      }
      if (DateTime.now().isAfter(deadline)) break;
    }
  });
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.byType(LinearProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}

void main() {
  for (final allowed in [true, false]) {
    testWidgets(
      'actual restricted host recovery entry permits only selected staff actions allowed=$allowed',
      (tester) async {
        final paths = (await tester.runAsync(tempPaths))!;
        late LocalComposition s;
        await tester.runAsync(() async {
          s = await LocalComposition.open(
            paths: paths,
            secureKeys: MemoryKeyStore(),
            clock: FakeClock(),
          );
          final owner = await s.identity.createProfile(
            'Owner',
            'owner local passphrase',
          );
          final company =
              (await s.companies.createCompany(
                        owner,
                        const CompanyDraft('Company', 'Asia/Tokyo'),
                        'create',
                      )
                      as Committed<Company>)
                  .value;
          CommandContext command(String op) => CommandContext(
            companyId: company.id,
            session: owner,
            operationId: op,
            authorityGenerationId: company.authorityGenerationId,
          );
          final staff =
              (await s.companies.createStaff(
                        command('staff'),
                        const StaffDraft(name: 'Operator'),
                      )
                      as Committed<StaffRecord>)
                  .value;
          await s.companies.grantCapabilities(
            command('caps'),
            staff.membershipId,
            allowed
                ? {Capability.manageMemberships, Capability.exportAttendance}
                : {},
          );
          await s.companies.activateOperator(
            command('activate'),
            staff.membershipId,
            'operator local passphrase',
          );
          s.identity.lock();
        });
        await tester.runAsync(() async {
          await tester.pumpWidget(CheckApp(composition: Future.value(s)));
        });
        await settleIo(tester);
        await tester.tap(find.text('Skip'));
        await settleIo(tester);
        await tester.tap(find.text('Unlock company operator'));
        await settleIo(tester);
        await tester.tap(find.text('Operator'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(
          find.widgetWithText(TextField, 'Operator passphrase'),
          'operator local passphrase',
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Unlock operator'));
        });
        await tester.runAsync(() async {
          await tester.pump(const Duration(milliseconds: 50));
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (find.text('Unlocking…').evaluate().isNotEmpty &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 50));
          }
        });
        await settleIo(tester);
        expect(find.text('Unlocking…'), findsNothing);
        expect(find.text('Backup / recovery'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Backup / recovery'));
        });
        await settleIo(tester);
        expect(find.text('Encrypted backup and passive restore'), findsNothing);
        expect(
          find.text('Recover staff identity on this device'),
          findsNothing,
        );
        expect(
          find.text('Activate or recover owner on this device'),
          findsNothing,
        );
        expect(find.text('Move this owner device'), findsNothing);
        expect(find.text('Public authority history'), findsNothing);
        expect(
          find.text('Approve staff replacement and recovery export'),
          allowed ? findsOneWidget : findsNothing,
        );
        if (allowed) {
          await tester.runAsync(() async {
            await tester.tap(
              find.text('Approve staff replacement and recovery export'),
            );
          });
          await settleIo(tester);
          expect(find.text('Approve staff replacement'), findsOneWidget);
          expect(find.text('Select the original employee'), findsOneWidget);
        }
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox.shrink());
        });
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await paths.root.delete(recursive: true);
        });
      },
    );
  }
}
