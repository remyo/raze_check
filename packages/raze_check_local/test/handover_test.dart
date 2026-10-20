@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';
import 'receipt_import_test.dart' as attendance;

void main() {
  late TwoDeviceFixture pair;
  late EnrollmentDevice target;
  late LocalArchiveService sourceArchive, targetArchive;
  LocalArchiveService archive(EnrollmentDevice d) => LocalArchiveService(
    paths: d.storage.paths,
    keys: d.storage.keys,
    repository: d.storage.repo,
    identity: d.identity,
    clock: d.clock,
    ids: SecureIds(),
  );
  LocalHandoverService handover(EnrollmentDevice d, LocalArchiveService a) =>
      LocalHandoverService(
        repository: d.storage.repo,
        identity: d.identity,
        keys: d.storage.keys,
        clock: d.clock,
        ids: SecureIds(),
        archives: a,
      );
  setUp(() async {
    pair = await TwoDeviceFixture.create();
    target = await EnrollmentDevice.create(pair.manager.clock, 'Setup');
    sourceArchive = archive(pair.manager);
    targetArchive = archive(target);
  });
  tearDown(() async {
    await target.storage.dispose();
    await pair.dispose();
  });
  for (final pendingSlot in [false, true]) {
    test(
      'same owner handover freezes before snapshot and lost ack cannot resume source pendingSlot=$pendingSlot',
      () async {
        final owner = pair.manager.identity.requireActor(pair.manager.session);
        final code = await pair.manager.capture.createWorkplaceCode(
          pair.context('owner-workplace'),
        );
        final verifiedCode = await pair.manager.capture.verifyWorkplace(
          pair.manager.session,
          pair.companyId,
          MessageCodec().encode(code),
        );
        final punch = await pair.manager.capture.beginDraft(
          pair.manager.session,
          pair.companyId,
          verifiedCode,
          PunchKind.checkIn,
        );
        final unsent =
            (await pair.manager.capture.recordPunch(
                      punch.context(pair.manager.session),
                      verifiedCode,
                      PunchKind.checkIn,
                    )
                    as Committed<AttendanceReceipt>)
                .value;
        if (pendingSlot) {
          await pair.manager.capture.finishDraft(
            pair.manager.session,
            pair.companyId,
            unsent.eventId,
          );
          await pair.manager.capture.beginDraft(
            pair.manager.session,
            pair.companyId,
            verifiedCode,
            PunchKind.checkOut,
          );
        }
        final retainedDraft = await pair.manager.capture.currentDraft(
          pair.manager.session,
          pair.companyId,
        );
        final retainedIntent = (await pair.manager.storage.repo.read(
          pair.companyId,
          'capture-intent:${retainedDraft!.operationId}',
        ))!;
        expect(
          await pair.manager.storage.repo.listRecords(
            pair.companyId,
            'trustedCredential',
          ),
          isEmpty,
        );
        final draft = await target.identity.stageRecoveryIdentity(
          target.session,
          companyId: pair.companyId,
          personId: owner.personId,
          displayName: 'Owner',
          rootFingerprint: pair.company.rootFingerprint,
          passphrase: 'new owner passphrase',
        );
        final replacement = LocalDeviceReplacementService(
          repository: target.storage.repo,
          identity: target.identity,
          keys: target.storage.keys,
          clock: target.clock,
          ids: SecureIds(),
        );
        final request = await replacement.createRequest(
          target.session,
          pair.companyId,
          null,
          candidate: draft,
        );
        final verified = await pair.manager.enrollment.verifyIncoming(
          pair.manager.session,
          MessageCodec().encode(request),
        );
        final source = handover(pair.manager, sourceArchive);
        await expectLater(
          source.begin(
            pair.context('failed-preparation'),
            verified,
            archivePassphrase: 'short',
          ),
          throwsA(isA<CheckException>()),
        );
        await expectLater(
          pair.manager.enrollment.createInvitation(
            pair.context('preparing-frozen'),
          ),
          throwsA(isA<CheckException>()),
        );
        await source.cancel(pair.context('cancel-before-offer'));
        await pair.manager.enrollment.createInvitation(
          pair.context('resumed-after-cancel'),
        );
        final offer = await source.begin(
          pair.context('handover'),
          verified,
          archivePassphrase: 'handover archive secret',
        );
        await expectLater(
          pair.manager.enrollment.createInvitation(pair.context('frozen')),
          throwsA(
            isA<CheckException>().having(
              (e) => e.code,
              'code',
              CheckError.recoveryRequired,
            ),
          ),
        );
        await expectLater(
          source.exportArtifact(
            pair.manager.session,
            HandoverOffer(
              offer.transfer,
              ArchiveDescriptor(
                artifactId: SecureIds().next(),
                createdUtcMs: offer.archive.createdUtcMs,
                scope: offer.archive.scope,
                counts: {},
              ),
            ),
          ),
          throwsA(
            isA<CheckException>().having(
              (e) => e.code,
              'code',
              CheckError.unauthorized,
            ),
          ),
        );
        final file = File('${target.storage.paths.root.path}/handover.backup');
        await file.writeAsBytes(
          await source.exportArtifact(pair.manager.session, offer),
        );
        var preview = await targetArchive.inspect(
          target.session,
          file.path,
          'handover archive secret',
        );
        expect(
          preview.manifestSha256Base64Url,
          offer.transfer.payload.field<String>('snapshotSha256Base64Url'),
        );
        // A self-signed request and snapshot do not replace possession of the
        // exact fresh private key. Passive restore may complete; activation cannot.
        final pending = target.identity.requireRecoveryIdentity(
          target.session,
          draft,
        );
        final freshSeed = (await target.storage.keys.read(
          pending.profile.signingKeyId,
        ))!;
        await target.storage.keys.delete(pending.profile.signingKeyId);
        await expectLater(
          handover(
            target,
            targetArchive,
          ).activate(target.session, preview, offer, candidate: draft),
          throwsA(
            isA<CheckException>().having(
              (e) => e.code,
              'code',
              CheckError.recoveryRequired,
            ),
          ),
        );
        expect(
          (await target.identity.profiles()).any(
            (p) => p.personId == owner.personId,
          ),
          isFalse,
        );
        await target.storage.keys.write(
          pending.profile.signingKeyId,
          freshSeed,
        );
        preview = await targetArchive.inspect(
          target.session,
          file.path,
          'handover archive secret',
        );
        await file.delete();
        final ack = await handover(
          target,
          targetArchive,
        ).activate(target.session, preview, offer, candidate: draft);
        await expectLater(
          source.cancel(pair.context('cancel')),
          throwsA(isA<CheckException>()),
        );
        target.session = await target.identity.unlock(
          owner.personId,
          'new owner passphrase',
        );
        final recovered = (await target.companies.readCompany(
          target.session,
          pair.companyId,
        ))!;
        expect(recovered.creationPersonId, owner.personId);
        expect(
          recovered.authorityGenerationId,
          isNot(pair.company.authorityGenerationId),
        );
        expect(await target.canIssueAttendance(pair.companyId), isTrue);
        expect(
          await target.capture.currentDraft(target.session, pair.companyId),
          isNull,
        );
        final nextCode = await target.capture.createWorkplaceCode(
          CommandContext(
            companyId: pair.companyId,
            session: target.session,
            operationId: 'fresh-owner-code',
            authorityGenerationId: recovered.authorityGenerationId,
          ),
        );
        final nextVerified = await target.capture.verifyWorkplace(
          target.session,
          pair.companyId,
          MessageCodec().encode(nextCode),
        );
        final nextDraft = await target.capture.beginDraft(
          target.session,
          pair.companyId,
          nextVerified,
          PunchKind.checkOut,
        );
        expect(
          await target.capture.recordPunch(
            nextDraft.context(target.session),
            nextVerified,
            PunchKind.checkOut,
          ),
          isA<Committed<AttendanceReceipt>>(),
        );
        final historical = await attendance
            .service(target)
            .verifyIncoming(target.session, pair.companyId, unsent.bytes);
        expect(historical.historicalCredential, isTrue);
        expect(
          (await target.storage.repo.read(
            pair.companyId,
            unsent.eventId,
          ))!.payload,
          unsent.bytes,
        );
        expect(
          (await target.storage.repo.read(
            pair.companyId,
            retainedIntent.id,
          ))!.payload,
          retainedIntent.payload,
        );
        expect(await pair.manager.canIssueAttendance(pair.companyId), isFalse);
        final ackVerified =
            await MessageVerifier(
              LocalKeyService(pair.manager.storage.keys),
            ).verify(
              ack,
              TrustContext(
                companyId: pair.companyId,
                rootPublicKey: base64Url.decode(pair.company.rootPublicKey),
                authorities: [
                  AuthorityCertificate(pair.company.authority),
                  AuthorityCertificate(
                    offer.transfer.payload.field<List<Object?>>(
                      'nextAuthority',
                    ),
                  ),
                ],
              ),
            );
        // Finish uses durable source trust and re-verifies incoming bytes itself.
        expect(
          (await pair.manager.enrollment.verifyIncoming(
            pair.manager.session,
            MessageCodec().encode(ack),
          )).message.payload.messageId,
          ackVerified.message.payload.messageId,
        );
        await source.finish(pair.context('finish'), ackVerified);
        expect(
          MessageCodec().encode(
            (await handover(
              target,
              targetArchive,
            ).activationAcknowledgment(target.session, pair.companyId))!,
          ),
          MessageCodec().encode(ack),
        );
        expect(
          (await source.pendingOffer(
            pair.manager.session,
            pair.companyId,
          ))!.archive.artifactId,
          offer.archive.artifactId,
        );
      },
    );
  }
  test(
    'lost-source recovery requires checkpoint consent and competing recoveries quarantine, never overwrite',
    () async {
      final owner = pair.manager.identity.requireActor(pair.manager.session);
      final original = await sourceArchive.create(
        pair.manager.session,
        CompanyScope(pair.companyId),
        'portable root passphrase',
      );
      final bytes = await sourceArchive.shareBytes(
        pair.manager.session,
        original.artifactId,
      );
      Future<Company> recoverOn(
        EnrollmentDevice device,
        LocalArchiveService a,
      ) async {
        final file = File(
          '${device.storage.paths.root.path}/checkpoint.backup',
        );
        await file.writeAsBytes(bytes);
        final preview = await a.inspect(
          device.session,
          file.path,
          'portable root passphrase',
        );
        final draft = await device.identity.stageRecoveryIdentity(
          device.session,
          companyId: pair.companyId,
          personId: owner.personId,
          displayName: 'Owner',
          rootFingerprint: pair.company.rootFingerprint,
          passphrase: 'new owner passphrase',
        );
        final h = handover(device, a);
        await expectLater(
          h.recover(
            device.session,
            preview,
            RecoveryAcknowledgment(
              manifestId: preview.manifestId,
              manifestSha256Base64Url: preview.manifestSha256Base64Url,
              acceptsMissingData: false,
            ),
            candidate: draft,
          ),
          throwsA(isA<CheckException>()),
        );
        expect(
          (await device.identity.profiles()).any(
            (p) => p.personId == owner.personId,
          ),
          isFalse,
        );
        await h.recover(
          device.session,
          preview,
          RecoveryAcknowledgment(
            manifestId: preview.manifestId,
            manifestSha256Base64Url: preview.manifestSha256Base64Url,
            acceptsMissingData: true,
          ),
          candidate: draft,
        );
        device.session = await device.identity.unlock(
          owner.personId,
          'new owner passphrase',
        );
        return (await device.companies.readCompany(
          device.session,
          pair.companyId,
        ))!;
      }

      final first = await recoverOn(target, targetArchive);
      final sibling = await EnrollmentDevice.create(
        pair.manager.clock,
        'Other recovered setup',
      );
      addTearDown(sibling.storage.dispose);
      final second = await recoverOn(sibling, archive(sibling));
      expect(first.authorityGenerationId, isNot(second.authorityGenerationId));
      final staleFile = File('${target.storage.paths.root.path}/old.backup');
      await staleFile.writeAsBytes(bytes);
      final stale = await targetArchive.inspect(
        target.session,
        staleFile.path,
        'portable root passphrase',
      );
      await expectLater(
        targetArchive.apply(stale, RestoreChoice.mergeNonConflicting),
        throwsA(isA<CheckException>()),
      );
      expect(
        (await target.companies.readCompany(
          target.session,
          pair.companyId,
        ))!.authorityGenerationId,
        first.authorityGenerationId,
      );
      final history = LocalAuthorityHistoryService(
        repository: target.storage.repo,
        identity: target.identity,
        keys: target.storage.keys,
        ids: SecureIds(),
      );
      final file = AuthorityHistoryFile.batches(
        pair.companyId,
        pair.company.rootFingerprint,
        [
          AuthorityCertificate(pair.company.authority),
          AuthorityCertificate(second.authority),
        ],
      ).single;
      await expectLater(
        history.importHistory(target.session, pair.companyId, file),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.recoveryRequired,
          ),
        ),
      );
      final context = CommandContext(
        companyId: pair.companyId,
        session: target.session,
        operationId: 'after-fork',
        authorityGenerationId: first.authorityGenerationId,
      );
      await expectLater(
        target.enrollment.createInvitation(context),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.recoveryRequired,
          ),
        ),
      );
      expect(
        (await target.storage.repo.listRecords(
          pair.companyId,
          'authorityConflict',
        )),
        hasLength(1),
      );
    },
  );
}
