@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';
import 'receipt_import_test.dart' show service;

Future<SignedMessage> resign(
  EnrollmentDevice d,
  SignedMessage original,
  List<Object?> values, {
  Company? issuer,
}) async {
  final actor = d.identity.requireActor(d.session);
  final payload = Uint8List.fromList(
    utf8.encode(jsonEncode(MessagePayload(original.kind, values).values)),
  );
  return SignedMessage(
    kind: original.kind,
    keyId: await messageKeyId(
      issuer == null
          ? actor.publicKey
          : AuthorityCertificate(issuer.authority).publicKey,
    ),
    payloadBytes: payload,
    signature: await LocalKeyService(d.storage.keys).sign(
      messageSigningBytes(original.kind, payload),
      issuer?.authoritySigningKeyId ?? actor.signingKeyId,
    ),
  );
}

void main() {
  test(
    'conflicting receipt ID rejected, new probable duplicate retained, future clock flagged',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final r = await p.captureCheckIn(), m = service(p.manager);
      final v = await m.verifyIncoming(p.manager.session, p.companyId, r.bytes);
      await m.importReceipt(p.context('receive'), v);
      final changed = List<Object?>.of(r.message.payload.values)
        ..[9] = r.claimedUtcMs + 300001;
      final conflict = await resign(p.staff, r.message, changed);
      final result = await m.importReceipt(
        p.context('conflict'),
        await m.verifyIncoming(
          p.manager.session,
          p.companyId,
          MessageCodec().encode(conflict),
        ),
      );
      expect(result.error, CheckError.duplicateConflict);
      changed[1] = SecureIds().next();
      final future = await resign(p.staff, r.message, changed);
      final futureResult = await m.importReceipt(
        p.context('future'),
        await m.verifyIncoming(
          p.manager.session,
          p.companyId,
          MessageCodec().encode(future),
        ),
      );
      expect(futureResult.status, ImportStatus.needsReview);
      final futureState = await m.get(
        p.manager.session,
        p.companyId,
        future.payload.messageId,
      );
      expect(futureState.flags, contains('clockAnomaly'));
      expect(futureState.claimedUtcMs, r.claimedUtcMs + 300001);
      expect(futureState.receivedUtcMs, r.claimedUtcMs);
      changed[1] = SecureIds().next();
      changed[9] = r.claimedUtcMs + 1;
      final duplicate = await resign(p.staff, r.message, changed);
      final dup = await m.importReceipt(
        p.context('probable'),
        await m.verifyIncoming(
          p.manager.session,
          p.companyId,
          MessageCodec().encode(duplicate),
        ),
      );
      expect(dup.status, ImportStatus.needsReview);
      expect(
        (await m.get(p.manager.session, p.companyId, dup.eventId)).flags,
        contains('possibleDuplicate'),
      );
      expect(
        (await p.manager.storage.repo.read(p.companyId, r.eventId))!.payload,
        orderedEquals(r.bytes),
      );
    },
  );
  test(
    'revoked historical receipt is received for review; unknown key cannot issue',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final enrolled = await p.enrollStaff();
      final r = await p.captureCheckIn(), m = service(p.manager);
      await p.manager.companies.deactivateStaff(
        p.context('deactivate'),
        enrolled.membership.employeeId,
        'Left',
      );
      final v = await m.verifyIncoming(p.manager.session, p.companyId, r.bytes);
      expect(v.historicalCredential, isTrue);
      final result = await m.importReceipt(p.context('historical'), v);
      expect(result.status, ImportStatus.needsReview);
      expect(
        (await m.get(p.manager.session, p.companyId, r.eventId)).review,
        ReviewStatus.pending,
      );
      final unknown = await resign(
        p.manager,
        r.message,
        r.message.payload.values,
      );
      await expectLater(
        m.verifyIncoming(
          p.manager.session,
          p.companyId,
          MessageCodec().encode(unknown),
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.unauthorized,
          ),
        ),
      );
    },
  );
  test(
    'fresh and replay authorization, stale revision and selected wrong company',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final r = await p.captureCheckIn(),
          m = service(p.manager),
          s = service(p.staff);
      await m.importReceipt(
        p.context('receive'),
        await m.verifyIncoming(p.manager.session, p.companyId, r.bytes),
      );
      final staffContext = CommandContext(
        companyId: p.companyId,
        session: p.staff.session,
        operationId: 'illegal',
        authorityGenerationId: p.company.authorityGenerationId,
      );
      expect(
        (await s.decide(
                  staffContext,
                  r.eventId,
                  ReviewDecision.approve,
                  'Not permitted',
                )
                as Rejected)
            .error,
        CheckError.unauthorized,
      );
      expect(
        await m.decide(
          CommandContext(
            companyId: p.companyId,
            session: p.manager.session,
            operationId: 'stale',
            authorityGenerationId: p.company.authorityGenerationId,
            expectedRevision: 0,
          ),
          r.eventId,
          ReviewDecision.approve,
          'Checked',
        ),
        isA<VersionConflict<DecisionRecord>>(),
      );
      final other =
          (await p.manager.companies.createCompany(
                    p.manager.session,
                    const CompanyDraft('Other', 'Asia/Tokyo'),
                    'other',
                  )
                  as Committed<Company>)
              .value;
      final wrong = CommandContext(
        companyId: other.id,
        session: p.manager.session,
        operationId: 'wrong',
        authorityGenerationId: other.authorityGenerationId,
      );
      final verified = await m.verifyIncoming(
        p.manager.session,
        p.companyId,
        r.bytes,
      );
      expect(
        (await m.importReceipt(wrong, verified)).error,
        CheckError.wrongCompany,
      );
      await m.decide(
        p.context('decision'),
        r.eventId,
        ReviewDecision.approve,
        'Checked',
      );
      p.manager.identity.lock();
      expect(
        (await m.decide(
                  p.context('decision'),
                  r.eventId,
                  ReviewDecision.approve,
                  'Checked',
                )
                as Rejected)
            .error,
        CheckError.locked,
      );
    },
  );
  test(
    'owner same repository import reuses receipt/event/outbox and saves credential history',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final m = service(p.manager);
      final code = await p.manager.capture.createWorkplaceCode(
        p.context('code'),
      );
      final verified = await p.manager.capture.verifyWorkplace(
        p.manager.session,
        p.companyId,
        MessageCodec().encode(code),
      );
      final draft = await p.manager.capture.beginDraft(
        p.manager.session,
        p.companyId,
        verified,
        PunchKind.checkIn,
      );
      final r =
          (await p.manager.capture.recordPunch(
                    draft.context(p.manager.session),
                    verified,
                    PunchKind.checkIn,
                  )
                  as Committed<AttendanceReceipt>)
              .value;
      final outbox = (await p.manager.storage.repo.read(
        p.companyId,
        'outbox:${r.eventId}',
      ))!;
      final received = await m.importReceipt(
        p.context('owner-import'),
        await m.verifyIncoming(p.manager.session, p.companyId, r.bytes),
      );
      expect(received.status, ImportStatus.received);
      expect(
        (await p.manager.storage.repo.read(
          p.companyId,
          'outbox:${r.eventId}',
        ))!.payload,
        orderedEquals(outbox.payload),
      );
      expect(
        (await p.manager.storage.repo.read(p.companyId, r.eventId))!.payload,
        orderedEquals(r.bytes),
      );
      final snap = await p.manager.storage.repo.snapshot(
        CompanyScope(p.companyId),
      );
      expect(
        snap.records.where((r) => r.kind == 'trustedCredential').length,
        1,
      );
    },
  );
  test(
    'manual before enrollment transfers only explicitly linked employee history and removes placeholder export',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final m = service(p.manager);
      final staff =
          (await p.manager.companies.createStaff(
                    p.context('manual-staff'),
                    const StaffDraft(name: 'Manual'),
                  )
                  as Committed<StaffRecord>)
              .value;
      final unrelated =
          (await p.manager.companies.createStaff(
                    p.context('unrelated-staff'),
                    const StaffDraft(name: 'Manual'),
                  )
                  as Committed<StaffRecord>)
              .value;
      Future<AttendanceRecord> punch(String employee, String op) async =>
          (await m.recordManual(
                    p.context(op),
                    ManualPunch(
                      employeeId: employee,
                      kind: PunchKind.checkIn,
                      utcMs: 1792368000000,
                      offsetMinutes: 540,
                      reason: 'Camera failed',
                    ),
                  )
                  as Committed<AttendanceRecord>)
              .value;
      final record = await punch(staff.employeeId, 'manual'),
          other = await punch(unrelated.employeeId, 'other-manual');
      await m.decide(
        p.context('manual-review'),
        record.eventId,
        ReviewDecision.approve,
        'Checked',
      );
      final original = (await p.manager.storage.repo.read(
        p.companyId,
        record.eventId,
      ))!.payload;
      final request = await p.join();
      final grant =
          (await p.manager.enrollment.approveJoin(
                    p.context('link'),
                    request,
                    existingEmployeeId: staff.employeeId,
                  )
                  as Committed<SignedMessage>)
              .value;
      await p.manager.enrollment.approveJoin(
        p.context('link'),
        request,
        existingEmployeeId: staff.employeeId,
      );
      await p.staff.acceptGrantTwice(grant);
      final person = p.staff.identity.requireActor(p.staff.session).personId;
      final old = await p.manager.storage.repo.snapshot(
        PersonalScope(staff.personId),
      );
      final linked = await p.manager.storage.repo.snapshot(
        PersonalScope(person),
      );
      expect(old.events.where((r) => r.id == record.eventId), isEmpty);
      expect(
        old.records.where((r) => r.id == 'attendance-state:${record.eventId}'),
        isEmpty,
      );
      expect(
        linked.events.where((r) => r.id == record.eventId).single.payload,
        orderedEquals(original),
      );
      expect(
        linked.events.where((r) => r.kind == 'attendanceDecisionRecord').length,
        1,
      );
      expect(linked.events.where((r) => r.id == other.eventId), isEmpty);
      expect(
        (await m.get(
          p.manager.session,
          p.companyId,
          record.eventId,
        )).employeeId,
        staff.employeeId,
      );
    },
  );
  test(
    'shared repository staff capture imports under owner without replacing originals or leaking coworkers',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final d = p.manager;
      final owner = d.identity.requireActor(d.session).personId;
      final invite = await d.enrollment.createInvitation(
        p.context('local-invite'),
      );
      final code = await d.capture.createWorkplaceCode(p.context('local-code'));
      final staff = await d.identity.createProfile(
        'Local staff',
        'a strong local passphrase',
      );
      final person = d.identity.requireActor(staff).personId;
      final invitation = await d.enrollment.acceptInvitation(
        staff,
        MessageCodec().encode(invite),
        acceptedRootFingerprint: p.company.rootFingerprint,
      );
      final join = await d.enrollment.requestJoin(
        staff,
        invitation,
        SecureIds().next(),
      );
      d.session = await d.identity.unlock(owner, 'a strong local passphrase');
      final grant =
          (await d.enrollment.approveJoin(
                    p.context('local-approve'),
                    await d.enrollment.verifyIncoming(
                      d.session,
                      MessageCodec().encode(join),
                    ),
                  )
                  as Committed<SignedMessage>)
              .value;
      d.session = await d.identity.unlock(person, 'a strong local passphrase');
      await d.acceptGrantTwice(grant);
      final workplace = await d.capture.verifyWorkplace(
        d.session,
        p.companyId,
        MessageCodec().encode(code),
      );
      final draft = await d.capture.beginDraft(
        d.session,
        p.companyId,
        workplace,
        PunchKind.checkIn,
      );
      final receipt =
          (await d.capture.recordPunch(
                    draft.context(d.session),
                    workplace,
                    PunchKind.checkIn,
                  )
                  as Committed<AttendanceReceipt>)
              .value;
      d.session = await d.identity.unlock(owner, 'a strong local passphrase');
      final m = service(d);
      final original = (await d.storage.repo.read(
        p.companyId,
        p.companyId,
      ))!.payload;
      final result = await m.importReceipt(
        p.context('local-import'),
        await m.verifyIncoming(d.session, p.companyId, receipt.bytes),
      );
      expect(result.status, ImportStatus.received);
      await m.decide(
        p.context('local-decision'),
        receipt.eventId,
        ReviewDecision.approve,
        'Checked',
      );
      expect(
        (await d.storage.repo.read(p.companyId, receipt.eventId))!.payload,
        orderedEquals(receipt.bytes),
      );
      expect(
        (await d.storage.repo.read(p.companyId, p.companyId))!.payload,
        orderedEquals(original),
      );
      d.session = await d.identity.unlock(person, 'a strong local passphrase');
      expect(
        (await m.get(d.session, p.companyId, receipt.eventId)).review,
        ReviewStatus.approved,
      );
      expect((await m.list(d.session, p.companyId)).length, 1);
      final snapshot = await d.storage.repo.snapshot(PersonalScope(person));
      expect(snapshot.records.where((r) => r.kind == 'membership').length, 1);
    },
  );
  test(
    'storage failure sends no acknowledgment and retry imports once',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final r = await p.captureCheckIn(), m = service(p.manager);
      final verified = await m.verifyIncoming(
        p.manager.session,
        p.companyId,
        r.bytes,
      );
      await p.manager.storage.failBeforeCommit();
      final failed = await m.importReceipt(p.context('failure'), verified);
      expect(failed.status, ImportStatus.rejected);
      expect(failed.returnMessage, isNull);
      expect(await p.manager.storage.repo.read(p.companyId, r.eventId), isNull);
      await p.manager.storage.reopen();
      p.manager.rebuildServices();
      final retry = await service(
        p.manager,
      ).importReceipt(p.context('failure'), verified);
      expect(retry.status, ImportStatus.received);
    },
  );
}
