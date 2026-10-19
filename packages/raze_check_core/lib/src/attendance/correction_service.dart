import '../contracts/context.dart';
import '../contracts/result.dart';
import '../messaging/message_types.dart';
import '../messaging/message_verifier.dart';
import 'review_models.dart';

abstract interface class CorrectionService {
  Future<SignedMessage> request(
    SessionHandle session,
    String companyId,
    String eventId,
    ProposedCorrection change,
    String operationId,
  );
  Future<CommandResult<CorrectionRecord>> resolve(
    CommandContext context,
    VerifiedMessage request,
    bool approve,
    String reason,
  );
  Future<CommandResult<CorrectionRecord>> correct(
    CommandContext context,
    String eventId,
    ProposedCorrection change,
    String reason,
  );
}
