import 'package:raze_check_core/raze_check_core.dart';
import '../recovery/recovery_shared.dart';

/// Contracts only: hosts cannot supply a role, capability grant or database.
final class CheckServices {
  const CheckServices({
    required this.identity,
    required this.companies,
    required this.enrollment,
    required this.capture,
    required this.attendance,
    required this.backups,
    required this.restores,
    required this.handover,
    required this.queries,
    required this.transfer,
    required this.recoveryIdentity,
    required this.replacement,
    required this.history,
    required this.staffBackups,
    required this.files,
    required this.shareReport,
  });
  final IdentityService identity;
  final CompanyService companies;
  final EnrollmentService enrollment;
  final CaptureService capture;
  final AttendanceService attendance;
  ReceiptImportService get imports => attendance;
  ReviewService get review => attendance;
  CorrectionService get corrections => attendance;
  UpdateService get updates => attendance;
  final BackupService backups;
  final RestoreService restores;
  final HandoverService handover;
  final AttendanceQueries queries;
  final TransferPort Function(TransferGuard) transfer;
  final RecoveryIdentityService recoveryIdentity;
  final DeviceReplacementService replacement;
  final AuthorityHistoryService history;
  final StaffRecoveryBackupService staffBackups;
  final RecoveryFiles files;

  /// Adapter encodes/shares the authorized snapshot and rechecks guard after staging.
  final Future<ShareOutcome> Function(AttendanceReport, TransferGuard)
  shareReport;
}
