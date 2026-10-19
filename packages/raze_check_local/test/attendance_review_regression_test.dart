@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'support/two_device_fixture.dart';
import 'receipt_import_test.dart' show service;
import 'attendance_adversarial_test.dart' show resign;

Future<AttendanceReceipt> ownerPunch(
  TwoDeviceFixture p,
  PunchKind kind, {
  bool another = false,
}) async {
  final d = p.manager;
  if (another) {
    final prior = (await d.capture.currentDraft(d.session, p.companyId))!;
    await d.capture.finishDraft(d.session, p.companyId, prior.eventId!);
  }
  final code = await d.capture.createWorkplaceCode(
    p.context('regression-code'),
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
    kind,
  );
  return (await d.capture.recordPunch(draft.context(d.session), verified, kind)
          as Committed<AttendanceReceipt>)
      .value;
}

void main() {
  test(
    'shared pending correction request rejects conflicting wire and kind without mutation',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final d = p.manager,
          s = service(d),
          receipt = await ownerPunch(p, PunchKind.checkIn);
      await s.importReceipt(
        p.context('regression-import'),
        await s.verifyIncoming(d.session, p.companyId, receipt.bytes),
      );
      final original = await s.request(
        d.session,
        p.companyId,
        receipt.eventId,
        ProposedCorrection(
          kind: PunchKind.checkOut,
          utcMs: receipt.claimedUtcMs + 60000,
          offsetMinutes: 540,
          reason: 'Missed checkout',
        ),
        'regression-request',
      );
      final changed = List<Object?>.of(original.payload.values)
        ..[6] = receipt.claimedUtcMs + 120000;
      final conflicting = await resign(d, original, changed);
      final before = await d.storage.repo.snapshot(CompanyScope(p.companyId));
      final result = await s.resolve(
        p.context('regression-conflict'),
        await s.verifyIncoming(
          d.session,
          p.companyId,
          MessageCodec().encode(conflicting),
        ),
        true,
        'Verified',
      );
      expect(result, isA<Rejected<CorrectionRecord>>());
      expect((result as Rejected).error, CheckError.duplicateConflict);
      final after = await d.storage.repo.snapshot(CompanyScope(p.companyId));
      expect(after.revisions, before.revisions);
      expect(after.events.length, before.events.length);
      expect(after.outbox.length, before.outbox.length);
      expect(
        await d.storage.repo.read(
          p.companyId,
          'resolution:${original.payload.messageId}',
        ),
        isNull,
      );
      expect(await s.history(d.session, p.companyId, receipt.eventId), isEmpty);
      expect(
        (await d.storage.repo.read(
          p.companyId,
          'correction-request:${original.payload.messageId}',
        ))!.payload,
        orderedEquals(MessageCodec().encode(original)),
      );
      final verified = await s.verifyIncoming(
        d.session,
        p.companyId,
        MessageCodec().encode(original),
      );
      final approved =
          (await s.resolve(
                    p.context('regression-approve'),
                    verified,
                    true,
                    'Verified',
                  )
                  as Committed<CorrectionRecord>)
              .value;
      final repeated =
          (await s.resolve(
                    p.context('regression-repeat'),
                    verified,
                    true,
                    'Verified',
                  )
                  as Committed<CorrectionRecord>)
              .value;
      expect(repeated.decision.decisionId, approved.decision.decisionId);
      expect(
        (await s.history(d.session, p.companyId, receipt.eventId)).length,
        1,
      );

      final wrongKindMessage = await resign(
        d,
        original,
        List<Object?>.of(original.payload.values)..[1] = SecureIds().next(),
      );
      final wrongKind = StoredRecord(
        'correction-request:${wrongKindMessage.payload.messageId}',
        p.companyId,
        'attendanceUpdate',
        1,
        MessageCodec().encode(wrongKindMessage),
      );
      await d.storage.repo.commit(
        p.context('seed-wrong-kind'),
        requestDigest: d.storage.digest(42),
        build: (_) async => Mutation([], [wrongKind], [], wrongKind),
      );
      final beforeKind = await d.storage.repo.snapshot(
        CompanyScope(p.companyId),
      );
      final kindResult = await s.resolve(
        p.context('regression-kind-conflict'),
        await s.verifyIncoming(
          d.session,
          p.companyId,
          MessageCodec().encode(wrongKindMessage),
        ),
        true,
        'Verified',
      );
      expect(kindResult, isA<Rejected<CorrectionRecord>>());
      expect((kindResult as Rejected).error, CheckError.duplicateConflict);
      expect(
        (await d.storage.repo.snapshot(CompanyScope(p.companyId))).revisions,
        beforeKind.revisions,
      );
      expect(
        await d.storage.repo.read(
          p.companyId,
          'resolution:${wrongKindMessage.payload.messageId}',
        ),
        isNull,
      );
      expect(
        (await s.history(d.session, p.companyId, receipt.eventId)).length,
        1,
      );
    },
  );

  test(
    'shared checkout capture flags survive list detail import and replay without duplicates',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final d = p.manager, s = service(d);
      final receipt = await ownerPunch(p, PunchKind.checkOut);
      Future<void> flags(String eventId, List<String> expected) async {
        expect(
          (await s.list(
            d.session,
            p.companyId,
          )).singleWhere((r) => r.eventId == eventId).flags,
          unorderedEquals(expected),
        );
        expect(
          (await s.get(d.session, p.companyId, eventId)).flags,
          unorderedEquals(expected),
        );
        expect(
          (await d.capture.getReceipt(
            d.session,
            p.companyId,
            eventId,
          )).flags.map((f) => f.name),
          unorderedEquals(expected),
        );
      }

      await flags(receipt.eventId, ['missingCheckIn']);
      // A management projection can already exist before the first import.
      await s.decide(
        p.context('regression-review'),
        receipt.eventId,
        ReviewDecision.reject,
        'Missing earlier punch',
      );
      final verified = await s.verifyIncoming(
        d.session,
        p.companyId,
        receipt.bytes,
      );
      final first = await s.importReceipt(
        p.context('regression-import'),
        verified,
      );
      expect(first.status, ImportStatus.needsReview);
      await flags(receipt.eventId, ['missingCheckIn']);
      expect(
        (await s.importReceipt(
          p.context('regression-import'),
          verified,
        )).status,
        ImportStatus.alreadyReceived,
      );
      expect(
        (await s.importReceipt(
          p.context('regression-import-again'),
          verified,
        )).status,
        ImportStatus.alreadyReceived,
      );
      await flags(receipt.eventId, ['missingCheckIn']);
      expect(
        (await d.storage.repo.read(p.companyId, receipt.eventId))!.payload,
        orderedEquals(receipt.bytes),
      );
      final again = await ownerPunch(p, PunchKind.checkOut, another: true);
      final expected = [
        'possibleDuplicate',
        'unexpectedOrder',
        'missingCheckIn',
      ];
      await flags(again.eventId, expected);
      final next = await s.verifyIncoming(d.session, p.companyId, again.bytes);
      expect(
        (await s.importReceipt(
          p.context('regression-import-next'),
          next,
        )).status,
        ImportStatus.needsReview,
      );
      await flags(again.eventId, expected);
      await s.importReceipt(p.context('regression-import-next'), next);
      await flags(again.eventId, expected);
      expect(
        (await d.storage.repo.read(p.companyId, again.eventId))!.payload,
        orderedEquals(again.bytes),
      );
    },
  );
}
