import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'support/dashboard_fixture.dart';

void main() {
  testWidgets('full feature shells fit phone/tablet, light/dark and large text', (
    tester,
  ) async {
    final f = (await tester.runAsync(dashboardFixture))!;
    addTearDown(() async {
      await tester.runAsync(f.pair.dispose);
    });
    final manrope = FontLoader('packages/raze_check_feature/Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      manrope.addFont(
        rootBundle.load(
          'packages/raze_check_feature/assets/fonts/Manrope-$weight.ttf',
        ),
      );
    }
    await tester.runAsync(manrope.load);
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(icons.load);
    final output = Platform.environment['RAZE_VISUAL_DIR'];
    for (final manager in [false, true]) {
      for (final dark in [false, true]) {
        final device = manager ? f.pair.manager : f.pair.staff;
        final services = featureServices(device);
        final boundaryKey = GlobalKey();
        var width = 390.0, scale = 1.0;
        final entry = RazeCheckFeature(
          services: services,
          initialCompanyId: f.pair.companyId,
          host: CheckFeatureHost(onExit: () {}),
        );
        Future<void> mount() async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, width == 768 ? 1100 : 900);
          await tester.runAsync(() async {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? CheckTheme.dark() : CheckTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: boundaryKey, child: child!),
                ),
                home: entry,
              ),
            );
          });
          await settleFeature(tester);
        }

        await mount();
        await unlockFeature(tester, manager ? 'Owner' : 'Staff');
        await settleFeature(
          tester,
          until: manager ? 'A clear view' : 'Your attendance',
        );
        for (final size in [320.0, 390.0, 768.0]) {
          for (final textScale in [1.0, 2.0]) {
            width = size;
            scale = textScale;
            await mount();
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'full shell $width scale $scale dark $dark manager $manager',
            );
            expect(find.byKey(const Key('company-switcher')), findsOneWidget);
            expect(find.text(manager ? 'Overview' : 'Home'), findsOneWidget);
            expect(find.text('Attendance'), findsOneWidget);
            if (output != null &&
                ((scale == 1 && width != 320) ||
                    (manager && !dark && width == 320 && scale == 2))) {
              await tester.runAsync(() async {
                final boundary =
                    boundaryKey.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(output).create(recursive: true);
                await File('$output/full-shell-metadata.txt').writeAsString(
                  'SYNTHETIC TEST DATA. Actual Flutter RazeCheckFeature with real local services. '
                  'Independent synthetic staff and manager repositories, one local-only receipt and one manager-received receipt. '
                  'Bundled Manrope and MaterialIcons loaded. Captures use 1.0 text scale; '
                  'assertions also cover 320/390/768 at 1.0/2.0. Not physical-device evidence.\n',
                );
                await File(
                  '$output/full-${manager ? "manager" : "staff"}-${dark ? "dark" : "light"}-${width.toInt()}${scale == 2 ? "-2x" : ""}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
        }
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
