/// Local tutorial preferences, independent of business data and identity.
final class GuideProgress {
  const GuideProgress({
    required this.guideId,
    required this.variantId,
    required this.contentRevision,
    this.stepId,
    this.viewed = false,
    this.invitationDismissed = false,
  });
  final String guideId;
  final String variantId;
  final int contentRevision;
  final String? stepId;
  final bool viewed;
  final bool invitationDismissed;
}

final class GuideProgressSnapshot {
  GuideProgressSnapshot({
    this.welcomeDismissed = false,
    List<GuideProgress> entries = const [],
  }) : entries = List.unmodifiable(entries) {
    final keys = <(String, String)>{};
    for (final entry in this.entries) {
      if (!keys.add((entry.guideId, entry.variantId))) {
        throw ArgumentError('Duplicate guide and variant');
      }
    }
  }
  final bool welcomeDismissed;
  final List<GuideProgress> entries;
}

abstract interface class GuideProgressStore {
  Future<GuideProgressSnapshot> read();
  Future<void> write(GuideProgressSnapshot snapshot);
  Future<void> flush();
}
