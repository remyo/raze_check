import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_feature/src/guides/guide_scope.dart';
import 'package:raze_check_feature/src/guides/guide_models.dart';
import 'package:raze_check_feature/src/guides/guide_library_screen.dart';
import 'support/guide_fixture.dart';
import 'guide_entry_test.dart' show mountGuides, drainGuideFuture;
import 'support/dashboard_fixture.dart';

void main() {
  for (final outerHost in [false, true]) {
    testWidgets(
      'library Show me reveals the real same-route destination (outer=$outerHost)',
      (tester) async {
        final pair = await mountGuides(
          tester,
          automatic: false,
          outer: outerHost ? GlobalKey<NavigatorState>() : null,
        );
        await unlockFeature(tester, 'Staff');
        final workspace = tester.element(find.byType(CompanyWorkspace));
        final controller = GuideScope.maybeOf(workspace)!;
        final original = controller.currentContext!;
        expect(controller.audience.variants['companies'], 'personal');
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Help & Guides'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Set up and switch companies'),
              matching: find.byType(Card),
            ),
            matching: find.text('Start'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show me'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Company name'), findsOneWidget);
        expect(find.byType(GuideLibraryScreen), findsNothing);
        expect(controller.currentContext!.token, isNot(same(original.token)));
        expect(
          controller.currentContext!.destination,
          GuideDestination.createCompany,
        );
        expect(controller.active?.stepIndex, 0);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('guide-highlight'))).height,
          greaterThan(0),
        );
        expect(find.text('Step 2 of 4'), findsOneWidget);
        if (!outerHost) {
          controller.skip();
          tester
              .widget<CompanySetupScreen>(find.byType(CompanySetupScreen))
              .onCancel();
          await tester.pumpAndSettle();
          final before = await tester.runAsync(
            () => pair.staff.storage.count('membership'),
          );
          late Future<void> navigation;
          await tester.runAsync(() async {
            controller.start('membership', restart: true);
            navigation = controller.showDestination();
            await tester.pump();
          });
          await settleFeature(tester);
          await drainGuideFuture(tester, navigation);
          await tester.pumpAndSettle();
          expect(find.text('Read invitation'), findsOneWidget);
          expect(find.text('Membership active'), findsNothing);
          controller.next();
          controller.back();
          controller.skip();
          expect(
            await tester.runAsync(() => pair.staff.storage.count('membership')),
            before,
          );
        }
      },
    );
  }
  testWidgets('outer recovery page is protected by the gate lifetime on lock', (
    tester,
  ) async {
    final outer = GlobalKey<NavigatorState>();
    await mountGuides(tester, automatic: false, outer: outer);
    await unlockFeature(tester, 'Staff');
    final lock = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Lock'))
        .onPressed!;
    await tester.runAsync(() async {
      await tester.tap(find.text('Backup / recovery'));
      await tester.pump();
    });
    await settleFeature(tester);
    expect(find.byType(RecoveryWorkspace), findsOneWidget);
    lock();
    await settleFeature(tester);
    expect(find.byType(RecoveryWorkspace), findsNothing);
    expect(outer.currentState!.canPop(), isTrue);
  });
  testWidgets(
    'outer settings retain validated audience then hide at original idle lock',
    (tester) async {
      final outer = GlobalKey<NavigatorState>();
      final pair = await mountGuides(tester, automatic: false, outer: outer);
      await unlockFeature(tester, 'Staff');
      final gateContext = tester.element(find.byType(CheckProfileGate));
      final c = GuideScope.maybeOf(gateContext)!;
      final registry = GuideScope.registryOf(gateContext);
      final session = tester
          .widget<CompanyWorkspace>(find.byType(CompanyWorkspace))
          .session;
      final originalRemaining = pair.staff.identity.remainingIdleTime(session);
      // Re-arm the same original deadline in the test clock's zone after real
      // unlock I/O completes; tutorial actions must not move it.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help & Guides'));
      await tester.pumpAndSettle();
      expect(
        GuideScope.registryOf(tester.element(find.text('Replay introduction'))),
        same(registry),
      );
      await tester.tap(find.text('Replay introduction'));
      await tester.pumpAndSettle();
      pair.staff.clock.advance(const Duration(minutes: 4));
      await tester.pump(const Duration(minutes: 4));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(
        pair.staff.identity.remainingIdleTime(session),
        originalRemaining - const Duration(minutes: 4),
      );
      pair.staff.clock.advance(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      await settleFeature(tester);
      expect(find.text('Step 1 of 5'), findsNothing);
      expect(c.active, isNull);
      outer.currentState!.popUntil((route) => route.isFirst);
      await settleFeature(tester, until: 'Unlock Staff');
      await unlockFeature(tester, 'Staff');
      expect(c.active, isNull);
    },
  );
  testWidgets(
    'Settings and library retain origin audience and reject a changed permission generation',
    (tester) async {
      await mountGuides(tester, automatic: false);
      await unlockFeature(tester, 'Staff');
      final c = GuideScope.maybeOf(
        tester.element(find.byType(CheckProfileGate)),
      )!;
      final original = c.currentContext!;
      var permitted = true;
      Future<void> validate() async {
        await original.validateCurrent();
        if (!permitted) throw StateError('Permission generation changed');
      }

      await c.bind(
        testGuideContext(
          authorityToken: original.authorityToken,
          variants: {'welcome': 'public', 'companies': 'personal'},
          validateCurrent: validate,
        ),
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help & Guides'));
      await tester.pumpAndSettle();
      expect(find.text('Set up and switch companies'), findsOneWidget);
      expect(c.audience.variants['companies'], 'personal');
      await tester.pageBack();
      await tester.pumpAndSettle();
      permitted = false;
      c.invalidateAuthority(original.authorityToken);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help & Guides'));
      await tester.pumpAndSettle();
      expect(find.byType(GuideLibraryScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'outer library hides while backgrounded and on host exit even when host keeps feature mounted',
    (tester) async {
      final outer = GlobalKey<NavigatorState>();
      var exits = 0;
      await mountGuides(
        tester,
        automatic: false,
        outer: outer,
        onExit: () => exits++,
      );
      await unlockFeature(tester, 'Staff');
      final exit = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Exit Raze Check',
            ),
          )
          .onPressed!;
      final c = GuideScope.maybeOf(
        tester.element(find.byType(CheckProfileGate)),
      )!;
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help & Guides'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replay introduction'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 5'), findsNothing);
      expect(c.active, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 5'), findsOneWidget);
      exit();
      await tester.pumpAndSettle();
      expect(exits, 1);
      expect(find.text('Step 1 of 5'), findsNothing);
      expect(c.active, isNull);
    },
  );
  testWidgets('Settings leaves a real company draft in place', (tester) async {
    await mountGuides(tester, automatic: false);
    await unlockFeature(tester, 'Staff');
    await tester.tap(find.text('Create company'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Company name'),
      'Unsubmitted draft',
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help & Guides'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Unsubmitted draft'), findsOneWidget);
  });
}
