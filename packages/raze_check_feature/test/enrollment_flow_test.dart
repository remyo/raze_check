@Timeout(Duration(minutes: 2))
library;

import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';

class FakeMessagePort implements EnrollmentMessagePort {
  final incoming = Queue<Uint8List>();
  final sent = <Uint8List>[];
  @override
  Future<Uint8List?> receive() async =>
      incoming.isEmpty ? null : incoming.removeFirst();
  @override
  Future<void> send(Uint8List bytes) async {
    sent.add(Uint8List.fromList(bytes));
  }
}

void main() {
  late TwoDeviceFixture pair;
  setUp(() async => pair = await TwoDeviceFixture.create());
  tearDown(() => pair.dispose());
  Future<void> press(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await settleEnrollment(tester);
  }

  testWidgets(
    'injected bytes run invitation consent, pending, manager approval and grant receipt',
    (tester) async {
      final managerPort = FakeMessagePort(), staffPort = FakeMessagePort();
      Future<void> show(
        EnrollmentDevice device,
        FakeMessagePort port, {
        bool manager = false,
      }) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: EnrollmentWorkspace(
                  key: UniqueKey(),
                  service: device.enrollment,
                  session: device.session,
                  ids: SecureIds(),
                  messages: port,
                  company: manager ? pair.company : null,
                  canManage: manager,
                  onChanged: () {},
                  onLocked: () {},
                ),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await settleEnrollment(tester);
      }

      await show(pair.manager, managerPort, manager: true);
      await press(tester, 'Create invitation');
      expect(
        find.textContaining(pair.company.rootFingerprint.substring(0, 12)),
        findsOneWidget,
      );
      await press(tester, 'Send invitation');
      staffPort.incoming.add(managerPort.sent.single);
      await show(pair.staff, staffPort);
      await press(tester, 'Read invitation');
      expect(find.text(pair.company.rootFingerprint), findsOneWidget);
      expect(
        await pair.staff.storage.keys.read('vault:${pair.companyId}'),
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm and request to join'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await press(tester, 'Confirm and request to join');
      expect(find.text('Awaiting manager approval'), findsOneWidget);
      expect(find.textContaining('cannot record attendance'), findsOneWidget);
      managerPort.incoming.add(staffPort.sent.single);
      await show(pair.manager, managerPort, manager: true);
      await press(tester, 'Read join request');
      expect(find.text('Staff'), findsOneWidget);
      expect(
        await tester.runAsync(() => pair.manager.employeeCount(pair.companyId)),
        0,
      );
      await press(tester, 'Approve and send membership');
      staffPort.incoming.add(managerPort.sent.last);
      await show(pair.staff, staffPort);
      await press(tester, 'Receive membership');
      expect(find.text('Membership active'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => pair.staff.canIssueAttendance(pair.companyId),
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'request send failure preserves pending state and retries exact committed bytes',
    (tester) async {
      final port = FailingSendPort();
      port.incoming.add(
        await tester.runAsync(
              () async => MessageCodec().encode(
                await pair.manager.enrollment.createInvitation(
                  pair.context('invite'),
                ),
              ),
            )
            as Uint8List,
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnrollmentWorkspace(
                service: pair.staff.enrollment,
                session: pair.staff.session,
                messages: port,
                ids: SecureIds(),
                onChanged: () {},
                onLocked: () {},
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await settleEnrollment(tester);
      await press(tester, 'Read invitation');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await press(tester, 'Confirm and request to join');
      expect(find.text('Awaiting manager approval'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => pair.staff.canIssueAttendance(pair.companyId),
        ),
        isFalse,
      );
      // Recreate the feature as after process restart: pending state comes
      // from the encrypted personal outbox, not an in-memory widget field.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnrollmentWorkspace(
                key: UniqueKey(),
                service: pair.staff.enrollment,
                session: pair.staff.session,
                messages: port,
                ids: SecureIds(),
                onChanged: () {},
                onLocked: () {},
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await settleEnrollment(tester);
      expect(find.text('Awaiting manager approval'), findsOneWidget);
      port.fail = false;
      await press(tester, 'Send join request again');
      expect(port.sent, hasLength(1));
      expect(port.sent.single, port.firstAttempt);
    },
  );
}

final class FailingSendPort extends FakeMessagePort {
  bool fail = true;
  Uint8List? firstAttempt;
  @override
  Future<void> send(Uint8List bytes) async {
    firstAttempt ??= Uint8List.fromList(bytes);
    if (fail) throw StateError('Sharing unavailable');
    await super.send(bytes);
  }
}

Future<void> settleEnrollment(WidgetTester tester) async {
  await tester.runAsync(() async {
    // Render busy before testing it; tap can schedule a frame without pumping.
    await tester.pump();
    final until = DateTime.now().add(const Duration(seconds: 10));
    while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
        DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}
