import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/repository_fixture.dart';

void main() {
  test(
    'schema-one reopen preserves committed data and foreign keys are enabled',
    () async {
      final fixture = await RepositoryFixture.open();
      addTearDown(fixture.dispose);
      await fixture.commit();
      await fixture.reopen();
      expect(await fixture.count('example'), 1);
      expect(
        (await fixture.database.customSelect('PRAGMA foreign_keys').getSingle())
            .read<int>('foreign_keys'),
        1,
      );
      expect(
        (await fixture.database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        1,
      );
      await expectLater(
        fixture.database.customStatement(
          "INSERT INTO revision_journal(company_id, revision, operation_id) VALUES('missing', 1, 'missing')",
        ),
        throwsA(anything),
      );
    },
  );

  test('unsupported newer schema fails without resetting user data', () async {
    final fixture = await RepositoryFixture.open();
    addTearDown(fixture.dispose);
    await fixture.commit();
    await fixture.database.customStatement('PRAGMA user_version = 2');
    await fixture.reopen();
    await expectLater(
      fixture.database.customSelect('SELECT COUNT(*) FROM stored_rows').get(),
      throwsA(anything),
    );
    await fixture.repo.close();
    final raw = NativeDatabase(fixture.paths.database);
    final rescue = InspectionDatabase(raw);
    expect(
      (await rescue
              .customSelect('SELECT COUNT(*) AS n FROM stored_rows')
              .getSingle())
          .read<int>('n'),
      2,
    );
    await rescue.close();
  });
}

final class InspectionDatabase extends GeneratedDatabase {
  InspectionDatabase(super.executor);
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [];
}
