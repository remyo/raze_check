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
  CheckError.incompatibleCompanyName =>
    'The company name exceeds the 120-character membership limit. Ask the owner to open More → Correct company name, then retry enrollment or replacement.',
  CheckError.wrongSecret => 'The passphrase is incorrect. Try again.',
  CheckError.recoveryRequired =>
    'This device cannot unlock the saved data because a local security key is '
        'missing. Restore your verified external backup in Raze Check on another '
        'device or a fresh installation. Recovery cannot start here. Keep the '
        'existing data until you have usable recovery material.',
  CheckError.locked => 'The session is locked. Unlock again.',
  CheckError.storageFailure => 'Could not save or read local data. Try again.',
  CheckError.invalidSignature =>
    'Local data could not be authenticated. Recovery is required.',
  _ => 'The profile could not be opened (${code.name}).',
};
