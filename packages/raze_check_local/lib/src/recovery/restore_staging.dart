import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:raze_check_core/raze_check_core.dart';
import '../database/local_check_repository.dart';
import '../files/app_paths.dart';
import '../files/durable_directory.dart';
import '../files/immutable_attachment_store.dart';
import '../security/secure_key_store.dart';
import '../security/payload_cipher.dart';
import 'archive_validation.dart';

/// Installation-local I/O intent, intentionally excluded from portable records.
/// SQLite FULL journals own allocations before side effects. Secrets and all
/// staged content are encrypted under a separately provisioned staging vault.
final class RestoreStaging {
  RestoreStaging({
    required this.paths,
    required this.keys,
    required this.repository,
    this.fault,
  });
  final AppPaths paths;
  final SecureKeyStore keys;
  final LocalCheckRepository repository;
  final FutureOr<void> Function(String)? fault;
  Directory _dir(String id) {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) archiveBad();
    return Directory('${paths.root.path}/restore/$id');
  }

  String _scope(String id) => 'restore-$id';
  AesPayloadCipher get _cipher => AesPayloadCipher(VaultKeys(keys));
  Future<void> _save(String id, Map<String, dynamic> plan) async =>
      repository.saveRestoreJournal(
        id,
        await _cipher.seal(
          scopeId: _scope(id),
          recordId: 'journal',
          revision: 1,
          plain: archiveJson(plan),
        ),
      );
  Future<Map<String, dynamic>> _load(String id, Uint8List body) async =>
      jsonDecode(
            utf8.decode(
              await _cipher.open(
                scopeId: _scope(id),
                recordId: 'journal',
                revision: 1,
                sealed: body,
              ),
            ),
          )
          as Map<String, dynamic>;
  Future<void> stage(
    String id,
    Map<String, Uint8List> files,
    String archiveId,
  ) async {
    final journals = await repository.restoreJournals();
    if (journals.containsKey(id) ||
        await keys.read('vault:${_scope(id)}') != null ||
        await _dir(id).exists()) {
      archiveBad(CheckError.duplicateConflict);
    }
    if (journals.length >= 100) {
      archiveBad(CheckError.limitExceeded);
    }
    await repository.saveRestoreJournal(id, Uint8List(0));
    try {
      await VaultKeys(keys).create(_scope(id));
      final dir = await _dir(id).create(recursive: true);
      final entries = <String>[];
      for (final e in files.entries) {
        final index = entries.length;
        entries.add(e.key);
        final sealed = await _cipher.seal(
          scopeId: _scope(id),
          recordId: e.key,
          revision: 1,
          plain: e.value,
        );
        await File('${dir.path}/$index.enc').writeAsBytes(sealed, flush: true);
      }
      DurableDirectory.through(dir, paths.root);
      await _save(id, {
        'version': 1,
        'state': 'inspection',
        'archiveId': archiveId,
        'contentHash': await archiveHash(files['manifest.json']!),
        'entries': entries,
        'allocations': <dynamic>[],
        'moves': <dynamic>[],
      });
    } catch (_) {
      await discard(id);
      rethrow;
    }
  }

  Future<Map<String, Uint8List>> files(String id) async {
    final plan = await _load(id, (await repository.restoreJournals())[id]!);
    final result = <String, Uint8List>{};
    var i = 0, total = 0;
    for (final name in plan['entries'] as List) {
      final file = File('${_dir(id).path}/${i++}.enc');
      final length = await file.length();
      if (length > 64 * 1024 * 1024 + 29 ||
          (total += length) > 64 * 1024 * 1024 + 10000 * 29) {
        archiveBad(CheckError.limitExceeded);
      }
      result[name as String] = await _cipher.open(
        scopeId: _scope(id),
        recordId: name,
        revision: 1,
        sealed: await file.readAsBytes(),
      );
    }
    return result;
  }

  Future<bool> apply(
    String id,
    ArchiveValidation validated,
    Map<String, Uint8List> files,
    void Function() guard,
  ) async {
    final plan = await _load(id, (await repository.restoreJournals())[id]!);
    if (plan['state'] != 'inspection') archiveBad(CheckError.invalidTransition);
    final allocations = plan['allocations'] as List;
    final scopes = {
      ...validated.scopeIds,
      ...validated.profiles.map((p) => p['personId'] as String),
    };
    for (final scope in scopes) {
      if (await keys.read('vault:$scope') == null) {
        allocations.add([
          'vault:$scope',
          base64Encode(secureRandomBytes(32)),
          false,
        ]);
      }
    }
    for (final e in validated.roots.entries) {
      final key = 'company-root:${e.key}',
          value = base64Decode(e.value['seed'] as String),
          old = await keys.read(key);
      if (old == null) {
        if (await repository.read(e.key, e.key) != null) {
          archiveBad(CheckError.duplicateConflict);
        }
        allocations.add([key, base64Encode(value), false]);
      } else if (base64Encode(old) != base64Encode(value)) {
        archiveBad(CheckError.duplicateConflict);
      }
    }
    guard();
    plan['state'] = 'applying';
    await _save(id, plan);
    await fault?.call('journal');
    try {
      for (final allocation in allocations) {
        final key = allocation[0] as String;
        if (await keys.read(key) != null) {
          archiveBad(CheckError.duplicateConflict);
        }
        await keys.write(key, base64Decode(allocation[1] as String));
        allocation[2] = true;
        await _save(id, plan);
        await fault?.call('keyWritten');
      }
      await fault?.call('keys');
      final store = ImmutableAttachmentStore(paths: paths, cipher: _cipher);
      for (final a in validated.attachments) {
        if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(a.companyId)) {
          archiveBad();
        }
        final relative = 'attachments/${a.companyId}/${a.sha256}.enc';
        final target = File('${paths.root.path}/$relative');
        if (await target.exists()) {
          await store.read(a);
          continue;
        }
        final sealed = await _cipher.seal(
          scopeId: a.companyId,
          recordId: 'attachment:${a.sha256}',
          revision: 1,
          plain: files['attachments/${a.sha256}']!,
        );
        final staged = File(
          '${_dir(id).path}/move-${(plan['moves'] as List).length}.enc',
        );
        await staged.writeAsBytes(sealed, flush: true);
        (plan['moves'] as List).add([relative, await archiveHash(sealed)]);
        await _save(id, plan);
        await target.parent.create(recursive: true);
        // The application has one serialized restore coordinator. Recheck and
        // never overwrite content created before this publication boundary.
        if (await target.exists()) {
          await store.read(a);
          (plan['moves'] as List).removeLast();
          await _save(id, plan);
          continue;
        }
        await staged.rename(target.path);
        DurableDirectory.through(target.parent, paths.root);
        await fault?.call('attachmentMoved');
      }
      await fault?.call('attachments');
      guard();
      await fault?.call('beforeDatabase');
      final changed = await repository.importArchive(
        files['records.json']!,
        archiveId: validated.manifest['archiveId'] as String,
        contentHash: plan['contentHash'] as String,
        profiles: validated.profiles,
        beforeCommit: guard,
      );
      await fault?.call('afterDatabase');
      await discard(id);
      return changed;
    } on Exception {
      await _recover(id, plan);
      rethrow;
    }
  }

  Future<void> _recover(String id, Map<String, dynamic> plan) async {
    if (plan['state'] == 'applying' &&
        !await repository.hasRestoreCommit(
          plan['archiveId'] as String,
          contentHash: plan['contentHash'] as String,
        )) {
      // A scope vault is shared as soon as it is written. Another normal
      // writer may use it even without any restore-owned attachment move.
      // Only private staging keys (discard below) and unrelated acknowledged
      // recovery allocations are cleanup candidates; shared vaults stay.
      for (final allocation in (plan['allocations'] as List).reversed) {
        final old = await keys.read(allocation[0] as String);
        if (!(allocation[0] as String).startsWith('vault:') &&
            allocation[2] == true &&
            old != null &&
            base64Encode(old) == allocation[1]) {
          await keys.delete(allocation[0] as String);
        }
      }
    }
    await discard(id);
  }

  Future<void> recoverPendingApplications() async {
    for (final e in (await repository.restoreJournals()).entries) {
      if (e.value.isEmpty) {
        await discard(e.key);
        continue;
      }
      final plan = await _load(e.key, e.value);
      if (plan['state'] == 'applying') await _recover(e.key, plan);
    }
  }

  Future<void> resume() async {
    for (final e in (await repository.restoreJournals()).entries) {
      if (e.value.isEmpty) {
        await discard(e.key);
        continue;
      }
      // Missing/corrupt journal key fails closed. Do not guess ownership.
      await _recover(e.key, await _load(e.key, e.value));
    }
  }

  Future<void> discard(String id) async {
    await repository.saveRestoreJournal(id, Uint8List(0));
    final dir = _dir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
    await keys.delete('vault:${_scope(id)}');
    await repository.deleteRestoreJournal(id);
  }
}
