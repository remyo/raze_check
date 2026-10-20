import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/src/guides/guide_catalog.dart';
import 'package:raze_check_feature/src/guides/guide_controller.dart';
import 'package:raze_check_feature/src/guides/guide_library_screen.dart';
import 'package:raze_check_feature/src/guides/guide_scene.dart';
import 'package:raze_check_feature/src/guides/guide_scope.dart';
import 'support/guide_fixture.dart';

void main() {
  testWidgets(
    'library has permitted statuses, Continue, Restart and introduction replay',
    (tester) async {
      final c = GuideController(catalog: GuideCatalog());
      await c.initialize();
      final scene = testGuideContext(
        variants: {'welcome': 'public', 'companies': 'personal'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GuideScope(
            controller: c,
            child: GuideScene(
              context: scene,
              child: const GuideLibraryScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not started'), findsNWidgets(2));
      expect(find.text('Manage staff and operator access'), findsNothing);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 4'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('In progress'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 4'), findsOneWidget);
      c.skip();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 4'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        c.next();
      }
      await tester.pumpAndSettle();
      expect(find.text('Viewed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
}
