import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'archive_records.dart';

Uint8List archiveJson(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));
Future<String> archiveHash(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Never archiveBad([CheckError error = CheckError.incompleteArchive]) =>
    throw CheckException(error);

Future<ArchiveValidation> validateArchive(Map<String, Uint8List> files) =>
    Isolate.run(() async {
      final validation = ArchiveValidation();
      await validation.read(files);
      return validation;
    });

final class ArchiveValidation {
  final scopeIds = <String>{};
  final counts = <String, int>{}, revisions = <String, int>{};
  final companies = <String, Company>{};
  final authorities = <String, List<List<Object?>>>{};
  final roots = <String, Map<String, dynamic>>{};
  final attachments = <AttachmentManifestEntry>[];
  final records = <String>{}, associations = <String>{};
  final operations = <String, StoredOperation>{};
  final journal = <String, int>{};
  final profiles = <Map<String, dynamic>>[];
  late Map<String, dynamic> manifest;
  late ExportScope scope;
  Future<void> read(Map<String, Uint8List> files) async {
    try {
      manifest =
          jsonDecode(utf8.decode(files['manifest.json']!))
              as Map<String, dynamic>;
      if (manifest.keys.toSet().difference({
            'formatVersion',
            'archiveId',
            'createdUtcMs',
            'scopeKind',
            'scopeId',
            'personId',
            'companyRootFingerprints',
            'authorityHeads',
            'recordCountsByKind',
            'files',
          }).isNotEmpty ||
          manifest.length != 10 ||
          manifest['formatVersion'] != 1 ||
          manifest['archiveId'] is! String ||
          manifest['createdUtcMs'] is! int ||
          manifest['personId'] is! String) {
        archiveBad();
      }
      scope = switch (manifest['scopeKind']) {
        'personal' => PersonalScope(manifest['scopeId'] as String),
        'company' => CompanyScope(manifest['scopeId'] as String),
        _ => archiveBad(),
      };
      final expected = <String>{'manifest.json'};
      for (final f in manifest['files'] as List) {
        if (f is! Map ||
            f.length != 3 ||
            f.keys.toSet().difference({
              'path',
              'byteLength',
              'sha256',
            }).isNotEmpty) {
          archiveBad();
        }
        final path = f['path'] as String;
        final bytes = files[path];
        if (f['byteLength'] is! int ||
            f['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(f['sha256'] as String)) {
          archiveBad();
        }
        if (!expected.add(path) ||
            bytes == null ||
            bytes.length != f['byteLength'] ||
            await archiveHash(bytes) != f['sha256']) {
          archiveBad();
        }
      }
      if (expected.length != files.length ||
          !expected.containsAll(files.keys)) {
        archiveBad();
      }
      final recovery =
          jsonDecode(utf8.decode(files['recovery.json']!))
              as Map<String, dynamic>;
      if (recovery.length != 2 ||
          recovery['version'] != 1 ||
          recovery['profiles'] is! List) {
        archiveBad();
      }
      final people = <String>{};
      for (final value in recovery['profiles'] as List) {
        final p = Map<String, dynamic>.from(value as Map);
        if (p.length != 4 ||
            p['version'] != 1 ||
            p['personId'] is! String ||
            p['displayName'] is! String ||
            p['installations'] is! List ||
            !people.add(p['personId'] as String)) {
          archiveBad();
        }
        final installationKeys = <String, String>{};
        for (final i in p['installations'] as List) {
          if (i is! List ||
              i.length != 2 ||
              i[0] is! String ||
              base64Url.decode(i[1] as String).length != 32) {
            archiveBad();
          }
          final prior = installationKeys[i[0]];
          if (prior != null && prior != i[1]) {
            archiveBad(CheckError.duplicateConflict);
          }
          installationKeys[i[0] as String] = i[1] as String;
        }
        profiles.add(p);
      }
      if (!people.contains(manifest['personId'])) {
        archiveBad(CheckError.recoveryRequired);
      }
      await ArchiveRecords.readInline(files['records.json']!, (
        kind,
        value,
      ) async {
        String company;
        switch (kind) {
          case 'record':
            final r = (value as ArchiveRecord).record;
            company = r.companyId;
            records.add(jsonEncode([company, r.id]));
            counts[r.kind] = (counts[r.kind] ?? 0) + 1;
            if (r.kind == 'operatorCredential') archiveBad();
            if (r.kind == 'company') {
              final c = Company.fromJson(
                jsonDecode(utf8.decode(r.payload)) as Map<String, dynamic>,
              );
              if (c.id != r.id || c.id != company) archiveBad();
              companies[company] = c;
            }
            if (r.kind == 'authority') {
              final a = List<Object?>.from(
                jsonDecode(utf8.decode(r.payload)) as List,
              );
              if (a[0] != r.id) archiveBad();
              (authorities[company] ??= []).add(a);
            }
            if (r.kind == 'companyRootRecovery') {
              if (scope is PersonalScope) archiveBad(CheckError.unauthorized);
              roots[company] =
                  jsonDecode(utf8.decode(r.payload)) as Map<String, dynamic>;
            }
            if (r.kind == 'retiredLocalCredential') {
              final j = jsonDecode(utf8.decode(r.payload)) as Map;
              if (j.length != 8 ||
                  j.keys.toSet().difference({
                    'version',
                    'reason',
                    'id',
                    'companyId',
                    'membershipId',
                    'personId',
                    'installationId',
                    'publicKey',
                  }).isNotEmpty ||
                  j['version'] != 1 ||
                  j['reason'] != 'freshLocalSetupRequired') {
                archiveBad();
              }
            }
          case 'operation':
            final o = value as StoredOperation;
            company = o.companyId;
            if (o.result?.kind == 'operatorCredential' ||
                o.retiredLocalCredential &&
                    o.result?.kind != 'retiredLocalCredential') {
              archiveBad();
            }
            // Keep only bounded routing/provenance, never retain saved payloads.
            operations[jsonEncode([company, o.operationId])] = StoredOperation(
              companyId: company,
              operationId: o.operationId,
              authorityGenerationId: o.authorityGenerationId,
              requestDigest: Uint8List(32),
              expectedRevision: o.expectedRevision,
              revision: o.revision,
              result: o.result == null
                  ? null
                  : StoredRecord(
                      o.result!.id,
                      company,
                      o.result!.kind,
                      o.result!.revision,
                      Uint8List(0),
                    ),
              personalOwners: o.personalOwners,
              retiredLocalCredential: o.retiredLocalCredential,
            );
            if (scope case PersonalScope(:final personId)) {
              if (o.personalOwners.length != 1 ||
                  !o.personalOwners.contains(personId) ||
                  o.retiredLocalCredential ||
                  o.result?.kind == 'companyRootRecovery' ||
                  o.result?.kind == 'retiredLocalCredential') {
                archiveBad(CheckError.unauthorized);
              }
            }
          case 'journal':
            final j = value as RevisionEntry;
            company = j.companyId;
            journal[jsonEncode([company, j.operationId])] = j.revision;
          case 'association':
            final a = value as PersonalRecordAssociation;
            company = a.companyId!;
            if (scope case PersonalScope(:final personId)) {
              if (personId != a.personId) archiveBad(CheckError.unauthorized);
            }
            associations.add(jsonEncode([company, a.recordId, a.personId]));
          case 'attachment':
            final a = value as AttachmentManifestEntry;
            company = a.companyId;
            attachments.add(a);
            final bytes = files['attachments/${a.sha256}'];
            if (bytes == null ||
                bytes.length != a.byteLength ||
                await archiveHash(bytes) != a.sha256) {
              archiveBad();
            }
          case 'revision':
            final r = value as ArchiveRevision;
            company = r.companyId;
            revisions[company] = r.revision;
          default:
            archiveBad();
        }
        scopeIds.add(company);
        if (scope case CompanyScope(:final companyId)) {
          if (company != companyId) archiveBad(CheckError.wrongCompany);
        }
      });
      if (scope case PersonalScope(:final personId)) {
        if (personId != manifest['personId'] || profiles.length != 1) {
          archiveBad(CheckError.unauthorized);
        }
        for (final key in records) {
          final r = jsonDecode(key) as List;
          if (!associations.contains(jsonEncode([...r, personId]))) {
            archiveBad(CheckError.unauthorized);
          }
        }
        final maxima = <String, int>{};
        for (final o in operations.values) {
          if (o.revision != null && o.revision! > (maxima[o.companyId] ?? 0)) {
            maxima[o.companyId] = o.revision!;
          }
        }
        if (jsonEncode(_sorted(maxima)) != jsonEncode(_sorted(revisions))) {
          archiveBad();
        }
        for (final o in operations.values) {
          if (o.result != null &&
              !associations.contains(
                jsonEncode([o.companyId, o.result!.id, personId]),
              )) {
            archiveBad(CheckError.unauthorized);
          }
        }
      }
      for (final a in associations) {
        final v = jsonDecode(a) as List;
        if (!records.contains(jsonEncode(v.take(2).toList()))) archiveBad();
      }
      for (final a in attachments) {
        if (!records.contains(jsonEncode([a.companyId, a.recordId]))) {
          archiveBad();
        }
      }
      final attachmentNames = attachments
          .map((a) => 'attachments/${a.sha256}')
          .toSet();
      if (files.keys
          .where((n) => n.startsWith('attachments/'))
          .toSet()
          .difference(attachmentNames)
          .isNotEmpty) {
        archiveBad();
      }
      for (final e in operations.entries) {
        if (e.value.revision != journal[e.key] ||
            e.value.revision != null &&
                e.value.revision! > (revisions[e.value.companyId] ?? -1)) {
          archiveBad();
        }
      }
      if (journal.keys.any((key) => !operations.containsKey(key))) archiveBad();
      if (jsonEncode(_sorted(counts)) !=
          jsonEncode(
            _sorted(
              Map<String, int>.from(manifest['recordCountsByKind'] as Map),
            ),
          )) {
        archiveBad();
      }
      final expectedRoots = <String, String>{}, heads = <String, String>{};
      for (final c in companies.values) {
        final public = base64Url.decode(c.rootPublicKey);
        if (public.length != 32 ||
            await archiveHash(public) != c.rootFingerprint) {
          archiveBad();
        }
        expectedRoots[c.id] = c.rootFingerprint;
        heads[c.id] = c.authorityGenerationId;
        final history = authorities[c.id] ?? [];
        final byId = <String, List<Object?>>{};
        for (final a in history) {
          if (a.length != 7 ||
              a[0] is! String ||
              a[2] is! int ||
              a[3] is! String ||
              a[5] is! int ||
              byId.containsKey(a[0])) {
            archiveBad();
          }
          if (!await Ed25519().verify(
            utf8.encode(
              'RAZE_CHECK_AUTHORITY_V1\n${jsonEncode(a.take(6).toList())}',
            ),
            signature: Signature(
              base64Url.decode(a[6] as String),
              publicKey: SimplePublicKey(public, type: KeyPairType.ed25519),
            ),
          )) {
            archiveBad(CheckError.invalidSignature);
          }
          byId[a[0] as String] = a;
        }
        if (jsonEncode(byId[c.authorityGenerationId]) !=
            jsonEncode(c.authority)) {
          archiveBad();
        }
        final children = <Object?, String>{};
        for (final a in history) {
          final parent = a[1];
          if (parent == null) {
            if (a[2] != 1) archiveBad();
          } else if (!byId.containsKey(parent) ||
              (a[2] != (byId[parent]![2] as int) + 1 ||
                  (a[5] as int) < (byId[parent]![5] as int))) {
            archiveBad();
          }
          if (children.containsKey(parent) && children[parent] != a[0]) {
            archiveBad(CheckError.duplicateConflict);
          }
          children[parent] = a[0] as String;
        }
        if (scope is CompanyScope) {
          final root = roots[c.id];
          if (root == null || !people.contains(c.creationPersonId)) {
            archiveBad(CheckError.recoveryRequired);
          }
          final seed = base64Decode(root['seed'] as String);
          if (seed.length != 32 ||
              base64UrlEncode(
                    (await (await Ed25519().newKeyPairFromSeed(
                      seed,
                    )).extractPublicKey()).bytes,
                  ) !=
                  c.rootPublicKey ||
              root['publicKey'] != c.rootPublicKey ||
              root['keyId'] != 'company-root:${c.id}') {
            archiveBad(CheckError.recoveryRequired);
          }
        }
      }
      if (scope is CompanyScope && companies.length != 1) {
        archiveBad(CheckError.recoveryRequired);
      }
      if (jsonEncode(_sorted(expectedRoots)) !=
              jsonEncode(
                _sorted(
                  Map<String, dynamic>.from(
                    manifest['companyRootFingerprints'] as Map,
                  ),
                ),
              ) ||
          jsonEncode(_sorted(heads)) !=
              jsonEncode(
                _sorted(
                  Map<String, dynamic>.from(manifest['authorityHeads'] as Map),
                ),
              )) {
        archiveBad();
      }
    } on CheckException {
      rethrow;
    } catch (_) {
      archiveBad();
    }
  }

  static Map<String, dynamic> _sorted(Map<String, dynamic> map) => {
    for (final key in map.keys.toList()..sort()) key: map[key],
  };
}
