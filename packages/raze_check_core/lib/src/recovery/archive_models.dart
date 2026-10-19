import '../contracts/check_repository.dart';

final class ArchiveDescriptor {
  const ArchiveDescriptor({
    required this.artifactId,
    required this.createdUtcMs,
    required this.scope,
    required this.counts,
    this.externalCopyConfirmed = false,
    this.manifestSha256Base64Url = '',
  });
  final String artifactId, manifestSha256Base64Url;
  final int createdUtcMs;
  final ExportScope scope;
  final Map<String, int> counts;
  final bool externalCopyConfirmed;
}

enum RestoreChoice { newInstallation, mergeNonConflicting }

final class RestorePreview {
  const RestorePreview({
    required this.manifestId,
    required this.personId,
    required this.companyIds,
    required this.authorityHistory,
    required this.counts,
    required this.hashes,
    required this.conflicts,
    required this.stagingToken,
    required this.filesComplete,
    this.manifestSha256Base64Url = '',
    this.companyRootFingerprints = const {},
  });
  final Map<String, String> companyRootFingerprints;
  final String manifestId, personId, stagingToken, manifestSha256Base64Url;
  final List<String> companyIds, conflicts;
  final Map<String, List<List<Object?>>> authorityHistory;
  final Map<String, int> counts;
  final Map<String, String> hashes;
  final bool filesComplete;
}

final class RestoreResult {
  const RestoreResult(this.archiveId, {required this.duplicate});
  final String archiveId;
  final bool duplicate;
  bool get requiresActivation => true;
}
