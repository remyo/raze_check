import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/src/recovery/archive_records.dart';
import 'support/repository_fixture.dart';
import 'package:raze_check_local/raze_check_local.dart';

void main() {
  test(
    'one read transaction excludes a concurrent committed revision from later pages',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final f = await RepositoryFixture.open();
      addTearDown(f.dispose);
      await f.commit();
      final second = await LocalCheckRepository.open(
        paths: f.paths,
        cipher: AesPayloadCipher(VaultKeys(f.keys)),
      );
      addTearDown(second.close);
      final e = ArchiveRecords();
      var wrote = false;
      await f.repo.visitArchive(const CompanyScope('company-a'), (
        kind,
        value,
      ) async {
        await e.add(kind, value);
        if (!wrote) {
          wrote = true;
          final row = f.record('later');
          expect(
            await second.commit(
              f.context('later'),
              requestDigest: f.digest(2),
              build: (_) async => Mutation([row], [], [], row),
            ),
            isA<Committed>(),
          );
        }
      });
      final ids = <String>{};
      var revision = -1;
      await ArchiveRecords.read(e.finish(), (kind, value) async {
        if (kind == 'record') ids.add((value as ArchiveRecord).record.id);
        if (kind == 'revision') revision = (value as ArchiveRevision).revision;
      });
      expect(ids, isNot(contains('later')));
      expect(revision, 1);
      expect(await f.repo.watchRevision('company-a').first, 2);
    },
  );
  test(
    'bounded traversal and indexed records preserve old result bytes and associations',
    () async {
      final f = await RepositoryFixture.open();
      addTearDown(f.dispose);
      final old = f.record('row', body: 'old'),
          newer = f.record('row', revision: 2, body: 'new');
      for (final (i, r) in [(1, old), (2, newer)]) {
        await f.repo.commit(
          f.context('op$i'),
          requestDigest: f.digest(i),
          build: (_) async => Mutation(
            [r],
            [],
            [],
            r,
            personalRecords: [const PersonalRecordAssociation('person', 'row')],
            personalOperationOwners: {'person'},
          ),
        );
      }
      final encoder = ArchiveRecords();
      await f.repo.visitArchive(const CompanyScope('company-a'), encoder.add);
      final bytes = encoder.finish();
      final seen = <String, List<Object>>{};
      await ArchiveRecords.read(bytes, (kind, value) async {
        (seen[kind] ??= []).add(value);
      });
      expect(
        utf8.decode((seen['record']!.single as ArchiveRecord).record.payload),
        'new',
      );
      expect(
        utf8.decode(
          (seen['operation']!.first as StoredOperation).result!.payload,
        ),
        'old',
      );
      expect(
        (seen['association']!.single as PersonalRecordAssociation).personId,
        'person',
      );
      expect(seen['journal']!.length, 2);
    },
  );
  test(
    'indexed format rejects invalid refs duplicate declarations and reference amplification',
    () async {
      for (final value in [
        '[[1]\n,["e",0,999]\n]',
        '[[1]\n,["s","x"]\n,["s","x"]\n]',
      ]) {
        await expectLater(
          ArchiveRecords.read(
            Uint8List.fromList(utf8.encode(value)),
            (_, _) async {},
          ),
          throwsA(isA<CheckException>()),
        );
      }
    },
  );
  test(
    'cancelled consistent traversal releases transaction and accepts next write',
    () async {
      final f = await RepositoryFixture.open();
      addTearDown(f.dispose);
      await f.commit();
      await expectLater(
        f.repo.visitArchive(
          const CompanyScope('company-a'),
          (_, _) async {},
          cancelled: () => true,
        ),
        throwsA(isA<CheckException>()),
      );
      expect(await f.commit(operationId: 'op2', id: 'row2'), isA<Committed>());
    },
  );
}
