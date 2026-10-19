import 'dart:typed_data';
import '../contracts/context.dart';
import '../contracts/result.dart';
import '../messaging/message_types.dart';
import '../messaging/message_verifier.dart';
import 'attendance_models.dart';

abstract interface class CaptureService {
  Future<SignedMessage> createWorkplaceCode(CommandContext context);
  Future<VerifiedMessage> verifyWorkplace(
    SessionHandle session,
    String companyId,
    Uint8List bytes,
  );
  Future<CaptureDraft> beginDraft(
    SessionHandle session,
    String companyId,
    VerifiedMessage workplace,
    PunchKind kind,
  );
  Future<CaptureDraft?> currentDraft(SessionHandle session, String companyId);

  /// Explicitly leaves the associated receipt to start another punch. Pending
  /// drafts cannot be cleared; a retry must retain its original operation ID.
  Future<void> finishDraft(
    SessionHandle session,
    String companyId,
    String eventId,
  );
  Future<CommandResult<AttendanceReceipt>> recordPunch(
    CommandContext context,
    VerifiedMessage workplace,
    PunchKind kind,
  );
  Future<AttendanceReceipt> getReceipt(
    SessionHandle session,
    String companyId,
    String eventId,
  );
  Future<List<AttendanceReceipt>> listOutbox(
    SessionHandle session,
    String companyId,
  );
}

/// Byte-only camera/file/share boundary. Task 9 installs native adapters.
abstract interface class AttendanceMessagePort {
  Future<Uint8List?> receive();
  Future<void> send(Uint8List bytes);
}
