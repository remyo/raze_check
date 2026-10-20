import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/src/guides/guide_catalog.dart';
import 'package:raze_check_feature/src/guides/guide_models.dart';

void main() {
  test(
    'all 22 approved variants retain semantic positions and safe targets',
    () {
      const matrix = {
        'welcome': ['public'],
        'companies': ['personal'],
        'membership': ['staff', 'owner', 'operator'],
        'capture': ['staff', 'owner'],
        'exchange': ['staff'],
        'review': ['staff', 'owner', 'operator'],
        'team': ['owner', 'operator'],
        'reports': ['personal', 'owner', 'operator'],
        'backup': ['personal', 'owner'],
        'new-device': [
          'staff-replacement',
          'owner-target',
          'owner-source',
          'owner-recovery',
        ],
      };
      const lengths = [5, 4, 6, 4, 5, 5, 4, 3, 5, 5];
      final catalog = GuideCatalog(),
          safe = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');
      var variants = 0, index = 0;
      for (final entry in matrix.entries) {
        final first = catalog.resolve(entry.key, entry.value.first);
        for (final variant in entry.value) {
          variants++;
          final g = catalog.resolve(entry.key, variant);
          expect(g.revision, 1);
          expect(g.steps.length, lengths[index]);
          expect(g.steps.map((s) => s.id), first.steps.map((s) => s.id));
          for (final id in [g.id, g.variantId, ...g.steps.map((s) => s.id)]) {
            expect(safe.hasMatch(id), true, reason: id);
          }
          if (g.id == 'welcome') {
            expect(g.steps.every((s) => s.targetId == null), true);
          }
          if (g.id == 'capture' && variant == 'owner') {
            expect(g.steps.skip(1).every((s) => s.targetId == null), true);
          }
          if (g.id == 'team' && variant == 'operator') {
            expect(g.steps.skip(2).every((s) => s.targetId == null), true);
          }
          if (g.id == 'membership') {
            final counterpart = variant == 'staff' ? [1, 4] : [2, 3, 5];
            for (final slot in counterpart) {
              expect(g.steps[slot].targetId, isNull);
            }
          }
        }
        index++;
      }
      expect(variants, 22);
      final lost = catalog
          .resolve('new-device', 'owner-recovery')
          .steps[3]
          .body;
      expect(lost, contains('backup'));
      expect(lost, contains('checkpoint'));
      expect(lost, isNot(contains('signed handover offer')));
      expect(lost, isNot(contains('Source shares')));
    },
  );

  test('catalog has 46 stable positions and filters unsupported entries', () {
    final c = GuideCatalog();
    final all = c.available(
      GuideAudience(
        variants: const {
          'welcome': 'public',
          'companies': 'personal',
          'membership': 'staff',
          'capture': 'staff',
          'exchange': 'staff',
          'review': 'staff',
          'team': 'owner',
          'reports': 'personal',
          'backup': 'personal',
          'new-device': 'staff-replacement',
          'unknown': 'public',
        },
      ),
    );
    final safeId = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');
    for (final g in all) {
      expect(safeId.hasMatch(g.id), isTrue);
      expect(safeId.hasMatch(g.variantId), isTrue);
      for (final step in g.steps) {
        expect(safeId.hasMatch(step.id), isTrue);
      }
    }
    expect(all.map((g) => g.steps.length), [5, 4, 6, 4, 5, 5, 4, 3, 5, 5]);
    expect(all.expand((g) => g.steps).map((s) => s.id).toSet().length, 46);
    expect(
      c
          .available(
            GuideAudience(
              variants: const {'welcome': 'public', 'team': 'public'},
            ),
          )
          .map((g) => g.id),
      ['welcome'],
    );
    expect(() => c.resolve('team', 'public'), throwsArgumentError);
  });
}
