@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';
import 'recovery_continuation_test.dart' as recovery;
import 'receipt_import_test.dart' show service;

void main() {
  test(
    'returning staff crosses three actual lost-source transitions and new G3 employee completes enrollment',
    () async {
      final pair = await TwoDeviceFixture.create();
      await pair.enrollStaff();
      final targets = <EnrollmentDevice>[];
      addTearDown(() async {
        for (final d in targets) {
          await d.storage.dispose();
        }
        await pair.dispose();
      });
      final oldReceipt = await pair.captureCheckIn();
      await service(pair.manager).importReceipt(
        pair.context('receive-before-transitions'),
        await service(pair.manager).verifyIncoming(
          pair.manager.session,
          pair.companyId,
          oldReceipt.bytes,
        ),
      );
      final originalPerson = pair.manager.identity
          .requireActor(pair.manager.session)
          .personId;
      var source = pair.manager, company = pair.company;
      final generations = [company.authorityGenerationId];
      for (var transition = 0; transition < 3; transition++) {
        final outgoing = recovery.archive(source);
        final backup = await outgoing.create(
          source.session,
          CompanyScope(company.id),
          'recovery archive passphrase',
        );
        final target = await EnrollmentDevice.create(
          pair.manager.clock,
          'Replacement setup',
        );
        targets.add(target);
        final file = File('${target.storage.paths.root.path}/recovery.backup');
        await file.writeAsBytes(
          await outgoing.shareBytes(source.session, backup.artifactId),
        );
        final incoming = recovery.archive(target);
        final preview = await incoming.inspect(
          target.session,
          file.path,
          'recovery archive passphrase',
        );
        final candidate = await target.identity.stageRecoveryIdentity(
          target.session,
          companyId: company.id,
          personId: originalPerson,
          displayName: 'Recovered owner',
          rootFingerprint: company.rootFingerprint,
          passphrase: 'new owner passphrase',
        );
        final handover = LocalHandoverService(
          repository: target.storage.repo,
          identity: target.identity,
          keys: target.storage.keys,
          clock: target.clock,
          ids: SecureIds(),
          archives: incoming,
        );
        await handover.recover(
          target.session,
          preview,
          RecoveryAcknowledgment(
            manifestId: preview.manifestId,
            manifestSha256Base64Url: preview.manifestSha256Base64Url,
            acceptsMissingData: true,
          ),
          candidate: candidate,
        );
        target.session = await target.identity.unlock(
          originalPerson,
          'new owner passphrase',
        );
        company = (await target.companies.readCompany(
          target.session,
          company.id,
        ))!;
        expect(
          AuthorityCertificate(company.authority).sequence,
          transition + 2,
        );
        generations.add(company.authorityGenerationId);
        source = target;
      }
      expect(generations.toSet(), hasLength(4));
      // No transfer/intermediate signed envelope was created or replayed.
      final history = LocalAuthorityHistoryService(
        repository: source.storage.repo,
        identity: source.identity,
        keys: source.storage.keys,
        ids: SecureIds(),
      );
      final batches = await history.exportHistory(source.session, company.id);
      final staffHistory = LocalAuthorityHistoryService(
        repository: pair.staff.storage.repo,
        identity: pair.staff.identity,
        keys: pair.staff.storage.keys,
        ids: SecureIds(),
      );
      for (final batch in batches) {
        await staffHistory.importHistory(pair.staff.session, company.id, batch);
      }
      final code = await source.capture.createWorkplaceCode(
        recovery.context(source, company, 'g3-workplace'),
      );
      final verified = await pair.staff.capture.verifyWorkplace(
        pair.staff.session,
        company.id,
        MessageCodec().encode(code),
      );
      await pair.staff.capture.finishDraft(
        pair.staff.session,
        company.id,
        oldReceipt.eventId,
      );
      final draft = await pair.staff.capture.beginDraft(
        pair.staff.session,
        company.id,
        verified,
        PunchKind.checkOut,
      );
      expect(
        await pair.staff.capture.recordPunch(
          draft.context(pair.staff.session),
          verified,
          PunchKind.checkOut,
        ),
        isA<Committed<AttendanceReceipt>>(),
      );
      expect(
        MessageCodec().encode(
          (await service(source).verifyIncoming(
            source.session,
            company.id,
            oldReceipt.bytes,
          )).message,
        ),
        oldReceipt.bytes,
      );
      expect(
        (await pair.staff.storage.repo.read(
          company.id,
          oldReceipt.eventId,
        ))!.payload,
        oldReceipt.bytes,
      );
      final newcomer = await EnrollmentDevice.create(
        pair.manager.clock,
        'New G3 employee',
      );
      targets.add(newcomer);
      final invitation = await source.enrollment.createInvitation(
        recovery.context(source, company, 'g3-invitation'),
      );
      final candidateService = newcomer.enrollment as InvitationHistoryService;
      final candidate = await candidateService.beginInvitation(
        newcomer.session,
        MessageCodec().encode(invitation),
        acceptedRootFingerprint: company.rootFingerprint,
      );
      for (final batch in batches) {
        await candidateService.stageHistory(newcomer.session, candidate, batch);
      }
      final accepted = await candidateService.finishInvitation(
        newcomer.session,
        candidate,
      );
      final request = await newcomer.enrollment.requestJoin(
        newcomer.session,
        accepted,
        SecureIds().next(),
      );
      final grant =
          (await source.enrollment.approveJoin(
                    recovery.context(source, company, 'g3-approve'),
                    await source.enrollment.verifyIncoming(
                      source.session,
                      MessageCodec().encode(request),
                    ),
                  )
                  as Committed<SignedMessage>)
              .value;
      expect(
        await newcomer.enrollment.acceptGrant(
          newcomer.session,
          await newcomer.enrollment.verifyIncoming(
            newcomer.session,
            MessageCodec().encode(grant),
          ),
        ),
        isA<Committed<Membership>>(),
      );
      expect(await newcomer.canIssueAttendance(company.id), isTrue);
    },
  );
}
