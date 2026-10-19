import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:raze_check_core/raze_check_core.dart';
import '../database/local_check_repository.dart';
import '../files/app_paths.dart';
import '../files/immutable_attachment_store.dart';
import '../security/local_identity_service.dart';
import '../security/payload_cipher.dart';
import '../security/secure_key_store.dart';
import 'archive_codec.dart';
import 'archive_records.dart';
import 'archive_validation.dart';
import 'backup_catalog.dart';
import 'restore_staging.dart';

final class LocalArchiveService implements BackupService, RestoreService {
  LocalArchiveService({
    required this.paths,
    required this.keys,
    required this.repository,
    required this.identity,
    required this.clock,
    required this.ids,
    FutureOr<void> Function(String)? fault,
  }) : staging = RestoreStaging(
         paths: paths,
         keys: keys,
         repository: repository,
         fault: fault,
       ),
       catalog = BackupCatalog(paths, keys);
  final AppPaths paths;
  final SecureKeyStore keys;
  final LocalCheckRepository repository;
  final LocalIdentityService identity;
  final CheckClock clock;
  final IdGenerator ids;
  final RestoreStaging staging;
  final BackupCatalog catalog;
  final _previews =
      Map<
        RestorePreview,
        ({SessionHandle session, DateTime created})
      >.identity();
  bool _busy = false;
  Future<T> _serial<T>(Future<T> Function() action) async {
    if (_busy) archiveBad(CheckError.invalidTransition);
    _busy = true;
    try {
      await staging.recoverPendingApplications();
      return await action();
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    } finally {
      _busy = false;
    }
  }

  ActorIdentity _personal(SessionHandle session) {
    final actor = identity.requireActor(session);
    if (actor.restrictedCompanyId != null) archiveBad(CheckError.unauthorized);
    return actor;
  }

  Future<void> _authorize(SessionHandle session, ExportScope scope) async {
    final actor = _personal(session);
    if (scope case PersonalScope(:final personId)) {
      if (personId != actor.personId) archiveBad(CheckError.unauthorized);
      return;
    }
    final company = (scope as CompanyScope).companyId;
    final index = await repository.read(
      company,
      'member-index:${actor.personId}',
    );
    if (index == null) archiveBad(CheckError.unauthorized);
    final member = await repository.read(
      company,
      (jsonDecode(utf8.decode(index.payload)) as Map)['membershipId'] as String,
    );
    if (member == null) archiveBad(CheckError.unauthorized);
    AccessPolicy(identity).require(
      session,
      Membership.fromJson(
        jsonDecode(utf8.decode(member.payload)) as Map<String, dynamic>,
      ),
      Capability.backupCompany,
    );
  }

  @override
  String get storageDescription =>
      '${catalog.directory.path} (private app storage; removed on uninstall)';
  @override
  Future<ArchiveDescriptor> create(
    SessionHandle session,
    ExportScope scope,
    String passphrase,
  ) => _serial(() async {
    await _authorize(session, scope);
    final actor = identity.requireActor(session),
        encoder = await ArchiveRecordWorker.start();
    final counts = <String, int>{},
        companies = <String, Company>{},
        entries = <AttachmentManifestEntry>[];
    late Uint8List records;
    try {
      await repository.visitArchive(
        scope,
        (kind, value) async {
          if (kind == 'record') {
            final r = ArchiveRecords.portableRecord(
              (value as ArchiveRecord).record,
            );
            counts[r.kind] = (counts[r.kind] ?? 0) + 1;
            if (r.kind == 'company') {
              companies[r.companyId] = Company.fromJson(
                jsonDecode(utf8.decode(r.payload)) as Map<String, dynamic>,
              );
            }
          }
          if (kind == 'attachment') {
            entries.add(value as AttachmentManifestEntry);
          }
          await encoder.add(kind, value);
        },
        cancelled: () {
          try {
            identity.requireActor(session);
            return false;
          } on CheckException {
            return true;
          }
        },
      );
      records = await encoder.finish();
    } finally {
      encoder.dispose();
    }
    final requiredPeople = {
      actor.personId,
      if (scope is CompanyScope)
        ...companies.values.map((c) => c.creationPersonId),
    };
    final profiles = (await identity.profiles())
        .where((p) => requiredPeople.contains(p.personId))
        .map(
          (p) => <String, dynamic>{
            'version': 1,
            'personId': p.personId,
            'displayName': p.displayName,
            'installations': [
              [p.installationId, base64UrlEncode(p.publicKey)],
            ],
          },
        )
        .toList();
    if (profiles.length != requiredPeople.length) {
      archiveBad(CheckError.recoveryRequired);
    }
    final files = <String, Uint8List>{
      'records.json': records,
      'recovery.json': archiveJson({'version': 1, 'profiles': profiles}),
    };
    final store = ImmutableAttachmentStore(
      paths: paths,
      cipher: AesPayloadCipher(VaultKeys(keys)),
    );
    var total = files.values.fold(0, (n, b) => n + b.length);
    for (final entry in entries) {
      final name = 'attachments/${entry.sha256}';
      if (!files.containsKey(name)) {
        total += entry.byteLength;
        if (total > ArchiveLimits.bytes) archiveBad(CheckError.limitExceeded);
        files[name] = await store.read(entry);
      }
    }
    final artifactId = ids.next(),
        created = clock.nowUtc().millisecondsSinceEpoch;
    final manifest = <String, dynamic>{
      'formatVersion': 1,
      'archiveId': artifactId,
      'createdUtcMs': created,
      'scopeKind': scope is PersonalScope ? 'personal' : 'company',
      'scopeId': scope is PersonalScope
          ? scope.personId
          : (scope as CompanyScope).companyId,
      'personId': actor.personId,
      'companyRootFingerprints': {
        for (final c in companies.values) c.id: c.rootFingerprint,
      },
      'authorityHeads': {
        for (final c in companies.values) c.id: c.authorityGenerationId,
      },
      'recordCountsByKind': counts,
      'files': [
        for (final e in files.entries)
          {
            'path': e.key,
            'byteLength': e.value.length,
            'sha256': await archiveHash(e.value),
          },
      ],
    };
    files['manifest.json'] = archiveJson(manifest);
    await validateArchive(files);
    final sealed = await ArchiveCodec.seal(files, passphrase);
    await _authorize(session, scope);
    await catalog.publish(sealed, {
      'artifactId': artifactId,
      'createdUtcMs': created,
      'scopeKind': manifest['scopeKind'],
      'scopeId': manifest['scopeId'],
      'personId': actor.personId,
      'counts': counts,
      'externalCopyConfirmed': false,
    }, () => identity.requireActor(session));
    return ArchiveDescriptor(
      artifactId: artifactId,
      createdUtcMs: created,
      scope: scope,
      counts: Map.unmodifiable(counts),
    );
  });
  ExportScope _scope(Map<String, dynamic> m) => m['scopeKind'] == 'personal'
      ? PersonalScope(m['scopeId'] as String)
      : CompanyScope(m['scopeId'] as String);
  @override
  Future<ArchiveDescriptor?> last(SessionHandle session) async {
    _personal(session);
    final m = await catalog.read();
    if (m == null) return null;
    await _authorize(session, _scope(m));
    return ArchiveDescriptor(
      artifactId: m['artifactId'] as String,
      createdUtcMs: m['createdUtcMs'] as int,
      scope: _scope(m),
      counts: Map<String, int>.from(m['counts'] as Map),
      externalCopyConfirmed: m['externalCopyConfirmed'] == true,
    );
  }

  @override
  Future<Uint8List> shareBytes(SessionHandle session, String artifactId) async {
    final m = await catalog.read();
    if (m == null || m['artifactId'] != artifactId) {
      archiveBad(CheckError.unauthorized);
    }
    await _authorize(session, _scope(m));
    final file = catalog.artifact(artifactId);
    if (await file.length() > ArchiveLimits.bytes) {
      archiveBad(CheckError.limitExceeded);
    }
    final bytes = await file.readAsBytes();
    await _authorize(session, _scope(m));
    return bytes;
  }

  @override
  Future<void> confirmExternalCopy(SessionHandle session, String artifactId) =>
      _serial(() async {
        final m = await catalog.read();
        if (m == null || m['artifactId'] != artifactId) {
          archiveBad(CheckError.unauthorized);
        }
        await _authorize(session, _scope(m));
        m['externalCopyConfirmed'] = true;
        await catalog.write(m, () => identity.requireActor(session));
      });
  @override
  Future<RestorePreview> inspect(
    SessionHandle session,
    String selectedFile,
    String passphrase,
  ) => _serial(() async {
    _personal(session);
    // The selected source is only read. Count actual bytes, never allocate from
    // untrusted picker metadata or delete a source supplied by a caller.
    final source = File(selectedFile);
    if (await source.length() > ArchiveLimits.bytes) {
      archiveBad(CheckError.limitExceeded);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in source.openRead()) {
      if (bytes.length + chunk.length > ArchiveLimits.bytes) {
        archiveBad(CheckError.limitExceeded);
      }
      bytes.add(chunk);
    }
    final files = await ArchiveCodec.open(bytes.takeBytes(), passphrase);
    final validated = await validateArchive(files);
    final conflicts = await repository.archiveConflicts(files['records.json']!);
    _personal(session);
    final token = ids.next();
    await staging.stage(
      token,
      files,
      validated.manifest['archiveId'] as String,
    );
    try {
      _personal(session);
      final preview = RestorePreview(
        manifestId: validated.manifest['archiveId'] as String,
        personId: validated.manifest['personId'] as String,
        companyIds: List.unmodifiable(validated.revisions.keys),
        authorityHistory: Map.unmodifiable(validated.authorities),
        counts: Map.unmodifiable(validated.counts),
        hashes: {
          for (final f in validated.manifest['files'] as List)
            f['path'] as String: f['sha256'] as String,
        },
        conflicts: List.unmodifiable(conflicts),
        stagingToken: token,
        filesComplete: true,
      );
      _previews[preview] = (session: session, created: clock.nowUtc());
      return preview;
    } catch (_) {
      await staging.discard(token);
      rethrow;
    }
  });
  @override
  Future<RestoreResult> apply(RestorePreview preview, RestoreChoice choice) =>
      _serial(() async {
        final bound = _previews[preview];
        if (bound == null ||
            clock.nowUtc().difference(bound.created) >
                const Duration(minutes: 5)) {
          archiveBad(CheckError.invalidTransition);
        }
        void guard() {
          _personal(bound.session);
        }

        guard();
        final files = await staging.files(preview.stagingToken),
            validated = await validateArchive(files);
        if (preview.conflicts.isNotEmpty ||
            (await repository.archiveConflicts(
              files['records.json']!,
            )).isNotEmpty) {
          archiveBad(CheckError.duplicateConflict);
        }
        if (choice == RestoreChoice.newInstallation) {
          for (final c in validated.companies.keys) {
            if (await repository.read(c, c) != null &&
                !await repository.hasRestoreCommit(preview.manifestId)) {
              archiveBad(CheckError.duplicateConflict);
            }
          }
        }
        final changed = await staging.apply(
          preview.stagingToken,
          validated,
          files,
          guard,
        );
        _previews.remove(preview);
        return RestoreResult(preview.manifestId, duplicate: !changed);
      });
  @override
  Future<void> discard(RestorePreview preview) async {
    if (_previews.remove(preview) != null) {
      await staging.discard(preview.stagingToken);
    }
  }

  Future<void> resume() => _serial(staging.resume);
}
