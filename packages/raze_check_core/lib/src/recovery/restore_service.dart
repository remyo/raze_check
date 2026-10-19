import '../contracts/context.dart';
import 'archive_models.dart';

abstract interface class RestoreService {
  Future<RestorePreview> inspect(
    SessionHandle session,
    String selectedFile,
    String passphrase,
  );
  Future<RestoreResult> apply(RestorePreview preview, RestoreChoice choice);
  Future<void> discard(RestorePreview preview);
}
