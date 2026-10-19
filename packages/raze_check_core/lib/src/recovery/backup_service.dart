import 'dart:typed_data';
import '../contracts/check_repository.dart';
import '../contracts/context.dart';
import 'archive_models.dart';
import '../messaging/message_types.dart';
import '../messaging/message_verifier.dart';

abstract interface class BackupService {
  Future<ArchiveDescriptor> create(
    SessionHandle session,
    ExportScope scope,
    String passphrase,
  );
  Future<ArchiveDescriptor?> last(SessionHandle session);
  Future<Uint8List> shareBytes(SessionHandle session, String artifactId);
  Future<void> confirmExternalCopy(SessionHandle session, String artifactId);
  String get storageDescription;
}

abstract interface class StaffRecoveryBackupService {
  Future<ArchiveDescriptor> createStaffRecovery(
    CommandContext context,
    VerifiedMessage request,
    SignedMessage grant,
    String passphrase,
  );
}
