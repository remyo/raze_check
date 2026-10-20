import '../contracts/context.dart';
import '../company/company_models.dart';
import 'review_models.dart';

/// A requested scope, never a permission. Services authorize it on every read.
enum AttendanceScope { personal, management }

final class DateRange {
  DateRange(DateTime start, DateTime end)
    : start = DateTime.utc(start.year, start.month, start.day),
      end = DateTime.utc(end.year, end.month, end.day) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('Invalid date range');
    }
  }
  final DateTime start, end;
}

/// Opaque service-issued continuation; reconstructing it never grants access.
abstract interface class AttendanceCursor {}

final class AttendanceCorrectionRequest {
  const AttendanceCorrectionRequest({
    required this.requestId,
    required this.reason,
    required this.proposedKind,
    required this.proposedUtcMs,
    this.outcome,
  });
  final String requestId, reason, proposedKind;
  final int proposedUtcMs;
  final CorrectionOutcome? outcome;
}

final class AttendanceItem {
  AttendanceItem(
    this.record,
    this.employeeName, {
    List<DecisionRecord> decisions = const [],
    List<AttendanceCorrectionRequest> requests = const [],
  }) : decisions = List.unmodifiable(decisions),
       requests = List.unmodifiable(requests);
  final AttendanceRecord record;
  final String employeeName;
  final List<DecisionRecord> decisions;
  final List<AttendanceCorrectionRequest> requests;
}

final class AttendanceHistoryPage {
  AttendanceHistoryPage(
    List<AttendanceItem> items, {
    this.next,
    this.refreshRequired = false,
  }) : items = List.unmodifiable(items);
  final List<AttendanceItem> items;
  final AttendanceCursor? next;
  final bool refreshRequired;
}

class StaffOverview {
  const StaffOverview({
    required this.company,
    required this.total,
    required this.savedOnDevice,
    required this.received,
    required this.pending,
    required this.approved,
    required this.rejected,
    this.latest,
    this.lastReceivedUtcMs,
  });
  final Company company;
  final int total, savedOnDevice, received, pending, approved, rejected;
  final AttendanceItem? latest;
  final int? lastReceivedUtcMs;
}

final class ManagerOverview extends StaffOverview {
  const ManagerOverview({
    required super.company,
    required super.total,
    required super.savedOnDevice,
    required super.received,
    required super.pending,
    required super.approved,
    required super.rejected,
    super.latest,
    super.lastReceivedUtcMs,
  });
}

final class AttendanceReport {
  AttendanceReport({
    required this.company,
    required this.range,
    required this.scope,
    required this.generatedUtcMs,
    required List<AttendanceItem> rows,
  }) : rows = List.unmodifiable(rows);
  final Company company;
  final DateRange range;
  final AttendanceScope scope;
  final int generatedUtcMs;
  final List<AttendanceItem> rows;
}

abstract interface class AttendanceQueries {
  Stream<StaffOverview> forStaff(SessionHandle session, String companyId);
  Stream<ManagerOverview> forManager(CommandContext context);
  Future<void> authorize(
    SessionHandle session,
    String companyId, {
    AttendanceScope scope = AttendanceScope.personal,
  });
  Future<AttendanceHistoryPage> historyPage(
    SessionHandle session,
    String companyId, {
    AttendanceScope scope = AttendanceScope.personal,
    AttendanceCursor? cursor,
    int pageSize = 25,
    bool Function()? cancelled,
  });
  Future<void> authorizeReport(CommandContext context, AttendanceScope scope);
  Future<AttendanceReport> report(
    CommandContext context,
    DateRange range, {
    AttendanceScope scope = AttendanceScope.personal,
    bool Function()? cancelled,
  });
}
