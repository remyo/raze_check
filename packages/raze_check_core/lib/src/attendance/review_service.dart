import '../contracts/context.dart';
import '../contracts/result.dart';
import 'review_models.dart';

abstract interface class ReviewService {
  Future<List<AttendanceSubject>> subjects(
    SessionHandle session,
    String companyId,
  );
  Future<CommandResult<DecisionRecord>> decide(
    CommandContext context,
    String eventId,
    ReviewDecision decision,
    String reason,
  );
  Future<CommandResult<AttendanceRecord>> recordManual(
    CommandContext context,
    ManualPunch draft,
  );
  Future<AttendanceRecord> get(
    SessionHandle session,
    String companyId,
    String eventId,
  );
  Future<List<AttendanceRecord>> list(SessionHandle session, String companyId);
  Future<List<DecisionRecord>> history(
    SessionHandle session,
    String companyId,
    String eventId,
  );
}
