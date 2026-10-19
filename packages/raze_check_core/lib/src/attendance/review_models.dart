import '../messaging/message_types.dart';
import '../contracts/result.dart';
import 'attendance_models.dart';

enum ReviewStatus { pending, approved, rejected }

enum ReviewDecision { approve, reject }

enum CorrectionOutcome { approved, rejected }

enum AttendanceSource { staticQr, manual }

enum ImportStatus { received, alreadyReceived, needsReview, rejected }

final class ImportOutcome {
  const ImportOutcome(
    this.status,
    this.eventId, {
    this.returnMessage,
    this.error,
  });
  final ImportStatus status;
  final String eventId;
  final SignedMessage? returnMessage;
  final CheckError? error;
}

final class ManualPunch {
  const ManualPunch({
    required this.employeeId,
    required this.kind,
    required this.utcMs,
    required this.offsetMinutes,
    required this.reason,
  });
  final String employeeId, reason;
  final PunchKind kind;
  final int utcMs, offsetMinutes;
}

final class ProposedCorrection {
  const ProposedCorrection({
    required this.kind,
    required this.utcMs,
    required this.offsetMinutes,
    required this.reason,
  });
  final PunchKind kind;
  final int utcMs, offsetMinutes;
  final String reason;
  List<Object?> toValues() => [kind.name, utcMs, offsetMinutes, reason];
}

/// Current projection only. Original event and history remain independent.
final class AttendanceRecord {
  AttendanceRecord(Map<String, dynamic> data)
    : data = Map.unmodifiable({
        ...data,
        'flags': List<String>.unmodifiable(
          (data['flags'] as List).cast<String>(),
        ),
      });
  final Map<String, dynamic> data;
  String get eventId => data['eventId'] as String;
  String get companyId => data['companyId'] as String;
  String get employeeId => data['employeeId'] as String;
  String get personId => data['personId'] as String;
  AttendanceSource get source =>
      AttendanceSource.values.byName(data['source'] as String);
  bool get returnEligible => source == AttendanceSource.staticQr;
  ReviewStatus get review =>
      ReviewStatus.values.byName(data['review'] as String);
  DeliveryStatus get delivery =>
      DeliveryStatus.values.byName(data['delivery'] as String);
  int get decisionRevision => data['decisionRevision'] as int;
  int get claimedUtcMs => data['claimedUtcMs'] as int;
  int? get receivedUtcMs => data['receivedUtcMs'] as int?;
  PunchKind get effectiveKind =>
      PunchKind.values.byName(data['effectiveKind'] as String);
  int get effectiveUtcMs => data['effectiveUtcMs'] as int;
  int get effectiveOffsetMinutes => data['effectiveOffsetMinutes'] as int;
  List<String> get flags => data['flags'] as List<String>;
}

final class DecisionRecord {
  DecisionRecord(Map<String, dynamic> data, {this.returnMessage})
    : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;
  final SignedMessage? returnMessage;
  String get eventId => data['eventId'] as String;
  String get decisionId => data['decisionId'] as String;
  int get revision => data['decisionRevision'] as int;
  String get reason => data['reason'] as String;
  String get actorPersonId => data['actorPersonId'] as String;
  String? get correctionId => data['correctionId'] as String?;
  String? get requestId => data['requestId'] as String?;
  CorrectionOutcome? get correctionOutcome => data['correctionOutcome'] == null
      ? null
      : CorrectionOutcome.values.byName(data['correctionOutcome'] as String);
}

final class CorrectionRecord {
  const CorrectionRecord(this.decision);
  final DecisionRecord decision;
}

final class AttendanceSubject {
  const AttendanceSubject(this.employeeId, this.name);
  final String employeeId, name;
}
