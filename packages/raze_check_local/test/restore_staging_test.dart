import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:raze_check_local/src/recovery/archive_records.dart';
import 'package:raze_check_local/src/recovery/restore_staging.dart';
import 'support/repository_fixture.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'passive restore preserves records and old operations, blocks every repository writer',
    () async {
      final source = await RepositoryFixture.open(),
          target = await RepositoryFixture.open();
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      await source.commit();
      final encoder = ArchiveRecords();
      await source.repo.visitArchive(
        const CompanyScope('company-a'),
        encoder.add,
      );
      final data = encoder.finish();
      expect(await target.repo.archiveConflicts(data), isEmpty);
      await target.repo.importArchive(
        data,
        archiveId: 'archive',
        beforeCommit: () {},
      );
      expect(
        (await target.repo.read('company-a', 'record-1'))!.payload,
        (await source.repo.read('company-a', 'record-1'))!.payload,
      );
      expect(
        await target.repo.importArchive(
          data,
          archiveId: 'archive',
          beforeCommit: () {},
        ),
        false,
      );
      final result = await target.commit(operationId: 'new', id: 'new');
      expect((result as Rejected).error, CheckError.recoveryRequired);
      await expectLater(
        target.repo.prepare(
          target.context('prepare'),
          requestDigest: Uint8List(32),
        ),
        throwsA(isA<CheckException>()),
      );
    },
  );
  test(
    'failure before database acceptance rolls back all imported rows and gates',
    () async {
      final source = await RepositoryFixture.open(),
          target = await RepositoryFixture.open();
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      await source.commit();
      final e = ArchiveRecords();
      await source.repo.visitArchive(const CompanyScope('company-a'), e.add);
      final data = e.finish();
      await expectLater(
        target.repo.importArchive(
          data,
          archiveId: 'archive',
          beforeCommit: () => throw StateError('fault'),
        ),
        throwsA(anything),
      );
      expect(await target.repo.read('company-a', 'record-1'), null);
      expect(await target.commit(), isA<Committed>());
      expect(await target.repo.archiveConflicts(data), isEmpty);
    },
  );
  test(
    'restore receipt binds recovery and attachment manifest, not only records',
    () async {
      final source = await RepositoryFixture.open(),
          target = await RepositoryFixture.open();
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      await source.commit();
      final encoder = ArchiveRecords();
      await source.repo.visitArchive(
        const CompanyScope('company-a'),
        encoder.add,
      );
      final data = encoder.finish();
      await target.repo.importArchive(
        data,
        archiveId: 'manifest-bound',
        contentHash: 'a' * 64,
        beforeCommit: () {},
      );
      await expectLater(
        target.repo.importArchive(
          data,
          archiveId: 'manifest-bound',
          contentHash: 'b' * 64,
          beforeCommit: () {},
        ),
        throwsA(isA<CheckException>()),
      );
      expect(
        await target.repo.hasRestoreCommit(
          'manifest-bound',
          contentHash: 'a' * 64,
        ),
        true,
      );
      expect(
        await target.repo.hasRestoreCommit(
          'manifest-bound',
          contentHash: 'b' * 64,
        ),
        false,
      );
    },
  );

  test(
    'staging identity collision preserves pre-existing secure key',
    () async {
      final fixture = await RepositoryFixture.open();
      addTearDown(fixture.dispose);
      const id = '12345678-1234-1234-1234-123456789abc';
      final old = Uint8List.fromList(List.filled(32, 42));
      await fixture.keys.write('vault:restore-$id', old);
      final staging = RestoreStaging(
        paths: fixture.paths,
        keys: fixture.keys,
        repository: fixture.repo,
      );
      await expectLater(
        staging.stage(id, {}, 'archive'),
        throwsA(isA<CheckException>()),
      );
      expect(await fixture.keys.read('vault:restore-$id'), old);
      expect(await fixture.repo.restoreJournals(), isEmpty);
    },
  );
}
