import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:raze_check_local/src/database/check_database.dart'
    show CheckDatabase;
import 'support/repository_fixture.dart';

void main() {
  late RepositoryFixture fixture;
  setUp(() async {
    fixture = await RepositoryFixture.open();
  });
  tearDown(() => fixture.dispose());

  test(
    'replays the original result without executing a retry builder',
    () async {
      expect(
        (await fixture.commitExample(operationId: 'op-1')).duplicate,
        isFalse,
      );
      final retry =
          await fixture.repo.commit(
                fixture.context('op-1'),
                requestDigest: fixture.digest(),
                build: (_) async => throw StateError('must not run'),
              )
              as Committed<StoredRecord>;
      expect(retry.duplicate, isTrue);
      expect(retry.value.id, 'record-1');
      expect(retry.revision, 1);
      expect(await fixture.count('example'), 1);
      expect(await fixture.count('receipt'), 1);
    },
  );

  test(
    'same operation with different normalized intent is a conflict',
    () async {
      await fixture.commitExample(operationId: 'op-1');
      final result = await fixture.commit(digestValue: 2);
      expect(
        result,
        isA<Rejected<StoredRecord>>().having(
          (r) => r.error,
          'error',
          CheckError.duplicateConflict,
        ),
      );
      expect(await fixture.count('example'), 1);
    },
  );

  test(
    'wrong-company lookups and transaction reads never return another company',
    () async {
      await fixture.commitExample(operationId: 'op-1');
      expect(await fixture.repo.read('company-b', 'record-1'), isNull);
      final result = await fixture.repo.commit(
        fixture.context('op-2', companyId: 'company-b'),
        requestDigest: fixture.digest(),
        build: (view) async {
          expect(await view.read('record-1'), isNull);
          expect(await view.list('example'), isEmpty);
          final row = fixture.record('record-b', companyId: 'company-b');
          return Mutation([row], [], [], row);
        },
      );
      expect(result, isA<Committed<StoredRecord>>());
    },
  );

  test(
    'a mutation cannot smuggle another company into any row or result',
    () async {
      final row = fixture.record('foreign', companyId: 'company-b');
      final result = await fixture.repo.commit(
        fixture.context('op-1'),
        requestDigest: fixture.digest(),
        build: (_) async => Mutation([row], [], [], row),
      );
      expect(
        result,
        isA<Rejected<StoredRecord>>().having(
          (r) => r.error,
          'error',
          CheckError.wrongCompany,
        ),
      );
      expect(await fixture.count('example'), 0);
    },
  );

  test(
    'crash and reopen retain records, exact result bytes, and replay identity',
    () async {
      await fixture.commitExample(operationId: 'op-1');
      await fixture.reopen();
      expect(
        utf8.decode(
          (await fixture.repo.read('company-a', 'record-1'))!.payload,
        ),
        'private employee name',
      );
      expect(
        (await fixture.commitExample(operationId: 'op-1')).duplicate,
        isTrue,
      );
      expect(await fixture.count('receipt'), 1);
    },
  );

  test(
    'storage failure rolls back records, operations, outbox and revisions',
    () async {
      final revisions = <int>[];
      final subscription = fixture.repo
          .watchRevision('company-a')
          .listen(revisions.add);
      await Future<void>.delayed(Duration.zero);
      await fixture.failBeforeCommit();
      final result = await fixture.commit();
      expect(
        result,
        isA<Rejected<StoredRecord>>().having(
          (r) => r.error,
          'error',
          CheckError.storageFailure,
        ),
      );
      expect(await fixture.count('example'), 0);
      expect(await fixture.count('receipt'), 0);
      final snapshot = await fixture.repo.snapshot(
        const CompanyScope('company-a'),
      );
      expect(snapshot.operations, isEmpty);
      expect(snapshot.journal, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(revisions.where((r) => r > 0), isEmpty);
      await subscription.cancel();
    },
  );

  test(
    'all logical bodies including the operation result are encrypted on disk',
    () async {
      await fixture.commit();
      final bytes = await fixture.diskBytes();
      expect(latin1.decode(bytes), isNot(contains('private employee name')));
      final rows = await fixture.database
          .customSelect('SELECT body FROM stored_rows')
          .get();
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(
          row.read<Uint8List>('body'),
          isNot(utf8.encode('private employee name')),
        );
      }
    },
  );

  test(
    'expected revision rejects stale edits while retries return saved result',
    () async {
      await fixture.commit(expectedRevision: 0);
      expect(
        await fixture.commit(
          operationId: 'op-2',
          id: 'record-2',
          expectedRevision: 0,
        ),
        isA<VersionConflict<StoredRecord>>().having(
          (r) => r.currentRevision,
          'revision',
          1,
        ),
      );
      expect(
        await fixture.commit(expectedRevision: 0),
        isA<Committed<StoredRecord>>().having(
          (r) => r.duplicate,
          'duplicate',
          true,
        ),
      );
    },
  );

  test('revision subscribers observe only readable committed data', () async {
    final next = fixture.repo
        .watchRevision('company-a')
        .firstWhere((r) => r == 1);
    await fixture.commit();
    expect(await next, 1);
    expect(await fixture.repo.read('company-a', 'record-1'), isNotNull);
  });

  test(
    'snapshot captures records operations journal and outbox at one revision',
    () async {
      await fixture.commit();
      final snapshot = await fixture.repo.snapshot(
        const CompanyScope('company-a'),
      );
      await fixture.commit(operationId: 'op-2', id: 'record-2');
      expect(snapshot.records.map((r) => r.id), ['record-1']);
      expect(snapshot.outbox.map((r) => r.id), ['outbox-record-1']);
      expect(snapshot.operations.single.operationId, 'op-1');
      expect(snapshot.journal.single.revision, 1);
      expect(snapshot.revisions['company-a'], 1);
      expect(
        () => snapshot.records.add(fixture.record('bad')),
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.records.single.payload[0] = 0,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'a queued operation survives reopen and can then commit exactly once',
    () async {
      await fixture.repo.prepare(
        fixture.context('queued-1'),
        requestDigest: fixture.digest(),
      );
      await fixture.reopen();
      expect(
        (await fixture.repo.pendingOperations('company-a')).single.operationId,
        'queued-1',
      );
      final committed = await fixture.commit(operationId: 'queued-1');
      expect(committed, isA<Committed<StoredRecord>>());
      expect(await fixture.repo.pendingOperations('company-a'), isEmpty);
      expect(
        (await fixture.commitExample(operationId: 'queued-1')).duplicate,
        isTrue,
      );
    },
  );

  test('concurrent retries cannot run the mutation twice', () async {
    var builds = 0;
    Future<CommandResult<StoredRecord>> run() => fixture.repo.commit(
      fixture.context('concurrent'),
      requestDigest: fixture.digest(),
      build: (_) async {
        builds++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final row = fixture.record('once');
        return Mutation([row], [], [], row);
      },
    );
    final results = await Future.wait([run(), run()]);
    expect(builds, 1);
    expect(
      results.whereType<Committed<StoredRecord>>().where((r) => r.duplicate),
      hasLength(1),
    );
  });
  test('immutable events reject replacement with different bytes', () async {
    final event = fixture.record('event-1', kind: 'attendance');
    await fixture.repo.commit(
      fixture.context('event-op'),
      requestDigest: fixture.digest(),
      build: (_) async => Mutation([], [event], [], event),
    );
    final changed = fixture.record(
      'event-1',
      kind: 'attendance',
      revision: 2,
      body: 'changed',
    );
    final result = await fixture.repo.commit(
      fixture.context('rewrite'),
      requestDigest: fixture.digest(),
      build: (_) async => Mutation([], [changed], [], changed),
    );
    expect(
      result,
      isA<Rejected<StoredRecord>>().having(
        (r) => r.error,
        'error',
        CheckError.duplicateConflict,
      ),
    );
    expect(
      utf8.decode((await fixture.repo.read('company-a', 'event-1'))!.payload),
      'private employee name',
    );
  });

  test(
    'personal snapshots export only explicit records and complete safe operations',
    () async {
      final own = fixture.record('own');
      final other = fixture.record('other');
      final event = fixture.record('own-event', kind: 'attendance');
      final outbox = fixture.record('own-outbox', kind: 'receipt');
      final authority = fixture.record('public-authority', kind: 'authority');
      await fixture.repo.commit(
        fixture.context('personal'),
        requestDigest: fixture.digest(),
        build: (_) async => Mutation(
          [own, other],
          [event],
          [outbox],
          own,
          authorityHistory: [authority],
          personalRecords: [
            const PersonalRecordAssociation('person-a', 'own'),
            const PersonalRecordAssociation('person-a', 'own-event'),
            const PersonalRecordAssociation('person-a', 'own-outbox'),
            const PersonalRecordAssociation('person-a', 'public-authority'),
          ],
          personalOperationOwners: {'person-a'},
        ),
      );
      await fixture.repo.prepare(
        fixture.context('private-queued'),
        requestDigest: fixture.digest(),
        personalOwners: {'person-b'},
      );
      final snapshot = await fixture.repo.snapshot(
        const PersonalScope('person-a'),
      );
      expect(snapshot.records.map((r) => r.id), ['own']);
      expect(snapshot.personalRecords.map((r) => r.recordId).toSet(), {
        'own',
        'own-event',
        'own-outbox',
        'public-authority',
      });
      expect(snapshot.personalRecords.map((r) => r.companyId).toSet(), {
        'company-a',
      });
      expect(snapshot.operations.single.personalOwners, {'person-a'});
      expect(snapshot.events.map((r) => r.id), ['own-event']);
      expect(snapshot.outbox.map((r) => r.id), ['own-outbox']);
      expect(snapshot.authorityHistory.map((r) => r.id), ['public-authority']);
      expect(snapshot.operations.map((o) => o.operationId), ['personal']);
      expect(snapshot.journal.map((j) => j.operationId), ['personal']);
      expect(
        await fixture.repo.pendingOperations('company-a', personId: 'person-a'),
        isEmpty,
      );
      expect(
        (await fixture.repo.snapshot(const PersonalScope('unknown'))).records,
        isEmpty,
      );
    },
  );

  test(
    'a personal operation result cannot escape its record association',
    () async {
      await fixture.repo.commit(
        fixture.context('unsafe'),
        requestDigest: fixture.digest(),
        build: (_) async {
          final row = fixture.record('secret');
          return Mutation(
            [row],
            [],
            [],
            row,
            personalOperationOwners: {'person-a'},
          );
        },
      );
      final snapshot = await fixture.repo.snapshot(
        const PersonalScope('person-a'),
      );
      expect(snapshot.records, isEmpty);
      expect(snapshot.operations, isEmpty);
      expect(snapshot.journal, isEmpty);
    },
  );

  test('bounded snapshot rejects oversized logical data', () async {
    await fixture.commit();
    await expectLater(
      fixture.repo.snapshot(const CompanyScope('company-a'), maxBytes: 8),
      throwsA(
        isA<CheckException>().having(
          (e) => e.code,
          'code',
          CheckError.limitExceeded,
        ),
      ),
    );
  });
  test(
    'snapshot attachment references stay stable and bytes are encrypted immutable content',
    () async {
      final store = ImmutableAttachmentStore(
        paths: fixture.paths,
        cipher: AesPayloadCipher(VaultKeys(fixture.keys)),
      );
      final bytes = Uint8List.fromList(utf8.encode('private attachment bytes'));
      final attachment = await store.put(
        companyId: 'company-a',
        recordId: 'record-1',
        plain: bytes,
      );
      final row = fixture.record('record-1');
      await fixture.repo.commit(
        fixture.context('with-file'),
        requestDigest: fixture.digest(),
        build: (_) async => Mutation(
          [row],
          [],
          [],
          row,
          attachments: [attachment],
          personalRecords: [
            const PersonalRecordAssociation('person-a', 'record-1'),
          ],
          personalOperationOwners: {'person-a'},
        ),
      );
      final snapshot = await fixture.repo.snapshot(
        const PersonalScope('person-a'),
      );
      await store.put(
        companyId: 'company-a',
        recordId: 'record-1',
        plain: Uint8List.fromList([9]),
      );
      expect(snapshot.attachments.single.sha256, attachment.sha256);
      expect(await store.read(snapshot.attachments.single), bytes);
      expect(
        (await fixture.repo.snapshot(
          const PersonalScope('person-b'),
        )).attachments,
        isEmpty,
      );
      expect(() => snapshot.attachments.clear(), throwsUnsupportedError);
      final files = await fixture.paths.root
          .list(recursive: true)
          .where((e) => e.path.endsWith('.enc'))
          .toList();
      expect(files, hasLength(2));
      for (final file in files) {
        expect(
          latin1.decode(await File(file.path).readAsBytes()),
          isNot(contains('private attachment bytes')),
        );
      }
    },
  );

  test(
    'prepared intent cannot be changed or exposed to another person after reopen',
    () async {
      await fixture.repo.prepare(
        fixture.context('queued'),
        requestDigest: fixture.digest(),
        personalOwners: {'person-a'},
      );
      await fixture.reopen();
      expect(
        await fixture.repo.pendingOperations('company-a', personId: 'person-b'),
        isEmpty,
      );
      expect(
        (await fixture.repo.pendingOperations(
          'company-a',
          personId: 'person-a',
        )).single.requestDigest,
        fixture.digest(),
      );
      await expectLater(
        fixture.repo.prepare(
          fixture.context('queued'),
          requestDigest: fixture.digest(2),
          personalOwners: {'person-a'},
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.duplicateConflict,
          ),
        ),
      );
      await expectLater(
        fixture.repo.prepare(
          fixture.context('queued'),
          requestDigest: fixture.digest(),
          personalOwners: {'person-b'},
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.duplicateConflict,
          ),
        ),
      );
    },
  );
  test(
    'an oversized snapshot is rejected before decrypting record bodies',
    () async {
      await fixture.commit();
      final cipher = CountingCipher(AesPayloadCipher(VaultKeys(fixture.keys)));
      final repo = LocalCheckRepository(
        database: fixture.database,
        cipher: cipher,
      );
      await expectLater(
        repo.snapshot(const CompanyScope('company-a'), maxBytes: 1),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.limitExceeded,
          ),
        ),
      );
      expect(cipher.opens, 0);
    },
  );
  test(
    'snapshot remains consistent while another database connection commits',
    () async {
      await fixture.commit();
      final cipher = PausingCipher(AesPayloadCipher(VaultKeys(fixture.keys)));
      final snapshots = LocalCheckRepository(
        database: fixture.database,
        cipher: cipher,
      );
      // Separate executors intentionally exercise independent connections.
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final other = LocalCheckRepository(
        database: CheckDatabase.open(fixture.paths),
        cipher: AesPayloadCipher(VaultKeys(fixture.keys)),
      );
      addTearDown(other.close);
      final pendingSnapshot = snapshots.snapshot(
        const CompanyScope('company-a'),
      );
      await cipher.started.future;
      try {
        final row = fixture.record('concurrent-row');
        final saved = await other.commit(
          fixture.context('concurrent-op'),
          requestDigest: fixture.digest(),
          build: (_) async => Mutation([row], [], [], row),
        );
        expect(saved, isA<Committed<StoredRecord>>());
      } finally {
        cipher.proceed.complete();
      }
      final snapshot = await pendingSnapshot;
      expect(snapshot.records.map((r) => r.id), ['record-1']);
      expect(snapshot.operations.map((o) => o.operationId), ['op-1']);
      expect(snapshot.journal.map((j) => j.revision), [1]);
      expect(snapshot.revisions, {'company-a': 1});
    },
  );
}

final class CountingCipher implements PayloadCipher {
  CountingCipher(this.delegate);
  final PayloadCipher delegate;
  int opens = 0;
  @override
  Future<Uint8List> open({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List sealed,
  }) {
    opens++;
    return delegate.open(
      scopeId: scopeId,
      recordId: recordId,
      revision: revision,
      sealed: sealed,
    );
  }

  @override
  Future<Uint8List> seal({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List plain,
  }) => delegate.seal(
    scopeId: scopeId,
    recordId: recordId,
    revision: revision,
    plain: plain,
  );
}

final class PausingCipher implements PayloadCipher {
  PausingCipher(this.delegate);
  final PayloadCipher delegate;
  final started = Completer<void>();
  final proceed = Completer<void>();
  @override
  Future<Uint8List> open({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List sealed,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await proceed.future;
    }
    return delegate.open(
      scopeId: scopeId,
      recordId: recordId,
      revision: revision,
      sealed: sealed,
    );
  }

  @override
  Future<Uint8List> seal({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List plain,
  }) => delegate.seal(
    scopeId: scopeId,
    recordId: recordId,
    revision: revision,
    plain: plain,
  );
}
