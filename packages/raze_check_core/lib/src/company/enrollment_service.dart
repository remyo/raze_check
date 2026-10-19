import 'dart:typed_data';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../contracts/context.dart';
import '../contracts/result.dart';
import '../messaging/message_types.dart';
import '../messaging/message_verifier.dart';
import 'company_models.dart';

/// The caller must display and explicitly confirm the full root fingerprint
/// (a short prefix may be shown beside it) before calling acceptInvitation.
abstract interface class EnrollmentService {
  Future<SignedMessage> createInvitation(CommandContext context);
  Future<VerifiedMessage> acceptInvitation(
    SessionHandle session,
    Uint8List bytes, {
    required String acceptedRootFingerprint,
  });
  Future<VerifiedMessage> verifyIncoming(
    SessionHandle session,
    Uint8List bytes,
  );
  Future<SignedMessage> requestJoin(
    SessionHandle session,
    VerifiedMessage invitation,
    String operationId,
  );

  /// An explicit owner choice can link a previously manual staff record.
  Future<CommandResult<SignedMessage>> approveJoin(
    CommandContext context,
    VerifiedMessage joinRequest, {
    String? existingEmployeeId,
  });
  Future<CommandResult<Membership>> acceptGrant(
    SessionHandle session,
    VerifiedMessage grant,
  );
  Future<List<SignedMessage>> pendingJoins(SessionHandle session);
  Future<bool> canIssueAttendance(SessionHandle session, String companyId);
}

/// Task 9 supplies camera, image/file and share adapters. The feature always
/// exchanges the same bounded wire bytes, independently of transport.
abstract interface class EnrollmentMessagePort {
  Future<Uint8List?> receive();
  Future<void> send(Uint8List bytes);
}

/// Preview only. Computing a candidate fingerprint never verifies or pins it.
Future<String> invitationRootFingerprint(SignedMessage invitation) async {
  if (invitation.kind != MessageKind.invitation) {
    throw const CheckException(CheckError.malformed);
  }
  final root = base64Url.decode(
    invitation.payload.field<String>('rootPublicKeyBase64Url'),
  );
  return (await Sha256().hash(
    root,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
