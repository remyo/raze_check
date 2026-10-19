import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../security/payload_cipher.dart';
import '../security/secure_key_store.dart';
import 'app_paths.dart';

/// Content is encrypted before being written, addressed by its SHA-256, and
/// never modified or deleted. Thus a returned snapshot's manifest stays usable
/// while export reads the referenced files. Future GC must introduce leases.
final class ImmutableAttachmentStore {
  ImmutableAttachmentStore({required this.paths, required this.cipher});
  final AppPaths paths;
  final PayloadCipher cipher;
  Future<String> _hash(Uint8List bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  File _file(String companyId, String hash) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(companyId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const CheckException(CheckError.malformed);
    }
    return File('${paths.root.path}/attachments/$companyId/$hash.enc');
  }

  Future<AttachmentManifestEntry> put({
    required String companyId,
    required String recordId,
    required Uint8List plain,
  }) async {
    if (plain.length > 8 * 1024 * 1024) {
      throw const CheckException(CheckError.limitExceeded);
    }
    final bytes = Uint8List.fromList(plain);
    File? temporary;
    try {
      final hash = await _hash(bytes);
      final file = _file(companyId, hash);
      final entry = AttachmentManifestEntry(
        companyId: companyId,
        recordId: recordId,
        sha256: hash,
        byteLength: bytes.length,
      );
      if (await file.exists()) {
        await read(entry); // Do not silently replace corrupted content.
        return entry;
      }
      final sealed = await cipher.seal(
        scopeId: companyId,
        recordId: 'attachment:$hash',
        revision: 1,
        plain: bytes,
      );
      await file.parent.create(recursive: true);
      final suffix = base64UrlEncode(secureRandomBytes(16)).replaceAll('=', '');
      temporary = File('${file.path}.$suffix.tmp');
      await temporary.writeAsBytes(sealed, flush: true);
      // Concurrent puts of the same hash contain identical plaintext. Rename
      // publishes a complete file atomically; partial bytes are never visible.
      await temporary.rename(file.path);
      return entry;
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<Uint8List> read(AttachmentManifestEntry entry) async {
    try {
      if (entry.byteLength < 0 || entry.byteLength > 8 * 1024 * 1024) {
        throw const CheckException(CheckError.limitExceeded);
      }
      final file = _file(entry.companyId, entry.sha256);
      if (!await file.exists()) {
        throw const CheckException(CheckError.incompleteArchive);
      }
      final length = await file.length();
      if (length != entry.byteLength + 29) {
        throw const CheckException(CheckError.incompleteArchive);
      }
      final plain = await cipher.open(
        scopeId: entry.companyId,
        recordId: 'attachment:${entry.sha256}',
        revision: 1,
        sealed: await file.readAsBytes(),
      );
      if (plain.length != entry.byteLength ||
          await _hash(plain) != entry.sha256) {
        throw const CheckException(CheckError.incompleteArchive);
      }
      return plain.asUnmodifiableView();
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }
}
