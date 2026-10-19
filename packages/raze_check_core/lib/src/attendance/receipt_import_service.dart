import 'dart:typed_data';
import '../contracts/context.dart';
import '../messaging/message_verifier.dart';
import 'review_models.dart';

abstract interface class ReceiptImportService {
  Future<ImportOutcome> importReceipt(
    CommandContext context,
    VerifiedMessage receipt,
  );
  Future<VerifiedMessage> verifyIncoming(
    SessionHandle session,
    String companyId,
    Uint8List bytes,
  );
}
