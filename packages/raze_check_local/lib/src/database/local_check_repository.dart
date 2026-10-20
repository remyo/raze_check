import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../security/payload_cipher.dart';
import '../files/app_paths.dart';
import 'check_database.dart' show CheckDatabase;
import '../recovery/archive_records.dart';
part 'archive_repository.dart';
part 'attendance_read.dart';

/// Transactional local adapter. Authorization stays in application services.
final class LocalCheckRepository implements CheckRepository {
  LocalCheckRepository({
    required CheckDatabase database,
    required PayloadCipher cipher,
  }) : _db = database,
       _payloadCipher = cipher;

  /// Open private storage and validate its schema before returning services.
  static Future<LocalCheckRepository> open({
    required AppPaths paths,
    required PayloadCipher cipher,
  }) async {
    final database = CheckDatabase.open(paths);
    try {
      await database.customSelect('SELECT 1').get();
      return LocalCheckRepository(database: database, cipher: cipher);
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  final CheckDatabase _db;
  final PayloadCipher _payloadCipher;
  Future<void> _tail = Future.value();

  // A builder can await encryption and service work. Serialize the entire
  // transaction, rather than merely individual SQLite statements.
  Future<T> _exclusive<T>(Future<T> Function() work) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
    }
  }

  static Variable<String> _s(String value) => Variable.withString(value);
  static Variable<int> _i(int value) => Variable.withInt(value);
  static Variable<Uint8List> _b(Uint8List value) => Variable.withBlob(value);
  void _validateIntent(CommandContext context, Uint8List digest) {
    if (context.companyId.isEmpty ||
        context.operationId.isEmpty ||
        context.authorityGenerationId.isEmpty ||
        digest.length != 32 ||
        (context.expectedRevision != null && context.expectedRevision! < 0)) {
      throw const CheckException(CheckError.malformed);
    }
  }

  Future<void> _ensureCompany(String companyId) => _db.customStatement(
    'INSERT OR IGNORE INTO company_scopes(company_id) VALUES(?)',
    [companyId],
  );
  Future<int> _revision(String companyId) async =>
      (await _db
              .customSelect(
                'SELECT revision FROM company_scopes WHERE company_id = ?',
                variables: [_s(companyId)],
              )
              .getSingleOrNull())
          ?.read<int>('revision') ??
      0;

  Future<StoredOperation?> _operation(String companyId, String id) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM operation_rows WHERE company_id = ? AND operation_id = ?',
          variables: [_s(companyId), _s(id)],
        )
        .getSingleOrNull();
    return row == null ? null : _decodeOperation(row);
  }

  Future<StoredOperation> _decodeOperation(
    QueryRow row, {
    String? personId,
    _SnapshotBudget? snapshotBudget,
  }) async {
    final company = row.read<String>('company_id');
    final id = row.read<String>('operation_id');
    final revision = row.readNullable<int>('revision');
    final body =
        jsonDecode(
              utf8.decode(
                await _payloadCipher.open(
                  scopeId: company,
                  recordId: 'operation:$id',
                  revision: revision ?? 0,
                  sealed: row.read<Uint8List>('body'),
                ),
              ),
            )
            as Map<String, dynamic>;
    final owners = await _operationOwners(
      company,
      id,
      personId: personId,
      budget: snapshotBudget,
    );
    return StoredOperation(
      retiredLocalCredential: body['retiredLocalCredential'] == true,
      personalOwners: owners.map((r) => r.read<String>('person_id')).toSet(),
      companyId: company,
      operationId: id,
      authorityGenerationId: body['authorityGenerationId'] as String,
      requestDigest: base64Decode(body['requestDigest'] as String),
      expectedRevision: body['expectedRevision'] as int?,
      revision: revision,
      result: body['result'] == null
          ? null
          : _fromJson(body['result'] as Map<String, dynamic>),
    );
  }

  Future<List<QueryRow>> _operationOwners(
    String companyId,
    String operationId, {
    String? personId,
    _SnapshotBudget? budget,
  }) async {
    final where =
        'company_id = ? AND operation_id = ? ${personId == null ? '' : 'AND person_id = ?'}';
    final variables = [
      _s(companyId),
      _s(operationId),
      if (personId != null) _s(personId),
    ];
    int? limit;
    if (budget != null) {
      // Count links and actual UTF-8 bytes inside SQLite before materializing
      // any owner IDs. Each exported link is one logical snapshot item.
      final totals = await _db
          .customSelect(
            'SELECT COUNT(*) AS n, COALESCE(SUM(length(CAST(person_id AS BLOB)) + 128), 0) AS size FROM personal_operations WHERE $where',
            variables: variables,
          )
          .getSingle();
      limit = totals.read<int>('n');
      budget.reserve(totals.read<int>('size'), limit);
    }
    return _db
        .customSelect(
          'SELECT person_id FROM personal_operations WHERE $where ORDER BY person_id ${limit == null ? '' : 'LIMIT ?'}',
          variables: [...variables, if (limit != null) _i(limit)],
        )
        .get();
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  void _checkReplay(
    StoredOperation existing,
    CommandContext context,
    Uint8List digest,
  ) {
    if (existing.retiredLocalCredential) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    if (existing.authorityGenerationId != context.authorityGenerationId ||
        !_sameBytes(existing.requestDigest, digest)) {
      throw const CheckException(CheckError.duplicateConflict);
    }
  }

  Future<void> _saveOperation(
    CommandContext context,
    Uint8List digest, {
    int? revision,
    StoredRecord? result,
    bool retiredLocalCredential = false,
  }) async {
    final body = await _payloadCipher.seal(
      scopeId: context.companyId,
      recordId: 'operation:${context.operationId}',
      revision: revision ?? 0,
      plain: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'retiredLocalCredential': retiredLocalCredential,
            'authorityGenerationId': context.authorityGenerationId,
            'requestDigest': base64Encode(digest),
            'expectedRevision': context.expectedRevision,
            'result': result == null ? null : _toJson(result),
          }),
        ),
      ),
    );
    await _db.customInsert(
      '''INSERT INTO operation_rows(company_id, operation_id, status, revision, body)
      VALUES(?, ?, ?, ?, ?) ON CONFLICT(company_id, operation_id) DO UPDATE SET
      status = excluded.status, revision = excluded.revision, body = excluded.body''',
      variables: [
        _s(context.companyId),
        _s(context.operationId),
        _s(revision == null ? 'pending' : 'committed'),
        Variable<int>(revision),
        _b(body),
      ],
    );
  }

  Future<void> _associateOperation(
    String company,
    String operation,
    Set<String> people,
  ) async {
    for (final person in people) {
      if (person.isEmpty) throw const CheckException(CheckError.malformed);
      await _db.customStatement(
        'INSERT OR IGNORE INTO personal_operations(person_id, company_id, operation_id) VALUES(?, ?, ?)',
        [person, company, operation],
      );
    }
  }

  @override
  Future<void> prepare(
    CommandContext context, {
    required Uint8List requestDigest,
    Set<String> personalOwners = const {},
  }) {
    final digest = Uint8List.fromList(requestDigest);
    final owners = Set<String>.of(personalOwners);
    return _exclusive(() async {
      try {
        _validateIntent(context, digest);
        await _db.transaction(() async {
          await _requireWritable(context.companyId);
          final existing = await _operation(
            context.companyId,
            context.operationId,
          );
          if (existing != null) {
            _checkReplay(existing, context, digest);
            // An idempotent prepare cannot broaden another person's intent.
            final rows = await _db
                .customSelect(
                  'SELECT person_id FROM personal_operations WHERE company_id = ? AND operation_id = ?',
                  variables: [_s(context.companyId), _s(context.operationId)],
                )
                .get();
            final saved = rows.map((r) => r.read<String>('person_id')).toSet();
            if (saved.length != owners.length || !saved.containsAll(owners)) {
              throw const CheckException(CheckError.duplicateConflict);
            }
            return;
          }
          await _ensureCompany(context.companyId);
          await _saveOperation(context, digest);
          await _associateOperation(
            context.companyId,
            context.operationId,
            owners,
          );
        });
      } on CheckException {
        rethrow;
      } catch (_) {
        throw const CheckException(CheckError.storageFailure);
      }
    });
  }

  @override
  Future<CommandResult<StoredRecord>> commit(
    CommandContext context, {
    required Uint8List requestDigest,
    required Future<Mutation> Function(ReadView) build,
    Future<void> Function(ReadView)? authorize,
    void Function()? beforeCommit,
  }) => _commit(
    context,
    requestDigest: requestDigest,
    build: build,
    authorize: authorize,
    beforeCommit: beforeCommit,
  );

  /// Recovery services must verify exact grant/target/root authorization inside
  /// authorize. This adapter boundary is intentionally absent from core/UI.
  Future<CommandResult<StoredRecord>> commitRecovery(
    CommandContext context, {
    required Uint8List requestDigest,
    required Future<Mutation> Function(ReadView) build,
    required Future<void> Function(ReadView) authorize,
    required void Function() beforeCommit,
    bool releasePassive = false,
  }) => _commit(
    context,
    requestDigest: requestDigest,
    build: build,
    authorize: authorize,
    beforeCommit: beforeCommit,
    recovery: true,
    releasePassive: releasePassive,
  );

  Future<CommandResult<StoredRecord>> _commit(
    CommandContext context, {
    required Uint8List requestDigest,
    required Future<Mutation> Function(ReadView) build,
    Future<void> Function(ReadView)? authorize,
    void Function()? beforeCommit,
    bool recovery = false,
    bool releasePassive = false,
  }) {
    final digest = Uint8List.fromList(requestDigest);
    return _exclusive(() async {
      try {
        _validateIntent(context, digest);
        return await _db.transaction<CommandResult<StoredRecord>>(() async {
          if (!recovery) await _requireWritable(context.companyId);
          final existing = await _operation(
            context.companyId,
            context.operationId,
          );
          if (authorize != null) {
            final authorizationView = _TransactionReadView(
              this,
              context.companyId,
            );
            try {
              await authorize(authorizationView);
            } finally {
              authorizationView.active = false;
            }
          }
          if (existing != null) {
            _checkReplay(existing, context, digest);
            if (existing.result != null) {
              beforeCommit?.call();
              return Committed(existing.result!, existing.revision!, true);
            }
          }
          final revision = await _revision(context.companyId);
          if (context.expectedRevision != null &&
              context.expectedRevision != revision) {
            return VersionConflict(revision);
          }
          await _ensureCompany(context.companyId);
          final view = _TransactionReadView(this, context.companyId);
          late final Mutation mutation;
          try {
            mutation = await build(view);
          } finally {
            view.active = false;
          }
          _validateRecord(mutation.result, context.companyId);
          final groups = {
            'entity': mutation.records,
            'event': mutation.events,
            'outbox': mutation.outbox,
            'authority': mutation.authorityHistory,
            'recovery': mutation.recovery,
          };
          final ids = <String>{};
          for (final group in groups.entries) {
            for (final record in group.value) {
              _validateRecord(record, context.companyId);
              if (!ids.add(record.id)) {
                throw const CheckException(CheckError.malformed);
              }
              await _saveRecord(record, group.key);
            }
          }
          for (final association in mutation.removePersonalRecords) {
            if (association.companyId != null &&
                association.companyId != context.companyId) {
              throw const CheckException(CheckError.wrongCompany);
            }
            if (association.personId.isEmpty || association.recordId.isEmpty) {
              throw const CheckException(CheckError.malformed);
            }
            await _db.customStatement(
              'DELETE FROM personal_records WHERE person_id = ? AND company_id = ? AND record_id = ?',
              [association.personId, context.companyId, association.recordId],
            );
          }
          for (final association in mutation.personalRecords) {
            if (association.companyId != null &&
                association.companyId != context.companyId) {
              throw const CheckException(CheckError.wrongCompany);
            }
            if (association.personId.isEmpty) {
              throw const CheckException(CheckError.malformed);
            }
            await _db.customStatement(
              'INSERT OR IGNORE INTO personal_records(person_id, company_id, record_id) VALUES(?, ?, ?)',
              [association.personId, context.companyId, association.recordId],
            );
          }
          for (final attachment in mutation.attachments) {
            if (attachment.companyId != context.companyId) {
              throw const CheckException(CheckError.wrongCompany);
            }
            if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(attachment.sha256) ||
                attachment.byteLength < 0 ||
                attachment.byteLength > 8 * 1024 * 1024) {
              throw const CheckException(CheckError.malformed);
            }
            final sealed = await _payloadCipher.seal(
              scopeId: context.companyId,
              recordId: 'manifest:${attachment.recordId}:${attachment.sha256}',
              revision: 1,
              plain: Uint8List.fromList(
                utf8.encode(jsonEncode({'byteLength': attachment.byteLength})),
              ),
            );
            // Immutable manifests: repeated links must agree on the byte length.
            final old = await _db
                .customSelect(
                  'SELECT * FROM attachment_rows WHERE company_id = ? AND record_id = ? AND sha256 = ?',
                  variables: [
                    _s(context.companyId),
                    _s(attachment.recordId),
                    _s(attachment.sha256),
                  ],
                )
                .getSingleOrNull();
            if (old != null) {
              final previous = await _decodeAttachment(old);
              if (previous.byteLength != attachment.byteLength) {
                throw const CheckException(CheckError.duplicateConflict);
              }
            } else {
              await _db.customInsert(
                'INSERT INTO attachment_rows(company_id, record_id, sha256, body) VALUES(?, ?, ?, ?)',
                variables: [
                  _s(context.companyId),
                  _s(attachment.recordId),
                  _s(attachment.sha256),
                  _b(sealed),
                ],
              );
            }
          }
          final next = revision + 1;
          await _saveOperation(
            context,
            digest,
            revision: next,
            result: mutation.result,
          );
          await _associateOperation(
            context.companyId,
            context.operationId,
            mutation.personalOperationOwners,
          );
          await _db.customInsert(
            'INSERT INTO revision_journal(company_id, revision, operation_id) VALUES(?, ?, ?)',
            variables: [
              _s(context.companyId),
              _i(next),
              _s(context.operationId),
            ],
          );
          await _db.customUpdate(
            'UPDATE company_scopes SET revision = ? WHERE company_id = ?',
            variables: [_i(next), _s(context.companyId)],
            updates: {_db.companyScopes},
          );
          if (releasePassive) {
            await _db.customStatement(
              'DELETE FROM passive_scopes WHERE company_id=?',
              [context.companyId],
            );
          }
          beforeCommit?.call();
          return Committed(mutation.result, next, false);
        });
      } on CheckException catch (error) {
        return Rejected(error.code);
      } catch (_) {
        return const Rejected(CheckError.storageFailure);
      }
    });
  }

  void _validateRecord(StoredRecord record, String company) {
    if (record.companyId != company) {
      throw const CheckException(CheckError.wrongCompany);
    }
    if (record.id.isEmpty ||
        record.kind.isEmpty ||
        record.revision < 1 ||
        record.payload.length > 8 * 1024 * 1024) {
      throw const CheckException(CheckError.malformed);
    }
  }

  Future<void> _saveRecord(StoredRecord record, String category) async {
    final old = await _db
        .customSelect(
          'SELECT * FROM stored_rows WHERE company_id = ? AND id = ?',
          variables: [_s(record.companyId), _s(record.id)],
        )
        .getSingleOrNull();
    if (old != null) {
      final previous = await _decodeRecord(old);
      if (old.read<String>('category') != category ||
          previous.kind != record.kind ||
          category == 'event' ||
          category == 'authority' ||
          record.revision <= previous.revision) {
        throw const CheckException(CheckError.duplicateConflict);
      }
    }
    final body = await _payloadCipher.seal(
      scopeId: record.companyId,
      recordId: 'record:${record.id}',
      revision: record.revision,
      plain: record.payload,
    );
    await _db.customInsert(
      '''INSERT INTO stored_rows(company_id, id, category, kind, revision, body)
      VALUES(?, ?, ?, ?, ?, ?) ON CONFLICT(company_id, id) DO UPDATE SET
      revision = excluded.revision, body = excluded.body''',
      variables: [
        _s(record.companyId),
        _s(record.id),
        _s(category),
        _s(record.kind),
        _i(record.revision),
        _b(body),
      ],
    );
  }

  Future<StoredRecord> _decodeRecord(QueryRow row) async {
    final company = row.read<String>('company_id');
    final id = row.read<String>('id');
    final revision = row.read<int>('revision');
    return StoredRecord(
      id,
      company,
      row.read<String>('kind'),
      revision,
      await _payloadCipher.open(
        scopeId: company,
        recordId: 'record:$id',
        revision: revision,
        sealed: row.read<Uint8List>('body'),
      ),
    );
  }

  Future<StoredRecord?> _read(String companyId, String recordId) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM stored_rows WHERE company_id = ? AND id = ?',
          variables: [_s(companyId), _s(recordId)],
        )
        .getSingleOrNull();
    return row == null ? null : _decodeRecord(row);
  }

  @override
  Future<StoredRecord?> read(String companyId, String recordId) =>
      _exclusive(() => _storage(() => _read(companyId, recordId)));
  @override
  Stream<int> watchRevision(String companyId) => _db
      .customSelect(
        'SELECT revision FROM company_scopes WHERE company_id = ?',
        variables: [_s(companyId)],
        readsFrom: {_db.companyScopes},
      )
      .watchSingleOrNull()
      .map((row) => row?.read<int>('revision') ?? 0)
      .distinct();
  @override
  Future<List<StoredOperation>> pendingOperations(
    String companyId, {
    String? personId,
  }) => _exclusive(
    () => _storage(() async {
      final rows = await _db
          .customSelect(
            '''SELECT o.* FROM operation_rows o WHERE o.company_id = ? AND o.status = 'pending'
      ${personId == null ? '' : 'AND EXISTS(SELECT 1 FROM personal_operations p WHERE p.company_id = o.company_id AND p.operation_id = o.operation_id AND p.person_id = ?)'}
      ORDER BY o.operation_id''',
            variables: [_s(companyId), if (personId != null) _s(personId)],
          )
          .get();
      return List.unmodifiable(
        await Future.wait(
          rows.map((row) => _decodeOperation(row, personId: personId)),
        ),
      );
    }),
  );
  Future<T> _storage<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }

  // Drift's native transaction() starts BEGIN IMMEDIATE. A snapshot is a
  // read-only WAL snapshot: hold this connection exclusively, without taking
  // the writer reservation that would block independent connections.
  Future<T> _readTransaction<T>(Future<T> Function() action) =>
      _db.exclusively(() async {
        await _db.customStatement('BEGIN DEFERRED');
        try {
          final result = await action();
          await _db.customStatement('COMMIT');
          return result;
        } catch (_) {
          await _db.customStatement('ROLLBACK');
          rethrow;
        }
      });

  Future<List<QueryRow>> _snapshotRows(
    String sql,
    List<Variable> variables,
    _SnapshotBudget budget,
  ) async {
    final totals = await _db
        .customSelect(
          'SELECT COUNT(*) AS n, COALESCE(SUM(length(body) + 256), 0) AS size FROM ($sql)',
          variables: variables,
        )
        .getSingle();
    budget.check(totals.read<int>('size'), totals.read<int>('n'));
    return _db.customSelect(sql, variables: variables).get();
  }

  @override
  Future<LogicalSnapshot> snapshot(
    ExportScope scope, {
    int maxBytes = 64 * 1024 * 1024,
    int maxEntries = 64 * 1024 * 1024 ~/ 128,
  }) => _exclusive(
    () => _storage(() async {
      if (maxBytes < 1 ||
          maxBytes > 64 * 1024 * 1024 ||
          maxEntries < 1 ||
          maxEntries > 64 * 1024 * 1024 ~/ 128) {
        throw const CheckException(CheckError.limitExceeded);
      }
      final budget = _SnapshotBudget(maxBytes, maxEntries);
      return _readTransaction(() async {
        final personal = scope is PersonalScope;
        final scopeId = switch (scope) {
          PersonalScope(:final personId) => personId,
          CompanyScope(:final companyId) => companyId,
        };
        if (scopeId.isEmpty) throw const CheckException(CheckError.malformed);
        final rows = await _snapshotRows(
          '''SELECT r.* FROM stored_rows r WHERE ${personal ? 'EXISTS(SELECT 1 FROM personal_records p WHERE p.company_id = r.company_id AND p.record_id = r.id AND p.person_id = ?)' : 'r.company_id = ?'} ORDER BY r.company_id, r.id LIMIT ?''',
          [_s(scopeId), _i(maxEntries + 1)],
          budget,
        );
        final groups = <String, List<StoredRecord>>{};
        for (final row in rows) {
          budget.add(row.read<Uint8List>('body').length + 256);
          final record = await _decodeRecord(row);
          (groups[row.read<String>('category')] ??= []).add(record);
        }
        final opRows = await _snapshotRows(
          '''SELECT o.* FROM operation_rows o WHERE ${personal ? 'EXISTS(SELECT 1 FROM personal_operations p WHERE p.company_id = o.company_id AND p.operation_id = o.operation_id AND p.person_id = ?)' : 'o.company_id = ?'} ORDER BY o.company_id, o.operation_id LIMIT ?''',
          [_s(scopeId), _i(maxEntries + 1)],
          budget,
        );
        final operations = <StoredOperation>[];
        for (final row in opRows) {
          budget.add(row.read<Uint8List>('body').length + 256);
          final operation = await _decodeOperation(
            row,
            personId: personal ? scopeId : null,
            snapshotBudget: budget,
          );
          if (personal && operation.result != null) {
            final result = operation.result!;
            final association = await _db
                .customSelect(
                  'SELECT 1 FROM personal_records WHERE person_id = ? AND company_id = ? AND record_id = ?',
                  variables: [_s(scopeId), _s(result.companyId), _s(result.id)],
                )
                .getSingleOrNull();
            if (association == null) continue;
          }
          operations.add(operation);
        }
        final journal = <RevisionEntry>[];
        final revisions = <String, int>{};
        // Personal journals follow safe operation IDs; do not expose unrelated
        // operations, authority generations or current employer-wide revisions.
        for (final operation in operations) {
          if (operation.revision != null) {
            final row = await _db
                .customSelect(
                  'SELECT * FROM revision_journal WHERE company_id = ? AND operation_id = ?',
                  variables: [
                    _s(operation.companyId),
                    _s(operation.operationId),
                  ],
                )
                .getSingleOrNull();
            if (row != null) {
              budget.add(128);
              final revision = row.read<int>('revision');
              journal.add(
                RevisionEntry(
                  operation.companyId,
                  revision,
                  operation.operationId,
                ),
              );
              if (revision > (revisions[operation.companyId] ?? 0)) {
                revisions[operation.companyId] = revision;
              }
            }
          }
        }
        if (!personal) revisions[scopeId] = await _revision(scopeId);
        journal.sort((a, b) {
          final company = a.companyId.compareTo(b.companyId);
          return company == 0 ? a.revision.compareTo(b.revision) : company;
        });
        final attachmentRows = await _snapshotRows(
          '''SELECT a.* FROM attachment_rows a WHERE ${personal ? 'EXISTS(SELECT 1 FROM personal_records p WHERE p.company_id = a.company_id AND p.record_id = a.record_id AND p.person_id = ?)' : 'a.company_id = ?'} ORDER BY a.company_id, a.record_id, a.sha256 LIMIT ?''',
          [_s(scopeId), _i(maxEntries + 1)],
          budget,
        );
        final attachments = <AttachmentManifestEntry>[];
        for (final row in attachmentRows) {
          budget.add(row.read<Uint8List>('body').length + 256);
          final entry = await _decodeAttachment(row);
          budget.addBytes(entry.byteLength);
          attachments.add(entry);
        }
        final associationRows = await _db
            .customSelect(
              'SELECT person_id, company_id, record_id FROM personal_records WHERE ${personal ? 'person_id' : 'company_id'} = ? ORDER BY company_id, record_id, person_id LIMIT ?',
              variables: [_s(scopeId), _i(maxEntries + 1)],
            )
            .get();
        final associations = <PersonalRecordAssociation>[];
        for (final row in associationRows) {
          budget.add(384);
          associations.add(
            PersonalRecordAssociation(
              row.read<String>('person_id'),
              row.read<String>('record_id'),
              companyId: row.read<String>('company_id'),
            ),
          );
        }
        return LogicalSnapshot(
          personalRecords: associations,
          scope: scope,
          revisions: revisions,
          records: groups['entity'] ?? [],
          events: groups['event'] ?? [],
          outbox: groups['outbox'] ?? [],
          authorityHistory: groups['authority'] ?? [],
          recovery: groups['recovery'] ?? [],
          operations: operations,
          journal: journal,
          attachments: attachments,
        );
      });
    }),
  );
  Future<AttachmentManifestEntry> _decodeAttachment(QueryRow row) async {
    final company = row.read<String>('company_id');
    final record = row.read<String>('record_id');
    final hash = row.read<String>('sha256');
    final body =
        jsonDecode(
              utf8.decode(
                await _payloadCipher.open(
                  scopeId: company,
                  recordId: 'manifest:$record:$hash',
                  revision: 1,
                  sealed: row.read<Uint8List>('body'),
                ),
              ),
            )
            as Map<String, dynamic>;
    return AttachmentManifestEntry(
      companyId: company,
      recordId: record,
      sha256: hash,
      byteLength: body['byteLength'] as int,
    );
  }

  static Map<String, dynamic> _toJson(StoredRecord row) => {
    'id': row.id,
    'companyId': row.companyId,
    'kind': row.kind,
    'revision': row.revision,
    'payload': base64Encode(row.payload),
  };
  static StoredRecord _fromJson(Map<String, dynamic> row) => StoredRecord(
    row['id'] as String,
    row['companyId'] as String,
    row['kind'] as String,
    row['revision'] as int,
    base64Decode(row['payload'] as String),
  );
  Future<List<StoredRecord>> listRecords(
    String companyId,
    String kind,
  ) => _exclusive(
    () => _storage(() async {
      final rows = await _db
          .customSelect(
            'SELECT * FROM stored_rows WHERE company_id = ? AND kind = ? ORDER BY id',
            variables: [_s(companyId), _s(kind)],
          )
          .get();
      return List.unmodifiable(await Future.wait(rows.map(_decodeRecord)));
    }),
  );

  /// Routing only; callers must resolve and authorize each company membership.
  Future<List<String>> listCompanyIds() => _exclusive(
    () => _storage(
      () async =>
          (await _db
                  .customSelect(
                    'SELECT company_id FROM company_scopes ORDER BY company_id',
                  )
                  .get())
              .map((r) => r.read<String>('company_id'))
              .toList(growable: false),
    ),
  );

  /// Allocates a random company exactly once before its encrypted vault exists.
  /// The intent digest is encrypted using the already provisioned personal vault.
  Future<CompanyCreationReservation> reserveCompanyCreation({
    required String personId,
    required String operationId,
    required Uint8List requestDigest,
    required IdGenerator ids,
  }) => _exclusive(
    () => _storage(() async {
      if (personId.isEmpty ||
          operationId.isEmpty ||
          requestDigest.length != 32) {
        throw const CheckException(CheckError.malformed);
      }
      return _db.transaction(() async {
        final old = await _db
            .customSelect(
              'SELECT company_id, authority_generation_id, body FROM company_creation_reservations WHERE person_id = ? AND operation_id = ?',
              variables: [_s(personId), _s(operationId)],
            )
            .getSingleOrNull();
        if (old != null) {
          final body =
              jsonDecode(
                    utf8.decode(
                      await _payloadCipher.open(
                        scopeId: personId,
                        recordId: 'company-reservation:$operationId',
                        revision: 1,
                        sealed: old.read<Uint8List>('body'),
                      ),
                    ),
                  )
                  as Map<String, dynamic>;
          if (body['companyId'] != old.read<String>('company_id') ||
              body['authorityGenerationId'] !=
                  old.read<String>('authority_generation_id')) {
            throw const CheckException(CheckError.invalidSignature);
          }
          final digest = base64Decode(body['requestDigest'] as String);
          if (!_sameBytes(digest, requestDigest)) {
            throw const CheckException(CheckError.duplicateConflict);
          }
          return CompanyCreationReservation(
            old.read<String>('company_id'),
            old.read<String>('authority_generation_id'),
          );
        }
        final companyId = ids.next();
        final generationId = ids.next();
        final body = await _payloadCipher.seal(
          scopeId: personId,
          recordId: 'company-reservation:$operationId',
          revision: 1,
          plain: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'companyId': companyId,
                'authorityGenerationId': generationId,
                'requestDigest': base64Encode(requestDigest),
              }),
            ),
          ),
        );
        await _db.customInsert(
          'INSERT INTO company_creation_reservations(person_id, operation_id, company_id, authority_generation_id, body) VALUES(?, ?, ?, ?, ?)',
          variables: [
            _s(personId),
            _s(operationId),
            _s(companyId),
            _s(generationId),
            _b(body),
          ],
        );
        return CompanyCreationReservation(companyId, generationId);
      });
    }),
  );

  Future<void> _requireWritable(String company) async {
    final lifecycle = await _read(company, 'authority-lifecycle');
    if (lifecycle != null &&
        (jsonDecode(utf8.decode(lifecycle.payload)) as Map)['state'] !=
            'active') {
      throw const CheckException(CheckError.recoveryRequired);
    }
    final conflicts = await _db
        .customSelect(
          "SELECT 1 FROM stored_rows WHERE company_id=? AND kind='authorityConflict' LIMIT 1",
          variables: [_s(company)],
        )
        .getSingleOrNull();
    if (conflicts != null) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    if (await _db
            .customSelect(
              'SELECT 1 FROM passive_scopes WHERE company_id=?',
              variables: [_s(company)],
            )
            .getSingleOrNull() !=
        null) {
      throw const CheckException(CheckError.recoveryRequired);
    }
  }

  Future<void> close() => _exclusive(_db.close);
}

final class _TransactionReadView implements ReadView {
  _TransactionReadView(this.repository, this.companyId);
  final LocalCheckRepository repository;
  final String companyId;
  bool active = true;
  void _requireActive() {
    if (!active) throw const CheckException(CheckError.invalidTransition);
  }

  @override
  Future<StoredRecord?> read(String id) {
    _requireActive();
    return repository._read(companyId, id);
  }

  @override
  Future<List<StoredRecord>> list(String kind) async {
    _requireActive();
    final rows = await repository._db
        .customSelect(
          'SELECT * FROM stored_rows WHERE company_id = ? AND kind = ? ORDER BY id',
          variables: [
            Variable.withString(companyId),
            Variable.withString(kind),
          ],
        )
        .get();
    return List.unmodifiable(
      await Future.wait(rows.map(repository._decodeRecord)),
    );
  }
}

final class _SnapshotBudget {
  _SnapshotBudget(this.maxBytes, this.maxEntries);
  final int maxBytes;
  final int maxEntries;
  int bytes = 0;
  int entries = 0;
  void check(int size, int count) {
    if (bytes + size > maxBytes || entries + count > maxEntries) {
      throw const CheckException(CheckError.limitExceeded);
    }
  }

  void reserve(int size, int count) {
    check(size, count);
    bytes += size;
    entries += count;
  }

  void addBytes(int size) => reserve(size, 0);
  void add(int size) => reserve(size, 1);
}

/// Random IDs reserved together once for a create-company intent.
final class CompanyCreationReservation {
  const CompanyCreationReservation(this.companyId, this.authorityGenerationId);
  final String companyId, authorityGenerationId;
}
