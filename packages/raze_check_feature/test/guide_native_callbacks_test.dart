import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_feature/src/guides/guide_catalog.dart';
import 'package:raze_check_feature/src/guides/guide_controller.dart';
import 'package:raze_check_feature/src/guides/guide_layer.dart';
import 'package:raze_check_feature/src/guides/guide_scene.dart';
import 'package:raze_check_feature/src/guides/guide_scope.dart';
import 'support/guide_fixture.dart';
import 'support/dashboard_fixture.dart';
import 'enrollment_flow_test.dart' show FakeMessagePort, settleEnrollment;
import '../../raze_check_local/test/support/two_device_fixture.dart';

void main() {
  for (final report in [true, false]) {
    for (final leave in [false, true]) {
      testWidgets(
        '${report ? "CSV share" : "invitation history Files"} pauses exact scene and validates return leave=$leave',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1100, 1500));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final pair = report
              ? (await tester.runAsync(dashboardFixture))!.pair
              : (await tester.runAsync(TwoDeviceFixture.create))!;
          final controller = GuideController(catalog: GuideCatalog());
          await controller.initialize();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            await tester.runAsync(pair.dispose);
          });
          final pending = Completer<void>(), entered = Completer<void>();
          final messages = FakeMessagePort();
          if (!report) {
            messages.incoming.add(
              (await tester.runAsync(
                () async => MessageCodec().encode(
                  await pair.manager.enrollment.createInvitation(
                    pair.context('history-invite'),
                  ),
                ),
              ))!,
            );
          }
          final scene = testGuideContext(
            variants: {
              if (report) 'reports': 'personal' else 'membership': 'staff',
            },
          );
          await tester.runAsync(() async {
            await tester.pumpWidget(
              MaterialApp(
                home: GuideScope(
                  controller: controller,
                  child: GuideLayer(
                    child: GuideScene(
                      context: scene,
                      child: Scaffold(
                        body: report
                            ? AttendanceReportScreen(
                                services: featureServices(
                                  pair.staff,
                                  shareReport: (_, guard) async {
                                    await guard();
                                    entered.complete();
                                    await pending.future;
                                    return ShareOutcome.dismissed;
                                  },
                                ),
                                session: pair.staff.session,
                                company: pair.company,
                                canExport: false,
                                personalAllowed: true,
                              )
                            : EnrollmentWorkspace(
                                service: pair.staff.enrollment,
                                session: pair.staff.session,
                                ids: SecureIds(),
                                messages: messages,
                                pickHistory: (guard) async {
                                  await guard();
                                  entered.complete();
                                  await pending.future;
                                  return null;
                                },
                                onChanged: () {},
                                onLocked: () {},
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          });
          await settleEnrollment(tester);
          if (report) {
            await tester.enterText(
              find.widgetWithText(TextField, 'Start date (YYYY-MM-DD)'),
              '2026-10-19',
            );
            await tester.enterText(
              find.widgetWithText(TextField, 'End date (YYYY-MM-DD)'),
              '2026-10-19',
            );
            await tester.runAsync(() async {
              await tester.tap(find.text('Generate report'));
              await tester.pump();
            });
            await settleFeature(tester);
            expect(find.text('Share CSV'), findsOneWidget);
          } else {
            await tester.runAsync(() async {
              await tester.tap(find.text('Read invitation'));
              await tester.pump();
            });
            await settleEnrollment(tester);
            await tester.tap(find.byType(CheckboxListTile));
            await tester.pump();
          }
          controller.start(report ? 'reports' : 'membership');
          await tester.pumpAndSettle();
          final original = controller.currentContext!;
          final step = controller.active!.stepIndex;
          final label = report
              ? 'Share CSV'
              : 'Add missing public authority history from Files';
          // Invoke the real current UI callback without overlay hit testing.
          await tester.runAsync(() async {
            if (report) {
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, label),
                  )
                  .onPressed!();
            } else {
              tester
                  .widget<TextButton>(find.widgetWithText(TextButton, label))
                  .onPressed!();
            }
          });
          for (var i = 0; i < 100 && !entered.isCompleted; i++) {
            await tester.pump();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
          }
          expect(
            entered.isCompleted,
            isTrue,
            reason: 'Native callback must be reached',
          );
          await tester.pump();
          final pausedWhilePending = controller.paused;
          if (leave) await tester.pumpWidget(const SizedBox());
          pending.complete();
          for (
            var i = 0;
            i < 200 &&
                (controller.paused ||
                    find.byType(LinearProgressIndicator).evaluate().isNotEmpty);
            i++
          ) {
            await tester.pump();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
          }
          await tester.pump();
          expect(pausedWhilePending, isTrue);
          expect(controller.paused, isFalse);
          if (leave) {
            expect(controller.active, isNull);
            expect(controller.currentContext, isNull);
          } else {
            expect(controller.currentContext!.token, same(original.token));
            expect(controller.active?.stepIndex, step);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
