@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';

void main() {
  late TwoDeviceFixture pair;
  setUp(() async => pair = await TwoDeviceFixture.create());
  tearDown(() => pair.dispose());
  test(
    'pinned history import persists all ancestors without activating or choosing manager head; fork quarantines',
    () async {
      await pair.enrollStaff();
      final before = (await pair.staff.storage.repo.read(
        pair.companyId,
        pair.companyId,
      ))!.payload;
      final chain = await descendants(pair, 3);
      final history = LocalAuthorityHistoryService(
        repository: pair.staff.storage.repo,
        identity: pair.staff.identity,
        keys: pair.staff.storage.keys,
        ids: SecureIds(),
      );
      final bytes = AuthorityHistoryFile.batches(
        pair.companyId,
        pair.company.rootFingerprint,
        chain,
      ).single;
      await pair.staff.storage.failBeforeCommit();
      await expectLater(
        history.importHistory(pair.staff.session, pair.companyId, bytes),
        throwsA(isA<CheckException>()),
      );
      expect(
        await pair.staff.storage.repo.listRecords(pair.companyId, 'authority'),
        hasLength(1),
      );
      await pair.staff.storage.database.customStatement(
        'DROP TRIGGER injected_failure',
      );
      await history.importHistory(pair.staff.session, pair.companyId, bytes);
      await history.importHistory(pair.staff.session, pair.companyId, bytes);
      expect(
        (await pair.staff.storage.repo.read(
          pair.companyId,
          pair.companyId,
        ))!.payload,
        before,
      );
      expect(
        (await pair.staff.storage.repo.snapshot(
          CompanyScope(pair.companyId),
        )).authorityHistory,
        hasLength(4),
      );
      final sibling = await child(pair, chain.first, SecureIds().next());
      await expectLater(
        history.importHistory(
          pair.staff.session,
          pair.companyId,
          AuthorityHistoryFile.batches(
            pair.companyId,
            pair.company.rootFingerprint,
            [sibling],
          ).single,
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.recoveryRequired,
          ),
        ),
      );
      final snap = await pair.staff.storage.repo.snapshot(
        CompanyScope(pair.companyId),
      );
      expect(snap.authorityHistory, hasLength(4));
      expect(
        snap.events.where((e) => e.kind == 'authorityConflict'),
        hasLength(1),
      );
    },
  );
  test(
    'new G3 staff requires consent plus complete staged history; unpinned import cannot establish trust',
    () async {
      final chain = await descendants(pair, 3);
      final original = await pair.manager.enrollment.createInvitation(
        pair.context('g0-invite'),
      );
      final values = [...original.payload.values]..[7] = chain.last.values;
      final invitation = await sign(pair, MessageKind.invitation, values);
      final history = LocalAuthorityHistoryService(
        repository: pair.staff.storage.repo,
        identity: pair.staff.identity,
        keys: pair.staff.storage.keys,
        ids: SecureIds(),
      );
      final bytes = AuthorityHistoryFile.batches(
        pair.companyId,
        pair.company.rootFingerprint,
        chain,
      ).single;
      await expectLater(
        history.importHistory(pair.staff.session, pair.companyId, bytes),
        throwsA(isA<CheckException>()),
      );
      final service = pair.staff.enrollment as InvitationHistoryService;
      final draft = await service.beginInvitation(
        pair.staff.session,
        MessageCodec().encode(invitation),
        acceptedRootFingerprint: pair.company.rootFingerprint,
      );
      await expectLater(
        service.finishInvitation(pair.staff.session, draft),
        throwsA(isA<CheckException>()),
      );
      expect(
        await pair.staff.storage.keys.read('vault:${pair.companyId}'),
        isNull,
      );
      await service.stageHistory(pair.staff.session, draft, bytes);
      await pair.staff.storage.failBeforeCommit();
      await expectLater(
        service.finishInvitation(pair.staff.session, draft),
        throwsA(isA<CheckException>()),
      );
      expect(
        await pair.staff.storage.repo.read(
          pair.companyId,
          'enrollment-trust:${pair.staff.identity.requireActor(pair.staff.session).personId}',
        ),
        isNull,
      );
      expect(
        await pair.staff.storage.repo.listRecords(pair.companyId, 'authority'),
        isEmpty,
      );
      await pair.staff.storage.database.customStatement(
        'DROP TRIGGER injected_failure',
      );
      final accepted = await service.finishInvitation(
        pair.staff.session,
        draft,
      );
      expect(accepted.message.payload.messageId, invitation.payload.messageId);
      expect(await pair.staff.canIssueAttendance(pair.companyId), isFalse);
      expect(
        (await pair.staff.storage.repo.snapshot(
          CompanyScope(pair.companyId),
        )).authorityHistory,
        hasLength(4),
      );
      expect(
        (await pair.staff.enrollment.requestJoin(
          pair.staff.session,
          accepted,
          SecureIds().next(),
        )).kind,
        MessageKind.joinRequest,
      );
    },
  );
  test(
    'returning G0 staff uses a verified G3 workplace without rewriting the historical membership credential or manager company',
    () async {
      final enrollment = await pair.enrollStaff();
      final chain = await descendants(pair, 3);
      final history = LocalAuthorityHistoryService(
        repository: pair.staff.storage.repo,
        identity: pair.staff.identity,
        keys: pair.staff.storage.keys,
        ids: SecureIds(),
      );
      await history.importHistory(
        pair.staff.session,
        pair.companyId,
        AuthorityHistoryFile.batches(
          pair.companyId,
          pair.company.rootFingerprint,
          chain,
        ).single,
      );
      final message = await sign(pair, MessageKind.workplace, [
        pair.companyId,
        SecureIds().next(),
        pair.manager.clock.nowUtc().millisecondsSinceEpoch,
        pair.company.workplaceId,
        SecureIds().next(),
        chain.last.values,
      ]);
      final verified = await pair.staff.capture.verifyWorkplace(
        pair.staff.session,
        pair.companyId,
        MessageCodec().encode(message),
      );
      final draft = await pair.staff.capture.beginDraft(
        pair.staff.session,
        pair.companyId,
        verified,
        PunchKind.checkIn,
      );
      final receipt = await pair.staff.capture.recordPunch(
        draft.context(pair.staff.session),
        verified,
        PunchKind.checkIn,
      );
      expect(receipt, isA<Committed<AttendanceReceipt>>());
      final original = MessageCodec().decode(
        (receipt as Committed<AttendanceReceipt>).value.bytes,
        maxBytes: MessageLimits.fileBytes,
      );
      expect(
        original.payload.field<String>('membershipAuthorityGenerationId'),
        pair.company.authorityGenerationId,
      );
      expect(
        (await pair.staff.storage.repo.read(
          pair.companyId,
          'credential:${enrollment.membership.id}:1',
        ))!.revision,
        1,
      );
      expect(
        Company.fromJson(
          jsonDecode(
                utf8.decode(
                  (await pair.staff.storage.repo.read(
                    pair.companyId,
                    pair.companyId,
                  ))!.payload,
                ),
              )
              as Map<String, dynamic>,
        ).authorityGenerationId,
        pair.company.authorityGenerationId,
      );
    },
  );
  test(
    'G3 replacement preserves shared manager company and blocks its now known stale generation',
    () async {
      await pair.enrollStaff();
      final old = pair.staff.identity.requireActor(pair.staff.session);
      final membership = (await pair.staff.companies.membership(
        pair.staff.session,
        pair.companyId,
      ))!;
      final before = (await pair.manager.storage.repo.read(
        pair.companyId,
        pair.companyId,
      ))!.payload;
      final chain = await descendants(pair, 3);
      final invitation = await pair.manager.enrollment.createInvitation(
        pair.context('replacement-invite'),
      );
      final values = [...invitation.payload.values]..[7] = chain.last.values;
      final updated = await sign(pair, MessageKind.invitation, values);
      final onboarding = pair.manager.enrollment as InvitationHistoryService;
      final consent = await onboarding.beginInvitation(
        pair.manager.session,
        MessageCodec().encode(updated),
        acceptedRootFingerprint: pair.company.rootFingerprint,
      );
      await onboarding.stageHistory(
        pair.manager.session,
        consent,
        AuthorityHistoryFile.batches(
          pair.companyId,
          pair.company.rootFingerprint,
          chain,
        ).single,
      );
      final draft = await pair.manager.identity.stageRecoveryIdentity(
        pair.manager.session,
        companyId: pair.companyId,
        personId: old.personId,
        displayName: 'Staff',
        rootFingerprint: pair.company.rootFingerprint,
        passphrase: 'replacement passphrase',
      );
      await (pair.manager.enrollment as RecoveryInvitationService)
          .bindRecoveryInvitation(pair.manager.session, consent, draft);
      final replacement = LocalDeviceReplacementService(
        repository: pair.manager.storage.repo,
        identity: pair.manager.identity,
        keys: pair.manager.storage.keys,
        clock: pair.manager.clock,
        ids: SecureIds(),
      );
      final request = await replacement.createRequest(
        pair.manager.session,
        pair.companyId,
        membership.employeeId,
        candidate: draft,
      );
      final fresh = pair.manager.identity
          .requireRecoveryIdentity(pair.manager.session, draft)
          .profile;
      final grant = await sign(pair, MessageKind.membershipGrant, [
        pair.companyId,
        SecureIds().next(),
        pair.manager.clock.nowUtc().millisecondsSinceEpoch,
        request.payload.messageId,
        membership.id,
        membership.revision + 1,
        old.personId,
        membership.employeeId,
        fresh.installationId,
        base64UrlEncode(fresh.publicKey),
        pair.company.name,
        pair.company.timeZoneId,
        pair.company.workplaceId,
        chain.last.values,
      ]);
      final result = await replacement.accept(
        pair.manager.session,
        await replacement.verifyPendingGrant(
          pair.manager.session,
          MessageCodec().encode(grant),
          candidate: draft,
        ),
        candidate: draft,
      );
      expect(
        result,
        isA<Committed<Membership>>(),
        reason: result is Rejected<Membership> ? result.error.name : null,
      );
      expect(
        (await pair.manager.storage.repo.read(
          pair.companyId,
          pair.companyId,
        ))!.payload,
        before,
      );
      await expectLater(
        pair.manager.capture.createWorkplaceCode(
          pair.context('stale-workplace'),
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
        pair.manager.enrollment.createInvitation(pair.context('stale-manager')),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.recoveryRequired,
          ),
        ),
      );
    },
  );
  test(
    'candidate expires on lock and cancellation without creating a pin',
    () async {
      final original = await pair.manager.enrollment.createInvitation(
        pair.context('inv'),
      );
      final service = pair.staff.enrollment as InvitationHistoryService;
      final draft = await service.beginInvitation(
        pair.staff.session,
        MessageCodec().encode(original),
        acceptedRootFingerprint: pair.company.rootFingerprint,
      );
      service.cancelInvitation(draft);
      await expectLater(
        service.finishInvitation(pair.staff.session, draft),
        throwsA(isA<CheckException>()),
      );
      final second = await service.beginInvitation(
        pair.staff.session,
        MessageCodec().encode(original),
        acceptedRootFingerprint: pair.company.rootFingerprint,
      );
      pair.staff.identity.lock();
      await expectLater(
        service.finishInvitation(pair.staff.session, second),
        throwsA(isA<CheckException>()),
      );
      expect(
        await pair.staff.storage.keys.read('vault:${pair.companyId}'),
        isNull,
      );
    },
  );
}

Future<AuthorityCertificate> child(
  TwoDeviceFixture p,
  AuthorityCertificate parent,
  String id,
) async {
  final a = p.manager.identity.requireActor(p.manager.session);
  final values = <Object?>[
    id,
    parent.generationId,
    parent.sequence + 1,
    SecureIds().next(),
    base64UrlEncode(a.publicKey),
    p.manager.clock.nowUtc().millisecondsSinceEpoch,
  ];
  final signature = await LocalKeyService(p.manager.storage.keys).sign(
    Uint8List.fromList(
      utf8.encode('RAZE_CHECK_AUTHORITY_V1\n${jsonEncode(values)}'),
    ),
    'company-root:${p.companyId}',
  );
  return AuthorityCertificate([...values, base64UrlEncode(signature)]);
}

Future<List<AuthorityCertificate>> descendants(
  TwoDeviceFixture p,
  int n,
) async {
  final chain = [AuthorityCertificate(p.company.authority)];
  for (var i = 0; i < n; i++) {
    chain.add(await child(p, chain.last, SecureIds().next()));
  }
  return chain;
}

Future<SignedMessage> sign(
  TwoDeviceFixture p,
  MessageKind kind,
  List<Object?> values,
) async {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(values)));
  final a = p.manager.identity.requireActor(p.manager.session);
  return SignedMessage(
    kind: kind,
    keyId: await messageKeyId(a.publicKey),
    payloadBytes: bytes,
    signature: await LocalKeyService(
      p.manager.storage.keys,
    ).sign(messageSigningBytes(kind, bytes), a.signingKeyId),
  );
}
