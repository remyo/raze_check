import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_feature/src/guides/guide_controller.dart';
import 'package:raze_check_feature/src/guides/guide_library_screen.dart';
import 'package:raze_check_feature/src/guides/guide_models.dart';
import 'package:raze_check_feature/src/guides/guide_panel.dart';
import 'package:raze_check_feature/src/guides/guide_scope.dart';
import 'package:raze_check_feature/src/guides/guide_target.dart';
import 'package:raze_check_feature/src/guides/welcome_screen.dart';

import 'support/dashboard_fixture.dart';
import 'support/guide_fixture.dart';

// Full-entry captures use real, independent local repositories and inert external
// adapters. No punch, review, archive, sharing or permission action creates a view.
void main() {
  for (final dark in [false, true]) {
    testWidgets('welcome ${dark ? 'dark' : 'light'} full-entry render', (
      tester,
    ) async {
      final scene = await _mount(tester, dark: dark, automaticWelcome: true);
      _expectWelcome(tester, scene);
      await _expectGuideControls(tester, find.byType(WelcomeScreen));
      _resetScroll(tester, find.byType(WelcomeScreen));
      await tester.pumpAndSettle();
      await scene.capture('welcome-${dark ? 'dark' : 'light'}.png');
      if (!dark) {
        await scene.resize(const Size(320, 900), 2);
        _expectWelcome(tester, scene);
        await _expectGuideControls(tester, find.byType(WelcomeScreen));
        _resetScroll(tester, find.byType(WelcomeScreen));
        await tester.pumpAndSettle();
        await scene.capture('welcome-large-text.png');
      }
      await scene.close();
    });
  }

  testWidgets('staff library exposes the real staff guide variants', (
    tester,
  ) async {
    final scene = await _mount(tester);
    await scene.unlock();
    expect(scene.controller.audience.variants['capture'], 'staff');
    expect(scene.controller.audience.variants['review'], 'staff');
    expect(scene.controller.audience.variants.containsKey('team'), isFalse);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
    });
    await _wait(
      tester,
      () =>
          find.text('Help & Guides').evaluate().isNotEmpty &&
          scene.controller.audience.variants['capture'] == 'staff',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Help & Guides'));
      await tester.pump();
    });
    await _wait(
      tester,
      () =>
          find.byType(GuideLibraryScreen).evaluate().isNotEmpty &&
          scene.controller.audience.variants['capture'] == 'staff',
    );
    expect(find.text('Check in and check out'), findsOneWidget);
    expect(
      find.text('Guide progress is shared on this device.'),
      findsOneWidget,
    );
    expect(find.text('Welcome to Raze Check'), findsOneWidget);
    expect(find.text('Manage staff and operator access'), findsNothing);
    expect(scene.controller.active, isNull);
    expect(tester.takeException(), isNull);
    await scene.capture('staff-guides.png');
    await scene.close();
  });

  testWidgets('staff capture aligns with Check in and remeasures on rotation', (
    tester,
  ) async {
    final scene = await _mount(tester, finishCompletedCapture: true);
    await scene.unlock();
    await scene.showGuide('capture', GuideDestination.capture);
    scene.controller.next();
    await _wait(tester, () => _hasStep(tester, 'capture-kind'));
    final target = find.byWidgetPredicate(
      (widget) => widget is GuideTarget && widget.id == 'capture-kind',
    );
    expect(
      find.descendant(
        of: target,
        matching: find.widgetWithText(FilledButton, 'Check in'),
      ),
      findsOneWidget,
    );
    _expectRun(scene, 'capture', 'staff', 'capture-kind');
    _expectAnchor(tester, target, requiredHighlight: true);
    await _expectGuideControls(tester, find.byType(GuidePanel));
    _resetScroll(tester, find.byType(GuidePanel));
    await tester.pumpAndSettle();
    await scene.capture('capture-highlight.png');

    final token = scene.controller.active!.contextToken;
    await scene.resize(const Size(844, 390), 1);
    _expectRun(scene, 'capture', 'staff', 'capture-kind');
    expect(scene.controller.active!.contextToken, same(token));
    _expectAnchor(tester, target);
    await _expectGuideControls(tester, find.byType(GuidePanel));
    _resetScroll(tester, find.byType(GuidePanel));
    await tester.pumpAndSettle();
    await scene.capture('capture-landscape.png');

    // Saved-receipt controls are absent until a real business action supplies
    // them. The guide must remain an explanation with an empty highlight.
    scene.controller.next();
    scene.controller.next();
    await _wait(tester, () => _hasStep(tester, 'capture-saved'));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is GuideTarget && widget.id == 'capture-saved',
      ),
      findsNothing,
    );
    expect(tester.getSize(find.byKey(const Key('guide-highlight'))), Size.zero);
    expect(find.text('Saved on this device'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await scene.close();
  });

  testWidgets('management review is the owner guide over received attendance', (
    tester,
  ) async {
    final scene = await _mount(tester, owner: true, dark: true);
    await scene.unlock();
    await scene.showGuide('review', GuideDestination.attendance);
    expect(find.byType(ReviewQueueScreen), findsOneWidget);
    expect(
      tester.widget<ReviewQueueScreen>(find.byType(ReviewQueueScreen)).records,
      isNotEmpty,
    );
    _expectRun(scene, 'review', 'owner', 'review-details');
    expect(find.text('Step 1 of 5'), findsOneWidget);
    await _expectGuideControls(tester, find.byType(GuidePanel));
    _resetScroll(tester, find.byType(GuidePanel));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await scene.capture('management-review.png');
    await scene.close();
  });

  testWidgets('reduced motion preserves the full-entry welcome controls', (
    tester,
  ) async {
    final scene = await _mount(
      tester,
      automaticWelcome: true,
      reducedMotion: true,
    );
    _expectWelcome(tester, scene);
    expect(
      MediaQuery.of(
        tester.element(find.byType(WelcomeScreen)),
      ).disableAnimations,
      isTrue,
    );
    await _expectGuideControls(tester, find.byType(WelcomeScreen));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    _expectRun(scene, 'welcome', 'public', 'welcome-profiles');
    expect(find.text('Step 2 of 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await scene.close();
  });

  testWidgets('owner backup uses the actual company scope on tablet', (
    tester,
  ) async {
    final scene = await _mount(tester, owner: true);
    await scene.resize(const Size(768, 1024), 1);
    await scene.unlock();
    await tester.runAsync(() async {
      await tester.tap(find.text('Backup / recovery'));
      await tester.pump();
    });
    await settleFeature(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Encrypted backup and passive restore'));
      await tester.pump();
    });
    await settleFeature(tester);
    await _wait(
      tester,
      () =>
          scene.controller.currentContext?.destination ==
          GuideDestination.backup,
    );
    expect(scene.controller.audience.variants['backup'], 'personal');
    final scope = find.byType(DropdownButton<String>);
    await tester.tap(scope);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.textContaining('Company: ').last);
      await tester.pump();
    });
    await _wait(
      tester,
      () => scene.controller.audience.variants['backup'] == 'owner',
    );
    expect(
      tester.widget<DropdownButton<String>>(scope).value,
      startsWith('Company: '),
    );
    await tester.tap(find.text('Show me how'));
    await _wait(tester, () => _hasStep(tester, 'backup-scope'));
    _expectRun(scene, 'backup', 'owner', 'backup-scope');
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.byKey(const Key('archive-passphrase')), findsOneWidget);
    expect(find.text('Save or share encrypted backup'), findsNothing);
    await _expectGuideControls(tester, find.byType(GuidePanel));
    _resetScroll(tester, find.byType(GuidePanel));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await scene.capture('backup-tablet.png');
    await scene.close();
  });
}

void _expectWelcome(WidgetTester tester, _VisualScene scene) {
  expect(find.byType(WelcomeScreen), findsOneWidget);
  expect(find.text('Offline attendance'), findsOneWidget);
  expect(find.text('Step 1 of 5'), findsOneWidget);
  _expectRun(scene, 'welcome', 'public', 'welcome-offline');
  expect(tester.takeException(), isNull);
}

void _expectRun(_VisualScene scene, String guide, String variant, String step) {
  final run = scene.controller.active!;
  expect(run.definition.id, guide);
  expect(run.definition.variantId, variant);
  expect(run.definition.steps[run.stepIndex].id, step);
}

bool _hasStep(WidgetTester tester, String step) {
  final panels = find.byType(GuidePanel);
  if (panels.evaluate().length != 1) return false;
  final run = tester.widget<GuidePanel>(panels).run;
  return run.definition.steps[run.stepIndex].id == step;
}

void _expectAnchor(
  WidgetTester tester,
  Finder target, {
  bool requiredHighlight = false,
}) {
  expect(find.byType(GuidePanel), findsOneWidget);
  final highlight = tester.getRect(find.byKey(const Key('guide-highlight')));
  if (requiredHighlight) expect(highlight.isEmpty, isFalse);
  if (!highlight.isEmpty) {
    final actual = tester.getRect(target);
    expect(highlight.left, closeTo(actual.left, .1));
    expect(highlight.top, closeTo(actual.top, .1));
    expect(highlight.width, closeTo(actual.width, .1));
    expect(highlight.height, closeTo(actual.height, .1));
    expect(
      tester.getRect(find.byType(GuidePanel)).overlaps(highlight),
      isFalse,
    );
  } else {
    // An unplaceable target keeps its real explanation and reachable controls.
    expect(find.text('Check in or Check out'), findsOneWidget);
  }
  expect(tester.takeException(), isNull);
}

Future<void> _expectGuideControls(
  WidgetTester tester,
  Finder presentation,
) async {
  final controls = find.descendant(
    of: presentation,
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );
  expect(controls, findsWidgets);
  for (final element in controls.evaluate().toList()) {
    final control = find.byWidget(element.widget);
    final size = tester.getSize(control);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    if ((element.widget as ButtonStyleButton).onPressed != null) {
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(control).getSemanticsData().label.trim(),
        isNotEmpty,
      );
      expect(control.hitTestable(), findsOneWidget);
    }
  }
  expect(tester.takeException(), isNull);
}

void _resetScroll(WidgetTester tester, Finder presentation) {
  final scrollables = find.descendant(
    of: presentation,
    matching: find.byType(Scrollable),
  );
  for (final element in scrollables.evaluate()) {
    tester
        .state<ScrollableState>(find.byWidget(element.widget))
        .position
        .jumpTo(0);
  }
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    do {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    } while (!ready() && DateTime.now().isBefore(deadline));
  });
  await tester.pumpAndSettle();
  expect(ready(), isTrue, reason: 'Expected guide scene must finish binding');
  expect(tester.takeException(), isNull);
}

Future<_VisualScene> _mount(
  WidgetTester tester, {
  bool owner = false,
  bool dark = false,
  bool automaticWelcome = false,
  bool reducedMotion = false,
  bool finishCompletedCapture = false,
}) async {
  final fixture = (await tester.runAsync(dashboardFixture))!;
  if (finishCompletedCapture) {
    // Retain both real receipts, but close the fixture's already-saved checkout
    // draft so CaptureWorkspace presents its normal new-punch controls.
    await tester.runAsync(() async {
      final staff = fixture.pair.staff;
      final draft = await staff.capture.currentDraft(
        staff.session,
        fixture.pair.companyId,
      );
      await staff.capture.finishDraft(
        staff.session,
        fixture.pair.companyId,
        draft!.eventId!,
      );
    });
  }
  addTearDown(() async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.runAsync(fixture.pair.dispose);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final manrope = FontLoader('packages/raze_check_feature/Manrope');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    manrope.addFont(
      rootBundle.load(
        'packages/raze_check_feature/assets/fonts/Manrope-$weight.ttf',
      ),
    );
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await tester.runAsync(manrope.load);
  await tester.runAsync(icons.load);
  final scene = _VisualScene(
    tester,
    owner: owner,
    dark: dark,
    reducedMotion: reducedMotion,
    entry: RazeCheckFeature(
      services: featureServices(
        owner ? fixture.pair.manager : fixture.pair.staff,
      ),
      initialCompanyId: fixture.pair.companyId,
      host: CheckFeatureHost(
        onExit: () {},
        guideProgress: MemoryGuideProgressStore(),
        guides: GuidePresentationConfig(automaticWelcome: automaticWelcome),
      ),
    ),
  );
  await scene.resize(const Size(390, 844), 1);
  await settleFeature(tester);
  if (automaticWelcome) {
    await _wait(
      tester,
      () => find.text('Offline attendance').evaluate().isNotEmpty,
    );
  }
  return scene;
}

class _VisualScene {
  _VisualScene(
    this.tester, {
    required this.entry,
    required this.owner,
    required this.dark,
    required this.reducedMotion,
  });
  final WidgetTester tester;
  final RazeCheckFeature entry;
  final bool owner, dark, reducedMotion;
  final boundaryKey = GlobalKey();

  GuideController get controller => GuideScope.maybeOf(
    tester.element(find.byType(CheckProfileGate, skipOffstage: false)),
  )!;

  Future<void> resize(Size viewport, double scale) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? CheckTheme.dark() : CheckTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          // Above the complete nested navigator and every guide presentation.
          child: RepaintBoundary(key: boundaryKey, child: child!),
        ),
        home: entry,
      ),
    );
    await tester.pump();
    await settleFeature(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> unlock() async {
    await unlockFeature(tester, owner ? 'Owner' : 'Staff');
    await settleFeature(
      tester,
      until: owner ? 'Company attendance' : 'Your attendance',
    );
    await _wait(
      tester,
      () =>
          controller.audience.variants['capture'] ==
          (owner ? 'owner' : 'staff'),
    );
  }

  Future<void> showGuide(String id, GuideDestination destination) async {
    controller.start(id, restart: true);
    final navigation = controller.showDestination();
    await _wait(
      tester,
      () =>
          controller.currentContext?.destination == destination &&
          find.byType(GuidePanel).evaluate().isNotEmpty,
    );
    await tester.runAsync(() => navigation);
    await settleFeature(tester);
    expect(controller.active?.definition.id, id);
  }

  Future<void> capture(String name) async {
    expect(tester.takeException(), isNull);
    final output = Platform.environment['RAZE_VISUAL_DIR'];
    if (output == null) return;
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final rendered = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/$name').writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        rendered.dispose();
      }
    });
  }

  Future<void> close() async {
    // Unmount before testWidgets performs its own fake-zone cleanup; Drift's
    // final stream cancellation schedules real-I/O cleanup timers.
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
