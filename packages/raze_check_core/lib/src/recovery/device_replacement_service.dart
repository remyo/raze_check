import 'authority_history.dart';
import 'archive_models.dart';
import 'dart:typed_data';
import '../contracts/context.dart';
import '../contracts/result.dart';
import '../company/company_models.dart';
import '../messaging/message_types.dart';
import '../messaging/message_verifier.dart';

/// Identity-owned, live pending key. Public identifiers alone are not access.
abstract interface class RecoveryIdentityCandidate {}

abstract interface class RecoveryIdentityService {
  /// Explicit continuation for the already unlocked person; reuses its local key.
  Future<RecoveryIdentityCandidate> continueRecoveryIdentity(
    SessionHandle session, {
    required String companyId,
    required String rootFingerprint,
  });
  Future<RecoveryIdentityCandidate> stageRecoveryIdentity(
    SessionHandle session, {
    required String companyId,
    required String personId,
    required String displayName,
    required String rootFingerprint,
    required String passphrase,
  });
  Future<void> cancelRecoveryIdentity(
    SessionHandle session,
    RecoveryIdentityCandidate candidate,
  );
}

abstract interface class DeviceReplacementService {
  Future<List<StaffRecord>> subjects(SessionHandle session, String companyId);
  Future<VerifiedMessage> verifyPendingGrant(
    SessionHandle session,
    Uint8List bytes, {
    required RecoveryIdentityCandidate candidate,
  });
  Future<SignedMessage> createRequest(
    SessionHandle session,
    String companyId,
    String? employeeId, {
    required RecoveryIdentityCandidate candidate,
  });
  Future<SignedMessage> authorize(
    CommandContext context,
    VerifiedMessage request,
  );

  /// Completion publishes credentials; explicitly unlock the original person
  /// using the new local passphrase to obtain a new ordinary session.
  Future<CommandResult<Membership>> accept(
    SessionHandle session,
    VerifiedMessage grant, {
    required RecoveryIdentityCandidate candidate,
  });
}

/// Explicit invitation consent for a pending recovery; publishes no company pin.
abstract interface class RecoveryInvitationService {
  Future<void> bindRecoveryInvitation(
    SessionHandle session,
    InvitationCandidate invitation,
    RecoveryIdentityCandidate candidate,
  );
}

/// Authenticated personal preview is consumed only as passive recovery data.
abstract interface class StaffRecoveryRestoreService {
  Future<void> applyRecoveryPersonal(
    SessionHandle session,
    RestorePreview preview,
    RecoveryIdentityCandidate candidate,
  );
}
