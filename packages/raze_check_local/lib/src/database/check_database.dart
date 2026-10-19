import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../files/app_paths.dart';
import 'tables.dart';
part 'check_database.g.dart';

@DriftDatabase(
  tables: [
    CompanyScopes,
    StoredRows,
    OperationRows,
    RevisionJournal,
    PersonalRecords,
    PersonalOperations,
    AttachmentRows,
  ],
)
class CheckDatabase extends _$CheckDatabase {
  CheckDatabase(super.executor);
  CheckDatabase.open(AppPaths paths)
    : super(NativeDatabase.createInBackground(paths.database));
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        "CREATE INDEX stored_kind ON stored_rows(company_id, kind)",
      );
      await customStatement(
        "CREATE INDEX personal_record_scope ON personal_records(person_id, company_id)",
      );
      // History cannot be rewritten even by a future accidental SQL update.
      for (final action in ['UPDATE', 'DELETE']) {
        await customStatement(
          '''CREATE TRIGGER immutable_history_${action.toLowerCase()}
          BEFORE $action ON stored_rows WHEN OLD.category IN ('event', 'authority')
          BEGIN SELECT RAISE(ABORT, 'immutable history'); END''',
        );
      }
    },
    onUpgrade: (m, from, to) async {
      // Add explicit, transactional version steps here for future schemas.
      // Never drop/reset data to make an unknown schema appear usable.
      throw const CheckException(CheckError.unsupportedVersion);
    },
    beforeOpen: (details) async {
      if (details.versionBefore != null &&
          details.versionBefore! > schemaVersion) {
        throw const CheckException(CheckError.unsupportedVersion);
      }
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement('PRAGMA synchronous = FULL');
    },
  );
}
