import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'support/dashboard_fixture.dart';

void main() {
  test(
    'theme preserves 48 pixel minimum controls and readable surface contrast',
    () {
      for (final theme in [CheckTheme.light(), CheckTheme.dark()]) {
        expect(
          theme.iconButtonTheme.style!.minimumSize!.resolve({}),
          const Size(48, 48),
        );
        final a = theme.colorScheme.onSurface.computeLuminance(),
            b = theme.colorScheme.surface.computeLuminance();
        expect(
          (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
          greaterThan(4.5),
        );
      }
    },
  );
  testWidgets(
    'real dashboards fit phone/tablet and large text with semantic controls',
    (tester) async {
      final f = (await tester.runAsync(dashboardFixture))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.pair.dispose);
      });
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        final loader = FontLoader('packages/raze_check_feature/Manrope')
          ..addFont(
            rootBundle.load(
              'packages/raze_check_feature/assets/fonts/Manrope-$weight.ttf',
            ),
          );
        await tester.runAsync(loader.load);
      }
      final material = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await tester.runAsync(material.load);
      final semantics = tester.ensureSemantics();

      final output = Platform.environment['RAZE_VISUAL_DIR'];
      for (final width in [320.0, 390.0, 768.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final dark in [false, true]) {
            for (final manager in [false, true]) {
              tester.view.reset();
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = Size(width, width == 768 ? 1100 : 900);
              final key = GlobalKey();
              await tester.pumpWidget(
                MaterialApp(
                  theme: dark ? CheckTheme.dark() : CheckTheme.light(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: RepaintBoundary(
                    key: key,
                    child: Scaffold(
                      appBar: AppBar(
                        leading: Image.asset(
                          'packages/raze_check_feature/assets/branding/raze_check_logo_master.png',
                          semanticLabel: 'Raze Check mascot',
                        ),
                        title: const Text('Synthetic test records'),
                      ),
                      body: manager
                          ? ManagerHomeScreen(
                              overview: f.manager,
                              onAttendance: () {},
                              onManual: () {},
                              onInvite: () {},
                              onWorkplace: () {},
                              backupLabel: 'No backup recorded on this device.',
                            )
                          : StaffHomeScreen(
                              overview: f.staff,
                              onCapture: () {},
                              onAttendance: () {},
                              backupLabel: 'No backup recorded on this device.',
                            ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: 'width $width scale $scale dark $dark manager $manager',
              );
              expect(find.text('Absent'), findsNothing);
              expect(find.text('Salary'), findsNothing);
              if (scale == 1 && width == 390) {
                await expectLater(
                  tester,
                  meetsGuideline(androidTapTargetGuideline),
                );
                await expectLater(
                  tester,
                  meetsGuideline(labeledTapTargetGuideline),
                );
              }
              if (output != null && scale == 1 && width != 320) {
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                await tester.runAsync(() async {
                  final image = await boundary.toImage();
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await Directory(output).create(recursive: true);
                  await File(
                    '$output/${manager ? "manager" : "staff"}-${dark ? "dark" : "light"}-${width.toInt()}.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
            }
          }
        }
      }
      semantics.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
