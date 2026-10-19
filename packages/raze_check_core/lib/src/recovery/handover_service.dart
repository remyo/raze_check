import 'dart:typed_data';
import '../contracts/context.dart';
import '../messaging/message_types.dart';
import '../messaging/message_verifier.dart';
import 'archive_models.dart';
import 'device_replacement_service.dart';

final class HandoverOffer {
  const HandoverOffer(this.transfer, this.archive);
  final SignedMessage transfer;
  final ArchiveDescriptor archive;
}

final class RecoveryAcknowledgment {
  const RecoveryAcknowledgment({
    required this.manifestId,
    required this.manifestSha256Base64Url,
    required this.acceptsMissingData,
  });
  final String manifestId, manifestSha256Base64Url;
  final bool acceptsMissingData;
}

final class RecoveryResult {
  const RecoveryResult(this.personId, this.companyId, this.generationId);
  final String personId, companyId, generationId;
}

abstract interface class HandoverService {
  Future<HandoverOffer?> pendingOffer(SessionHandle session, String companyId);
  Future<SignedMessage?> activationAcknowledgment(
    SessionHandle session,
    String companyId,
  );

  Future<HandoverOffer> begin(
    CommandContext context,
    VerifiedMessage targetRequest, {
    required String archivePassphrase,
  });
  Future<Uint8List> exportArtifact(SessionHandle session, HandoverOffer offer);
  Future<void> cancel(CommandContext context);
  Future<SignedMessage> activate(
    SessionHandle session,
    RestorePreview preview,
    HandoverOffer offer, {
    required RecoveryIdentityCandidate candidate,
  });
  Future<void> finish(CommandContext context, VerifiedMessage transferAck);
  Future<RecoveryResult> recover(
    SessionHandle session,
    RestorePreview preview,
    RecoveryAcknowledgment acknowledgment, {
    required RecoveryIdentityCandidate candidate,
  });
}
