part of 'local_check_repository.dart';

/// Archive adapter hooks are intentionally outside CheckRepository: feature
/// code cannot call these or obtain a database handle.
extension ArchiveRepository on LocalCheckRepository {
  Future<void> visitArchive(
    ExportScope scope,
    ArchiveVisitor visitor, {
    bool Function()? cancelled,
  }) => _exclusive(
    () => _storage(
      () => _readTransaction(() async {
        final watch = Stopwatch()..start();
        var items = 0, raw = 0;
        void check([int bytes = 0, int count = 0]) {
          if (cancelled?.call() == true ||
              watch.elapsed > const Duration(minutes: 5)) {
            throw const CheckException(CheckError.invalidTransition);
          }
          if ((items += count) > 524288 || (raw += bytes) > 64 * 1024 * 1024) {
            throw const CheckException(CheckError.limitExceeded);
          }
        }

        final personal = scope is PersonalScope;
        final id = switch (scope) {
          PersonalScope(:final personId) => personId,
          CompanyScope(:final companyId) => companyId,
        };
        final revisions = <String, int>{};
        Future<void> pages(
          String sql,
          List<String> columns,
          Future<void> Function(QueryRow) consume, {
          bool body = true,
        }) async {
          List<String>? cursor;
          final tuple = '(${columns.join(',')})';
          while (true) {
            check();
            final where = cursor == null
                ? ''
                : 'WHERE $tuple > (${List.filled(columns.length, '?').join(',')})';
            final routing = await _db
                .customSelect(
                  'SELECT ${columns.join(',')}${body ? ',length(body) AS body_length' : ''} FROM ($sql) $where ORDER BY ${columns.join(',')} LIMIT 32',
                  variables: [
                    LocalCheckRepository._s(id),
                    if (cursor != null) ...cursor.map(LocalCheckRepository._s),
                  ],
                )
                .get();
            if (routing.isEmpty) break;
            for (final metadata in routing) {
              check();
              if (body &&
                  metadata.read<int>('body_length') > 12 * 1024 * 1024) {
                throw const CheckException(CheckError.limitExceeded);
              }
              final ids = columns.map((c) => metadata.read<String>(c)).toList();
              if (ids.any((v) => utf8.encode(v).length > 1024)) {
                throw const CheckException(CheckError.limitExceeded);
              }
              final row = await _db
                  .customSelect(
                    'SELECT * FROM ($sql) WHERE ${columns.map((c) => '$c=?').join(' AND ')}',
                    variables: [
                      LocalCheckRepository._s(id),
                      ...ids.map(LocalCheckRepository._s),
                    ],
                  )
                  .getSingle();
              await consume(row);
              cursor = ids;
            }
          }
        }

        await pages(
          'SELECT r.* FROM stored_rows r WHERE ${personal ? 'EXISTS(SELECT 1 FROM personal_records p WHERE p.company_id=r.company_id AND p.record_id=r.id AND p.person_id=?)' : 'r.company_id=?'}',
          ['company_id', 'id'],
          (row) async {
            final record = await _decodeRecord(row);
            check(record.payload.length, 1);
            await visitor(
              'record',
              ArchiveRecord(row.read<String>('category'), record),
            );
          },
        );
        await pages(
          'SELECT o.* FROM operation_rows o WHERE ${personal ? 'EXISTS(SELECT 1 FROM personal_operations p WHERE p.company_id=o.company_id AND p.operation_id=o.operation_id AND p.person_id=?)' : 'o.company_id=?'}',
          ['company_id', 'operation_id'],
          (row) async {
            final operation = await _decodeOperation(
              row,
              personId: personal ? id : null,
              snapshotBudget: _SnapshotBudget(64 * 1024 * 1024, 524288 - items),
            );
            if (personal && operation.result != null) {
              final r = operation.result!;
              if (await _db
                      .customSelect(
                        'SELECT 1 FROM personal_records WHERE person_id=? AND company_id=? AND record_id=?',
                        variables: [
                          LocalCheckRepository._s(id),
                          LocalCheckRepository._s(r.companyId),
                          LocalCheckRepository._s(r.id),
                        ],
                      )
                      .getSingleOrNull() ==
                  null) {
                return;
              }
            }
            check(
              operation.requestDigest.length +
                  (operation.result?.payload.length ?? 0),
              1 + operation.personalOwners.length,
            );
            await visitor('operation', operation);
            if (operation.revision != null) {
              final j = await _db
                  .customSelect(
                    'SELECT * FROM revision_journal WHERE company_id=? AND operation_id=?',
                    variables: [
                      LocalCheckRepository._s(operation.companyId),
                      LocalCheckRepository._s(operation.operationId),
                    ],
                  )
                  .getSingleOrNull();
              if (j == null || j.read<int>('revision') != operation.revision) {
                throw const CheckException(CheckError.incompleteArchive);
              }
              check(0, 1);
              await visitor(
                'journal',
                RevisionEntry(
                  operation.companyId,
                  operation.revision!,
                  operation.operationId,
                ),
              );
              if (operation.revision! > (revisions[operation.companyId] ?? 0)) {
                revisions[operation.companyId] = operation.revision!;
              }
            }
          },
        );
        await pages(
          'SELECT a.* FROM attachment_rows a WHERE ${personal ? 'EXISTS(SELECT 1 FROM personal_records p WHERE p.company_id=a.company_id AND p.record_id=a.record_id AND p.person_id=?)' : 'a.company_id=?'}',
          ['company_id', 'record_id', 'sha256'],
          (row) async {
            check(0, 1);
            await visitor('attachment', await _decodeAttachment(row));
          },
        );
        await pages(
          'SELECT * FROM personal_records WHERE ${personal ? 'person_id' : 'company_id'}=?',
          ['company_id', 'record_id', 'person_id'],
          (row) async {
            check(0, 1);
            await visitor(
              'association',
              PersonalRecordAssociation(
                row.read<String>('person_id'),
                row.read<String>('record_id'),
                companyId: row.read<String>('company_id'),
              ),
            );
          },
          body: false,
        );
        if (!personal) revisions[id] = await _revision(id);
        for (final e in revisions.entries) {
          check(0, 1);
          await visitor('revision', ArchiveRevision(e.key, e.value));
        }
      }),
    ),
  );

  Future<void> saveRestoreJournal(String id, Uint8List body) => _exclusive(
    () => _db.customStatement(
      'INSERT INTO restore_jobs(id,body) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body',
      [id, body],
    ),
  );
  Future<Map<String, Uint8List>> restoreJournals() => _exclusive(
    () async => {
      for (final row
          in await _db
              .customSelect('SELECT * FROM restore_jobs LIMIT 101')
              .get())
        row.read<String>('id'): row.read<Uint8List>('body'),
    },
  );
  Future<void> deleteRestoreJournal(String id) => _exclusive(
    () => _db.customStatement('DELETE FROM restore_jobs WHERE id=?', [id]),
  );
  Future<List<String>> archiveConflicts(Uint8List data) =>
      _exclusive(() => _readTransaction(() => _archiveConflicts(data)));
  Future<List<String>> _archiveConflicts(Uint8List data) async {
    final conflicts = <String>[];
    bool same(StoredRecord a, StoredRecord b) =>
        a.id == b.id &&
        a.companyId == b.companyId &&
        a.kind == b.kind &&
        a.revision == b.revision &&
        _sameBytes(a.payload, b.payload);
    await ArchiveRecords.read(data, (kind, value) async {
      switch (kind) {
        case 'record':
          final r = value as ArchiveRecord;
          final old = await _db
              .customSelect(
                'SELECT * FROM stored_rows WHERE company_id=? AND id=?',
                variables: [
                  LocalCheckRepository._s(r.record.companyId),
                  LocalCheckRepository._s(r.record.id),
                ],
              )
              .getSingleOrNull();
          if (old != null &&
              (old.read<String>('category') != r.category ||
                  !same(await _decodeRecord(old), r.record))) {
            conflicts.add('Record conflict: ${r.record.id}');
          }
        case 'operation':
          final o = value as StoredOperation,
              old = await _operation((value).companyId, value.operationId);
          if (old != null &&
              (o.retiredLocalCredential != old.retiredLocalCredential ||
                  o.authorityGenerationId != old.authorityGenerationId ||
                  !_sameBytes(o.requestDigest, old.requestDigest) ||
                  o.expectedRevision != old.expectedRevision ||
                  o.revision != old.revision ||
                  o.personalOwners.length != old.personalOwners.length ||
                  !o.personalOwners.containsAll(old.personalOwners) ||
                  ((o.result == null) != (old.result == null)) ||
                  o.result != null && !same(o.result!, old.result!))) {
            conflicts.add('Operation conflict: ${o.operationId}');
          }
        case 'journal':
          final j = value as RevisionEntry;
          final old = await _db
              .customSelect(
                'SELECT * FROM revision_journal WHERE company_id=? AND (revision=? OR operation_id=?)',
                variables: [
                  LocalCheckRepository._s(j.companyId),
                  LocalCheckRepository._i(j.revision),
                  LocalCheckRepository._s(j.operationId),
                ],
              )
              .get();
          if (old.any(
            (r) =>
                r.read<int>('revision') != j.revision ||
                r.read<String>('operation_id') != j.operationId,
          )) {
            conflicts.add('Journal conflict: ${j.companyId}');
          }
        case 'revision':
          final r = value as ArchiveRevision,
              old = await _revision((value).companyId);
          if (old != 0 && old != r.revision) {
            conflicts.add('Revision conflict: ${r.companyId}');
          }
        case 'attachment':
          final a = value as AttachmentManifestEntry;
          final old = await _db
              .customSelect(
                'SELECT * FROM attachment_rows WHERE company_id=? AND record_id=? AND sha256=?',
                variables: [
                  LocalCheckRepository._s(a.companyId),
                  LocalCheckRepository._s(a.recordId),
                  LocalCheckRepository._s(a.sha256),
                ],
              )
              .getSingleOrNull();
          if (old != null &&
              (await _decodeAttachment(old)).byteLength != a.byteLength) {
            conflicts.add('Attachment conflict: ${a.sha256}');
          }
      }
      if (conflicts.length > 1000) {
        throw const CheckException(CheckError.duplicateConflict);
      }
    });
    return conflicts;
  }

  /// One transaction preserves original provenance and only inserts missing
  /// identities. The passive gate is accepted with the data, never afterwards.
  Future<bool> importArchive(
    Uint8List data, {
    required String archiveId,
    String? contentHash,
    required void Function() beforeCommit,
    List<Map<String, dynamic>> profiles = const [],
  }) => _exclusive(
    () => _storage(
      () => _db.transaction(() async {
        if (contentHash != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(contentHash)) {
          throw const CheckException(CheckError.malformed);
        }
        final hash = contentHash == null
            ? Uint8List.fromList((await Sha256().hash(data)).bytes)
            : Uint8List.fromList(
                List.generate(
                  32,
                  (i) => int.parse(
                    contentHash.substring(i * 2, i * 2 + 2),
                    radix: 16,
                  ),
                ),
              );
        final prior = await _db
            .customSelect(
              'SELECT body FROM restore_commits WHERE archive_id=?',
              variables: [LocalCheckRepository._s(archiveId)],
            )
            .getSingleOrNull();
        if (prior != null) {
          if (!_sameBytes(prior.read<Uint8List>('body'), hash)) {
            throw const CheckException(CheckError.duplicateConflict);
          }
          beforeCommit();
          return false;
        }
        if ((await _archiveConflicts(data)).isNotEmpty) {
          throw const CheckException(CheckError.duplicateConflict);
        }
        final newScopes = <String>{};
        Future<void> ensure(String company) async {
          if (await _db
                  .customSelect(
                    'SELECT 1 FROM company_scopes WHERE company_id=?',
                    variables: [LocalCheckRepository._s(company)],
                  )
                  .getSingleOrNull() ==
              null) {
            newScopes.add(company);
            await _ensureCompany(company);
          }
        }

        for (final p in profiles) {
          final person = p['personId'] as String;
          final old = await _db
              .customSelect(
                'SELECT body FROM restored_profiles WHERE person_id=?',
                variables: [LocalCheckRepository._s(person)],
              )
              .getSingleOrNull();
          final bytes = Uint8List.fromList(utf8.encode(jsonEncode(p)));
          if (old == null) {
            final sealed = await _payloadCipher.seal(
              scopeId: person,
              recordId: 'passive-profile',
              revision: 1,
              plain: bytes,
            );
            await _db.customStatement(
              'INSERT INTO restored_profiles(person_id,body) VALUES(?,?)',
              [person, sealed],
            );
          } else {
            final existing = await _payloadCipher.open(
              scopeId: person,
              recordId: 'passive-profile',
              revision: 1,
              sealed: old.read<Uint8List>('body'),
            );
            if (!_sameBytes(existing, bytes)) {
              throw const CheckException(CheckError.duplicateConflict);
            }
          }
        }
        await ArchiveRecords.read(data, (kind, value) async {
          switch (kind) {
            case 'record':
              final a = value as ArchiveRecord, r = a.record;
              await ensure(r.companyId);
              if (await _read(r.companyId, r.id) == null) {
                await _saveRecord(r, a.category);
              }
              if (r.kind == 'company' &&
                  profiles.any(
                    (p) =>
                        p['personId'] ==
                        Company.fromJson(
                          jsonDecode(utf8.decode(r.payload))
                              as Map<String, dynamic>,
                        ).creationPersonId,
                  )) {
                final c = Company.fromJson(
                  jsonDecode(utf8.decode(r.payload)) as Map<String, dynamic>,
                );
                final old = await _db
                    .customSelect(
                      'SELECT company_id,authority_generation_id,body FROM company_creation_reservations WHERE person_id=? AND operation_id=?',
                      variables: [
                        LocalCheckRepository._s(c.creationPersonId),
                        LocalCheckRepository._s(c.creationOperationId),
                      ],
                    )
                    .getSingleOrNull();
                if (old == null) {
                  final body = await _payloadCipher.seal(
                    scopeId: c.creationPersonId,
                    recordId: 'company-reservation:${c.creationOperationId}',
                    revision: 1,
                    plain: Uint8List.fromList(
                      utf8.encode(
                        jsonEncode({
                          'companyId': c.id,
                          'authorityGenerationId': c.authorityGenerationId,
                          'requestDigest': c.creationDigest,
                        }),
                      ),
                    ),
                  );
                  await _db.customStatement(
                    'INSERT INTO company_creation_reservations(person_id,operation_id,company_id,authority_generation_id,body) VALUES(?,?,?,?,?)',
                    [
                      c.creationPersonId,
                      c.creationOperationId,
                      c.id,
                      c.authorityGenerationId,
                      body,
                    ],
                  );
                } else if (old.read<String>('company_id') != c.id ||
                    old.read<String>('authority_generation_id') !=
                        c.authorityGenerationId) {
                  throw const CheckException(CheckError.duplicateConflict);
                }
              }
            case 'operation':
              final o = value as StoredOperation;
              await ensure(o.companyId);
              if (await _operation(o.companyId, o.operationId) == null) {
                await _saveOperation(
                  CommandContext(
                    companyId: o.companyId,
                    session: const _RestoreSession(),
                    operationId: o.operationId,
                    authorityGenerationId: o.authorityGenerationId,
                    expectedRevision: o.expectedRevision,
                  ),
                  o.requestDigest,
                  revision: o.revision,
                  result: o.result,
                  retiredLocalCredential: o.retiredLocalCredential,
                );
                await _associateOperation(
                  o.companyId,
                  o.operationId,
                  o.personalOwners,
                );
              }
            case 'journal':
              final j = value as RevisionEntry;
              await _db.customStatement(
                'INSERT OR IGNORE INTO revision_journal(company_id,revision,operation_id) VALUES(?,?,?)',
                [j.companyId, j.revision, j.operationId],
              );
            case 'association':
              final a = value as PersonalRecordAssociation;
              await _db.customStatement(
                'INSERT OR IGNORE INTO personal_records(person_id,company_id,record_id) VALUES(?,?,?)',
                [a.personId, a.companyId, a.recordId],
              );
            case 'attachment':
              final a = value as AttachmentManifestEntry;
              final body = await _payloadCipher.seal(
                scopeId: a.companyId,
                recordId: 'manifest:${a.recordId}:${a.sha256}',
                revision: 1,
                plain: Uint8List.fromList(
                  utf8.encode(jsonEncode({'byteLength': a.byteLength})),
                ),
              );
              await _db.customStatement(
                'INSERT OR IGNORE INTO attachment_rows(company_id,record_id,sha256,body) VALUES(?,?,?,?)',
                [a.companyId, a.recordId, a.sha256, body],
              );
            case 'revision':
              final r = value as ArchiveRevision;
              await ensure(r.companyId);
              await _db.customUpdate(
                'UPDATE company_scopes SET revision=? WHERE company_id=?',
                variables: [
                  LocalCheckRepository._i(r.revision),
                  LocalCheckRepository._s(r.companyId),
                ],
                updates: {_db.companyScopes},
              );
          }
        });
        for (final company in newScopes) {
          for (final row
              in await _db
                  .customSelect(
                    "SELECT * FROM stored_rows WHERE company_id=? AND kind='membership'",
                    variables: [LocalCheckRepository._s(company)],
                  )
                  .get()) {
            final member = Membership.fromJson(
              jsonDecode(utf8.decode((await _decodeRecord(row)).payload))
                  as Map<String, dynamic>,
            );
            final id = 'member-index:${member.personId}',
                bytes = Uint8List.fromList(
                  utf8.encode(jsonEncode({'membershipId': member.id})),
                );
            final old = await _read(company, id);
            if (old == null) {
              await _saveRecord(
                StoredRecord(id, company, 'membershipIndex', 1, bytes),
                'entity',
              );
            } else if (!_sameBytes(old.payload, bytes)) {
              throw const CheckException(CheckError.duplicateConflict);
            }
          }
          await _db.customStatement(
            'INSERT INTO passive_scopes(company_id,archive_id) VALUES(?,?)',
            [company, archiveId],
          );
        }
        await _db.customStatement(
          'INSERT INTO restore_commits(archive_id,body) VALUES(?,?)',
          [archiveId, hash],
        );
        beforeCommit();
        return true;
      }),
    ),
  );
  Future<bool> hasRestoreCommit(String archiveId, {String? contentHash}) =>
      _exclusive(() async {
        final row = await _db
            .customSelect(
              'SELECT body FROM restore_commits WHERE archive_id=?',
              variables: [LocalCheckRepository._s(archiveId)],
            )
            .getSingleOrNull();
        return row != null &&
            (contentHash == null ||
                row
                        .read<Uint8List>('body')
                        .map((b) => b.toRadixString(16).padLeft(2, '0'))
                        .join() ==
                    contentHash);
      });
  Future<List<Map<String, dynamic>>> passiveProfiles() => _exclusive(() async {
    final result = <Map<String, dynamic>>[];
    for (final r
        in await _db
            .customSelect(
              'SELECT * FROM restored_profiles ORDER BY person_id LIMIT 10001',
            )
            .get()) {
      if (result.length >= 10000) {
        throw const CheckException(CheckError.limitExceeded);
      }
      final plain = await _payloadCipher.open(
        scopeId: r.read<String>('person_id'),
        recordId: 'passive-profile',
        revision: 1,
        sealed: r.read<Uint8List>('body'),
      );
      result.add(jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
    }
    return result;
  });
}

final class _RestoreSession implements SessionHandle {
  const _RestoreSession();
}
