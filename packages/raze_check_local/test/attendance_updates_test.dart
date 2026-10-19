import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'support/two_device_fixture.dart';
import 'receipt_import_test.dart' show service;

void main() {
  test(
    'accept returns typed rejection for expired and restricted sessions',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final message = await p.invitation();
      final expired = p.staff.session;
      p.staff.identity.lock();
      expect(
        (await service(p.staff).accept(expired, message) as Rejected).error,
        CheckError.locked,
      );
      final operator =
          (await p.manager.companies.createStaff(
                    p.context('operator'),
                    const StaffDraft(name: 'Reviewer'),
                  )
                  as Committed<StaffRecord>)
              .value;
      await p.manager.companies.activateOperator(
        p.context('activate'),
        operator.membershipId,
        'a strong local passphrase',
      );
      final restricted = await p.manager.companies.unlockOperator(
        p.companyId,
        operator.membershipId,
        'a strong local passphrase',
      );
      expect(
        (await service(p.manager).accept(restricted, message) as Rejected)
            .error,
        CheckError.unauthorized,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'rejected correction preserves approved attendance and late ack never rolls back',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final receipt = await p.captureCheckIn(),
          m = service(p.manager),
          s = service(p.staff);
      final imported = await m.importReceipt(
        p.context('import'),
        await m.verifyIncoming(p.manager.session, p.companyId, receipt.bytes),
      );
      final decision =
          (await m.decide(
                    p.context('decision'),
                    receipt.eventId,
                    ReviewDecision.approve,
                    'Checked',
                  )
                  as Committed<DecisionRecord>)
              .value;
      Future<void> accept(SignedMessage msg) async {
        final result = await s.accept(
          p.staff.session,
          await s.verifyIncoming(
            p.staff.session,
            p.companyId,
            MessageCodec().encode(msg),
          ),
        );
        expect(result, isA<Committed<AttendanceRecord>>());
      }

      await accept(decision.returnMessage!);
      final request = await s.request(
        p.staff.session,
        p.companyId,
        receipt.eventId,
        ProposedCorrection(
          kind: receipt.kind,
          utcMs: receipt.claimedUtcMs,
          offsetMinutes: receipt.offsetMinutes,
          reason: 'Please check',
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
                    false,
                    'Already correct',
                  )
                  as Committed<CorrectionRecord>)
              .value;
      await accept(resolution.decision.returnMessage!);
      await accept(imported.returnMessage!);
      await accept(decision.returnMessage!);
      final record = await s.get(p.staff.session, p.companyId, receipt.eventId);
      expect(record.review, ReviewStatus.approved);
      expect(record.delivery, DeliveryStatus.received);
      expect(
        (await s.history(
          p.staff.session,
          p.companyId,
          receipt.eventId,
        )).last.correctionOutcome,
        CorrectionOutcome.rejected,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
