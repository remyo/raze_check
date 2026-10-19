@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';
import '../../raze_check_local/test/recovery_continuation_test.dart'
    as recovery;
import 'support/settle_review.dart';

void main() {
  for (final export in [true, false]) {
    testWidgets(
      'restricted operator approves exact selected staff; export=$export',
      (tester) async {
        late TwoDeviceFixture pair;
        late EnrollmentDevice target;
        late SignedMessage request;
        late StaffRecord original;
        await tester.runAsync(() async {
          pair = await TwoDeviceFixture.create();
          await pair.enrollStaff();
          target = await EnrollmentDevice.create(pair.manager.clock, 'Setup');
          final member = (await pair.staff.companies.membership(
            pair.staff.session,
            pair.companyId,
          ))!;
          original = (await pair.manager.companies.listStaff(
            pair.manager.session,
            pair.companyId,
          )).singleWhere((s) => s.membershipId == member.id);
          final candidate = await recovery.consent(
            pair.manager,
            target,
            pair.company,
          );
          final draft = await target.identity.stageRecoveryIdentity(
            target.session,
            companyId: pair.companyId,
            personId: original.personId,
            displayName: 'Recovered staff',
            rootFingerprint: pair.company.rootFingerprint,
            passphrase: 'new local passphrase',
          );
          await (target.enrollment as RecoveryInvitationService)
              .bindRecoveryInvitation(target.session, candidate, draft);
          request = await recovery
              .replacement(target)
              .createRequest(
                target.session,
                pair.companyId,
                member.employeeId,
                candidate: draft,
              );
          final op =
              (await pair.manager.companies.createStaff(
                        pair.context('operator'),
                        const StaffDraft(name: 'Operator'),
                      )
                      as Committed<StaffRecord>)
                  .value;
          await pair.manager.companies.grantCapabilities(
            pair.context('caps'),
            op.membershipId,
            {
              Capability.manageMemberships,
              if (export) Capability.exportAttendance,
            },
          );
          await pair.manager.companies.activateOperator(
            pair.context('activate'),
            op.membershipId,
            'operator passphrase',
          );
          pair.manager.identity.lock();
          pair.manager.session = await pair.manager.companies.unlockOperator(
            pair.companyId,
            op.membershipId,
            'operator passphrase',
          );
        });
        addTearDown(() async {
          await target.storage.dispose();
          await pair.dispose();
        });
        final sent = <Uint8List>[];
        final files = RecoveryFiles(
          pickBytes: (_) async => MessageCodec().encode(request),
          pickArchive: (_) async => null,
          releaseArchive: (_) async {},
          share: (bytes, name, guard) async {
            await guard();
            sent.add(bytes);
            return ShareOutcome.opened;
          },
        );
        final archives = recovery.archive(pair.manager);
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: ReplacementApprovalScreen(
                identity: pair.manager.identity,
                session: pair.manager.session,
                company: pair.company,
                companies: pair.manager.companies,
                enrollment: pair.manager.enrollment,
                service: recovery.replacement(pair.manager),
                backups: archives,
                staffBackups: archives,
                files: files,
              ),
            ),
          );
        });
        await settleReview(tester);
        await tester.tap(find.byType(DropdownButton<StaffRecord>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(original.details.name).last);
        await tester.pumpAndSettle();
        expect(find.textContaining(original.personId), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Read staff replacement request'));
        });
        await settleReview(tester);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(find.text('Authorize replacement'));
        });
        await settleReview(tester);
        expect(find.text('Share replacement grant'), findsOneWidget);
        await tester.ensureVisible(find.text('Share replacement grant'));
        await tester.runAsync(() async {
          await tester.tap(find.text('Share replacement grant'));
        });
        await settleReview(tester);
        expect(sent, hasLength(1));
        final grant = MessageCodec().decode(sent.single, maxBytes: 65536);
        expect(grant.kind, MessageKind.membershipGrant);
        expect(
          find.text('Export selected staff recovery archive'),
          export ? findsOneWidget : findsNothing,
        );
        if (export) {
          await tester.enterText(
            find.widgetWithText(TextField, 'Staff archive passphrase'),
            'staff archive passphrase',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Confirm staff archive passphrase'),
            'staff archive passphrase',
          );
          await tester.ensureVisible(
            find.text('Export selected staff recovery archive'),
          );
          await tester.runAsync(() async {
            await tester.tap(
              find.text('Export selected staff recovery archive'),
            );
          });
          await settleReview(tester);
          expect(sent, hasLength(2));
          expect(sent.last.length, greaterThan(100));
        } else {
          expect(find.text('Staff archive passphrase'), findsNothing);
          await tester.runAsync(() async {
            final verified = await pair.manager.enrollment.verifyIncoming(
              pair.manager.session,
              MessageCodec().encode(request),
            );
            await expectLater(
              archives.createStaffRecovery(
                pair.context('forbidden-export'),
                verified,
                grant,
                'staff archive passphrase',
              ),
              throwsA(
                isA<CheckException>().having(
                  (e) => e.code,
                  'code',
                  CheckError.unauthorized,
                ),
              ),
            );
          });
        }
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox.shrink());
        });
      },
    );
  }
}
