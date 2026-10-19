import '../contracts/context.dart';
import '../messaging/message_types.dart';
import 'receipt_import_service.dart';
import 'review_service.dart';
import 'correction_service.dart';
import 'update_service.dart';

abstract interface class AttendanceService
    implements
        ReceiptImportService,
        ReviewService,
        CorrectionService,
        UpdateService {
  Future<List<SignedMessage>> exchangeMessages(
    SessionHandle session,
    String companyId,
    String eventId,
  );
}
