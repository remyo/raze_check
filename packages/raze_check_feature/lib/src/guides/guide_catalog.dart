import 'guide_models.dart';
import 'content/welcome_company_guides.dart';
import 'content/attendance_guides.dart';
import 'content/management_guides.dart';
import 'content/recovery_guides.dart';

final class GuideCatalog {
  final List<GuideDefinition> _definitions = [
    ...welcomeCompanyGuides,
    ...attendanceGuides,
    ...managementGuides,
    ...recoveryGuides,
  ];
  GuideDefinition resolve(String guideId, String variantId) =>
      _definitions.firstWhere(
        (g) => g.id == guideId && g.variantId == variantId,
        orElse: () => throw ArgumentError('Unsupported guide or variant'),
      );
  List<GuideDefinition> available(GuideAudience audience) => List.unmodifiable(
    _definitions.where((g) => audience.variants[g.id] == g.variantId),
  );
}
