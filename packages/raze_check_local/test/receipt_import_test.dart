import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';

LocalAttendanceService service(EnrollmentDevice d) => LocalAttendanceService(
  repository: d.storage.repo,
  identity: d.identity,
  keys: d.storage.keys,
  clock: d.clock,
  ids: SecureIds(),
);
void main() {
  test(
    'manager derives and reconciles sequence hints from independently delivered originals',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final first = await p.captureCheckIn();
      p.staff.clock.advance(const Duration(minutes: 3));
      final middle = await p.capture(PunchKind.checkOut, newPunch: true);
      p.staff.clock.advance(const Duration(minutes: 3));
      final last = await p.capture(PunchKind.checkIn, newPunch: true);
      final m = service(p.manager);
      Future<ImportOutcome> receive(AttendanceReceipt r) async =>
          m.importReceipt(
            p.context('receive-${r.eventId}'),
            await m.verifyIncoming(p.manager.session, p.companyId, r.bytes),
          );
      Future<AttendanceRecord> read(AttendanceReceipt r) =>
          m.get(p.manager.session, p.companyId, r.eventId);
      expect((await receive(middle)).status, ImportStatus.needsReview);
      expect((await read(middle)).flags, contains('missingCheckIn'));
      await receive(last);
      await receive(first);
      expect((await read(middle)).flags, isNot(contains('missingCheckIn')));
      expect((await read(last)).flags, isNot(contains('missingCheckOut')));
      for (final r in [first, middle, last]) {
        expect(
          (await p.manager.storage.repo.read(p.companyId, r.eventId))!.payload,
          r.bytes,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'separated check-ins flag missing known checkout until its later delivery',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final first = await p.captureCheckIn();
      p.staff.clock.advance(const Duration(minutes: 3));
      final middle = await p.capture(PunchKind.checkOut, newPunch: true);
      p.staff.clock.advance(const Duration(minutes: 3));
      final last = await p.capture(PunchKind.checkIn, newPunch: true);
      final m = service(p.manager);
      Future<void> receive(AttendanceReceipt r) async {
        await m.importReceipt(
          p.context('receive-${r.eventId}'),
          await m.verifyIncoming(p.manager.session, p.companyId, r.bytes),
        );
      }

      await receive(first);
      await receive(last);
      final before = await m.get(p.manager.session, p.companyId, last.eventId);
      expect(before.flags, containsAll(['missingCheckOut', 'unexpectedOrder']));
      expect(before.flags, isNot(contains('possibleDuplicate')));
      await receive(middle);
      expect(
        (await m.get(p.manager.session, p.companyId, last.eventId)).flags,
        isNot(anyOf(contains('missingCheckOut'), contains('unexpectedOrder'))),
      );
      expect(
        (await p.manager.storage.repo.read(p.companyId, last.eventId))!.payload,
        last.bytes,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'receipt hints distinguish an authorized manual endpoint in mixed reports',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final enrollment = await p.enrollStaff();
      final m = service(p.manager);
      final manual =
          (await m.recordManual(
                    p.context('manual-check-in'),
                    ManualPunch(
                      employeeId: enrollment.membership.employeeId,
                      kind: PunchKind.checkIn,
                      utcMs: p.manager.clock.nowUtc().millisecondsSinceEpoch,
                      offsetMinutes: 540,
                      reason: 'Manager assisted check-in',
                    ),
                  )
                  as Committed<AttendanceRecord>)
              .value;
      expect(manual.review, ReviewStatus.pending);
      await m.decide(
        p.context('approve-manual'),
        manual.eventId,
        ReviewDecision.approve,
        'Manager confirmed manual check-in',
      );
      final manualOriginal = (await p.manager.storage.repo.read(
        p.companyId,
        manual.eventId,
      ))!.payload;
      p.staff.clock.advance(const Duration(minutes: 3));
      final receipt = await p.capture(PunchKind.checkOut);
      await m.importReceipt(
        p.context('receive-check-out'),
        await m.verifyIncoming(p.manager.session, p.companyId, receipt.bytes),
      );
      final report =
          await LocalAttendanceQueries(
            repository: p.manager.storage.repo,
            identity: p.manager.identity,
            clock: p.manager.clock,
          ).report(
            p.context('mixed-report'),
            DateRange(DateTime(2026, 10, 19), DateTime(2026, 10, 19)),
            scope: AttendanceScope.management,
          );
      expect(report.rows, hasLength(2));
      final manualRow = report.rows.singleWhere(
        (r) => r.record.eventId == manual.eventId,
      );
      final receiptRow = report.rows.singleWhere(
        (r) => r.record.eventId == receipt.eventId,
      );
      expect(manualRow.record.source, AttendanceSource.manual);
      expect(manualRow.record.review, ReviewStatus.approved);
      expect(manualRow.decisions, hasLength(1));
      expect(manualRow.record.flags, isEmpty);
      expect(receiptRow.record.source, AttendanceSource.staticQr);
      expect(receiptRow.record.flags, contains('missingCheckIn'));
      expect(
        (await p.manager.storage.repo.read(
          p.companyId,
          manual.eventId,
        ))!.payload,
        manualOriginal,
      );
      expect(
        (await p.manager.storage.repo.read(
          p.companyId,
          receipt.eventId,
        ))!.payload,
        receipt.bytes,
      );
      final csv = utf8.decode(AttendanceCsv.encode(report));
      expect(csv, contains('"manual"'));
      expect(csv, contains('"staticQr"'));
      expect(csv, contains('Manager assisted check-in'));
      expect(csv, contains('Manager confirmed manual check-in'));
      expect(csv, contains('No known preceding check-in receipt'));
      expect(
        attendanceHintLabel('missingCheckOut'),
        'No known check-out receipt between check-in receipts',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'receipt import deduplicates without approving and preserves exact original',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final receipt = await p.captureCheckIn();
      final manager = service(p.manager);
      final verified = await manager.verifyIncoming(
        p.manager.session,
        p.companyId,
        receipt.bytes,
      );
      final first = await manager.importReceipt(p.context('receive'), verified);
      expect(first.status, ImportStatus.received);
      expect(
        (await manager.importReceipt(p.context('receive2'), verified)).status,
        ImportStatus.alreadyReceived,
      );
      expect(
        (await manager.get(
          p.manager.session,
          p.companyId,
          receipt.eventId,
        )).review,
        ReviewStatus.pending,
      );
      final approved = await manager.decide(
        p.context('review-approve'),
        receipt.eventId,
        ReviewDecision.approve,
        'Checked',
      );
      expect(approved, isA<Committed<DecisionRecord>>());
      await manager.decide(
        p.context('review-approve'),
        receipt.eventId,
        ReviewDecision.approve,
        'Checked',
      );
      await manager.importReceipt(p.context('receive3'), verified);
      expect(
        (await manager.get(
          p.manager.session,
          p.companyId,
          receipt.eventId,
        )).review,
        ReviewStatus.approved,
      );
      expect(
        (await p.manager.storage.repo.read(
          p.companyId,
          receipt.eventId,
        ))!.payload,
        orderedEquals(receipt.bytes),
      );
      expect(
        (await manager.history(
          p.manager.session,
          p.companyId,
          receipt.eventId,
        )).length,
        1,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
