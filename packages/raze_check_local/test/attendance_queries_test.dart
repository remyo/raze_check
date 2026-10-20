import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart'
    show QueryInterceptor, QueryExecutor, ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:raze_check_local/src/database/check_database.dart';
import 'repository_test.dart' show CountingCipher, PausingCipher;
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';
import 'receipt_import_test.dart' show service;

LocalAttendanceQueries queries(EnrollmentDevice d) => LocalAttendanceQueries(
  repository: d.storage.repo,
  identity: d.identity,
  clock: d.clock,
);
void main() {
  test(
    'effective calendar dates honor DST and retain corrections plus original history',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final d = p.manager;
      final company =
          (await d.companies.createCompany(
                    d.session,
                    const CompanyDraft('DST synthetic', 'America/New_York'),
                    'dst-company',
                  )
                  as Committed<Company>)
              .value;
      CommandContext ctx(String id) => CommandContext(
        companyId: company.id,
        session: d.session,
        operationId: id,
        authorityGenerationId: company.authorityGenerationId,
      );
      final employee = (await d.companies.membership(
        d.session,
        company.id,
      ))!.employeeId;
      final attendance = service(d);
      Future<String> manual(String id, DateTime time) async =>
          (await attendance.recordManual(
                    ctx(id),
                    ManualPunch(
                      employeeId: employee,
                      kind: PunchKind.checkIn,
                      utcMs: time.millisecondsSinceEpoch,
                      offsetMinutes: -240,
                      reason: 'Synthetic manual',
                    ),
                  )
                  as Committed<AttendanceRecord>)
              .value
              .eventId;
      final before = await manual('before', DateTime.utc(2026, 3, 8, 4, 59));
      final included = await manual(
        'included',
        DateTime.utc(2026, 3, 9, 3, 59),
      );
      await manual('excluded', DateTime.utc(2026, 3, 9, 4));
      final q = queries(d),
          range = DateRange(DateTime(2026, 3, 8), DateTime(2026, 3, 8));
      expect(
        (await q.report(
          ctx('r1'),
          range,
          scope: AttendanceScope.management,
        )).rows.map((r) => r.record.eventId),
        [included],
      );
      await attendance.correct(
        ctx('correct'),
        before,
        ProposedCorrection(
          kind: PunchKind.checkOut,
          utcMs: DateTime.utc(2026, 3, 8, 5).millisecondsSinceEpoch,
          offsetMinutes: -300,
          reason: 'Cross date boundary',
        ),
        'Correct date',
      );
      await attendance.decide(
        ctx('approve'),
        before,
        ReviewDecision.approve,
        'Reviewed later',
      );
      final report = await q.report(
        ctx('r2'),
        range,
        scope: AttendanceScope.management,
      );
      expect(report.rows.map((r) => r.record.eventId), [before, included]);
      expect(
        report.rows.first.record.claimedUtcMs,
        DateTime.utc(2026, 3, 8, 4, 59).millisecondsSinceEpoch,
      );
      expect(
        report.rows.first.decisions.where((d) => d.correctionId != null),
        hasLength(1),
      );
      await manual('fall-in', DateTime.utc(2026, 11, 2, 4, 59));
      await manual('fall-out', DateTime.utc(2026, 11, 2, 5));
      expect(
        (await q.report(
          ctx('fall'),
          DateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 1)),
          scope: AttendanceScope.management,
        )).rows,
        hasLength(1),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'restricted export-only can report but cannot read review pages or fall back to personal',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final enrolled = await p.enrollStaff();
      final receipt = await p.captureCheckIn(), attendance = service(p.manager);
      await attendance.importReceipt(
        p.context('receive'),
        await attendance.verifyIncoming(
          p.manager.session,
          p.companyId,
          receipt.bytes,
        ),
      );
      await p.manager.companies.grantCapabilities(
        p.context('grant'),
        enrolled.membership.id,
        {Capability.exportAttendance},
      );
      await p.manager.companies.activateOperator(
        p.context('activate'),
        enrolled.membership.id,
        'an operator passphrase',
      );
      final operator = await p.manager.companies.unlockOperator(
        p.companyId,
        enrolled.membership.id,
        'an operator passphrase',
      );
      final ctx = CommandContext(
        companyId: p.companyId,
        session: operator,
        operationId: 'report',
        authorityGenerationId: p.company.authorityGenerationId,
      );
      final q = queries(p.manager),
          range = DateRange(DateTime(2026, 10, 19), DateTime(2026, 10, 19));
      expect(
        (await q.report(ctx, range, scope: AttendanceScope.management)).rows,
        hasLength(1),
      );
      await expectLater(
        q.report(ctx, range, scope: AttendanceScope.personal),
        throwsA(isA<CheckException>()),
      );
      await expectLater(
        q.historyPage(operator, p.companyId, scope: AttendanceScope.management),
        throwsA(isA<CheckException>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'SQL pages bound decryption, invalidate changed checkpoints and survive reopen',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      await p.captureCheckIn();
      await p.capture(PunchKind.checkOut, newPunch: true);
      final probe = PageProbe(),
          cipher = CountingCipher(
            AesPayloadCipher(VaultKeys(p.staff.storage.keys)),
          );
      final repository = LocalCheckRepository(
        database: CheckDatabase(
          NativeDatabase.createInBackground(
            p.staff.storage.paths.database,
          ).interceptWith(probe),
        ),
        cipher: cipher,
      );
      addTearDown(repository.close);
      final q = LocalAttendanceQueries(
        repository: repository,
        identity: p.staff.identity,
        clock: p.staff.clock,
      );
      await expectLater(
        q.historyPage(p.staff.session, p.companyId, cancelled: () => true),
        throwsA(isA<CheckException>()),
      );
      final page = await q.historyPage(
        p.staff.session,
        p.companyId,
        pageSize: 1,
      );
      expect(probe.eventRows, 1);
      expect(probe.maxRows, 1);
      expect(cipher.opens, lessThanOrEqualTo(7));
      final next = await q.historyPage(
        p.staff.session,
        p.companyId,
        pageSize: 1,
        cursor: page.next,
      );
      expect(
        next.items.single.record.eventId,
        isNot(page.items.single.record.eventId),
      );
      await expectLater(
        q.historyPage(p.staff.session, p.companyId, pageSize: 101),
        throwsA(isA<CheckException>()),
      );
      await p.capture(PunchKind.checkIn, newPunch: true);
      expect(
        (await q.historyPage(
          p.staff.session,
          p.companyId,
          cursor: page.next,
        )).refreshRequired,
        isTrue,
      );
      await p.restartStaff();
      expect(
        (await queries(
          p.staff,
        ).historyPage(p.staff.session, p.companyId, pageSize: 1)).items,
        hasLength(1),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'report reads labels and projections from one real WAL snapshot during concurrent edits',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final enrolled = await p.enrollStaff();
      final receipt = await p.captureCheckIn();
      final m = service(p.manager);
      await m.importReceipt(
        p.context('receive'),
        await m.verifyIncoming(p.manager.session, p.companyId, receipt.bytes),
      );
      final cipher = PausingCipher(
        AesPayloadCipher(VaultKeys(p.manager.storage.keys)),
      );
      final reading = LocalCheckRepository(
        database: p.manager.storage.database,
        cipher: cipher,
      );
      final other = LocalCheckRepository(
        database: CheckDatabase.open(p.manager.storage.paths),
        cipher: AesPayloadCipher(VaultKeys(p.manager.storage.keys)),
      );
      addTearDown(other.close);
      final writer = LocalCompanyService(
        repository: other,
        identity: p.manager.identity,
        keys: p.manager.storage.keys,
        clock: p.manager.clock,
        ids: SecureIds(),
      );
      final q = LocalAttendanceQueries(
        repository: reading,
        identity: p.manager.identity,
        clock: p.manager.clock,
      );
      final range = DateRange(DateTime(2026, 10, 19), DateTime(2026, 10, 19));
      final pending = q.report(
        p.context('report'),
        range,
        scope: AttendanceScope.management,
      );
      await cipher.started.future;
      try {
        expect(
          await writer.updateStaff(
            p.context('rename'),
            StaffUpdate(
              enrolled.membership.employeeId,
              const StaffDraft(name: 'Changed after snapshot'),
            ),
          ),
          isA<Committed<StaffRecord>>(),
        );
      } finally {
        cipher.proceed.complete();
      }
      expect((await pending).rows.single.employeeName, 'Staff');
      expect(
        (await q.report(
          p.context('report2'),
          range,
          scope: AttendanceScope.management,
        )).rows.single.employeeName,
        'Changed after snapshot',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'real receipts, bounded pages and explicit report scope remain independent',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final first = await p.captureCheckIn();
      await p.capture(PunchKind.checkOut, newPunch: true);
      final m = service(p.manager), s = service(p.staff);
      final received = await m.importReceipt(
        p.context('receive'),
        await m.verifyIncoming(p.manager.session, p.companyId, first.bytes),
      );
      await s.accept(
        p.staff.session,
        await s.verifyIncoming(
          p.staff.session,
          p.companyId,
          MessageCodec().encode(received.returnMessage!),
        ),
      );
      final q = queries(p.staff);
      final overview = await q.forStaff(p.staff.session, p.companyId).first;
      expect(overview.savedOnDevice, 1);
      expect(overview.pending, 2);
      expect(overview.received, 1);
      final page = await q.historyPage(
        p.staff.session,
        p.companyId,
        pageSize: 1,
      );
      expect(page.items, hasLength(1));
      expect(page.next, isNotNull);
      final second = await q.historyPage(
        p.staff.session,
        p.companyId,
        pageSize: 1,
        cursor: page.next,
      );
      expect(second.items, hasLength(1));
      expect(
        second.items.single.record.eventId,
        isNot(page.items.single.record.eventId),
      );
      final manager = await queries(
        p.manager,
      ).forManager(p.context('overview')).first;
      expect(
        manager.lastReceivedUtcMs,
        p.manager.clock.now.millisecondsSinceEpoch,
      );
      final range = DateRange(DateTime(2026, 10, 19), DateTime(2026, 10, 19));
      final report = await queries(
        p.manager,
      ).report(p.context('report'), range, scope: AttendanceScope.management);
      expect(report.rows, hasLength(1));
      expect(report.rows.single.employeeName, 'Staff');
      expect(
        (await queries(p.manager).report(
          p.context('own'),
          range,
          scope: AttendanceScope.personal,
        )).rows,
        isEmpty,
      );
      await s.request(
        p.staff.session,
        p.companyId,
        first.eventId,
        ProposedCorrection(
          kind: PunchKind.checkIn,
          utcMs: first.claimedUtcMs + 60000,
          offsetMinutes: 540,
          reason: 'Pending correction',
        ),
        'request',
      );
      final personalContext = CommandContext(
        companyId: p.companyId,
        session: p.staff.session,
        operationId: 'personal-report',
        authorityGenerationId: p.company.authorityGenerationId,
      );
      final personalReport = await q.report(
        personalContext,
        range,
        scope: AttendanceScope.personal,
      );
      expect(
        personalReport.rows
            .singleWhere((r) => r.record.eventId == first.eventId)
            .requests
            .single
            .outcome,
        isNull,
      );
      p.staff.identity.lock();
      await expectLater(
        q.historyPage(p.staff.session, p.companyId, cursor: page.next),
        throwsA(isA<CheckException>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

final class PageProbe extends QueryInterceptor {
  int eventRows = 0, maxRows = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains('SELECT r.* FROM stored_rows r')) {
      expect(statement, contains('LIMIT ?'));
      eventRows += rows.length;
      if (rows.length > maxRows) maxRows = rows.length;
    }
    return rows;
  }
}
