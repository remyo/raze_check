import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../../../raze_check_local/test/support/two_device_fixture.dart';
import '../../../raze_check_local/test/receipt_import_test.dart' show service;
import '../../../raze_check_local/test/attendance_queries_test.dart'
    show queries;

Future<({TwoDeviceFixture pair, StaffOverview staff, ManagerOverview manager})>
dashboardFixture() async {
  final p = await TwoDeviceFixture.create();
  await p.enrollStaff();
  final first = await p.captureCheckIn();
  await p.capture(PunchKind.checkOut, newPunch: true);
  final m = service(p.manager), s = service(p.staff);
  final got = await m.importReceipt(
    p.context('receive'),
    await m.verifyIncoming(p.manager.session, p.companyId, first.bytes),
  );
  await s.accept(
    p.staff.session,
    await s.verifyIncoming(
      p.staff.session,
      p.companyId,
      MessageCodec().encode(got.returnMessage!),
    ),
  );
  return (
    pair: p,
    staff: await queries(p.staff).forStaff(p.staff.session, p.companyId).first,
    manager: await queries(p.manager).forManager(p.context('overview')).first,
  );
}

CheckServices featureServices(EnrollmentDevice d) {
  final archive = LocalArchiveService(
    paths: d.storage.paths,
    keys: d.storage.keys,
    repository: d.storage.repo,
    identity: d.identity,
    clock: d.clock,
    ids: SecureIds(),
  );
  return CheckServices(
    identity: d.identity,
    companies: d.companies,
    enrollment: d.enrollment,
    capture: d.capture,
    attendance: service(d),
    backups: archive,
    restores: archive,
    handover: LocalHandoverService(
      repository: d.storage.repo,
      identity: d.identity,
      keys: d.storage.keys,
      clock: d.clock,
      ids: SecureIds(),
      archives: archive,
    ),
    queries: queries(d),
    transfer: (_) => TestTransfer(),
    recoveryIdentity: d.identity,
    replacement: LocalDeviceReplacementService(
      repository: d.storage.repo,
      identity: d.identity,
      keys: d.storage.keys,
      clock: d.clock,
      ids: SecureIds(),
    ),
    history: LocalAuthorityHistoryService(
      repository: d.storage.repo,
      identity: d.identity,
      keys: d.storage.keys,
      ids: SecureIds(),
    ),
    staffBackups: archive,
    files: RecoveryFiles(
      pickBytes: (_) async => null,
      pickArchive: (_) async => null,
      releaseArchive: (_) async {},
      share: (_, _, guard) async {
        await guard();
        return ShareOutcome.dismissed;
      },
    ),
    shareReport: (report, guard) async {
      await guard();
      AttendanceCsv.encode(report);
      return ShareOutcome.dismissed;
    },
  );
}

class TestTransfer implements TransferPort {
  @override
  Future<Uint8List?> scan({required Set<MessageKind> allowed}) async => null;
  @override
  Future<Uint8List?> pickMessage() async => null;
  @override
  Future<Uint8List?> decodePickedImage() async => null;
  @override
  Future<ShareOutcome> shareMessage(
    Uint8List bytes,
    String suggestedName,
  ) async => ShareOutcome.dismissed;
  @override
  Future<ShareOutcome> shareQrPng(Uint8List bytes) async =>
      ShareOutcome.dismissed;
}

Future<void> settleFeature(WidgetTester tester, {String? until}) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    do {
      await tester.pump();
      final busy =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
          find.text('Unlocking…').evaluate().isNotEmpty;
      if (!busy &&
          (until == null || find.textContaining(until).evaluate().isNotEmpty)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    } while (DateTime.now().isBefore(deadline));
  });
  await tester.pumpAndSettle();
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

Future<void> unlockFeature(WidgetTester tester, String name) async {
  await settleFeature(tester, until: 'Unlock $name');
  await tester.tap(find.text('Unlock $name'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('unlock-passphrase')),
    'a strong local passphrase',
  );
  await tester.runAsync(() async {
    await tester.tap(find.text('Unlock'));
    await tester.pump();
  });
  await settleFeature(tester);
}
