import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'support/two_device_fixture.dart';
import 'receipt_import_test.dart' show service;

void main() {
  test(
    'manual entry is pending with immutable provenance and explicit approval',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final enrollment = await p.enrollStaff();
      final s = service(p.manager);
      final result = await s.recordManual(
        p.context('manual'),
        ManualPunch(
          employeeId: enrollment.membership.employeeId,
          kind: PunchKind.checkIn,
          utcMs: 1792368000000,
          offsetMinutes: 540,
          reason: 'Camera failed',
        ),
      );
      final record = (result as Committed<AttendanceRecord>).value;
      expect(record.source, AttendanceSource.manual);
      expect(record.review, ReviewStatus.pending);
      expect(record.returnEligible, isFalse);
      final original = (await p.manager.storage.repo.read(
        p.companyId,
        record.eventId,
      ))!.payload;
      await s.correct(
        p.context('correct'),
        record.eventId,
        const ProposedCorrection(
          kind: PunchKind.checkOut,
          utcMs: 1792368060000,
          offsetMinutes: 540,
          reason: 'Wrong kind',
        ),
        'Verified',
      );
      expect(
        (await s.get(p.manager.session, p.companyId, record.eventId)).review,
        ReviewStatus.pending,
      );
      await s.decide(
        p.context('review'),
        record.eventId,
        ReviewDecision.approve,
        'Checked',
      );
      final changed = await s.get(
        p.manager.session,
        p.companyId,
        record.eventId,
      );
      expect(changed.effectiveKind, PunchKind.checkOut);
      expect(changed.review, ReviewStatus.approved);
      expect(
        (await p.manager.storage.repo.read(
          p.companyId,
          record.eventId,
        ))!.payload,
        orderedEquals(original),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'review operator can choose manual subject without staff administration',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final operator =
          (await p.manager.companies.createStaff(
                    p.context('operator'),
                    const StaffDraft(name: 'Reviewer'),
                  )
                  as Committed<StaffRecord>)
              .value;
      await p.manager.companies.grantCapabilities(
        p.context('grant-review'),
        operator.membershipId,
        {Capability.reviewAttendance},
      );
      await p.manager.companies.activateOperator(
        p.context('activate'),
        operator.membershipId,
        'a strong local passphrase',
      );
      final session = await p.manager.companies.unlockOperator(
        p.companyId,
        operator.membershipId,
        'a strong local passphrase',
      );
      final subjects = await service(p.manager).subjects(session, p.companyId);
      expect(subjects.any((s) => s.employeeId == operator.employeeId), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
