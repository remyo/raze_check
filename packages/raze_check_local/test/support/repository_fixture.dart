import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:raze_check_local/src/database/check_database.dart';
import 'memory_key_store.dart';
import 'temp_paths.dart';

final class RepositorySession implements SessionHandle {}

/// Real file-backed SQLite, real AES, and only an in-memory secure-key adapter.
final class RepositoryFixture {
  RepositoryFixture._(this.paths, this.keys, this.interceptor);
  final QueryInterceptor? interceptor;
  final AppPaths paths;
  final MemoryKeyStore keys;
  late CheckDatabase database;
  late LocalCheckRepository repo;
  final session = RepositorySession();
  static Future<RepositoryFixture> open({QueryInterceptor? interceptor}) async {
    final fixture = RepositoryFixture._(
      await tempPaths(),
      MemoryKeyStore(),
      interceptor,
    );
    await VaultKeys(fixture.keys).create('company-a');
    await VaultKeys(fixture.keys).create('company-b');
    fixture._connect();
    return fixture;
  }

  void _connect() {
    database = interceptor == null
        ? CheckDatabase.open(paths)
        : CheckDatabase(
            NativeDatabase.createInBackground(
              paths.database,
            ).interceptWith(interceptor!),
          );
    repo = LocalCheckRepository(
      database: database,
      cipher: AesPayloadCipher(VaultKeys(keys)),
    );
  }

  CommandContext context(
    String operationId, {
    String companyId = 'company-a',
    int? expectedRevision,
  }) => CommandContext(
    companyId: companyId,
    session: session,
    operationId: operationId,
    authorityGenerationId: 'authority-1',
    expectedRevision: expectedRevision,
  );
  Uint8List digest([int value = 1]) =>
      Uint8List.fromList(List.filled(32, value));
  StoredRecord record(
    String id, {
    String companyId = 'company-a',
    String kind = 'example',
    int revision = 1,
    String body = 'private employee name',
  }) => StoredRecord(
    id,
    companyId,
    kind,
    revision,
    Uint8List.fromList(utf8.encode(body)),
  );

  Future<CommandResult<StoredRecord>> commit({
    String operationId = 'op-1',
    String id = 'record-1',
    int digestValue = 1,
    int? expectedRevision,
  }) => repo.commit(
    context(operationId, expectedRevision: expectedRevision),
    requestDigest: digest(digestValue),
    build: (_) async => Mutation(
      [record(id)],
      [],
      [record('outbox-$id', kind: 'receipt')],
      record(id),
    ),
  );
  Future<Committed<StoredRecord>> commitExample({
    required String operationId,
  }) async =>
      (await commit(operationId: operationId)) as Committed<StoredRecord>;

  Future<void> failBeforeCommit() => database.customStatement('''
    CREATE TEMP TRIGGER injected_failure BEFORE INSERT ON revision_journal
    BEGIN SELECT RAISE(ABORT, 'injected storage failure'); END
  ''');
  Future<void> reopen() async {
    await repo.close();
    _connect();
  }

  Future<int> count(String kind) async =>
      (await database
              .customSelect(
                'SELECT COUNT(*) AS n FROM stored_rows WHERE kind = ?',
                variables: [Variable.withString(kind)],
              )
              .getSingle())
          .read<int>('n');
  Future<List<int>> diskBytes() async {
    await database.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    return File('${paths.root.path}/checks.sqlite').readAsBytes();
  }

  Future<void> dispose() async {
    await repo.close();
    await paths.root.delete(recursive: true);
  }
}
