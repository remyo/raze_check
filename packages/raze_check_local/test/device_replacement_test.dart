@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'receipt_import_test.dart' as attendance;
import 'authority_fork_test.dart' as lineage;
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';

void main() {
  late TwoDeviceFixture pair;
  late EnrollmentDevice target;
  setUp(() async {
    pair = await TwoDeviceFixture.create();
    await pair.enrollStaff();
    target = await EnrollmentDevice.create(
      pair.manager.clock,
      'New device setup',
    );
  });
  tearDown(() async {
    await target.storage.dispose();
    await pair.dispose();
  });
  LocalDeviceReplacementService service(EnrollmentDevice d) =>
      LocalDeviceReplacementService(
        repository: d.storage.repo,
        identity: d.identity,
        keys: d.storage.keys,
        clock: d.clock,
        ids: SecureIds(),
      );
  test(
    'no-backup original person remains pending until exact replacement grant; historical credential retained',
    () async {
      final receipt = await pair.captureCheckIn();
      final managerAttendance = attendance.service(pair.manager);
      await managerAttendance.importReceipt(
        pair.context('received-before-loss'),
        await managerAttendance.verifyIncoming(
          pair.manager.session,
          pair.companyId,
          receipt.bytes,
        ),
      );
      await managerAttendance.decide(
        pair.context('review-before-loss'),
        receipt.eventId,
        ReviewDecision.approve,
        'Checked',
      );
      final old = pair.staff.identity.requireActor(pair.staff.session);
      final member = (await pair.staff.companies.membership(
        pair.staff.session,
        pair.companyId,
      ))!;
      final invite = await pair.manager.enrollment.createInvitation(
        pair.context('new-device-invitation'),
      );
      await target.enrollment.acceptInvitation(
        target.session,
        MessageCodec().encode(invite),
        acceptedRootFingerprint: pair.company.rootFingerprint,
      );
      final draft = await target.identity.stageRecoveryIdentity(
        target.session,
        companyId: pair.companyId,
        personId: old.personId,
        displayName: 'Staff',
        rootFingerprint: pair.company.rootFingerprint,
        passphrase: 'new local passphrase',
      );
      expect(
        (await target.identity.profiles()).any(
          (p) => p.personId == old.personId,
        ),
        isFalse,
      );
      expect(await target.canIssueAttendance(pair.companyId), isFalse);
      final request = await service(target).createRequest(
        target.session,
        pair.companyId,
        member.employeeId,
        candidate: draft,
      );
      final verified = await pair.manager.enrollment.verifyIncoming(
        pair.manager.session,
        MessageCodec().encode(request),
      );
      final grant = await service(
        pair.manager,
      ).authorize(pair.context('replace'), verified);
      expect(
        MessageCodec().encode(
          await service(
            pair.manager,
          ).authorize(pair.context('replace-retry'), verified),
        ),
        MessageCodec().encode(grant),
      );
      final archives = LocalArchiveService(
        paths: pair.manager.storage.paths,
        keys: pair.manager.storage.keys,
        repository: pair.manager.storage.repo,
        identity: pair.manager.identity,
        clock: pair.manager.clock,
        ids: SecureIds(),
      );
      final exported = await archives.createStaffRecovery(
        pair.context('export-recovery'),
        verified,
        grant,
        'staff archive passphrase',
      );
      final encrypted = await archives.shareBytes(
        pair.manager.session,
        exported.artifactId,
      );
      final file = File(
        '${target.storage.paths.root.path}/received.razecheck-backup',
      );
      await file.writeAsBytes(encrypted);
      final incoming = LocalArchiveService(
        paths: target.storage.paths,
        keys: target.storage.keys,
        repository: target.storage.repo,
        identity: target.identity,
        clock: target.clock,
        ids: SecureIds(),
      );
      final preview = await incoming.inspect(
        target.session,
        file.path,
        'staff archive passphrase',
      );
      expect(preview.companyIds, [pair.companyId]);
      expect(preview.counts.containsKey('companyRootRecovery'), isFalse);
      // Existing invitation pin and accepted public ancestors can merge with the
      // projection; no active personal credential is installed by this apply.
      await incoming.apply(preview, RestoreChoice.mergeNonConflicting);
      expect(
        (await target.identity.profiles()).any(
          (p) => p.personId == old.personId,
        ),
        isFalse,
      );
      final returned = await target.enrollment.verifyIncoming(
        target.session,
        MessageCodec().encode(grant),
      );
      final acceptance = await service(
        target,
      ).accept(target.session, returned, candidate: draft);
      expect(
        acceptance,
        isA<Committed<Membership>>(),
        reason: acceptance is Rejected<Membership>
            ? acceptance.error.name
            : null,
      );
      target.session = await target.identity.unlock(
        old.personId,
        'new local passphrase',
      );
      final fresh = target.identity.requireActor(target.session);
      expect(fresh.personId, old.personId);
      expect(fresh.installationId, isNot(old.installationId));
      expect(await target.canIssueAttendance(pair.companyId), isTrue);
      expect(
        (await target.storage.repo.read(
          pair.companyId,
          receipt.eventId,
        ))!.payload,
        receipt.bytes,
      );
      expect(
        (await attendance
                .service(target)
                .get(target.session, pair.companyId, receipt.eventId))
            .review,
        ReviewStatus.approved,
      );
      expect(
        (await target.companies.membership(
          target.session,
          pair.companyId,
        ))!.employeeId,
        member.employeeId,
      );
      final history = (await pair.manager.storage.repo.listRecords(
        pair.companyId,
        'trustedCredential',
      )).map((r) => jsonDecode(utf8.decode(r.payload)) as Map).toList();
      expect(history, hasLength(2));
      expect(
        history.singleWhere(
          (c) => c['installationId'] == old.installationId,
        )['retired'],
        isTrue,
      );
      expect(
        () => fresh.requireCompany(SecureIds().next()),
        throwsA(isA<CheckException>()),
      );
    },
  );
  for (final restoreFirst in [false, true]) {
    test(
      'authenticated personal recovery preserves journal with restoreFirst=$restoreFirst',
      () async {
        final old = pair.staff.identity.requireActor(pair.staff.session);
        final member = (await pair.staff.companies.membership(
          pair.staff.session,
          pair.companyId,
        ))!;
        LocalArchiveService archive(EnrollmentDevice d) => LocalArchiveService(
          paths: d.storage.paths,
          keys: d.storage.keys,
          repository: d.storage.repo,
          identity: d.identity,
          clock: d.clock,
          ids: SecureIds(),
        );
        Company? other;
        AttendanceReceipt? otherReceipt;
        if (restoreFirst) {
          other =
              (await pair.staff.companies.createCompany(
                        pair.staff.session,
                        const CompanyDraft(
                          'Original owned company B',
                          'Asia/Tokyo',
                        ),
                        'other-company',
                      )
                      as Committed<Company>)
                  .value;
        }
        if (other != null) {
          final code = await pair.staff.capture.createWorkplaceCode(
            CommandContext(
              companyId: other.id,
              session: pair.staff.session,
              operationId: 'other-code',
              authorityGenerationId: other.authorityGenerationId,
            ),
          );
          final verified = await pair.staff.capture.verifyWorkplace(
            pair.staff.session,
            other.id,
            MessageCodec().encode(code),
          );
          final draft = await pair.staff.capture.beginDraft(
            pair.staff.session,
            other.id,
            verified,
            PunchKind.checkIn,
          );
          otherReceipt =
              (await pair.staff.capture.recordPunch(
                        draft.context(pair.staff.session),
                        verified,
                        PunchKind.checkIn,
                      )
                      as Committed<AttendanceReceipt>)
                  .value;
        }
        final savedReceipt = await pair.captureCheckIn();
        // Exercise both persisted pending and committed old-installation slots.
        if (!restoreFirst) {
          await pair.staff.capture.finishDraft(
            pair.staff.session,
            pair.companyId,
            savedReceipt.eventId,
          );
          await pair.staff.capture.beginDraft(
            pair.staff.session,
            pair.companyId,
            await pair.workplace(),
            PunchKind.checkOut,
          );
        }
        final oldDraft = await pair.staff.capture.currentDraft(
          pair.staff.session,
          pair.companyId,
        );
        final oldIntent = (await pair.staff.storage.repo.read(
          pair.companyId,
          'capture-intent:${oldDraft!.operationId}',
        ))!;

        final savedPin = (await pair.staff.storage.repo.read(
          pair.companyId,
          'enrollment-trust:${old.personId}',
        ))!;
        final savedJournal = (await pair.staff.storage.repo.snapshot(
          PersonalScope(old.personId),
        )).journal;
        final outgoing = archive(pair.staff);
        final exported = await outgoing.create(
          pair.staff.session,
          PersonalScope(old.personId),
          'personal archive passphrase',
        );
        final file = File(
          '${target.storage.paths.root.path}/personal.razecheck-backup',
        );
        await file.writeAsBytes(
          await outgoing.shareBytes(pair.staff.session, exported.artifactId),
        );
        final incoming = archive(target);
        if (restoreFirst) {
          final initial = await incoming.inspect(
            target.session,
            file.path,
            'personal archive passphrase',
          );
          await incoming.apply(initial, RestoreChoice.mergeNonConflicting);
        }
        final preview = await incoming.inspect(
          target.session,
          file.path,
          'personal archive passphrase',
        );
        if (!restoreFirst) {
          for (final claim in [
            (company: pair.companyId, person: old.personId, root: '0' * 64),
            (
              company: pair.companyId,
              person: SecureIds().next(),
              root: pair.company.rootFingerprint,
            ),
            (
              company: SecureIds().next(),
              person: old.personId,
              root: pair.company.rootFingerprint,
            ),
          ]) {
            final wrong = await target.identity.stageRecoveryIdentity(
              target.session,
              companyId: claim.company,
              personId: claim.person,
              displayName: 'Claim',
              rootFingerprint: claim.root,
              passphrase: 'new local passphrase',
            );
            await expectLater(
              incoming.applyRecoveryPersonal(target.session, preview, wrong),
              throwsA(
                isA<CheckException>().having(
                  (e) => e.code,
                  'code',
                  CheckError.unauthorized,
                ),
              ),
            );
            expect(
              await target.storage.repo.read(pair.companyId, pair.companyId),
              isNull,
            );
            await target.identity.cancelRecoveryIdentity(target.session, wrong);
          }
        }
        final draft = await target.identity.stageRecoveryIdentity(
          target.session,
          companyId: pair.companyId,
          personId: old.personId,
          displayName: 'Staff',
          rootFingerprint: pair.company.rootFingerprint,
          passphrase: 'new local passphrase',
        );
        await expectLater(
          incoming.applyRecoveryPersonal(pair.staff.session, preview, draft),
          throwsA(isA<CheckException>()),
        );
        await incoming.applyRecoveryPersonal(target.session, preview, draft);
        final chain = await lineage.descendants(pair, 3);
        final originalInvite = await pair.manager.enrollment.createInvitation(
          pair.context('newer-invite'),
        );
        final inviteFields = [...originalInvite.payload.values]
          ..[7] = chain.last.values;
        final newerInvite = await lineage.sign(
          pair,
          MessageKind.invitation,
          inviteFields,
        );
        final invitationService = target.enrollment as InvitationHistoryService;
        final consent = await invitationService.beginInvitation(
          target.session,
          MessageCodec().encode(newerInvite),
          acceptedRootFingerprint: pair.company.rootFingerprint,
        );
        await invitationService.stageHistory(
          target.session,
          consent,
          AuthorityHistoryFile.batches(
            pair.companyId,
            pair.company.rootFingerprint,
            chain,
          ).single,
        );
        await (target.enrollment as RecoveryInvitationService)
            .bindRecoveryInvitation(target.session, consent, draft);

        expect(
          await target.storage.repo.read(
            pair.companyId,
            'enrollment-trust:${target.identity.requireActor(target.session).personId}',
          ),
          isNull,
        );
        final request = await service(target).createRequest(
          target.session,
          pair.companyId,
          member.employeeId,
          candidate: draft,
        );
        final verified = await pair.manager.enrollment.verifyIncoming(
          pair.manager.session,
          MessageCodec().encode(request),
        );
        final originalGrant = await service(
          pair.manager,
        ).authorize(pair.context('replace-personal'), verified);
        final grantFields = [...originalGrant.payload.values]
          ..[13] = chain.last.values;
        final grant = await lineage.sign(
          pair,
          MessageKind.membershipGrant,
          grantFields,
        );
        final returned = await service(target).verifyPendingGrant(
          target.session,
          MessageCodec().encode(grant),
          candidate: draft,
        );
        final result = await service(
          target,
        ).accept(target.session, returned, candidate: draft);
        expect(
          result,
          isA<Committed<Membership>>(),
          reason: result is Rejected<Membership> ? result.error.name : null,
        );
        target.session = await target.identity.unlock(
          old.personId,
          'new local passphrase',
        );
        expect(await target.canIssueAttendance(pair.companyId), isTrue);
        expect(
          (await target.storage.repo.read(
            pair.companyId,
            savedReceipt.eventId,
          ))!.payload,
          savedReceipt.bytes,
        );
        expect(
          (await target.storage.repo.read(
            pair.companyId,
            savedPin.id,
          ))!.payload,
          savedPin.payload,
        );
        {
          expect(
            await target.capture.currentDraft(target.session, pair.companyId),
            isNull,
          );
          final originalCode = await pair.manager.capture.createWorkplaceCode(
            pair.context('new-code'),
          );
          final values = [...originalCode.payload.values]
            ..[5] = chain.last.values;
          final newCode = await lineage.sign(
            pair,
            MessageKind.workplace,
            values,
          );
          final verifiedCode = await target.capture.verifyWorkplace(
            target.session,
            pair.companyId,
            MessageCodec().encode(newCode),
          );
          final freshDraft = await target.capture.beginDraft(
            target.session,
            pair.companyId,
            verifiedCode,
            PunchKind.checkOut,
          );
          final newReceipt = await target.capture.recordPunch(
            freshDraft.context(target.session),
            verifiedCode,
            PunchKind.checkOut,
          );
          expect(newReceipt, isA<Committed<AttendanceReceipt>>());
          expect(
            (await target.storage.repo.read(
              pair.companyId,
              oldIntent.id,
            ))!.payload,
            oldIntent.payload,
          );
        }
        final restoredJournal = (await target.storage.repo.snapshot(
          PersonalScope(old.personId),
        )).journal;
        for (final entry in savedJournal) {
          expect(
            restoredJournal.any(
              (e) =>
                  e.companyId == entry.companyId &&
                  e.revision == entry.revision &&
                  e.operationId == entry.operationId,
            ),
            isTrue,
          );
        }

        expect(
          await target.storage.repo.hasRestoreCommit(exported.artifactId),
          isTrue,
        );
        expect(
          (await target.capture.getReceipt(
            target.session,
            pair.companyId,
            savedReceipt.eventId,
          )).bytes,
          savedReceipt.bytes,
        );
        if (other != null) {
          await expectLater(
            target.capture.getReceipt(
              target.session,
              other.id,
              otherReceipt!.eventId,
            ),
            throwsA(
              isA<CheckException>().having(
                (e) => e.code,
                'code',
                CheckError.unauthorized,
              ),
            ),
          );
          expect(
            await target.companies.readCompany(target.session, other.id),
            isNull,
          );
          expect(
            (await target.companies.listCompanies(
              target.session,
            )).map((c) => c.id),
            [pair.companyId],
          );
          expect(await target.canIssueAttendance(other.id), isFalse);
          await expectLater(
            incoming.create(
              target.session,
              CompanyScope(other.id),
              'must not export secret',
            ),
            throwsA(isA<CheckException>()),
          );
          final limited = await incoming.create(
            target.session,
            PersonalScope(old.personId),
            'limited personal export',
          );
          final limitedFile = File(
            '${target.storage.paths.root.path}/limited.backup',
          );
          await limitedFile.writeAsBytes(
            await incoming.shareBytes(target.session, limited.artifactId),
          );
          final limitedPreview = await incoming.inspect(
            target.session,
            limitedFile.path,
            'limited personal export',
          );
          expect(limitedPreview.companyIds, [pair.companyId]);
          await incoming.discard(limitedPreview);
          const newDraft = CompanyDraft('New owned company', 'Asia/Tokyo');
          final created = await target.companies.createCompany(
            target.session,
            newDraft,
            'new-owned-company',
          );
          expect(created, isA<Committed<Company>>());
          final c = (created as Committed<Company>).value;
          expect(
            await target.companies.readCompany(target.session, c.id),
            isNotNull,
          );
          target.identity.lock();
          target.session = await target.identity.unlock(
            old.personId,
            'new local passphrase',
          );
          expect(
            await target.companies.readCompany(target.session, c.id),
            isNotNull,
          );
          expect(
            (await target.companies.createCompany(
                      target.session,
                      newDraft,
                      'new-owned-company',
                    )
                    as Committed<Company>)
                .duplicate,
            isTrue,
          );
          expect(
            await target.companies.readCompany(target.session, other.id),
            isNull,
          );
        }
      },
    );
  }
  test(
    'accepted identity journal finishes publication after catalog I/O interruption',
    () async {
      final setup = target.identity.requireActor(target.session).personId;
      final writer = RecoveryFailWriter();
      target.identity = LocalIdentityService(
        keys: target.storage.keys,
        catalog: ProfileCatalog(
          paths: target.storage.paths,
          keys: target.storage.keys,
          stagingWriter: writer,
        ),
        clock: target.clock,
        ids: SecureIds(),
        repository: target.storage.repo,
      );
      target.session = await target.identity.unlock(
        setup,
        'a strong local passphrase',
      );
      target.rebuildServices();
      final old = pair.staff.identity.requireActor(pair.staff.session);
      final member = (await pair.staff.companies.membership(
        pair.staff.session,
        pair.companyId,
      ))!;
      final invite = await pair.manager.enrollment.createInvitation(
        pair.context('draft-invitation'),
      );
      final consent = await (target.enrollment as InvitationHistoryService)
          .beginInvitation(
            target.session,
            MessageCodec().encode(invite),
            acceptedRootFingerprint: pair.company.rootFingerprint,
          );
      final draft = await target.identity.stageRecoveryIdentity(
        target.session,
        companyId: pair.companyId,
        personId: old.personId,
        displayName: 'Staff',
        rootFingerprint: pair.company.rootFingerprint,
        passphrase: 'new local passphrase',
      );
      await (target.enrollment as RecoveryInvitationService)
          .bindRecoveryInvitation(target.session, consent, draft);
      final request = await service(target).createRequest(
        target.session,
        pair.companyId,
        member.employeeId,
        candidate: draft,
      );
      final grant = await service(pair.manager).authorize(
        pair.context('replace-fault'),
        await pair.manager.enrollment.verifyIncoming(
          pair.manager.session,
          MessageCodec().encode(request),
        ),
      );
      final verified = await service(target).verifyPendingGrant(
        target.session,
        MessageCodec().encode(grant),
        candidate: draft,
      );
      writer.fail = true;
      expect(
        (await service(
                  target,
                ).accept(target.session, verified, candidate: draft)
                as Rejected)
            .error,
        CheckError.storageFailure,
      );
      expect(
        (await target.identity.profiles()).any(
          (p) => p.personId == old.personId,
        ),
        isFalse,
      );
      target.identity.lock();
      target.identity = LocalIdentityService(
        keys: target.storage.keys,
        catalog: ProfileCatalog(
          paths: target.storage.paths,
          keys: target.storage.keys,
        ),
        clock: target.clock,
        ids: SecureIds(),
        repository: target.storage.repo,
      );
      await target.identity.resumeRecoveryIdentities();
      target.rebuildServices();
      target.session = await target.identity.unlock(
        old.personId,
        'new local passphrase',
      );
      expect(await target.canIssueAttendance(pair.companyId), isTrue);
      expect(
        target.identity.requireActor(target.session).authorizedCompanyIds,
        {pair.companyId},
      );
    },
  );
  test(
    'public IDs, canceled consent, canceled draft and abandoned restart cannot publish old identity',
    () async {
      final old = pair.staff.identity.requireActor(pair.staff.session);
      final draft = await target.identity.stageRecoveryIdentity(
        target.session,
        companyId: pair.companyId,
        personId: old.personId,
        displayName: 'Staff',
        rootFingerprint: pair.company.rootFingerprint,
        passphrase: 'new local passphrase',
      );
      await expectLater(
        target.identity.unlock(old.personId, 'new local passphrase'),
        throwsA(isA<CheckException>()),
      );
      final invite = await pair.manager.enrollment.createInvitation(
        pair.context('cancel-consent'),
      );
      final consent = await (target.enrollment as InvitationHistoryService)
          .beginInvitation(
            target.session,
            MessageCodec().encode(invite),
            acceptedRootFingerprint: pair.company.rootFingerprint,
          );
      await (target.enrollment as RecoveryInvitationService)
          .bindRecoveryInvitation(target.session, consent, draft);
      (target.enrollment as InvitationHistoryService).cancelInvitation(consent);
      await expectLater(
        service(target).createRequest(
          target.session,
          pair.companyId,
          'claim',
          candidate: draft,
        ),
        throwsA(isA<CheckException>()),
      );
      await target.identity.cancelRecoveryIdentity(target.session, draft);
      await expectLater(
        service(target).createRequest(
          target.session,
          pair.companyId,
          'missing',
          candidate: draft,
        ),
        throwsA(isA<CheckException>()),
      );
      expect((await target.identity.profiles()), hasLength(1));
      final abandoned = await target.identity.stageRecoveryIdentity(
        target.session,
        companyId: pair.companyId,
        personId: old.personId,
        displayName: 'Staff',
        rootFingerprint: pair.company.rootFingerprint,
        passphrase: 'new local passphrase',
      );
      final abandonedKey = target.identity
          .requireRecoveryIdentity(target.session, abandoned)
          .profile
          .signingKeyId;
      target.identity.lock();
      target.identity = LocalIdentityService(
        keys: target.storage.keys,
        catalog: ProfileCatalog(
          paths: target.storage.paths,
          keys: target.storage.keys,
        ),
        clock: target.clock,
        ids: SecureIds(),
        repository: target.storage.repo,
      );
      await target.identity.resumeRecoveryIdentities();
      expect(await target.storage.keys.read(abandonedKey), isNull);
      expect((await target.identity.profiles()), hasLength(1));
    },
  );
}

final class RecoveryFailWriter implements CatalogStagingWriter {
  bool fail = false;
  @override
  Future<void> write(File file, Uint8List bytes) async {
    if (fail) {
      throw const FileSystemException('injected publication interruption');
    }
    await file.writeAsBytes(bytes, flush: true);
  }
}
