import 'dart:typed_data';
import '../contracts/check_repository.dart';
import '../contracts/context.dart';
import 'archive_models.dart';

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
