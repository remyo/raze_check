import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';
import 'authority_fork_test.dart' as lineage;
import 'receipt_import_test.dart' show service;

void main() {
  for (final decision in [false, true]) {
    test(
      'G3 ${decision ? 'decision' : 'ack'} blocks shared G0 management without changing history and older returns cannot downgrade',
      () async {
        final p = await TwoDeviceFixture.create();
        addTearDown(p.dispose);
        final d = p.manager,
            m = service(p.manager),
            owner = d.identity.requireActor(d.session);
        Future<void> unlock(String person) async {
          d.session = await d.identity.unlock(
            person,
            'a strong local passphrase',
          );
        }

        final code = await d.capture.createWorkplaceCode(
          p.context('workplace'),
        );
        final invitation = await d.enrollment.createInvitation(
          p.context('shared-staff-invite'),
        );
        d.session = await d.identity.createProfile(
          'Shared staff',
          'a strong local passphrase',
        );
        final a = d.identity.requireActor(d.session);
        final consent = await d.enrollment.acceptInvitation(
          d.session,
          MessageCodec().encode(invitation),
          acceptedRootFingerprint: p.company.rootFingerprint,
        );
        final request = await d.enrollment.requestJoin(
          d.session,
          consent,
          SecureIds().next(),
        );
        await unlock(owner.personId);
        final grant =
            (await d.enrollment.approveJoin(
                      p.context('shared-staff-approve'),
                      await d.enrollment.verifyIncoming(
                        d.session,
                        MessageCodec().encode(request),
                      ),
                    )
                    as Committed<SignedMessage>)
                .value;
        await unlock(a.personId);
        expect(
          await d.enrollment.acceptGrant(
            d.session,
            await d.enrollment.verifyIncoming(
              d.session,
              MessageCodec().encode(grant),
            ),
          ),
          isA<Committed<Membership>>(),
        );
        final verified = await d.capture.verifyWorkplace(
          d.session,
          p.companyId,
          MessageCodec().encode(code),
        );
        final draft = await d.capture.beginDraft(
          d.session,
          p.companyId,
          verified,
          PunchKind.checkIn,
        );
        final receipt =
            (await d.capture.recordPunch(
                      draft.context(d.session),
                      verified,
                      PunchKind.checkIn,
                    )
                    as Committed<AttendanceReceipt>)
                .value;
        await unlock(owner.personId);
        final imported = await m.importReceipt(
          p.context('import'),
          await m.verifyIncoming(d.session, p.companyId, receipt.bytes),
        );
        final original = decision
            ? (await m.decide(
                        p.context('decision'),
                        receipt.eventId,
                        ReviewDecision.approve,
                        'Checked',
                      )
                      as Committed<DecisionRecord>)
                  .value
                  .returnMessage!
            : imported.returnMessage!;
        final before = (await d.storage.repo.read(
          p.companyId,
          p.companyId,
        ))!.payload;
        final credentials = (await d.storage.repo.listRecords(
          p.companyId,
          'trustedCredential',
        )).map((r) => base64UrlEncode(r.payload)).toList();
        final chain = await lineage.descendants(p, 3);
        await LocalAuthorityHistoryService(
          repository: d.storage.repo,
          identity: d.identity,
          keys: d.storage.keys,
          ids: SecureIds(),
        ).importHistory(
          d.session,
          p.companyId,
          AuthorityHistoryFile.batches(
            p.companyId,
            p.company.rootFingerprint,
            chain,
          ).single,
        );
        await d.enrollment.createInvitation(
          p.context('history-only-still-current'),
        );
        final values = [...original.payload.values]
          ..[1] = SecureIds().next()
          ..[original.payload.values.length - 1] = chain.last.values;
        if (decision) {
          values[5] = SecureIds().next();
          values[6] = 2;
        }
        final current = await lineage.sign(p, original.kind, values);
        await unlock(a.personId);
        expect(
          await m.accept(
            d.session,
            await m.verifyIncoming(
              d.session,
              p.companyId,
              MessageCodec().encode(current),
            ),
          ),
          isA<Committed<AttendanceRecord>>(),
        );
        await unlock(owner.personId);
        await expectLater(
          d.enrollment.createInvitation(
            p.context('history-only-still-current'),
          ),
          throwsA(
            isA<CheckException>().having(
              (e) => e.code,
              'code',
              CheckError.recoveryRequired,
            ),
          ),
        );
        await expectLater(
          d.capture.createWorkplaceCode(p.context('workplace')),
          throwsA(isA<CheckException>()),
        );
        expect(
          await m.decide(
            p.context('decision'),
            receipt.eventId,
            ReviewDecision.approve,
            'Checked',
          ),
          isA<Rejected<DecisionRecord>>(),
        );
        await unlock(a.personId);
        expect(
          await m.accept(
            d.session,
            await m.verifyIncoming(
              d.session,
              p.companyId,
              MessageCodec().encode(original),
            ),
          ),
          isA<Committed<AttendanceRecord>>(),
        );
        final correction = await m.request(
          d.session,
          p.companyId,
          receipt.eventId,
          ProposedCorrection(
            kind: receipt.kind,
            utcMs: receipt.claimedUtcMs,
            offsetMinutes: receipt.offsetMinutes,
            reason: 'Verify after authority change',
          ),
          'correction-after-observation',
        );
        expect(correction.kind, MessageKind.correctionRequest);
        expect(
          (await m.verifyIncoming(
            d.session,
            p.companyId,
            MessageCodec().encode(correction),
          )).message.payload.messageId,
          correction.payload.messageId,
        );
        final remote =
            jsonDecode(
                  utf8.decode(
                    (await d.storage.repo.read(
                      p.companyId,
                      'remote-authority:${a.personId}',
                    ))!.payload,
                  ),
                )
                as Map;
        expect(
          AuthorityCertificate(
            List<Object?>.from(remote['authority'] as List),
          ).generationId,
          chain.last.generationId,
        );
        expect(
          (await d.storage.repo.read(p.companyId, p.companyId))!.payload,
          before,
        );
        expect(
          (await d.storage.repo.listRecords(
            p.companyId,
            'trustedCredential',
          )).map((r) => base64UrlEncode(r.payload)),
          credentials,
        );
        expect(
          MessageCodec().encode(
            (await m.verifyIncoming(
              d.session,
              p.companyId,
              receipt.bytes,
            )).message,
          ),
          receipt.bytes,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
