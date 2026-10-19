import '../contracts/context.dart';
import '../contracts/result.dart';
import '../messaging/message_verifier.dart';
import 'review_models.dart';

abstract interface class UpdateService {
  Future<CommandResult<AttendanceRecord>> accept(
    SessionHandle session,
    VerifiedMessage update,
  );
}
