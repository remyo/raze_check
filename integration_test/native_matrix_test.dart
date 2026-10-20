import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../packages/raze_check_feature/test/support/settle_review.dart';
import '../packages/raze_check_local/test/support/acceptance_device.dart';
import 'support/native_acceptance.dart';

// These cases exercise application behavior over native SQLite and OS keys.
// Injected callbacks/SQL aborts and graceful reopen are not OS picker/disk/kill
// evidence. Each run owns a fresh namespace and preserves previous app data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native overnight correction keeps UTC offsets and company date',
    (tester) async {
      final devices = await nativeAcceptanceDevices(['overnight-manager']);
      final manager = devices.single;
      try {
        final company = await manager.createCompany();
        final subject = (await manager.attendance.subjects(
          manager.session,
          company.id,
        )).single;
        final original = DateTime.utc(2026, 10, 18, 14, 55);
        final effective = DateTime.utc(2026, 10, 18, 15, 5);
        final saved =
            await manager.attendance.recordManual(
                  manager.context(company),
                  ManualPunch(
                    employeeId: subject.employeeId,
                    kind: PunchKind.checkIn,
                    utcMs: original.millisecondsSinceEpoch,
                    offsetMinutes: 540,
                    reason: 'Synthetic overnight entry',
                  ),
                )
                as Committed<AttendanceRecord>;
        expect(
          await manager.attendance.correct(
            manager.context(company),
            saved.value.eventId,
            ProposedCorrection(
              kind: PunchKind.checkOut,
              utcMs: effective.millisecondsSinceEpoch,
              offsetMinutes: -240,
              reason: 'Synthetic offset correction',
            ),
            'Synthetic correction evidence',
          ),
          isA<Committed<CorrectionRecord>>(),
        );
        await manager.reopen();
        final before = await manager.queries.report(
          manager.context(company),
          DateRange(DateTime.utc(2026, 10, 18), DateTime.utc(2026, 10, 18)),
          scope: AttendanceScope.management,
        );
        final after = await manager.queries.report(
          manager.context(company),
          DateRange(DateTime.utc(2026, 10, 19), DateTime.utc(2026, 10, 19)),
          scope: AttendanceScope.management,
        );
        expect(before.rows, isEmpty);
        final record = after.rows.single.record;
        expect(record.eventId, saved.value.eventId);
        expect(record.claimedUtcMs, original.millisecondsSinceEpoch);
        expect(record.effectiveUtcMs, effective.millisecondsSinceEpoch);
        expect(record.effectiveOffsetMinutes, -240);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttendanceDetailScreen(
                record: record,
                history: after.rows.single.decisions,
                busy: false,
                canManage: false,
                onBack: () {},
                onReview: (_, _) async {},
                onCorrect: () {},
                availableMessages: const [],
                onSelectMessage: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Original: checkIn · offset 540 min · 2026-10-18T14:55:00.000Z',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Effective: checkOut · 2026-10-18T15:05:00.000Z · offset -240 min',
          ),
          findsOneWidget,
        );
        final overview = await manager.queries
            .forManager(manager.context(company))
            .first;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StaffHomeScreen(
                overview: overview,
                onCapture: () {},
                onAttendance: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('2026-10-19 00:05 Asia/Tokyo'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closeNativeAcceptance(devices);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'native delayed import rejects company change and five minute idle expiry',
    (tester) async {
      final devices = await nativeAcceptanceDevices([
        'callback-manager',
        'callback-staff',
      ]);
      final manager = devices[0], staff = devices[1];
      try {
        final a = await manager.createCompany();
        await enrollAcceptance(manager, staff, a);
        final receipt = await captureAcceptance(manager, staff, a);
        final b = await manager.createCompany();
        final person = manager.identity.requireActor(manager.session).personId;
        final port = _DelayedMessages();
        var locked = false;
        Future<void> show(Company company) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ReviewWorkspace(
                  key: const Key('native-transfer-review'),
                  service: manager.attendance,
                  session: manager.session,
                  company: company,
                  ids: SecureIds(),
                  canManage: true,
                  staff: const [],
                  messages: port,
                  onChanged: () {},
                  onLocked: () {
                    locked = true;
                  },
                ),
              ),
            ),
          );
          await settleReview(tester);
        }

        Future<void> start() async {
          port.pending = Completer<Uint8List?>();
          port.entered = Completer<void>();
          await tester.tap(find.text('Import receipt or correction'));
          await tester.pump();
          // receiveTransfer awaits a real database authorization before opening
          // the injected picker. Wait for that boundary, not one rendered frame.
          await tester.runAsync(
            () => port.entered.future.timeout(const Duration(seconds: 10)),
          );
        }

        await show(a);
        await start();
        await show(b);
        port.pending.complete(receipt.bytes);
        await settleReview(tester);
        expect(
          find.text('Return to the original company to continue'),
          findsOneWidget,
        );
        expect(await manager.attendance.list(manager.session, a.id), isEmpty);
        expect(await manager.attendance.list(manager.session, b.id), isEmpty);
        await show(a);
        await start();
        port.pending.complete(null);
        await settleReview(tester);
        expect(await manager.count('attendance'), 0);
        await start();
        manager.clock.advance(const Duration(minutes: 5));
        port.pending.complete(receipt.bytes);
        await settleReview(tester);
        expect(locked, isTrue);
        expect(await manager.count('attendance'), 0);
        expect(await manager.count('receiptImport'), 0);
        manager.session = await manager.identity.unlock(
          person,
          acceptancePassword,
        );
        expect(await manager.attendance.list(manager.session, a.id), isEmpty);
        expect(await manager.attendance.list(manager.session, b.id), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closeNativeAcceptance(devices);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'native injected SQL abort retains draft and exact retry receipt',
    (tester) async {
      final devices = await nativeAcceptanceDevices([
        'storage-manager',
        'storage-staff',
      ]);
      final manager = devices[0], staff = devices[1];
      try {
        final company = await manager.createCompany();
        await enrollAcceptance(manager, staff, company);
        final code = await manager.capture.createWorkplaceCode(
          manager.context(company),
        );
        final verified = await staff.capture.verifyWorkplace(
          staff.session,
          company.id,
          MessageCodec().encode(code),
        );
        final draft = await staff.capture.beginDraft(
          staff.session,
          company.id,
          verified,
          PunchKind.checkIn,
        );
        await staff.database.customStatement(
          "CREATE TEMP TRIGGER injected_failure BEFORE INSERT ON revision_journal BEGIN SELECT RAISE(ABORT, 'injected storage failure'); END",
        );
        final failed = await staff.capture.recordPunch(
          draft.context(staff.session),
          verified,
          draft.kind,
        );
        expect(
          failed,
          isA<Rejected<AttendanceReceipt>>().having(
            (r) => r.error,
            'error',
            CheckError.storageFailure,
          ),
        );
        expect(await staff.count('attendance'), 0);
        expect(await staff.count('attendanceOutbox'), 0);
        expect(
          (await staff.capture.currentDraft(
            staff.session,
            company.id,
          ))!.operationId,
          draft.operationId,
        );
        await staff.reopen();
        final saved =
            await staff.capture.recordPunch(
                  draft.context(staff.session),
                  verified,
                  draft.kind,
                )
                as Committed<AttendanceReceipt>;
        await staff.reopen();
        final retained = await staff.capture.getReceipt(
          staff.session,
          company.id,
          saved.value.eventId,
        );
        expect(retained.bytes, orderedEquals(saved.value.bytes));
        expect(
          (await staff.capture.currentDraft(
            staff.session,
            company.id,
          ))!.operationId,
          draft.operationId,
        );
        expect(await staff.count('attendance'), 1);
        expect(await staff.count('attendanceOutbox'), 1);
      } finally {
        await closeNativeAcceptance(devices);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'native handover survives graceful reopen lost ack and fresh capture',
    (tester) async {
      final devices = await nativeAcceptanceDevices([
        'handover-source',
        'handover-target',
      ]);
      final source = devices[0], target = devices[1];
      try {
        final company = await source.createCompany();
        final owner = source.identity.requireActor(source.session);
        final receipt = await captureAcceptance(source, source, company);
        final oldDraft = (await source.capture.currentDraft(
          source.session,
          company.id,
        ))!;
        final intent = (await source.repository.read(
          company.id,
          'capture-intent:${oldDraft.operationId}',
        ))!;
        final candidate = await target.identity.stageRecoveryIdentity(
          target.session,
          companyId: company.id,
          personId: owner.personId,
          displayName: 'Synthetic transferred owner',
          rootFingerprint: company.rootFingerprint,
          passphrase: acceptancePassword,
        );
        final replacement = LocalDeviceReplacementService(
          repository: target.repository,
          identity: target.identity,
          keys: target.keys,
          clock: target.clock,
          ids: SecureIds(),
        );
        final request = await replacement.createRequest(
          target.session,
          company.id,
          null,
          candidate: candidate,
        );
        final verified = await source.enrollment.verifyIncoming(
          source.session,
          MessageCodec().encode(request),
        );
        final offer = await source.handover.begin(
          source.context(company),
          verified,
          archivePassphrase: acceptancePassword,
        );
        await source.reopen();
        final reopenedOffer = (await source.handover.pendingOffer(
          source.session,
          company.id,
        ))!;
        expect(
          MessageCodec().encode(reopenedOffer.transfer),
          orderedEquals(MessageCodec().encode(offer.transfer)),
        );
        expect(reopenedOffer.archive.artifactId, offer.archive.artifactId);
        Future<void> expectFrozen() => expectLater(
          source.enrollment.createInvitation(source.context(company)),
          throwsA(
            isA<CheckException>().having(
              (e) => e.code,
              'code',
              CheckError.recoveryRequired,
            ),
          ),
        );
        await expectFrozen();
        final file = File(
          '${target.paths.root.path}/handover.razecheck-backup',
        );
        await file.writeAsBytes(
          await source.handover.exportArtifact(source.session, reopenedOffer),
          flush: true,
        );
        final preview = await target.archives.inspect(
          target.session,
          file.path,
          acceptancePassword,
        );
        final ack = await target.handover.activate(
          target.session,
          preview,
          reopenedOffer,
          candidate: candidate,
        );
        target.session = await target.identity.unlock(
          owner.personId,
          acceptancePassword,
        );
        await target.reopen();
        expect(
          MessageCodec().encode(
            (await target.handover.activationAcknowledgment(
              target.session,
              company.id,
            ))!,
          ),
          orderedEquals(MessageCodec().encode(ack)),
        );
        // Deliberately withhold the acknowledgment from the old installation.
        await source.reopen();
        await expectFrozen();
        expect(
          await target.capture.currentDraft(target.session, company.id),
          isNull,
        );
        final recovered = (await target.companies.readCompany(
          target.session,
          company.id,
        ))!;
        final code = await target.capture.createWorkplaceCode(
          target.context(recovered),
        );
        final workplace = await target.capture.verifyWorkplace(
          target.session,
          company.id,
          MessageCodec().encode(code),
        );
        final draft = await target.capture.beginDraft(
          target.session,
          company.id,
          workplace,
          PunchKind.checkOut,
        );
        expect(
          await target.capture.recordPunch(
            draft.context(target.session),
            workplace,
            draft.kind,
          ),
          isA<Committed<AttendanceReceipt>>(),
        );
        expect(
          (await target.repository.read(company.id, receipt.eventId))!.payload,
          orderedEquals(receipt.bytes),
        );
        expect(
          (await target.repository.read(company.id, intent.id))!.payload,
          orderedEquals(intent.payload),
        );
        expect(await target.count('attendance'), 2);
        expect(
          (await target.queries.historyPage(
            target.session,
            company.id,
            scope: AttendanceScope.management,
          )).items.length,
          2,
        );
        final verifiedAck = await source.enrollment.verifyIncoming(
          source.session,
          MessageCodec().encode(ack),
        );
        await source.handover.finish(source.context(company), verifiedAck);
      } finally {
        await closeNativeAcceptance(devices);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

final class _DelayedMessages implements AttendanceMessagePort {
  late Completer<Uint8List?> pending;
  late Completer<void> entered;
  @override
  Future<Uint8List?> receive() {
    entered.complete();
    return pending.future;
  }

  @override
  Future<void> send(Uint8List bytes) async {}
}
