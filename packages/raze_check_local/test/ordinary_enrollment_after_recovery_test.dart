@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';
import 'recovery_continuation_test.dart' as recovery;
import 'authority_fork_test.dart' as lineage;
import 'device_replacement_test.dart' show RecoveryFailWriter;

void main() {
  test(
    'recovered A joins genuinely new B only on its exact first grant and resumes catalog publication',
    () async {
      final pair = await TwoDeviceFixture.create();
      await pair.enrollStaff();
      final target = await EnrollmentDevice.create(pair.manager.clock, 'Setup');
      addTearDown(() async {
        await target.storage.dispose();
        await pair.dispose();
      });
      await recovery.recoverA(pair, target);
      final actor = target.identity.requireActor(target.session);
      final beforeA = (await target.storage.repo.snapshot(
        CompanyScope(pair.companyId),
      )).revisions;
      final key = await target.storage.keys.read(actor.signingKeyId),
          verifier = await target.storage.keys.read(
            'credential:${actor.personId}',
          );
      final b =
          (await pair.manager.companies.createCompany(
                    pair.manager.session,
                    const CompanyDraft('New employer', 'Asia/Tokyo'),
                    'new-b',
                  )
                  as Committed<Company>)
              .value;
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
        actor.personId,
        'new local passphrase',
      );
      target.rebuildServices();
      final invite = await pair.manager.enrollment.createInvitation(
        recovery.context(pair.manager, b, 'invite'),
      );
      final consent = await target.enrollment.acceptInvitation(
        target.session,
        MessageCodec().encode(invite),
        acceptedRootFingerprint: b.rootFingerprint,
      );
      final request = await target.enrollment.requestJoin(
        target.session,
        consent,
        SecureIds().next(),
      );
      expect(
        (await target.enrollment.pendingJoins(
          target.session,
        )).map((m) => m.payload.messageId),
        contains(request.payload.messageId),
      );
      expect(await target.companies.readCompany(target.session, b.id), isNull);
      expect(await target.canIssueAttendance(b.id), isFalse);
      final result =
          await pair.manager.enrollment.approveJoin(
                recovery.context(pair.manager, b, 'approve'),
                await pair.manager.enrollment.verifyIncoming(
                  pair.manager.session,
                  MessageCodec().encode(request),
                ),
              )
              as Committed<SignedMessage>;
      final grant = result.value;
      // The accepted invitation selects a newer exact lineage. A valid old
      // first grant is historical evidence, not authorization for this join.
      final parent = AuthorityCertificate(b.authority);
      final current = pair.manager.identity.requireActor(pair.manager.session);
      final certValues = <Object?>[
        SecureIds().next(),
        parent.generationId,
        parent.sequence + 1,
        current.installationId,
        base64UrlEncode(current.publicKey),
        pair.manager.clock.nowUtc().millisecondsSinceEpoch,
      ];
      final signature = await LocalKeyService(pair.manager.storage.keys).sign(
        Uint8List.fromList(
          utf8.encode('RAZE_CHECK_AUTHORITY_V1\n${jsonEncode(certValues)}'),
        ),
        'company-root:${b.id}',
      );
      final newer = AuthorityCertificate([
        ...certValues,
        base64UrlEncode(signature),
      ]);
      final newerInvite = await lineage.sign(
        pair,
        MessageKind.invitation,
        [...invite.payload.values]
          ..[1] = SecureIds().next()
          ..[7] = newer.values,
      );
      final staged = await (target.enrollment as InvitationHistoryService)
          .beginInvitation(
            target.session,
            MessageCodec().encode(newerInvite),
            acceptedRootFingerprint: b.rootFingerprint,
          );
      await (target.enrollment as InvitationHistoryService).stageHistory(
        target.session,
        staged,
        AuthorityHistoryFile.batches(b.id, b.rootFingerprint, [
          parent,
          newer,
        ]).single,
      );
      await (target.enrollment as InvitationHistoryService).finishInvitation(
        target.session,
        staged,
      );
      await expectLater(
        target.enrollment.verifyIncoming(
          target.session,
          MessageCodec().encode(grant),
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.revokedCredential,
          ),
        ),
      );
      final currentGrant = await lineage.sign(
        pair,
        MessageKind.membershipGrant,
        [...grant.payload.values]..[13] = newer.values,
      );
      final verified = await target.enrollment.verifyIncoming(
        target.session,
        MessageCodec().encode(currentGrant),
      );
      for (final index in [0, 3, 5, 6, 8, 9]) {
        final fields = [...currentGrant.payload.values]
          ..[index] = index == 5
              ? 2
              : index == 9
              ? base64UrlEncode(
                  pair.staff.identity
                      .requireActor(pair.staff.session)
                      .publicKey,
                )
              : SecureIds().next();
        final wrong = await lineage.sign(
          pair,
          MessageKind.membershipGrant,
          fields,
        );
        await expectLater(
          target.enrollment.verifyIncoming(
            target.session,
            MessageCodec().encode(wrong),
          ),
          throwsA(isA<CheckException>()),
        );
      }
      await expectLater(
        target.enrollment.verifyIncoming(
          pair.staff.session,
          MessageCodec().encode(grant),
        ),
        throwsA(isA<CheckException>()),
      );
      writer.fail = true;
      expect(
        await target.enrollment.acceptGrant(target.session, verified),
        isA<Rejected<Membership>>().having(
          (r) => r.error,
          'error',
          CheckError.storageFailure,
        ),
      );
      expect(await target.canIssueAttendance(b.id), isFalse);
      expect(await target.canIssueAttendance(pair.companyId), isTrue);
      writer.fail = false;
      target.identity.lock();
      target.session = await target.identity.unlock(
        actor.personId,
        'new local passphrase',
      );
      expect(await target.canIssueAttendance(b.id), isTrue);
      expect(await target.canIssueAttendance(pair.companyId), isTrue);
      expect(await target.storage.keys.read(actor.signingKeyId), key);
      expect(
        await target.storage.keys.read('credential:${actor.personId}'),
        verifier,
      );
      expect(
        (await target.storage.repo.snapshot(
          CompanyScope(pair.companyId),
        )).revisions,
        beforeA,
      );
      expect(
        await target.enrollment.acceptGrant(
          target.session,
          await target.enrollment.verifyIncoming(
            target.session,
            MessageCodec().encode(currentGrant),
          ),
        ),
        isA<Committed<Membership>>(),
      );
    },
  );
}
