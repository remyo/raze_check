import 'package:raze_check_core/raze_check_core.dart';

/// Application boundary: infrastructure errors become explicit UI outcomes.
final class ProfileCommands {
  ProfileCommands(this.identity);
  final IdentityService identity;
  Future<CommandResult<SessionHandle>> create(String name, String secret) =>
      _run(() => identity.createProfile(name, secret));
  Future<CommandResult<SessionHandle>> unlock(String personId, String secret) =>
      _run(() => identity.unlock(personId, secret));
  Future<CommandResult<SessionHandle>> _run(
    Future<SessionHandle> Function() action,
  ) async {
    try {
      return Committed(await action(), 1, false);
    } on CheckException catch (error) {
      return Rejected(error.code);
    }
  }
}

String profileError(CheckError code) => switch (code) {
  CheckError.wrongSecret => 'The passphrase is incorrect. Try again.',
  CheckError.recoveryRequired =>
    'Local keys are missing. An explicit recovery archive is required.',
  CheckError.locked => 'The session is locked. Unlock again.',
  CheckError.storageFailure => 'Could not save or read local data. Try again.',
  CheckError.invalidSignature =>
    'Local data could not be authenticated. Recovery is required.',
  _ => 'The profile could not be opened (${code.name}).',
};
