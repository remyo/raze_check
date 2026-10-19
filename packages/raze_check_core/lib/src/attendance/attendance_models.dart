import 'dart:typed_data';
import '../contracts/context.dart';
import '../messaging/message_codec.dart';
import '../messaging/message_limits.dart';
import '../messaging/message_types.dart';
import 'attendance_exceptions.dart';

enum PunchKind { checkIn, checkOut }

/// Transport acknowledgment only. Approval decisions are separate domain data.
enum DeliveryStatus { localOnly, received }

/// Original signed transport, with separate local review/delivery metadata.
final class AttendanceReceipt {
  AttendanceReceipt({
    required Uint8List bytes,
    required this.delivery,
    Set<AttendanceFlag> flags = const {},
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
       flags = Set.unmodifiable(flags) {
    if (message.kind != MessageKind.attendance) {
      throw ArgumentError('Not attendance');
    }
  }
  final Uint8List bytes;
  final DeliveryStatus delivery;
  final Set<AttendanceFlag> flags;
  SignedMessage get message =>
      MessageCodec().decode(bytes, maxBytes: MessageLimits.fileBytes);
  String get eventId => message.payload.messageId;
  String get companyId => message.payload.companyId;
  String get personId => message.payload.field<String>('personId');
  String get employeeId => message.payload.field<String>('employeeId');
  String get installationId => message.payload.field<String>('installationId');
  String get workplaceId => message.payload.field<String>('workplaceId');
  int get claimedUtcMs => message.payload.field<int>('claimedUtcMs');
  int get offsetMinutes => message.payload.field<int>('offsetMinutes');
  PunchKind get kind =>
      PunchKind.values.byName(message.payload.field<String>('kind'));
}

/// A persisted intent, recoverable before capture and after commit/navigation loss.
final class CaptureDraft {
  CaptureDraft({
    required this.companyId,
    required this.authorityGenerationId,
    required this.operationId,
    required this.kind,
    required Uint8List workplaceBytes,
    this.eventId,
  }) : workplaceBytes = Uint8List.fromList(workplaceBytes).asUnmodifiableView();
  final String companyId, authorityGenerationId, operationId;
  final PunchKind kind;
  final Uint8List workplaceBytes;
  final String? eventId;
  CommandContext context(SessionHandle session) => CommandContext(
    companyId: companyId,
    session: session,
    operationId: operationId,
    authorityGenerationId: authorityGenerationId,
  );
}
