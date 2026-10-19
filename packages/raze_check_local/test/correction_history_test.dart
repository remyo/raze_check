@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'support/two_device_fixture.dart';
import 'receipt_import_test.dart' show service;
import 'attendance_adversarial_test.dart' show resign;

void main() {
  for (final status in ReviewStatus.values) {
    test(
      'approve and deny no-op corrections independently preserve ${status.name} attendance',
      () async {
        final p = await TwoDeviceFixture.create();
        addTearDown(p.dispose);
        await p.enrollStaff();
        final r = await p.captureCheckIn(),
            m = service(p.manager),
            s = service(p.staff);
        final imported = await m.importReceipt(
          p.context('import'),
          await m.verifyIncoming(p.manager.session, p.companyId, r.bytes),
        );
        Future<void> accept(SignedMessage msg) async {
          expect(
            await s.accept(
              p.staff.session,
              await s.verifyIncoming(
                p.staff.session,
                p.companyId,
                MessageCodec().encode(msg),
              ),
            ),
            isA<Committed<AttendanceRecord>>(),
          );
        }

        if (status != ReviewStatus.pending) {
          final d =
              (await m.decide(
                        p.context('review'),
                        r.eventId,
                        status == ReviewStatus.approved
                            ? ReviewDecision.approve
                            : ReviewDecision.reject,
                        'Checked',
                      )
                      as Committed<DecisionRecord>)
                  .value;
          await accept(d.returnMessage!);
        }
        for (final approved in [true, false]) {
          final request = await s.request(
            p.staff.session,
            p.companyId,
            r.eventId,
            ProposedCorrection(
              kind: r.kind,
              utcMs: r.claimedUtcMs,
              offsetMinutes: r.offsetMinutes,
              reason: 'Please verify',
            ),
            'request-$approved',
          );
          final verified = await m.verifyIncoming(
            p.manager.session,
            p.companyId,
            MessageCodec().encode(request),
          );
          final result =
              (await m.resolve(
                        p.context('resolve-$approved'),
                        verified,
                        approved,
                        'Verified',
                      )
                      as Committed<CorrectionRecord>)
                  .value;
          final repeat =
              (await m.resolve(
                        p.context('resolve-again-$approved'),
                        verified,
                        approved,
                        'Verified',
                      )
                      as Committed<CorrectionRecord>)
                  .value;
          expect(repeat.decision.decisionId, result.decision.decisionId);
          expect(result.decision.requestId, request.payload.messageId);
          expect(
            result.decision.returnMessage!.payload.field<String>('outcome'),
            status.name,
          );
          await accept(result.decision.returnMessage!);
          await accept(result.decision.returnMessage!);
          expect(
            (await s.get(p.staff.session, p.companyId, r.eventId)).review,
            status,
          );
          expect(
            (await m.get(p.manager.session, p.companyId, r.eventId)).review,
            status,
          );
          final history = await s.history(
            p.staff.session,
            p.companyId,
            r.eventId,
          );
          expect(
            history
                .where((d) => d.requestId == request.payload.messageId)
                .single
                .correctionOutcome,
            approved ? CorrectionOutcome.approved : CorrectionOutcome.rejected,
          );
          expect(
            await m.resolve(
              p.context('conflict-$approved'),
              verified,
              !approved,
              'Verified',
            ),
            isA<Rejected<CorrectionRecord>>(),
          );
        }
        await accept(imported.returnMessage!);
        expect(
          (await s.get(p.staff.session, p.companyId, r.eventId)).review,
          status,
        );
        expect(
          (await p.manager.storage.repo.read(p.companyId, r.eventId))!.payload,
          orderedEquals(r.bytes),
        );
      },
    );
  }
  test(
    'later review retains manager correction; older staff resolution correlates without rollback',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final r = await p.captureCheckIn(),
          m = service(p.manager),
          s = service(p.staff);
      await m.importReceipt(
        p.context('import'),
        await m.verifyIncoming(p.manager.session, p.companyId, r.bytes),
      );
      final request = await s.request(
        p.staff.session,
        p.companyId,
        r.eventId,
        ProposedCorrection(
          kind: PunchKind.checkOut,
          utcMs: r.claimedUtcMs + 60000,
          offsetMinutes: 0,
          reason: 'Wrong punch',
        ),
        'request',
      );
      final resolution =
          (await m.resolve(
                    p.context('resolve'),
                    await m.verifyIncoming(
                      p.manager.session,
                      p.companyId,
                      MessageCodec().encode(request),
                    ),
                    true,
                    'Checked',
                  )
                  as Committed<CorrectionRecord>)
              .value;
      final correction =
          (await m.correct(
                    p.context('correct'),
                    r.eventId,
                    ProposedCorrection(
                      kind: PunchKind.checkIn,
                      utcMs: r.claimedUtcMs + 120000,
                      offsetMinutes: 60,
                      reason: 'Time corrected',
                    ),
                    'Verified',
                  )
                  as Committed<CorrectionRecord>)
              .value;
      expect(correction.decision.data['source'], 'managerCorrection');
      expect(correction.decision.requestId, isNull);
      final reviewed =
          (await m.decide(
                    p.context('review'),
                    r.eventId,
                    ReviewDecision.approve,
                    'Checked',
                  )
                  as Committed<DecisionRecord>)
              .value;
      expect(
        reviewed.returnMessage!.payload.field<int>('effectiveUtcMs'),
        r.claimedUtcMs + 120000,
      );
      Future<CommandResult<AttendanceRecord>> accept(SignedMessage msg) async =>
          s.accept(
            p.staff.session,
            await s.verifyIncoming(
              p.staff.session,
              p.companyId,
              MessageCodec().encode(msg),
            ),
          );
      await accept(reviewed.returnMessage!);
      await accept(resolution.decision.returnMessage!);
      await accept(correction.decision.returnMessage!);
      final current = await s.get(p.staff.session, p.companyId, r.eventId);
      expect(current.review, ReviewStatus.approved);
      expect(current.effectiveUtcMs, r.claimedUtcMs + 120000);
      expect(current.effectiveOffsetMinutes, 60);
      final history = await s.history(p.staff.session, p.companyId, r.eventId);
      expect(history.length, 3);
      expect(
        history
            .singleWhere((d) => d.requestId == request.payload.messageId)
            .correctionOutcome,
        CorrectionOutcome.approved,
      );
      final changed = List<Object?>.of(reviewed.returnMessage!.payload.values)
        ..[1] = SecureIds().next()
        ..[8] = 'Conflicting same revision';
      final conflict = await resign(
        p.manager,
        reviewed.returnMessage!,
        changed,
        issuer: p.company,
      );
      expect(
        (await accept(conflict) as Rejected).error,
        CheckError.duplicateConflict,
      );
      final reusedDecision =
          List<Object?>.of(reviewed.returnMessage!.payload.values)
            ..[1] = SecureIds().next()
            ..[6] = 4;
      expect(
        (await accept(
                  await resign(
                    p.manager,
                    reviewed.returnMessage!,
                    reusedDecision,
                    issuer: p.company,
                  ),
                )
                as Rejected)
            .error,
        CheckError.duplicateConflict,
      );
      final wrongHash = List<Object?>.of(reviewed.returnMessage!.payload.values)
        ..[1] = SecureIds().next()
        ..[4] = base64UrlEncode(Uint8List(32));
      expect(
        (await accept(
                  await resign(
                    p.manager,
                    reviewed.returnMessage!,
                    wrongHash,
                    issuer: p.company,
                  ),
                )
                as Rejected)
            .error,
        CheckError.invalidSignature,
      );
      final unknown = List<Object?>.of(reviewed.returnMessage!.payload.values)
        ..[1] = SecureIds().next()
        ..[3] = SecureIds().next();
      expect(
        await accept(
          await resign(
            p.manager,
            reviewed.returnMessage!,
            unknown,
            issuer: p.company,
          ),
        ),
        isA<Rejected<AttendanceRecord>>(),
      );
    },
  );
  test(
    'correction result remains explicit when local request is missing',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final r = await p.captureCheckIn(),
          m = service(p.manager),
          s = service(p.staff);
      await m.importReceipt(
        p.context('import'),
        await m.verifyIncoming(p.manager.session, p.companyId, r.bytes),
      );
      final saved = await s.request(
        p.staff.session,
        p.companyId,
        r.eventId,
        ProposedCorrection(
          kind: r.kind,
          utcMs: r.claimedUtcMs,
          offsetMinutes: r.offsetMinutes,
          reason: 'Check',
        ),
        'request',
      );
      final values = List<Object?>.of(saved.payload.values)
        ..[1] = SecureIds().next();
      final unseen = await resign(p.staff, saved, values);
      final resolution =
          (await m.resolve(
                    p.context('resolve'),
                    await m.verifyIncoming(
                      p.manager.session,
                      p.companyId,
                      MessageCodec().encode(unseen),
                    ),
                    false,
                    'No change',
                  )
                  as Committed<CorrectionRecord>)
              .value;
      final accepted = await s.accept(
        p.staff.session,
        await s.verifyIncoming(
          p.staff.session,
          p.companyId,
          MessageCodec().encode(resolution.decision.returnMessage!),
        ),
      );
      expect(accepted, isA<Committed<AttendanceRecord>>());
      final history = await s.history(p.staff.session, p.companyId, r.eventId);
      expect(history.single.requestId, unseen.payload.messageId);
      expect(history.single.correctionOutcome, CorrectionOutcome.rejected);
      expect(
        (await s.get(p.staff.session, p.companyId, r.eventId)).review,
        ReviewStatus.pending,
      );
    },
  );
}
