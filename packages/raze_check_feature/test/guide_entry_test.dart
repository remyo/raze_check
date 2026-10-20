import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_feature/src/guides/guide_scope.dart';
import 'package:raze_check_feature/src/guides/welcome_screen.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';
import 'support/dashboard_fixture.dart';
import 'support/guide_fixture.dart';

Future<TwoDeviceFixture> mountGuides(
  WidgetTester tester, {
  MemoryGuideProgressStore? store,
  bool automatic = true,
  double textScale = 1,
  GlobalKey<NavigatorState>? outer,
  VoidCallback? onExit,
}) async {
  final pair = (await tester.runAsync(TwoDeviceFixture.create))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(pair.dispose);
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: outer,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      theme: ThemeData(fontFamily: 'HostTypeface'),
      home: RazeCheckFeature(
        services: featureServices(pair.staff),
        host: CheckFeatureHost(
          onExit: onExit ?? () {},
          guideProgress: store,
          guides: GuidePresentationConfig(automaticWelcome: automatic),
          themeBuilder: (context, _) => Theme.of(context),
          iconBuilder: (_) => const Text('Host brand'),
          navigate: outer == null
              ? null
              : (_, page, name) => outer.currentState!.push<void>(
                  MaterialPageRoute(
                    builder: (_) => page,
                    settings: RouteSettings(name: name),
                  ),
                ),
        ),
      ),
    ),
  );
  await settleFeature(tester);
  return pair;
}

Future<void> drainGuideFuture(WidgetTester tester, Future<void> future) async {
  var done = false;
  Object? failure;
  future.then(
    (_) => done = true,
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  for (var i = 0; i < 300 && !done; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(
    done,
    isTrue,
    reason:
        'Guide persistence must settle across fake-frame and real-I/O zones',
  );
  expect(failure, isNull);
}

void main() {
  testWidgets(
    'opted-in session-only welcome supports narrow large text scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountGuides(tester, textScale: 2);
      final semantics = tester.ensureSemantics();

      final welcome = tester.element(find.byType(WelcomeScreen));
      expect(GuideScope.maybeOf(welcome)!.sessionOnly, isTrue);
      expect(find.text('Step 1 of 5'), findsOneWidget);
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 5'), findsOneWidget);
      await tester.ensureVisible(find.text('Skip'));
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Skip')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Skip'));
      await settleFeature(tester);
      expect(find.text('Create local profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets(
    'first-open five steps stay in first profile route and complete once',
    (tester) async {
      final store = MemoryGuideProgressStore();
      await mountGuides(tester, store: store);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Host brand'), findsOneWidget);
      expect(
        Theme.of(
          tester.element(find.byType(WelcomeScreen)),
        ).textTheme.bodyMedium!.fontFamily,
        'HostTypeface',
      );
      expect(
        ModalRoute.of(tester.element(find.byType(WelcomeScreen)))!.isFirst,
        isTrue,
      );
      for (var i = 1; i <= 5; i++) {
        expect(find.text('Step $i of 5'), findsOneWidget);
        await tester.tap(find.text(i == 5 ? 'Get started' : 'Next'));
        await settleFeature(tester);
      }
      expect(find.text('Create local profile'), findsOneWidget);
      expect(store.snapshot.welcomeDismissed, isTrue);
      expect(store.snapshot.entries.single.viewed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountGuides(tester, store: store);
      expect(find.byType(WelcomeScreen), findsNothing);
    },
  );
  testWidgets(
    'quit at step three resumes even though its invitation is dismissed',
    (tester) async {
      final store = MemoryGuideProgressStore();
      await mountGuides(tester, store: store);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Step 3 of 5'), findsOneWidget);
      await drainGuideFuture(
        tester,
        GuideScope.maybeOf(tester.element(find.byType(WelcomeScreen)))!.flush(),
      );
      expect(store.snapshot.entries.single.stepId, 'welcome-receipts');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountGuides(tester, store: store);
      expect(find.text('Step 3 of 5'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await settleFeature(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountGuides(tester, store: store);
      expect(find.text('Create local profile'), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    },
  );
  testWidgets('failed preferences do not block welcome exit or profile entry', (
    tester,
  ) async {
    await mountGuides(tester, store: MemoryGuideProgressStore(failRead: true));
    expect(find.textContaining('could not be saved'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await settleFeature(tester);
    expect(find.text('Create local profile'), findsOneWidget);
  });
  testWidgets(
    'embedded default off supports public library without an adapter',
    (tester) async {
      await mountGuides(tester, automatic: false);
      expect(find.byType(WelcomeScreen), findsNothing);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help & Guides'));
      await tester.pumpAndSettle();
      expect(
        find.text('Guide progress is shared on this device.'),
        findsOneWidget,
      );
      expect(find.text('Welcome to Raze Check'), findsOneWidget);
      expect(find.text('Set up and switch companies'), findsNothing);
      expect(
        GuideScope.maybeOf(
          tester.element(find.text('Replay introduction')),
        )!.sessionOnly,
        isTrue,
      );
      await tester.tap(find.text('Replay introduction'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 5'), findsOneWidget);
    },
  );
}
