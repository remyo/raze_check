import 'package:drift/drift.dart';

class CompanyScopes extends Table {
  TextColumn get companyId => text()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {companyId};
}

/// Categories distinguish mutable entities/outbox/recovery from immutable
/// events/authority history. Logical bodies are always encrypted.
class StoredRows extends Table {
  TextColumn get companyId => text().references(CompanyScopes, #companyId)();
  TextColumn get id => text()();
  TextColumn get category => text()();
  TextColumn get kind => text()();
  IntColumn get revision => integer()();
  BlobColumn get body => blob()();
  @override
  Set<Column> get primaryKey => {companyId, id};
}

class OperationRows extends Table {
  TextColumn get companyId => text().references(CompanyScopes, #companyId)();
  TextColumn get operationId => text()();
  TextColumn get status => text()();
  IntColumn get revision => integer().nullable()();
  BlobColumn get body => blob()();
  @override
  Set<Column> get primaryKey => {companyId, operationId};
}

class RevisionJournal extends Table {
  TextColumn get companyId => text()();
  IntColumn get revision => integer()();
  TextColumn get operationId => text()();
  @override
  Set<Column> get primaryKey => {companyId, revision};
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (company_id, operation_id) REFERENCES operation_rows(company_id, operation_id)',
  ];
}

class PersonalRecords extends Table {
  TextColumn get personId => text()();
  TextColumn get companyId => text()();
  TextColumn get recordId => text()();
  @override
  Set<Column> get primaryKey => {personId, companyId, recordId};
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (company_id, record_id) REFERENCES stored_rows(company_id, id)',
  ];
}

class PersonalOperations extends Table {
  TextColumn get personId => text()();
  TextColumn get companyId => text()();
  TextColumn get operationId => text()();
  @override
  Set<Column> get primaryKey => {personId, companyId, operationId};
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (company_id, operation_id) REFERENCES operation_rows(company_id, operation_id)',
  ];
}

class AttachmentRows extends Table {
  TextColumn get companyId => text()();
  TextColumn get recordId => text()();
  TextColumn get sha256 => text()();
  BlobColumn get body => blob()();
  @override
  Set<Column> get primaryKey => {companyId, recordId, sha256};
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (company_id, record_id) REFERENCES stored_rows(company_id, id)',
  ];
}
