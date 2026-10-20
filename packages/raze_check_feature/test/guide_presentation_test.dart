import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/src/guides/guide_anchor_registry.dart';
import 'package:raze_check_feature/src/guides/guide_artwork.dart';
import 'package:raze_check_feature/src/guides/guide_catalog.dart';
import 'package:raze_check_feature/src/guides/guide_controller.dart';
import 'package:raze_check_feature/src/guides/guide_invitation.dart';
import 'package:raze_check_feature/src/guides/guide_layer.dart';
import 'package:raze_check_feature/src/guides/guide_models.dart';
import 'package:raze_check_feature/src/guides/guide_panel.dart';
import 'package:raze_check_feature/src/guides/guide_scene.dart';
import 'package:raze_check_feature/src/guides/guide_scope.dart';
import 'package:raze_check_feature/src/guides/guide_target.dart';
import 'package:raze_check_feature/src/theme/check_theme.dart';
import 'support/guide_fixture.dart';

Future<GuideController> controller() async {
  final result = GuideController(catalog: GuideCatalog());
  await result.initialize();
  return result;
}

Widget host(GuideController controller, Widget child, {double scale = 1}) =>
    MaterialApp(
      theme: CheckTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: GuideScope(
            controller: controller,
            child: Scaffold(body: GuideLayer(child: child)),
          ),
        ),
      ),
    );
Future<void> settleGuide(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('absent scope preserves application callbacks', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuideLayer(
            child: Column(
              children: [
                GuideTarget(
                  id: 'companies-choose',
                  child: TextButton(
                    onPressed: () => calls++,
                    child: const Text('Business'),
                  ),
                ),
                const GuideInvitation(guideId: 'companies'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Business'));
    expect(calls, 1);
    expect(find.text('Show me how'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('guide navigation never runs the highlighted business command', (
    tester,
  ) async {
    final c = await controller();
    var calls = 0;
    final scene = testGuideContext(variants: {'companies': 'personal'});
    await tester.pumpWidget(
      host(
        c,
        GuideScene(
          context: scene,
          child: Align(
            alignment: Alignment.topLeft,
            child: GuideTarget(
              id: 'companies-choose',
              child: TextButton(
                onPressed: () => calls++,
                child: const Text('Business'),
              ),
            ),
          ),
        ),
      ),
    );
    await settleGuide(tester);
    c.start('companies');
    await settleGuide(tester);
    expect(
      tester
          .getRect(find.byType(GuidePanel))
          .overlaps(tester.getRect(find.text('Business'))),
      isFalse,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Back'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Next'));
    await settleGuide(tester);
    await tester.tap(find.text('Back'));
    await settleGuide(tester);
    expect(calls, 0);
    await tester.tap(find.text('Business'));
    expect(calls, 1);
    calls = 0;
    await tester.tap(find.text('Skip'));
    await settleGuide(tester);
    expect(c.active, isNull);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'registry separates scenes and rejects stale unregister and hidden targets',
    (tester) async {
      final registry = GuideAnchorRegistry();
      final token = Object(), other = Object();
      final layerKey = GlobalKey(),
          first = GlobalKey(),
          replacement = GlobalKey(),
          hidden = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            key: layerKey,
            child: Stack(
              children: [
                Positioned(
                  left: 20,
                  top: 20,
                  child: SizedBox(key: first, width: 60, height: 48),
                ),
                Positioned(
                  left: 120,
                  top: 20,
                  child: SizedBox(key: replacement, width: 60, height: 48),
                ),
                Offstage(child: SizedBox(key: hidden, width: 60, height: 48)),
              ],
            ),
          ),
        ),
      );
      final layer = layerKey.currentContext!.findRenderObject()! as RenderBox;
      registry.register(token, 'same', first);
      registry.register(other, 'same', first);
      registry.register(token, 'same', replacement);
      registry.unregister(token, 'same', first);
      expect(registry.bounds(token, 'same', layer)?.left, 120);
      expect(registry.bounds(other, 'same', layer)?.left, 20);
      registry.register(token, 'hidden', hidden);
      expect(registry.bounds(token, 'hidden', layer), isNull);
      registry.unregister(token, 'same', replacement);
      expect(registry.bounds(token, 'same', layer), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(registry.bounds(other, 'same', layer), isNull);
      registry.dispose();
    },
  );
  testWidgets('scroll remeasures bounds and offscreen fallback keeps Skip', (
    tester,
  ) async {
    final c = await controller();
    final scroll = ScrollController();
    final scene = testGuideContext(variants: {'companies': 'personal'});
    await tester.pumpWidget(
      host(
        c,
        GuideScene(
          context: scene,
          child: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                const SizedBox(height: 80),
                GuideTarget(
                  id: 'companies-choose',
                  child: TextButton(
                    onPressed: () {},
                    child: const Text('Business'),
                  ),
                ),
                const SizedBox(height: 1500),
              ],
            ),
          ),
        ),
      ),
    );
    await settleGuide(tester);
    c.start('companies');
    await settleGuide(tester);
    final highlight = find.byKey(const ValueKey('guide-highlight'));
    final before = tester.getRect(highlight);
    expect(before.height, greaterThan(0));
    scroll.jumpTo(30);
    await settleGuide(tester);
    expect(tester.getRect(highlight).top, closeTo(before.top - 30, .01));
    scroll.jumpTo(500);
    await settleGuide(tester);
    expect(tester.getSize(highlight), Size.zero);
    expect(find.text('Skip'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
  testWidgets('removal and replacement update an active highlight', (
    tester,
  ) async {
    final c = await controller();
    final scene = testGuideContext(variants: {'companies': 'personal'});
    var show = true, left = false;
    late StateSetter update;
    await tester.pumpWidget(
      host(
        c,
        GuideScene(
          context: scene,
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Align(
                alignment: left ? Alignment.topLeft : Alignment.topRight,
                child: show
                    ? GuideTarget(
                        key: ValueKey(left),
                        id: 'companies-choose',
                        child: const SizedBox(width: 70, height: 48),
                      )
                    : const SizedBox(),
              );
            },
          ),
        ),
      ),
    );
    await settleGuide(tester);
    c.start('companies');
    await settleGuide(tester);
    final highlight = find.byKey(const ValueKey('guide-highlight'));
    final old = tester.getRect(highlight);
    update(() => show = false);
    await settleGuide(tester);
    expect(tester.getSize(highlight), Size.zero);
    update(() {
      show = true;
      left = true;
    });
    await settleGuide(tester);
    expect(tester.getRect(highlight).left, lessThan(old.left));
    expect(tester.takeException(), isNull);
  });
  testWidgets('covering modal and routes invalidate a scene', (tester) async {
    final c = await controller();
    final navigator = GlobalKey<NavigatorState>();
    final scene = testGuideContext(variants: {'companies': 'personal'});
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: CheckTheme.light(),
        home: GuideScope(
          controller: c,
          child: GuideLayer(
            child: GuideScene(
              context: scene,
              child: const Scaffold(
                body: GuideTarget(
                  id: 'companies-choose',
                  child: Text('First route'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleGuide(tester);
    c.start('companies');
    await settleGuide(tester);
    showDialog<void>(
      context: tester.element(find.text('First route')),
      builder: (_) => const AlertDialog(content: Text('Covered')),
    );
    await settleGuide(tester);
    expect(find.byType(GuidePanel), findsNothing);
    expect(c.active, isNull);
    navigator.currentState!.pop();
    await settleGuide(tester);
    c.start('companies');
    await settleGuide(tester);
    expect(find.byType(GuidePanel), findsOneWidget);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another route')),
      ),
    );
    await settleGuide(tester);
    expect(c.active, isNull);
    expect(find.byType(GuidePanel), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('outer modal hides a nested Navigator scene', (tester) async {
    final c = await controller();
    final scene = testGuideContext(variants: {'companies': 'personal'});
    await tester.pumpWidget(
      MaterialApp(
        home: GuideScope(
          controller: c,
          child: GuideLayer(
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => GuideScene(
                  context: scene,
                  child: const Scaffold(body: Text('Nested')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleGuide(tester);
    c.start('companies');
    await settleGuide(tester);
    showDialog<void>(
      context: tester.element(find.text('Nested')),
      useRootNavigator: true,
      builder: (_) => const AlertDialog(content: Text('Outer modal')),
    );
    await settleGuide(tester);
    expect(c.active, isNull);
    expect(find.byType(GuidePanel), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    '320px and landscape keep 2x content scrollable and Skip reachable',
    (tester) async {
      final c = await controller();
      final scene = testGuideContext(variants: {'companies': 'personal'});
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpWidget(
        host(
          c,
          GuideScene(
            context: scene,
            child: const Center(
              child: GuideTarget(
                id: 'companies-choose',
                child: SizedBox(width: 100, height: 48),
              ),
            ),
          ),
          scale: 2,
        ),
      );
      await settleGuide(tester);
      c.start('companies');
      await settleGuide(tester);
      expect(find.text('Skip').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(640, 320);
      await settleGuide(tester);
      expect(find.text('Skip').hitTestable(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GuidePanel),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'landscape keyboard leaves scrollable controls at ${scale}x text',
      (tester) async {
        final c = await controller();
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(640, 320);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await tester.pumpWidget(
          host(
            c,
            GuideScene(
              context: testGuideContext(),
              child: const SizedBox.expand(),
            ),
            scale: scale,
          ),
        );
        await settleGuide(tester);
        c.start('welcome');
        await settleGuide(tester);
        expect(tester.getSize(find.byType(GuidePanel)).height, 76);
        expect(tester.takeException(), isNull);
        expect(find.text('Skip').hitTestable(), findsOneWidget);
        final skip = tester.getRect(find.widgetWithText(TextButton, 'Skip'));
        expect(skip.height, greaterThanOrEqualTo(48));
        expect(
          tester.getRect(find.byType(GuidePanel)).intersect(skip).height,
          greaterThanOrEqualTo(48),
        );
        final nextFinder = find.widgetWithText(FilledButton, 'Next');
        await tester.ensureVisible(nextFinder);
        await settleGuide(tester);
        final nextRect = tester.getRect(nextFinder);
        expect(nextRect.height, greaterThanOrEqualTo(48));
        expect(
          tester.getRect(find.byType(GuidePanel)).intersect(nextRect).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getRect(find.byType(GuidePanel)).contains(nextRect.center),
          isTrue,
        );
        await tester.tap(find.text('Next'));
        await settleGuide(tester);
        expect(c.active!.stepIndex, 1);
        await tester.ensureVisible(find.widgetWithText(TextButton, 'Skip'));
        await settleGuide(tester);
        await tester.tap(find.text('Skip'));
        await settleGuide(tester);
        expect(c.active, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('semantic step, ordered focus and accessible tap targets', (
    tester,
  ) async {
    final c = await controller();
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        c,
        GuideScene(context: testGuideContext(), child: const SizedBox.expand()),
      ),
    );
    await settleGuide(tester);
    c.start('welcome');
    await settleGuide(tester);
    expect(find.bySemanticsLabel('Step 1 of 5'), findsOneWidget);
    expect(
      await meetsGuideline(androidTapTargetGuideline).matchAsync(tester),
      isNull,
    );
    expect(
      await meetsGuideline(iOSTapTargetGuideline).matchAsync(tester),
      isNull,
    );
    expect(
      await meetsGuideline(labeledTapTargetGuideline).matchAsync(tester),
      isNull,
    );
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Next'),
    );
    next.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Skip'))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replacing scene context with the same token retains mounted targets',
    (tester) async {
      final c = await controller();
      final token = Object();
      var scene = testGuideContext(
        token: token,
        variants: {'companies': 'personal'},
      );
      late StateSetter update;
      await tester.pumpWidget(
        host(
          c,
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return GuideScene(
                context: scene,
                child: const Align(
                  alignment: Alignment.topRight,
                  child: GuideTarget(
                    id: 'companies-choose',
                    child: SizedBox(width: 70, height: 48),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await settleGuide(tester);
      c.start('companies');
      await settleGuide(tester);
      expect(
        tester.getSize(find.byKey(const ValueKey('guide-highlight'))).width,
        70,
      );
      update(
        () => scene = testGuideContext(
          token: token,
          variants: {'companies': 'personal'},
        ),
      );
      await settleGuide(tester);
      expect(c.active, isNull);
      c.start('companies');
      await settleGuide(tester);
      expect(
        tester.getSize(find.byKey(const ValueKey('guide-highlight'))).width,
        70,
      );
    },
  );

  testWidgets(
    'protected maintain-state Visibility invalidates and rebinds scenes',
    (tester) async {
      final c = await controller();
      var visible = true;
      late StateSetter update;
      final scene = GuideScene(
        context: testGuideContext(),
        child: const SizedBox.expand(),
      );
      await tester.pumpWidget(
        host(
          c,
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Visibility(
                visible: visible,
                maintainState: true,
                child: scene,
              );
            },
          ),
        ),
      );
      await settleGuide(tester);
      c.start('welcome');
      await settleGuide(tester);
      update(() => visible = false);
      await settleGuide(tester);
      expect(c.active, isNull);
      expect(find.byType(GuidePanel), findsNothing);
      update(() => visible = true);
      await settleGuide(tester);
      c.start('welcome');
      await settleGuide(tester);
      expect(find.byType(GuidePanel), findsOneWidget);
    },
  );

  testWidgets(
    'borrowed outer routes share ownership and use only their own duplicate target',
    (tester) async {
      final c = await controller();
      final navigator = GlobalKey<NavigatorState>();
      final source = testGuideContext(variants: {'companies': 'personal'});
      final destination = testGuideContext(variants: {'companies': 'personal'});
      late GuideScopeHandle handle;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: CheckTheme.light(),
          home: GuideScope(
            controller: c,
            child: Builder(
              builder: (context) {
                handle = GuideScope.capture(context)!;
                return GuideLayer(
                  child: GuideScene(
                    context: source,
                    child: const Scaffold(
                      body: Align(
                        alignment: Alignment.topLeft,
                        child: GuideTarget(
                          id: 'companies-choose',
                          child: SizedBox(width: 70, height: 48),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await settleGuide(tester);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => handle.wrap(
            GuideLayer(
              child: GuideScene(
                context: destination,
                child: const Scaffold(
                  body: Align(
                    alignment: Alignment.topRight,
                    child: GuideTarget(
                      id: 'companies-choose',
                      child: SizedBox(width: 100, height: 48),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settleGuide(tester);
      c.start('companies');
      await settleGuide(tester);
      final highlight = tester.getRect(
        find.byKey(const ValueKey('guide-highlight')),
      );
      expect(highlight.width, 100);
      expect(highlight.left, 700);
      navigator.currentState!.pop();
      await settleGuide(tester);
      c.start('companies');
      await settleGuide(tester);
      expect(
        tester.getRect(find.byKey(const ValueKey('guide-highlight'))).left,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rotation updates highlight to the current rendered target', (
    tester,
  ) async {
    final c = await controller();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 640);
    await tester.pumpWidget(
      host(
        c,
        GuideScene(
          context: testGuideContext(variants: {'companies': 'personal'}),
          child: const Align(
            alignment: Alignment.topRight,
            child: GuideTarget(
              id: 'companies-choose',
              child: SizedBox(width: 100, height: 48),
            ),
          ),
        ),
      ),
    );
    await settleGuide(tester);
    c.start('companies');
    await settleGuide(tester);
    expect(
      tester.getRect(find.byKey(const ValueKey('guide-highlight'))).left,
      900,
    );
    tester.view.physicalSize = const Size(640, 1000);
    await settleGuide(tester);
    expect(
      tester.getRect(find.byKey(const ValueKey('guide-highlight'))).left,
      540,
    );
    expect(
      tester
          .getRect(find.byType(GuidePanel))
          .overlaps(tester.getRect(find.byType(GuideTarget))),
      isFalse,
    );
  });

  testWidgets(
    'only explicit Show me opens a destination and pause hides guidance',
    (tester) async {
      final c = await controller();
      var opens = 0;
      final scene = testGuideContext(
        variants: {'companies': 'personal'},
        navigation: {
          GuideDestination.createCompany: () async {
            opens++;
          },
        },
      );
      await tester.pumpWidget(
        host(c, GuideScene(context: scene, child: const SizedBox.expand())),
      );
      await settleGuide(tester);
      c.start('companies');
      await settleGuide(tester);
      await tester.tap(find.text('Next'));
      await settleGuide(tester);
      await tester.tap(find.text('Back'));
      await settleGuide(tester);
      expect(opens, 0);
      await tester.tap(find.text('Show me'));
      await settleGuide(tester);
      expect(opens, 1);
      c.setPaused(true);
      await settleGuide(tester);
      expect(find.byType(GuidePanel), findsNothing);
      c.setPaused(false);
      await settleGuide(tester);
      expect(find.byType(GuidePanel), findsOneWidget);
    },
  );

  testWidgets('partial clipping and zero opacity cannot produce a spotlight', (
    tester,
  ) async {
    final registry = GuideAnchorRegistry();
    final layerKey = GlobalKey(),
        clippedKey = GlobalKey(),
        transparentKey = GlobalKey();
    final token = Object();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          key: layerKey,
          child: Stack(
            children: [
              Positioned(
                left: 40,
                top: 40,
                child: ClipRect(
                  child: SizedBox(
                    width: 40,
                    height: 48,
                    child: OverflowBox(
                      maxWidth: 100,
                      child: SizedBox(key: clippedKey, width: 100, height: 48),
                    ),
                  ),
                ),
              ),
              Opacity(
                opacity: 0,
                child: SizedBox(key: transparentKey, width: 100, height: 48),
              ),
            ],
          ),
        ),
      ),
    );
    final layer = layerKey.currentContext!.findRenderObject()! as RenderBox;
    registry.register(token, 'partial', clippedKey);
    registry.register(token, 'transparent', transparentKey);
    expect(registry.bounds(token, 'partial', layer), isNull);
    expect(registry.bounds(token, 'transparent', layer), isNull);
    registry.dispose();
  });

  testWidgets('invitations dismiss and welcome honors a host brand', (
    tester,
  ) async {
    final c = await controller();
    await tester.pumpWidget(
      host(
        c,
        GuideScene(
          context: testGuideContext(),
          child: const GuideInvitation(guideId: 'welcome'),
        ),
      ),
    );
    await settleGuide(tester);
    expect(find.text('Show me how'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss guide invitation'));
    await settleGuide(tester);
    expect(find.text('Show me how'), findsNothing);
    expect(c.active, isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideArtwork(
          guideId: 'welcome',
          stepIndex: 0,
          brandBuilder: (_) => const Text('Host brand'),
        ),
      ),
    );
    expect(find.text('Host brand'), findsOneWidget);
  });
}
