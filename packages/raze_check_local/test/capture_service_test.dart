import 'dart:convert';
import 'dart:typed_data';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'support/two_device_fixture.dart';

void main() {
  late TwoDeviceFixture pair;
  setUp(() async {
    pair = await TwoDeviceFixture.create();
    await pair.enrollStaff();
  });
  tearDown(() => pair.dispose());
  test(
    'committed receipt survives reopen with exact bytes and one event',
    () async {
      final saved = await pair.captureCheckIn();
      await pair.restartStaff();
      final exported = await pair.exportReceipt(saved.eventId);
      expect(exported.bytes, orderedEquals(saved.bytes));
      expect(await pair.staff.eventCount(), 1);
      expect(saved.delivery, DeliveryStatus.localOnly);
      expect(
        (await pair.staff.capture.currentDraft(
          pair.staff.session,
          pair.companyId,
        ))!.eventId,
        saved.eventId,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'rapid taps and operation replay commit one event',
    () async {
      final workplace = await pair.workplace();
      final drafts = await Future.wait(
        List.generate(
          2,
          (_) => pair.staff.capture.beginDraft(
            pair.staff.session,
            pair.companyId,
            workplace,
            PunchKind.checkIn,
          ),
        ),
      );
      expect(drafts[0].operationId, drafts[1].operationId);
      final results = await Future.wait(
        drafts.map(
          (d) => pair.staff.capture.recordPunch(
            d.context(pair.staff.session),
            workplace,
            d.kind,
          ),
        ),
      );
      expect(results.every((r) => r is Committed<AttendanceReceipt>), isTrue);
      expect(await pair.staff.eventCount(), 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'disk failure leaves draft and no event or outbox; retry same operation',
    () async {
      final workplace = await pair.workplace();
      final draft = await pair.staff.capture.beginDraft(
        pair.staff.session,
        pair.companyId,
        workplace,
        PunchKind.checkIn,
      );
      await pair.staff.storage.failBeforeCommit();
      expect(
        await pair.staff.capture.recordPunch(
          draft.context(pair.staff.session),
          workplace,
          draft.kind,
        ),
        isRejected(CheckError.storageFailure),
      );
      expect(await pair.staff.eventCount(), 0);
      expect(
        await pair.staff.capture.listOutbox(pair.staff.session, pair.companyId),
        isEmpty,
      );
      await pair.restartStaff();
      final result = await pair.staff.capture.recordPunch(
        draft.context(pair.staff.session),
        workplace,
        draft.kind,
      );
      expect(result, isA<Committed<AttendanceReceipt>>());
      expect(await pair.staff.eventCount(), 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'checkout keeps missing endpoint, next punches preserve review flags',
    () async {
      final first = await pair.capture(PunchKind.checkOut);
      expect(first.flags, contains(AttendanceFlag.missingCheckIn));
      final second = await pair.capture(PunchKind.checkOut, newPunch: true);
      expect(second.eventId, isNot(first.eventId));
      expect(
        second.flags,
        containsAll([
          AttendanceFlag.possibleDuplicate,
          AttendanceFlag.unexpectedOrder,
          AttendanceFlag.missingCheckIn,
        ]),
      );
      expect(second.offsetMinutes, 540);
      expect(
        second.claimedUtcMs,
        pair.staff.clock.nowUtc().millisecondsSinceEpoch,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'wrong company and missing membership cannot capture from a verified object',
    () async {
      final code = await pair.workplace();
      final draft = await pair.staff.capture.beginDraft(
        pair.staff.session,
        pair.companyId,
        code,
        PunchKind.checkIn,
      );
      final wrong = CommandContext(
        companyId: 'company-b',
        session: pair.staff.session,
        operationId: draft.operationId,
        authorityGenerationId: draft.authorityGenerationId,
      );
      expect(
        await pair.staff.capture.recordPunch(wrong, code, draft.kind),
        isRejected(CheckError.unauthorized),
      );
      pair.staff.session = await pair.staff.identity.createProfile(
        'Unenrolled',
        'another strong passphrase',
      );
      expect(
        await pair.staff.capture.recordPunch(
          draft.context(pair.staff.session),
          code,
          draft.kind,
        ),
        isRejected(CheckError.unauthorized),
      );
      expect(await pair.staff.eventCount(), 0);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'wrong-company workplace is rejected before creating a draft',
    () async {
      final second =
          (await pair.manager.companies.createCompany(
                    pair.manager.session,
                    const CompanyDraft('Other', 'Asia/Tokyo'),
                    'other-company',
                  )
                  as Committed<Company>)
              .value;
      final message = await pair.manager.capture.createWorkplaceCode(
        CommandContext(
          companyId: second.id,
          session: pair.manager.session,
          operationId: 'other-code',
          authorityGenerationId: second.authorityGenerationId,
        ),
      );
      final verified =
          await MessageVerifier(
            LocalKeyService(pair.manager.storage.keys),
          ).verify(
            message,
            TrustContext(
              companyId: second.id,
              rootPublicKey: base64Url.decode(second.rootPublicKey),
              authorities: [AuthorityCertificate(second.authority)],
            ),
          );
      await expectLater(
        pair.staff.capture.beginDraft(
          pair.staff.session,
          pair.companyId,
          verified,
          PunchKind.checkIn,
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.wrongCompany,
          ),
        ),
      );
      expect(await pair.staff.eventCount(), 0);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'retired credential rejects fresh capture and completed replay',
    () async {
      final code = await pair.workplace();
      final draft = await pair.staff.capture.beginDraft(
        pair.staff.session,
        pair.companyId,
        code,
        PunchKind.checkIn,
      );
      final saved = await pair.staff.capture.recordPunch(
        draft.context(pair.staff.session),
        code,
        draft.kind,
      );
      expect(saved, isA<Committed<AttendanceReceipt>>());
      final member = (await pair.staff.companies.membership(
        pair.staff.session,
        pair.companyId,
      ))!;
      await rewrite(
        pair,
        'credential:${member.id}:${member.revision}',
        (data) => {...data, 'retired': true},
      );
      expect(
        await pair.staff.capture.recordPunch(
          draft.context(pair.staff.session),
          code,
          draft.kind,
        ),
        isRejected(CheckError.revokedCredential),
      );
      await expectLater(
        pair.staff.capture.beginDraft(
          pair.staff.session,
          pair.companyId,
          code,
          PunchKind.checkOut,
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.revokedCredential,
          ),
        ),
      );
      // Historical receipt can still be retrieved by its original person.
      expect(
        (await pair.exportReceipt(
          (saved as Committed<AttendanceReceipt>).value.eventId,
        )).bytes,
        orderedEquals(saved.value.bytes),
      );
      expect(await pair.staff.eventCount(), 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'deactivation and changed authority reject transaction replay',
    () async {
      final code = await pair.workplace();
      final draft = await pair.staff.capture.beginDraft(
        pair.staff.session,
        pair.companyId,
        code,
        PunchKind.checkIn,
      );
      await pair.staff.capture.recordPunch(
        draft.context(pair.staff.session),
        code,
        draft.kind,
      );
      final member = (await pair.staff.companies.membership(
        pair.staff.session,
        pair.companyId,
      ))!;
      await rewrite(pair, member.id, (data) => {...data, 'active': false});
      expect(
        await pair.staff.capture.recordPunch(
          draft.context(pair.staff.session),
          code,
          draft.kind,
        ),
        isRejected(CheckError.unauthorized),
      );
      await rewrite(pair, member.id, (data) => {...data, 'active': true});
      await rewrite(
        pair,
        pair.companyId,
        (data) => {...data, 'authorityGenerationId': 'changed-authority'},
      );
      expect(
        await pair.staff.capture.recordPunch(
          draft.context(pair.staff.session),
          code,
          draft.kind,
        ),
        isRejected(CheckError.recoveryRequired),
      );
      expect(await pair.staff.eventCount(), 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'session lost during encryption rolls back event outbox and draft association',
    () async {
      final code = await pair.workplace();
      final draft = await pair.staff.capture.beginDraft(
        pair.staff.session,
        pair.companyId,
        code,
        PunchKind.checkIn,
      );
      final guarded = LocalCaptureService(
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
      expect(
        await guarded.recordPunch(
          draft.context(pair.staff.session),
          code,
          draft.kind,
        ),
        isRejected(CheckError.locked),
      );
      expect(await pair.staff.eventCount(), 0);
      expect(await pair.staff.storage.count('attendanceOutbox'), 0);
      final row = await pair.staff.storage.repo.read(
        pair.companyId,
        'capture-intent:${draft.operationId}',
      );
      expect((jsonDecode(utf8.decode(row!.payload)) as Map)['eventId'], isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Matcher isRejected(CheckError error) =>
    isA<Rejected<AttendanceReceipt>>().having((r) => r.error, 'error', error);

Future<void> rewrite(
  TwoDeviceFixture pair,
  String id,
  Map<String, dynamic> Function(Map<String, dynamic>) update,
) async {
  final row = (await pair.staff.storage.repo.read(pair.companyId, id))!;
  final changed = StoredRecord(
    id,
    row.companyId,
    row.kind,
    row.revision + 1,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode(
          update(jsonDecode(utf8.decode(row.payload)) as Map<String, dynamic>),
        ),
      ),
    ),
  );
  final result = await pair.staff.storage.repo.commit(
    CommandContext(
      companyId: pair.companyId,
      session: pair.staff.session,
      operationId: SecureIds().next(),
      authorityGenerationId: pair.company.authorityGenerationId,
    ),
    requestDigest: Uint8List(32),
    build: (_) async => Mutation([changed], [], [], changed),
  );
  expect(result, isA<Committed<StoredRecord>>());
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
  }) {
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
