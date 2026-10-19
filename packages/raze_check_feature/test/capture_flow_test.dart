@Timeout(Duration(minutes: 2))
library;

import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';

class CapturePort implements AttendanceMessagePort, EnrollmentMessagePort {
  Uint8List? incoming;
  Completer<Uint8List?>? delayed;
  bool failSend = false;
  final sent = <Uint8List>[];
  @override
  Future<Uint8List?> receive() async =>
      delayed == null ? incoming : delayed!.future;
  @override
  Future<void> send(Uint8List bytes) async {
    if (failSend) throw StateError('share failed');
    sent.add(bytes);
  }
}

void main() {
  late TwoDeviceFixture pair;
  setUp(() async {
    pair = await TwoDeviceFixture.create();
    await pair.enrollStaff();
  });
  tearDown(() => pair.dispose());
  Future<void> press(WidgetTester tester, String text) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(text));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester, CapturePort port) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CaptureWorkspace(
              key: UniqueKey(),
              service: pair.staff.capture,
              session: pair.staff.session,
              company: pair.company,
              messages: port,
              ids: SecureIds(),
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

  testWidgets(
    'capture and reopen receipt, failed share retries exact bytes without another punch',
    (tester) async {
      final port = CapturePort();
      port.incoming = await tester.runAsync(
        () async => MessageCodec().encode((await pair.workplace()).message),
      );
      await show(tester, port);
      await press(tester, 'Check in');
      expect(find.text('Saved on this device'), findsOneWidget);
      final saved = (await tester.runAsync(
        () => pair.staff.capture.listOutbox(pair.staff.session, pair.companyId),
      ))!.single;
      port.failSend = true;
      await press(tester, 'Share receipt');
      expect(find.text('Saved on this device'), findsOneWidget);
      await tester.runAsync(() => pair.restartStaff());
      await show(tester, port);
      expect(find.text('Saved on this device'), findsOneWidget);
      port.failSend = false;
      await press(tester, 'Share receipt');
      expect(port.sent.single, orderedEquals(saved.bytes));
      expect(await tester.runAsync(() => pair.staff.eventCount()), 1);
      await press(tester, 'New punch');
      await press(tester, 'Check out');
      expect(await tester.runAsync(() => pair.staff.eventCount()), 2);
    },
  );
  testWidgets('storage failure never displays saved and retains retry draft', (
    tester,
  ) async {
    final port = CapturePort();
    port.incoming = await tester.runAsync(
      () async => MessageCodec().encode((await pair.workplace()).message),
    );
    // Persist draft first so the injected failure exercises the event transaction.
    await tester.runAsync(() async {
      final code = await pair.workplace();
      await pair.staff.capture.beginDraft(
        pair.staff.session,
        pair.companyId,
        code,
        PunchKind.checkIn,
      );
      await pair.staff.storage.failBeforeCommit();
    });
    await show(tester, port);
    await press(tester, 'Retry saved punch');
    expect(find.text('Saved on this device'), findsNothing);
    expect(await tester.runAsync(() => pair.staff.eventCount()), 0);
  });
  testWidgets(
    'late workplace input after company view closes creates no punch',
    (tester) async {
      final port = CapturePort()..delayed = Completer<Uint8List?>();
      final bytes = await tester.runAsync(
        () async => MessageCodec().encode((await pair.workplace()).message),
      );
      await show(tester, port);
      await tester.runAsync(() async {
        await tester.tap(find.text('Check in'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Other company'))),
      );
      await tester.runAsync(() async {
        port.delayed!.complete(bytes);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('Saved on this device'), findsNothing);
      expect(await tester.runAsync(() => pair.staff.eventCount()), 0);
    },
  );
  testWidgets(
    'company navigation can leave attendance for enrollment and setup',
    (tester) async {
      final port = CapturePort();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CompanyWorkspace(
                companies: pair.manager.companies,
                enrollment: pair.manager.enrollment,
                capture: pair.manager.capture,
                messages: port,
                attendanceMessages: port,
                session: pair.manager.session,
                ids: SecureIds(),
                onAuthorizedActivity: () {},
                onSessionChanged: (_) {},
                onLocked: () {},
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      await press(tester, 'Attendance and receipts');
      expect(find.text('Display workplace code'), findsOneWidget);
      await press(tester, 'Invite or review join');
      expect(find.text('Create invitation'), findsOneWidget);
      expect(find.text('Display workplace code'), findsNothing);
      await tester.tap(find.byTooltip('Create company'));
      await tester.pumpAndSettle();
      expect(find.text('Company name'), findsOneWidget);
    },
  );
}
