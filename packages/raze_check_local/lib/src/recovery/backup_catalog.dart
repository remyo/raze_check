import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:raze_check_core/raze_check_core.dart';
import '../files/app_paths.dart';
import '../files/durable_directory.dart';
import '../security/secure_key_store.dart';
import '../security/payload_cipher.dart';
import 'archive_validation.dart';

final class BackupCatalog {
  BackupCatalog(this.paths, this.keys);
  final AppPaths paths;
  final SecureKeyStore keys;
  Directory get directory => Directory('${paths.root.path}/backups');
  File get _index => File('${directory.path}/catalog.enc');
  Future<Map<String, dynamic>?> read() async {
    if (!await _index.exists()) return null;
    return jsonDecode(
          utf8.decode(
            await AesPayloadCipher(VaultKeys(keys)).open(
              scopeId: 'backup-catalog',
              recordId: 'last',
              revision: 1,
              sealed: await _index.readAsBytes(),
            ),
          ),
        )
        as Map<String, dynamic>;
  }

  File artifact(String id) {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) archiveBad();
    return File('${directory.path}/$id.razecheck-backup');
  }

  Future<void> publish(
    Uint8List bytes,
    Map<String, dynamic> metadata,
    void Function() guard,
  ) async {
    await directory.create(recursive: true);
    final target = artifact(metadata['artifactId'] as String);
    if (await target.exists()) archiveBad(CheckError.duplicateConflict);
    final staged = File('${target.path}.tmp');
    try {
      await staged.writeAsBytes(bytes, flush: true);
      guard();
      await staged.rename(target.path);
      DurableDirectory.through(directory, paths.root);
      await write(metadata, guard);
    } catch (_) {
      if (await staged.exists()) await staged.delete();
      rethrow;
    }
  }

  Future<void> write(
    Map<String, dynamic> metadata,
    void Function() guard,
  ) async {
    if (!await _index.exists() &&
        await keys.read('vault:backup-catalog') == null) {
      await VaultKeys(keys).create('backup-catalog');
    }
    final sealed = await AesPayloadCipher(VaultKeys(keys)).seal(
      scopeId: 'backup-catalog',
      recordId: 'last',
      revision: 1,
      plain: archiveJson(metadata),
    );
    final temp = File('${_index.path}.${SecureIds().next()}.tmp');
    try {
      await temp.writeAsBytes(sealed, flush: true);
      guard();
      temp.renameSync(_index.path);
      DurableDirectory.through(directory, paths.root);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
