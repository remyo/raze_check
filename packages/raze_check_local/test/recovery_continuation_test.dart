@Timeout(Duration(minutes: 4))
library;

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';
import 'device_replacement_test.dart' show RecoveryFailWriter;

LocalDeviceReplacementService replacement(EnrollmentDevice d) =>
    LocalDeviceReplacementService(
      repository: d.storage.repo,
      identity: d.identity,
      keys: d.storage.keys,
      clock: d.clock,
      ids: SecureIds(),
    );
LocalArchiveService archive(EnrollmentDevice d) => LocalArchiveService(
  paths: d.storage.paths,
  keys: d.storage.keys,
  repository: d.storage.repo,
  identity: d.identity,
  clock: d.clock,
  ids: SecureIds(),
);
CommandContext context(EnrollmentDevice d, Company c, String op) =>
    CommandContext(
      companyId: c.id,
      session: d.session,
      operationId: op,
      authorityGenerationId: c.authorityGenerationId,
    );
Future<InvitationCandidate> consent(
  EnrollmentDevice source,
  EnrollmentDevice target,
  Company c,
) async {
  final invite = await source.enrollment.createInvitation(
    context(source, c, SecureIds().next()),
  );
  return (target.enrollment as InvitationHistoryService).beginInvitation(
    target.session,
    MessageCodec().encode(invite),
    acceptedRootFingerprint: c.rootFingerprint,
  );
}

Future<void> enroll(
  EnrollmentDevice source,
  EnrollmentDevice staff,
  Company c,
) async {
  final invite = await source.enrollment.createInvitation(
    context(source, c, 'invite-b'),
  );
  final verified = await staff.enrollment.acceptInvitation(
    staff.session,
    MessageCodec().encode(invite),
    acceptedRootFingerprint: c.rootFingerprint,
  );
  final request = await staff.enrollment.requestJoin(
    staff.session,
    verified,
    SecureIds().next(),
  );
  final grant =
      await source.enrollment.approveJoin(
            context(source, c, 'approve-b'),
            await source.enrollment.verifyIncoming(
              source.session,
              MessageCodec().encode(request),
            ),
          )
          as Committed<SignedMessage>;
  await staff.acceptGrantTwice(grant.value);
}

Future<void> recoverA(TwoDeviceFixture p, EnrollmentDevice target) async {
  final person = p.staff.identity.requireActor(p.staff.session).personId;
  final member = (await p.staff.companies.membership(
    p.staff.session,
    p.companyId,
  ))!;
  final root = await consent(p.manager, target, p.company);
  final draft = await target.identity.stageRecoveryIdentity(
    target.session,
    companyId: p.companyId,
    personId: person,
    displayName: 'Current local display',
    rootFingerprint: p.company.rootFingerprint,
    passphrase: 'new local passphrase',
  );
  await (target.enrollment as RecoveryInvitationService).bindRecoveryInvitation(
    target.session,
    root,
    draft,
  );
  final request = await replacement(target).createRequest(
    target.session,
    p.companyId,
    member.employeeId,
    candidate: draft,
  );
  final verified = await p.manager.enrollment.verifyIncoming(
    p.manager.session,
    MessageCodec().encode(request),
  );
  final grant = await replacement(
    p.manager,
  ).authorize(p.context('recover-a'), verified);
  final outgoing = archive(p.manager);
  final descriptor = await outgoing.createStaffRecovery(
    p.context('export-a'),
    verified,
    grant,
    'staff archive passphrase',
  );
  final file = File('${target.storage.paths.root.path}/a.backup');
  await file.writeAsBytes(
    await outgoing.shareBytes(p.manager.session, descriptor.artifactId),
  );
  final incoming = archive(target);
  await incoming.applyRecoveryPersonal(
    target.session,
    await incoming.inspect(
      target.session,
      file.path,
      'staff archive passphrase',
    ),
    draft,
  );
  final result = await replacement(target).accept(
    target.session,
    await replacement(target).verifyPendingGrant(
      target.session,
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
  target.session = await target.identity.unlock(person, 'new local passphrase');
}

void main() {
  late TwoDeviceFixture pair;
  late EnrollmentDevice target;
  setUp(() async {
    pair = await TwoDeviceFixture.create();
    await pair.enrollStaff();
    target = await EnrollmentDevice.create(pair.manager.clock, 'Setup');
  });
  tearDown(() async {
    await target.storage.dispose();
    await pair.dispose();
  });
  test(
    'staff B continuation preserves A and keys across cancellation expiry catalog failure and authenticated resume',
    () async {
      final b =
          (await pair.manager.companies.createCompany(
                    pair.manager.session,
                    const CompanyDraft('Employer B', 'Asia/Tokyo'),
                    'create-b',
                  )
                  as Committed<Company>)
              .value;
      await enroll(pair.manager, pair.staff, b);
      final member = (await pair.staff.companies.membership(
        pair.staff.session,
        b.id,
      ))!;
      await recoverA(pair, target);
      final actor = target.identity.requireActor(target.session),
          managerPerson = pair.manager.identity
              .requireActor(pair.manager.session)
              .personId;
      final key = await target.storage.keys.read(actor.signingKeyId),
          credential = await target.storage.keys.read(
            'credential:${actor.personId}',
          );
      await expectLater(
        target.identity.stageRecoveryIdentity(
          target.session,
          companyId: b.id,
          personId: actor.personId,
          displayName: 'Unrelated overwrite',
          rootFingerprint: b.rootFingerprint,
          passphrase: 'another passphrase',
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.duplicateConflict,
          ),
        ),
      );
      final beforeA = (await target.storage.repo.read(
        pair.companyId,
        pair.companyId,
      ))!.payload;
      expect(await target.companies.readCompany(target.session, b.id), isNull);
      final canceled = await target.identity.continueRecoveryIdentity(
        target.session,
        companyId: b.id,
        rootFingerprint: b.rootFingerprint,
      );
      await target.identity.cancelRecoveryIdentity(target.session, canceled);
      expect(await target.storage.keys.read(actor.signingKeyId), key);
      await expectLater(
        replacement(target).createRequest(
          target.session,
          b.id,
          member.employeeId,
          candidate: canceled,
        ),
        throwsA(isA<CheckException>()),
      );
      final expired = await target.identity.continueRecoveryIdentity(
        target.session,
        companyId: b.id,
        rootFingerprint: b.rootFingerprint,
      );
      target.clock.advance(const Duration(minutes: 6));
      await expectLater(
        replacement(target).createRequest(
          target.session,
          b.id,
          member.employeeId,
          candidate: expired,
        ),
        throwsA(isA<CheckException>()),
      );
      target.session = await target.identity.unlock(
        actor.personId,
        'new local passphrase',
      );
      await target.identity.resumeRecoveryIdentities();
      expect(await target.storage.keys.read(actor.signingKeyId), key);
      pair.manager.session = await pair.manager.identity.unlock(
        managerPerson,
        'a strong local passphrase',
      );
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
      final root = await consent(pair.manager, target, b);
      final draft = await target.identity.continueRecoveryIdentity(
        target.session,
        companyId: b.id,
        rootFingerprint: b.rootFingerprint,
      );
      await (target.enrollment as RecoveryInvitationService)
          .bindRecoveryInvitation(target.session, root, draft);
      final c =
          (await target.companies.createCompany(
                    target.session,
                    const CompanyDraft('Concurrent legitimate C', 'Asia/Tokyo'),
                    'create-c',
                  )
                  as Committed<Company>)
              .value;
      final request = await replacement(target).createRequest(
        target.session,
        b.id,
        member.employeeId,
        candidate: draft,
      );
      final grant = await replacement(pair.manager).authorize(
        context(pair.manager, b, 'replace-b'),
        await pair.manager.enrollment.verifyIncoming(
          pair.manager.session,
          MessageCodec().encode(request),
        ),
      );
      final wrongFields = [...grant.payload.values]..[6] = SecureIds().next();
      final wrongGrant = SignedMessage(
        kind: grant.kind,
        keyId: grant.keyId,
        payloadBytes: Uint8List.fromList(utf8.encode(jsonEncode(wrongFields))),
        signature: grant.signature,
      );
      await expectLater(
        replacement(target).verifyPendingGrant(
          target.session,
          MessageCodec().encode(wrongGrant),
          candidate: draft,
        ),
        throwsA(isA<CheckException>()),
      );
      final returned = await replacement(target).verifyPendingGrant(
        target.session,
        MessageCodec().encode(grant),
        candidate: draft,
      );
      writer.fail = true;
      expect(
        await replacement(
          target,
        ).accept(target.session, returned, candidate: draft),
        isA<Rejected<Membership>>().having(
          (r) => r.error,
          'error',
          CheckError.storageFailure,
        ),
      );
      expect(await target.canIssueAttendance(pair.companyId), isTrue);
      expect(await target.canIssueAttendance(b.id), isFalse);
      writer.fail = false;
      target.identity.lock();
      target.session = await target.identity.unlock(
        actor.personId,
        'new local passphrase',
      );
      await target.identity.resumeRecoveryIdentities();
      expect(await target.canIssueAttendance(b.id), isTrue);
      expect(
        await target.companies.readCompany(target.session, c.id),
        isNotNull,
      );
      expect(await target.canIssueAttendance(pair.companyId), isTrue);
      expect(await target.storage.keys.read(actor.signingKeyId), key);
      expect(
        await target.storage.keys.read('credential:${actor.personId}'),
        credential,
      );
      expect(
        (await target.storage.repo.read(
          pair.companyId,
          pair.companyId,
        ))!.payload,
        beforeA,
      );
      expect(
        target.identity.requireActor(target.session).installationId,
        actor.installationId,
      );
    },
  );
  test(
    'manager-only recovered A can continue original owned B from its company archive without replacing display identity',
    () async {
      final b =
          (await pair.staff.companies.createCompany(
                    pair.staff.session,
                    const CompanyDraft('Owned B', 'Asia/Tokyo'),
                    'own-b',
                  )
                  as Committed<Company>)
              .value;
      final outgoing = archive(pair.staff);
      final descriptor = await outgoing.create(
        pair.staff.session,
        CompanyScope(b.id),
        'company archive passphrase',
      );
      final file = File('${target.storage.paths.root.path}/b.backup');
      await file.writeAsBytes(
        await outgoing.shareBytes(pair.staff.session, descriptor.artifactId),
      );
      await recoverA(pair, target);
      final actor = target.identity.requireActor(target.session),
          key = await target.storage.keys.read(
            target.identity.requireActor(target.session).signingKeyId,
          );
      final incoming = archive(target);
      var draft = await target.identity.continueRecoveryIdentity(
        target.session,
        companyId: b.id,
        rootFingerprint: b.rootFingerprint,
      );
      await target.identity.cancelRecoveryIdentity(target.session, draft);
      final wrongRoot = await target.identity.continueRecoveryIdentity(
        target.session,
        companyId: b.id,
        rootFingerprint: '0' * 64,
      );
      final preview = await incoming.inspect(
        target.session,
        file.path,
        'company archive passphrase',
      );
      final service = LocalHandoverService(
        repository: target.storage.repo,
        identity: target.identity,
        keys: target.storage.keys,
        clock: target.clock,
        ids: SecureIds(),
        archives: incoming,
      );
      await expectLater(
        service.recover(
          target.session,
          preview,
          RecoveryAcknowledgment(
            manifestId: preview.manifestId,
            manifestSha256Base64Url: preview.manifestSha256Base64Url,
            acceptsMissingData: true,
          ),
          candidate: wrongRoot,
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.invalidSignature,
          ),
        ),
      );
      await target.identity.cancelRecoveryIdentity(target.session, wrongRoot);
      draft = await target.identity.continueRecoveryIdentity(
        target.session,
        companyId: b.id,
        rootFingerprint: b.rootFingerprint,
      );
      await expectLater(
        service.recover(
          target.session,
          preview,
          RecoveryAcknowledgment(
            manifestId: 'wrong',
            manifestSha256Base64Url: preview.manifestSha256Base64Url,
            acceptsMissingData: true,
          ),
          candidate: draft,
        ),
        throwsA(isA<CheckException>()),
      );
      expect(await target.companies.readCompany(target.session, b.id), isNull);
      await service.recover(
        target.session,
        preview,
        RecoveryAcknowledgment(
          manifestId: preview.manifestId,
          manifestSha256Base64Url: preview.manifestSha256Base64Url,
          acceptsMissingData: true,
        ),
        candidate: draft,
      );
      target.session = await target.identity.unlock(
        actor.personId,
        'new local passphrase',
      );
      expect(await target.canIssueAttendance(pair.companyId), isTrue);
      expect(await target.canIssueAttendance(b.id), isTrue);
      expect(
        (await target.companies.membership(target.session, b.id))!.owner,
        isTrue,
      );
      expect(
        target.identity.requireActor(target.session).installationId,
        actor.installationId,
      );
      expect(await target.storage.keys.read(actor.signingKeyId), key);
      expect(
        (await target.identity.profiles())
            .singleWhere((p) => p.personId == actor.personId)
            .displayName,
        'Current local display',
      );
    },
  );
}
