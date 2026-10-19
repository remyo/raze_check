@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';
import '../../raze_check_local/test/receipt_import_test.dart' show service;
import 'capture_flow_test.dart' show CapturePort;

void main() {
  testWidgets('manager imports, reviews and resends signed decision', (
    tester,
  ) async {
    final p = (await tester.runAsync(TwoDeviceFixture.create))!;
    addTearDown(p.dispose);
    await tester.runAsync(p.enrollStaff);
    final m = service(p.manager);
    final receipt = (await tester.runAsync(p.captureCheckIn))!;
    final port = CapturePort()..incoming = receipt.bytes;
    Future<void> press(String text) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(text));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewWorkspace(
              service: m,
              session: p.manager.session,
              company: p.company,
              ids: SecureIds(),
              canManage: true,
              staff: await p.manager.companies.listStaff(
                p.manager.session,
                p.companyId,
              ),
              messages: port,
              onChanged: () {},
              onLocked: () {},
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    await press('Import receipt or correction');
    expect(find.textContaining('pending'), findsWidgets);
    await press('View attendance');
    await tester.enterText(
      find.byKey(const Key('review-reason')),
      'Checked original',
    );
    await press('Approve attendance');
    expect(find.textContaining('approved'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Share selected return'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await press('Share selected return');
    expect(port.sent, isNotEmpty);
    final returned = MessageCodec().decode(
      port.sent.last,
      maxBytes: MessageLimits.fileBytes,
    );
    expect(returned.kind, MessageKind.attendanceDecision);
    await tester.scrollUntilVisible(
      find.text('Show receipt acknowledgment'),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await press('Show receipt acknowledgment');
    await tester.scrollUntilVisible(
      find.text('Share selected return'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await press('Share selected return');
    expect(
      MessageCodec()
          .decode(port.sent.last, maxBytes: MessageLimits.fileBytes)
          .kind,
      MessageKind.receiptAck,
    );
  });
  testWidgets('manual entry remains pending and local until explicit review', (
    tester,
  ) async {
    final p = (await tester.runAsync(TwoDeviceFixture.create))!;
    addTearDown(p.dispose);
    await tester.runAsync(p.enrollStaff);
    await showReview(tester, p, CapturePort());
    await pressReview(tester, 'Manual entry');
    await tester.tap(find.text('Employee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Camera failed',
    );
    await pressReview(tester, 'Save pending manual entry');
    expect(find.text('Attendance pending'), findsOneWidget);
    expect(find.text('Manual · local record'), findsOneWidget);
    expect(
      find.textContaining('no staff-phone return exchange'),
      findsOneWidget,
    );
    expect(find.text('Share selected return'), findsNothing);
    await tester.enterText(find.byKey(const Key('review-reason')), 'Checked');
    await pressReview(tester, 'Approve attendance');
    expect(find.text('Attendance approved'), findsOneWidget);
    final records = await tester.runAsync(
      () => service(p.manager).list(p.manager.session, p.companyId),
    );
    expect(records!.single.source, AttendanceSource.manual);
  });
  testWidgets(
    'staff request resolution displays separate correction result and pending attendance',
    (tester) async {
      final p = (await tester.runAsync(TwoDeviceFixture.create))!;
      addTearDown(p.dispose);
      await tester.runAsync(p.enrollStaff);
      final request = await tester.runAsync(() async {
        final r = await p.captureCheckIn(), m = service(p.manager);
        await m.importReceipt(
          p.context('import'),
          await m.verifyIncoming(p.manager.session, p.companyId, r.bytes),
        );
        return service(p.staff).request(
          p.staff.session,
          p.companyId,
          r.eventId,
          ProposedCorrection(
            kind: r.kind,
            utcMs: r.claimedUtcMs,
            offsetMinutes: r.offsetMinutes,
            reason: 'Please check',
          ),
          'request',
        );
      });
      await showReview(
        tester,
        p,
        CapturePort()..incoming = MessageCodec().encode(request!),
      );
      await pressReview(tester, 'Import receipt or correction');
      expect(find.text('Staff correction request'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Resolution reason'),
        'Already correct',
      );
      await pressReview(tester, 'Reject correction');
      expect(find.text('Attendance pending'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('correction rejected'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('correction rejected'), findsOneWidget);
    },
  );
  testWidgets('late received input after leaving company commits no import', (
    tester,
  ) async {
    final p = (await tester.runAsync(TwoDeviceFixture.create))!;
    addTearDown(p.dispose);
    await tester.runAsync(p.enrollStaff);
    final receipt = (await tester.runAsync(p.captureCheckIn))!;
    final port = CapturePort()..delayed = Completer<Uint8List?>();
    await showReview(tester, p, port);
    await tester.tap(find.text('Import receipt or correction'));
    await tester.pump();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Other company'))),
    );
    await tester.runAsync(() async {
      port.delayed!.complete(receipt.bytes);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(
      await tester.runAsync(
        () => p.manager.storage.repo.read(p.companyId, receipt.eventId),
      ),
      isNull,
    );
  });
}

Future<void> pressReview(WidgetTester tester, String text) async {
  await tester.runAsync(() async {
    await tester.tap(find.text(text));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pumpAndSettle();
}

Future<void> showReview(
  WidgetTester tester,
  TwoDeviceFixture p,
  CapturePort port,
) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewWorkspace(
            service: service(p.manager),
            session: p.manager.session,
            company: p.company,
            ids: SecureIds(),
            canManage: true,
            staff: const [],
            messages: port,
            onChanged: () {},
            onLocked: () {},
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pumpAndSettle();
}
