import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:raze_check_core/raze_check_core.dart';
import '../files/app_paths.dart';
import 'payload_cipher.dart';
import 'secure_key_store.dart';

/// Small versioned identity index only. Staff/attendance bodies belong to Drift.
final class ProfileCatalog {
  ProfileCatalog({required this.paths, required this.keys});
  final AppPaths paths;
  final SecureKeyStore keys;
  static const _scope = 'installation-catalog';
  Future<List<LocalProfile>> read() async {
    try {
      if (!await paths.catalog.exists()) return [];
      final bytes = await AesPayloadCipher(VaultKeys(keys)).open(
        scopeId: _scope,
        recordId: 'profiles',
        revision: 1,
        sealed: await paths.catalog.readAsBytes(),
      );
      final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (value['version'] != 1) {
        throw const CheckException(CheckError.unsupportedVersion);
      }
      return (value['profiles'] as List)
          .map((dynamic item) {
            final p = item as Map<String, dynamic>;
            return LocalProfile(
              personId: p['personId'] as String,
              displayName: p['displayName'] as String,
              installationId: p['installationId'] as String,
              signingKeyId: p['signingKeyId'] as String,
              publicKey: base64Decode(p['publicKey'] as String),
            );
          })
          .toList(growable: false);
    } on CheckException {
      rethrow;
    } on FileSystemException {
      throw const CheckException(CheckError.storageFailure);
    } catch (_) {
      throw const CheckException(CheckError.malformed);
    }
  }

  Future<void> write(List<LocalProfile> profiles) async {
    File? staging;
    try {
      // Never provision if encrypted state already exists.
      final vault = VaultKeys(keys);
      if (await paths.catalog.exists()) {
        await vault.require(_scope);
      } else if (await keys.read('vault:$_scope') == null) {
        await vault.create(_scope);
      }
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'profiles': profiles
                .map(
                  (p) => {
                    'personId': p.personId,
                    'displayName': p.displayName,
                    'installationId': p.installationId,
                    'signingKeyId': p.signingKeyId,
                    'publicKey': base64Encode(p.publicKey),
                  },
                )
                .toList(),
          }),
        ),
      );
      final sealed = await AesPayloadCipher(
        vault,
      ).seal(scopeId: _scope, recordId: 'profiles', revision: 1, plain: bytes);
      await paths.root.create(recursive: true);
      staging = File('${paths.catalog.path}.${SecureIds().next()}.tmp');
      await staging.writeAsBytes(sealed, flush: true);
      await staging.rename(paths.catalog.path);
      staging = null;
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    } finally {
      if (staging != null) {
        try {
          if (await staging.exists()) await staging.delete();
        } on FileSystemException {
          // Preserve the original typed failure. A stale encrypted staging file
          // is never read as live state, and must not invalidate a completed commit.
        }
      }
    }
  }
}
