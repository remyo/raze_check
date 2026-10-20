/// Stable domain errors; the feature layer supplies user-facing messages.
enum CheckError {
  locked,
  unauthorized,
  wrongCompany,
  malformed,
  unsupportedVersion,
  invalidSignature,
  unknownIssuer,
  revokedCredential,
  duplicateConflict,
  storageFailure,
  invalidTransition,
  limitExceeded,
  incompleteArchive,
  wrongSecret,
  recoveryRequired,
  incompatibleCompanyName,
}

final class CheckException implements Exception {
  const CheckException(this.code);

  final CheckError code;

  @override
  String toString() => 'CheckException(${code.name})';
}

sealed class CommandResult<T> {
  const CommandResult();
}

/// A durable commit, including idempotent retries of a previously saved command.
final class Committed<T> extends CommandResult<T> {
  const Committed(this.value, this.revision, this.duplicate);

  final T value;
  final int revision;
  final bool duplicate;
}

final class Rejected<T> extends CommandResult<T> {
  const Rejected(this.error);

  final CheckError error;
}

final class VersionConflict<T> extends CommandResult<T> {
  const VersionConflict(this.currentRevision);

  final int currentRevision;
}
