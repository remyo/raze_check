final class GuidePresentationConfig {
  const GuidePresentationConfig({this.automaticWelcome = false});
  final bool automaticWelcome;
}

enum GuideDestination {
  createCompany,
  joinCompany,
  capture,
  attendance,
  team,
  reports,
  backup,
  recovery,
}

final class GuideStep {
  const GuideStep({
    required this.id,
    required this.title,
    required this.body,
    this.targetId,
    this.destination,
  });
  final String id, title, body;
  final String? targetId;
  final GuideDestination? destination;
}

final class GuideDefinition {
  GuideDefinition({
    required this.id,
    required this.variantId,
    required this.revision,
    required this.title,
    required this.description,
    required List<GuideStep> steps,
  }) : steps = List.unmodifiable(steps);
  final String id, variantId, title, description;
  final int revision;
  final List<GuideStep> steps;
}

/// Presentation eligibility only; never grants business authority.
final class GuideAudience {
  GuideAudience({required Map<String, String> variants})
    : variants = Map.unmodifiable(variants);
  final Map<String, String> variants;
}

/// Ephemeral scene validation and guarded screen navigation only.
final class GuideContext {
  GuideContext({
    required this.token,
    required this.authorityToken,
    required this.audience,
    required this.validateCurrent,
    this.destination,
    Map<GuideDestination, Future<void> Function()> navigation = const {},
  }) : navigation = Map.unmodifiable(navigation);
  final Object token, authorityToken;
  final GuideAudience audience;
  final Future<void> Function() validateCurrent;
  final GuideDestination? destination;
  final Map<GuideDestination, Future<void> Function()> navigation;
}

final class GuideRun {
  const GuideRun({
    required this.definition,
    required this.stepIndex,
    required this.contextToken,
  });
  final GuideDefinition definition;
  final int stepIndex;
  final Object contextToken;
}
