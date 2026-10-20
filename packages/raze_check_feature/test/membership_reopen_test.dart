import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';
import 'enrollment_flow_test.dart' show FakeMessagePort, settleEnrollment;

void main() {
  testWidgets('existing selected active membership hydrates on reopening', (
    tester,
  ) async {
    final p = (await tester.runAsync(TwoDeviceFixture.create))!;
    addTearDown(() async {
      await tester.runAsync(p.dispose);
    });
    await tester.runAsync(p.enrollStaff);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentWorkspace(
              service: p.staff.enrollment,
              companies: p.staff.companies,
              session: p.staff.session,
              ids: SecureIds(),
              messages: FakeMessagePort(),
              company: p.company,
              onChanged: () {},
              onLocked: () {},
            ),
          ),
        ),
      );
    });
    await settleEnrollment(tester);
    expect(find.text('Membership active'), findsOneWidget);
  });
}
