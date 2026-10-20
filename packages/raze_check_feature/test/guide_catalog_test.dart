import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/src/guides/guide_catalog.dart';
import 'package:raze_check_feature/src/guides/guide_models.dart';

void main() {
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
