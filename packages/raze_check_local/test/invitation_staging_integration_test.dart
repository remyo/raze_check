@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';
import 'authority_fork_test.dart' as lineage;

void main() {
  test(
    'bounded multi-batch invitation staging rejects swapped canceled expired restarted and interrupted consent',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final chain = await lineage.descendants(p, 130);
      final original = await p.manager.enrollment.createInvitation(
        p.context('invite'),
      );
      final fields = [...original.payload.values]..[7] = chain.last.values;
      final invitation = await lineage.sign(p, MessageKind.invitation, fields);
      final bytes = MessageCodec().encode(invitation),
          batches = AuthorityHistoryFile.batches(
            p.companyId,
            p.company.rootFingerprint,
            chain,
          );
      expect(batches, hasLength(2));
      expect(batches.every((b) => b.length <= 65536), isTrue);
      final service = p.staff.enrollment as InvitationHistoryService;
      Future<InvitationCandidate> begin() => service.beginInvitation(
        p.staff.session,
        bytes,
        acceptedRootFingerprint: p.company.rootFingerprint,
      );
      Future<void> empty() async {
        expect(
          await p.staff.storage.repo.listRecords(
            p.companyId,
            'enrollmentTrust',
          ),
          isEmpty,
        );
        expect(
          await p.staff.storage.repo.listRecords(p.companyId, 'authority'),
          isEmpty,
        );
      }

      await expectLater(
        service.beginInvitation(
          p.staff.session,
          bytes,
          acceptedRootFingerprint: '0' * 64,
        ),
        throwsA(isA<CheckException>()),
      );
      var draft = await begin();
      await expectLater(
        service.stageHistory(p.manager.session, draft, batches.first),
        throwsA(isA<CheckException>()),
      );
      await expectLater(
        service.stageHistory(p.staff.session, draft, Uint8List(65537)),
        throwsA(isA<CheckException>()),
      );
      await expectLater(
        service.stageHistory(
          p.staff.session,
          draft,
          AuthorityHistoryFile.batches(
            SecureIds().next(),
            p.company.rootFingerprint,
            chain,
          ).first,
        ),
        throwsA(isA<CheckException>()),
      );
      await expectLater(
        service.stageHistory(
          p.staff.session,
          draft,
          AuthorityHistoryFile.batches(p.companyId, '0' * 64, chain).first,
        ),
        throwsA(isA<CheckException>()),
      );
      await service.stageHistory(p.staff.session, draft, batches.first);
      await expectLater(
        service.finishInvitation(p.staff.session, draft),
        throwsA(isA<CheckException>()),
      );
      await empty();
      service.cancelInvitation(draft);
      await expectLater(
        service.stageHistory(p.staff.session, draft, batches.last),
        throwsA(isA<CheckException>()),
      );
      draft = await begin();
      final otherFields = [...invitation.payload.values]
        ..[0] = SecureIds().next();
      final other = await lineage.sign(p, MessageKind.invitation, otherFields);
      await service.beginInvitation(
        p.staff.session,
        MessageCodec().encode(other),
        acceptedRootFingerprint: p.company.rootFingerprint,
      );
      await expectLater(
        service.stageHistory(p.staff.session, draft, batches.first),
        throwsA(isA<CheckException>()),
      );
      draft = await begin();
      final person = p.staff.identity.requireActor(p.staff.session).personId;
      p.staff.identity.lock();
      p.staff.session = await p.staff.identity.unlock(
        person,
        'a strong local passphrase',
      );
      await expectLater(
        service.stageHistory(p.staff.session, draft, batches.first),
        throwsA(isA<CheckException>()),
      );
      draft = await begin();
      p.staff.clock.advance(const Duration(minutes: 6));
      await expectLater(
        service.stageHistory(p.staff.session, draft, batches.first),
        throwsA(isA<CheckException>()),
      );
      p.staff.session = await p.staff.identity.unlock(
        person,
        'a strong local passphrase',
      );
      await expectLater(
        service.finishInvitation(p.staff.session, draft),
        throwsA(isA<CheckException>()),
      );
      draft = await begin();
      final reopened = LocalEnrollmentService(
        repository: p.staff.storage.repo,
        identity: p.staff.identity,
        keys: p.staff.storage.keys,
        clock: p.staff.clock,
        ids: SecureIds(),
      );
      await expectLater(
        reopened.finishInvitation(p.staff.session, draft),
        throwsA(isA<CheckException>()),
      );
      final tampered = SignedMessage(
        kind: invitation.kind,
        keyId: invitation.keyId,
        payloadBytes: Uint8List.fromList(
          utf8.encode(jsonEncode([...fields]..[3] = 'Changed label')),
        ),
        signature: invitation.signature,
      );
      draft = await service.beginInvitation(
        p.staff.session,
        MessageCodec().encode(tampered),
        acceptedRootFingerprint: p.company.rootFingerprint,
      );
      for (final batch in batches) {
        await service.stageHistory(p.staff.session, draft, batch);
      }
      await expectLater(
        service.finishInvitation(p.staff.session, draft),
        throwsA(isA<CheckException>()),
      );
      await empty();
      draft = await begin();
      for (final batch in batches) {
        await service.stageHistory(p.staff.session, draft, batch);
      }
      await p.staff.storage.failBeforeCommit();
      await expectLater(
        service.finishInvitation(p.staff.session, draft),
        throwsA(isA<CheckException>()),
      );
      await empty();
      await p.staff.storage.database.customStatement(
        'DROP TRIGGER injected_failure',
      );
      final accepted = await service.finishInvitation(p.staff.session, draft);
      expect(accepted.message.payload.messageId, invitation.payload.messageId);
      expect(
        await p.staff.storage.repo.listRecords(p.companyId, 'authority'),
        hasLength(131),
      );
      expect(await p.staff.canIssueAttendance(p.companyId), isFalse);
    },
  );
}
