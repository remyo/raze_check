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
    'company owner attendance uses the current local authority installation',
    () async {
      expect(await pair.manager.canIssueAttendance(pair.companyId), isTrue);
    },
  );
  test(
    'offline approval and grant retries create exactly one employee and membership',
    () async {
      final companyId = pair.companyId;
      expect(await pair.staff.canIssueAttendance(companyId), isFalse);
      final grant = await pair.approveSameJoinTwice();
      expect(await pair.manager.employeeCount(companyId), 1);
      expect(await pair.staff.canIssueAttendance(companyId), isFalse);
      await pair.staff.acceptGrantTwice(grant);
      expect(await pair.staff.membershipCount(companyId), 1);
      expect(await pair.staff.canIssueAttendance(companyId), isTrue);
      final member = (await pair.staff.companies.membership(
        pair.staff.session,
        companyId,
      ))!;
      expect(member.owner, isFalse);
      expect(member.capabilities, isEmpty);
      final personal = await pair.staff.storage.repo.snapshot(
        PersonalScope(member.personId),
      );
      expect(personal.recovery, isEmpty);
      expect(
        personal.records.where((r) => r.kind == 'membership'),
        hasLength(1),
      );
    },
  );
  test(
    'second local profile accepts grant in shared company without replacing public state',
    () async {
      await pair.enrollStaff();
      final firstPerson = pair.staff.identity
          .requireActor(pair.staff.session)
          .personId;
      final companyBefore = (await pair.staff.storage.repo.read(
        pair.companyId,
        pair.companyId,
      ))!;
      final authorityBefore = (await pair.staff.storage.repo.read(
        pair.companyId,
        pair.company.authorityGenerationId,
      ))!;
      pair.staff.session = await pair.staff.identity.createProfile(
        'Second staff',
        'a strong local passphrase',
      );
      final secondPerson = pair.staff.identity
          .requireActor(pair.staff.session)
          .personId;
      final request = await pair.join();
      final grant =
          (await pair.manager.enrollment.approveJoin(
                    pair.context('approve-second'),
                    request,
                  )
                  as Committed<SignedMessage>)
              .value;
      final verified = await pair.staff.enrollment.verifyIncoming(
        pair.staff.session,
        MessageCodec().encode(grant),
      );
      expect(
        await pair.staff.enrollment.acceptGrant(pair.staff.session, verified),
        isA<Committed<Membership>>(),
      );
      expect(
        (await pair.staff.enrollment.acceptGrant(pair.staff.session, verified)
                as Committed<Membership>)
            .duplicate,
        isTrue,
      );
      expect(await pair.staff.membershipCount(pair.companyId), 2);
      expect(
        (await pair.staff.storage.repo.read(
          pair.companyId,
          pair.companyId,
        ))!.payload,
        companyBefore.payload,
      );
      expect(
        (await pair.staff.storage.repo.read(
          pair.companyId,
          pair.company.authorityGenerationId,
        ))!.payload,
        authorityBefore.payload,
      );
      expect(await pair.staff.canIssueAttendance(pair.companyId), isTrue);
      pair.staff.session = await pair.staff.identity.unlock(
        firstPerson,
        'a strong local passphrase',
      );
      expect(await pair.staff.canIssueAttendance(pair.companyId), isTrue);
      pair.staff.session = await pair.staff.identity.unlock(
        secondPerson,
        'a strong local passphrase',
      );
      final member = (await pair.staff.companies.membership(
        pair.staff.session,
        pair.companyId,
      ))!;
      expect(member.personId, secondPerson);
      expect(member.owner, isFalse);
      expect(member.capabilities, isEmpty);
      final ownScope = await pair.staff.storage.repo.snapshot(
        PersonalScope(secondPerson),
      );
      expect(
        ownScope.records.where((r) => r.kind == 'membership'),
        hasLength(1),
      );
      expect(ownScope.authorityHistory, hasLength(1));
      // Authenticated conflicting shared metadata must block completed replay too.
      final conflicting =
          jsonDecode(utf8.decode(companyBefore.payload))
              as Map<String, dynamic>;
      conflicting['workplaceId'] = SecureIds().next();
      final conflictRow = StoredRecord(
        pair.companyId,
        pair.companyId,
        'company',
        companyBefore.revision + 1,
        Uint8List.fromList(utf8.encode(jsonEncode(conflicting))),
      );
      await pair.staff.storage.repo.commit(
        CommandContext(
          companyId: pair.companyId,
          session: pair.staff.session,
          operationId: 'inject-company-conflict',
          authorityGenerationId: pair.company.authorityGenerationId,
        ),
        requestDigest: Uint8List(32),
        build: (_) async => Mutation([conflictRow], [], [], conflictRow),
      );
      expect(
        (await pair.staff.enrollment.acceptGrant(pair.staff.session, verified)
                as Rejected<Membership>)
            .error,
        CheckError.recoveryRequired,
      );
      expect(
        (await pair.staff.storage.repo.read(
          pair.companyId,
          pair.companyId,
        ))!.payload,
        conflictRow.payload,
      );
    },
  );
  test(
    'same repository manager staff exchange reuses approved records and preserves owner authority',
    () async {
      final device = pair.manager;
      final ownerPerson = device.identity.requireActor(device.session).personId;
      final invitation = await device.enrollment.createInvitation(
        pair.context('local-invite'),
      );
      final companyBefore = (await device.storage.repo.read(
        pair.companyId,
        pair.companyId,
      ))!;
      final staffSession = await device.identity.createProfile(
        'On-device staff',
        'a strong local passphrase',
      );
      final staffPerson = device.identity.requireActor(staffSession).personId;
      final acceptedInvitation = await device.enrollment.acceptInvitation(
        staffSession,
        MessageCodec().encode(invitation),
        acceptedRootFingerprint: pair.company.rootFingerprint,
      );
      final join = await device.enrollment.requestJoin(
        staffSession,
        acceptedInvitation,
        SecureIds().next(),
      );
      device.session = await device.identity.unlock(
        ownerPerson,
        'a strong local passphrase',
      );
      final request = await device.enrollment.verifyIncoming(
        device.session,
        MessageCodec().encode(join),
      );
      final grant =
          (await device.enrollment.approveJoin(
                    pair.context('approve-local'),
                    request,
                  )
                  as Committed<SignedMessage>)
              .value;
      final approved = await device.storage.repo.snapshot(
        CompanyScope(pair.companyId),
      );
      final approvedMember = approved.records.singleWhere(
        (r) => r.id == grant.payload.field<String>('membershipId'),
      );
      final approvedStaff = approved.records.singleWhere(
        (r) => r.id == grant.payload.field<String>('employeeId'),
      );
      device.session = await device.identity.unlock(
        staffPerson,
        'a strong local passphrase',
      );
      final verified = await device.enrollment.verifyIncoming(
        device.session,
        MessageCodec().encode(grant),
      );
      expect(
        await device.enrollment.acceptGrant(device.session, verified),
        isA<Committed<Membership>>(),
      );
      expect(
        (await device.enrollment.acceptGrant(device.session, verified)
                as Committed<Membership>)
            .duplicate,
        isTrue,
      );
      expect(await device.membershipCount(pair.companyId), 2);
      expect(await device.canIssueAttendance(pair.companyId), isTrue);
      expect(
        (await device.storage.repo.read(
          pair.companyId,
          approvedMember.id,
        ))!.payload,
        approvedMember.payload,
      );
      expect(
        (await device.storage.repo.read(
          pair.companyId,
          approvedStaff.id,
        ))!.payload,
        approvedStaff.payload,
      );
      expect(
        (await device.storage.repo.read(
          pair.companyId,
          pair.companyId,
        ))!.payload,
        companyBefore.payload,
      );
      device.session = await device.identity.unlock(
        ownerPerson,
        'a strong local passphrase',
      );
      final ownerCompany = (await device.companies.readCompany(
        device.session,
        pair.companyId,
      ))!;
      expect(
        ownerCompany.authoritySigningKeyId,
        pair.company.authoritySigningKeyId,
      );
      expect(ownerCompany.creationPersonId, pair.company.creationPersonId);
      expect(
        ownerCompany.creationOperationId,
        pair.company.creationOperationId,
      );
      expect(ownerCompany.creationDigest, pair.company.creationDigest);
      expect(await device.canIssueAttendance(pair.companyId), isTrue);
      expect(
        await device.companies.listMemberships(device.session, pair.companyId),
        hasLength(2),
      );
      expect(
        (await device.enrollment.createInvitation(
          pair.context('local-invite-after-grant'),
        )).kind,
        MessageKind.invitation,
      );
    },
  );
  test(
    'explicit fingerprint acceptance and signature validation precede durable trust',
    () async {
      final message = await pair.manager.enrollment.createInvitation(
        pair.context('invite'),
      );
      await expectLater(
        pair.staff.enrollment.acceptInvitation(
          pair.staff.session,
          MessageCodec().encode(message),
          acceptedRootFingerprint: 'wrong',
        ),
        throwsCheck(CheckError.unauthorized),
      );
      expect(
        await pair.staff.storage.keys.read('vault:${pair.companyId}'),
        isNull,
      );
      final forged = SignedMessage(
        kind: message.kind,
        keyId: message.keyId,
        payloadBytes: message.payloadBytes,
        signature: Uint8List(64),
      );
      await expectLater(
        pair.staff.enrollment.acceptInvitation(
          pair.staff.session,
          MessageCodec().encode(forged),
          acceptedRootFingerprint: pair.company.rootFingerprint,
        ),
        throwsCheck(CheckError.invalidSignature),
      );
      expect(
        await pair.staff.storage.keys.read('vault:${pair.companyId}'),
        isNull,
      );
    },
  );
  test(
    'unapproved requests cannot act and wrong invitation kind is rejected',
    () async {
      final join = await pair.join();
      expect(await pair.staff.canIssueAttendance(pair.companyId), isFalse);
      await expectLater(
        pair.staff.enrollment.requestJoin(
          pair.staff.session,
          join,
          SecureIds().next(),
        ),
        throwsCheck(CheckError.malformed),
      );
      expect(
        (await pair.staff.enrollment.acceptGrant(pair.staff.session, join)
                as Rejected<Membership>)
            .error,
        CheckError.malformed,
      );
    },
  );
  test(
    'altered replay is rejected even with a new approval operation',
    () async {
      final request = await pair.join();
      expect(
        await pair.manager.enrollment.approveJoin(
          pair.context('approve'),
          request,
        ),
        isA<Committed<SignedMessage>>(),
      );
      final altered = request.message.payload.values.toList();
      altered[5] = 'Changed name';
      final signed = await signAsStaff(pair, MessageKind.joinRequest, altered);
      final verified = await pair.manager.enrollment.verifyIncoming(
        pair.manager.session,
        MessageCodec().encode(signed),
      );
      expect(
        (await pair.manager.enrollment.approveJoin(
                  pair.context('other-op'),
                  verified,
                )
                as Rejected<SignedMessage>)
            .error,
        CheckError.duplicateConflict,
      );
      expect(await pair.manager.employeeCount(pair.companyId), 1);
    },
  );
  test(
    'join QR extension attempting admin capabilities is malformed',
    () async {
      final request = await pair.join();
      final decoded =
          jsonDecode(utf8.decode(MessageCodec().encode(request.message)))
              as List;
      final payload = [
        ...request.message.payload.values,
        ['manageCompany'],
      ];
      decoded[3] = base64UrlEncode(utf8.encode(jsonEncode(payload)));
      await expectLater(
        pair.manager.enrollment.verifyIncoming(
          pair.manager.session,
          Uint8List.fromList(utf8.encode(jsonEncode(decoded))),
        ),
        throwsA(isA<CheckException>()),
      );
      expect(await pair.manager.employeeCount(pair.companyId), 0);
    },
  );
  test(
    'same-name manual staff stay separate until the owner explicitly links a request',
    () async {
      final manual =
          (await pair.manager.companies.createStaff(
                    pair.context('manual'),
                    const StaffDraft(name: 'Staff'),
                  )
                  as Committed<StaffRecord>)
              .value;
      final request = await pair.join();
      final grant =
          await pair.manager.enrollment.approveJoin(
                pair.context('link'),
                request,
                existingEmployeeId: manual.employeeId,
              )
              as Committed<SignedMessage>;
      expect(
        grant.value.payload.field<String>('employeeId'),
        manual.employeeId,
      );
      expect(
        grant.value.payload.field<String>('membershipId'),
        manual.membershipId,
      );
      expect(await pair.manager.employeeCount(pair.companyId), 1);
      final replay =
          await pair.manager.enrollment.approveJoin(
                pair.context('link'),
                request,
                existingEmployeeId: manual.employeeId,
              )
              as Committed<SignedMessage>;
      expect(replay.duplicate, isTrue);
      final oldScope = await pair.manager.storage.repo.snapshot(
        PersonalScope(manual.personId),
      );
      expect(oldScope.records, isEmpty);
      final newScope = await pair.manager.storage.repo.snapshot(
        PersonalScope(request.message.payload.field<String>('personId')),
      );
      expect(
        newScope.records.where((r) => r.id == manual.employeeId),
        hasLength(1),
      );
      await pair.staff.acceptGrantTwice(grant.value);
      expect(await pair.staff.canIssueAttendance(pair.companyId), isTrue);
    },
  );
  test('name matching never merges independently requested staff', () async {
    await pair.manager.companies.createStaff(
      pair.context('manual'),
      const StaffDraft(name: 'Staff'),
    );
    await pair.approveSameJoinTwice();
    expect(await pair.manager.employeeCount(pair.companyId), 2);
  });
  test(
    'reopened repositories retain exact request, approval and grant replay results',
    () async {
      final invitation = await pair.invitation();
      final op = SecureIds().next();
      final request = await pair.staff.enrollment.requestJoin(
        pair.staff.session,
        invitation,
        op,
      );
      final verified = await pair.manager.enrollment.verifyIncoming(
        pair.manager.session,
        MessageCodec().encode(request),
      );
      final granted =
          await pair.manager.enrollment.approveJoin(
                pair.context('approve'),
                verified,
              )
              as Committed<SignedMessage>;
      await pair.staff.acceptGrantTwice(granted.value);
      await pair.manager.storage.reopen();
      await pair.staff.storage.reopen();
      pair.manager.rebuildServices();
      pair.staff.rebuildServices();
      final replay =
          await pair.manager.enrollment.approveJoin(
                pair.context('approve'),
                verified,
              )
              as Committed<SignedMessage>;
      expect(
        MessageCodec().encode(replay.value),
        MessageCodec().encode(granted.value),
      );
      await pair.staff.acceptGrantTwice(replay.value);
      expect(await pair.staff.membershipCount(pair.companyId), 1);
    },
  );
  test(
    'expired approval context and grant handle reject fresh and replay commands',
    () async {
      final grant = await pair.approveSameJoinTwice();
      final verified = await pair.staff.enrollment.verifyIncoming(
        pair.staff.session,
        MessageCodec().encode(grant),
      );
      expect(
        await pair.staff.enrollment.acceptGrant(pair.staff.session, verified),
        isA<Committed<Membership>>(),
      );
      final request = await pair.manager.enrollment.verifyIncoming(
        pair.manager.session,
        MessageCodec().encode(
          (await pair.manager.storage.repo.snapshot(
                CompanyScope(pair.companyId),
              )).events
              .where((r) => r.kind == 'enrollmentApproval')
              .map(
                (r) => MessageCodec().decode(
                  r.payload,
                  maxBytes: MessageLimits.fileBytes,
                ),
              )
              .single,
        ),
      );
      pair.manager.clock.advance(const Duration(minutes: 5));
      expect(
        (await pair.manager.enrollment.approveJoin(
                  pair.context('approve'),
                  request,
                )
                as Rejected<SignedMessage>)
            .error,
        CheckError.locked,
      );
      expect(
        (await pair.staff.enrollment.acceptGrant(pair.staff.session, verified)
                as Rejected<Membership>)
            .error,
        CheckError.locked,
      );
    },
  );
  test(
    'losing the original session during grant encryption rolls back membership',
    () async {
      final grant = await pair.approveSameJoinTwice();
      final verified = await pair.staff.enrollment.verifyIncoming(
        pair.staff.session,
        MessageCodec().encode(grant),
      );
      final before = await pair.staff.storage.repo
          .watchRevision(pair.companyId)
          .first;
      final guarded = LocalEnrollmentService(
        repository: LocalCheckRepository(
          database: pair.staff.storage.database,
          cipher: LockOnSeal(
            AesPayloadCipher(VaultKeys(pair.staff.storage.keys)),
            pair.staff.identity.lock,
          ),
        ),
        identity: pair.staff.identity,
        keys: pair.staff.storage.keys,
        clock: pair.staff.clock,
        ids: SecureIds(),
      );
      final result = await guarded.acceptGrant(pair.staff.session, verified);
      expect((result as Rejected<Membership>).error, CheckError.locked);
      expect(
        await pair.staff.storage.repo.watchRevision(pair.companyId).first,
        before,
      );
      expect(await pair.staff.membershipCount(pair.companyId), 0);
    },
  );
  test(
    'forged grant and authentic grant for a different installation never activate staff',
    () async {
      final grant = await pair.approveSameJoinTwice();
      final forged = SignedMessage(
        kind: grant.kind,
        keyId: grant.keyId,
        payloadBytes: grant.payloadBytes,
        signature: Uint8List(64),
      );
      await expectLater(
        pair.staff.enrollment.verifyIncoming(
          pair.staff.session,
          MessageCodec().encode(forged),
        ),
        throwsCheck(CheckError.invalidSignature),
      );
      final actor = pair.staff.identity.requireActor(pair.staff.session);
      final values = grant.payload.values.toList();
      values[8] = SecureIds().next();
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(values)));
      final changed = SignedMessage(
        kind: MessageKind.membershipGrant,
        keyId: grant.keyId,
        payloadBytes: bytes,
        signature: await LocalKeyService(pair.manager.storage.keys).sign(
          messageSigningBytes(MessageKind.membershipGrant, bytes),
          pair.company.authoritySigningKeyId,
        ),
      );
      final verified = await pair.staff.enrollment.verifyIncoming(
        pair.staff.session,
        MessageCodec().encode(changed),
      );
      expect(
        (await pair.staff.enrollment.acceptGrant(pair.staff.session, verified)
                as Rejected<Membership>)
            .error,
        CheckError.unauthorized,
      );
      expect(await pair.staff.canIssueAttendance(pair.companyId), isFalse);
      expect(actor.personId, isNotEmpty);
    },
  );
}

Matcher throwsCheck(CheckError code) =>
    throwsA(isA<CheckException>().having((e) => e.code, 'code', code));
Future<SignedMessage> signAsStaff(
  TwoDeviceFixture pair,
  MessageKind kind,
  List<Object?> values,
) async {
  final actor = pair.staff.identity.requireActor(pair.staff.session);
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(values)));
  return SignedMessage(
    kind: kind,
    keyId: await messageKeyId(actor.publicKey),
    payloadBytes: bytes,
    signature: await LocalKeyService(
      pair.staff.storage.keys,
    ).sign(messageSigningBytes(kind, bytes), actor.signingKeyId),
  );
}

final class LockOnSeal implements PayloadCipher {
  LockOnSeal(this.delegate, this.lock);
  final PayloadCipher delegate;
  final void Function() lock;
  bool locked = false;
  @override
  Future<Uint8List> seal({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List plain,
  }) async {
    if (!locked) {
      locked = true;
      lock();
    }
    return delegate.seal(
      scopeId: scopeId,
      recordId: recordId,
      revision: revision,
      plain: plain,
    );
  }

  @override
  Future<Uint8List> open({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List sealed,
  }) => delegate.open(
    scopeId: scopeId,
    recordId: recordId,
    revision: revision,
    sealed: sealed,
  );
}
