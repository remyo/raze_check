// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'check_database.dart';

// ignore_for_file: type=lint
class $CompanyScopesTable extends CompanyScopes
    with TableInfo<$CompanyScopesTable, CompanyScope> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CompanyScopesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [companyId, revision];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'company_scopes';
  @override
  VerificationContext validateIntegrity(
    Insertable<CompanyScope> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {companyId};
  @override
  CompanyScope map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CompanyScope(
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $CompanyScopesTable createAlias(String alias) {
    return $CompanyScopesTable(attachedDatabase, alias);
  }
}

class CompanyScope extends DataClass implements Insertable<CompanyScope> {
  final String companyId;
  final int revision;
  const CompanyScope({required this.companyId, required this.revision});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['company_id'] = Variable<String>(companyId);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  CompanyScopesCompanion toCompanion(bool nullToAbsent) {
    return CompanyScopesCompanion(
      companyId: Value(companyId),
      revision: Value(revision),
    );
  }

  factory CompanyScope.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CompanyScope(
      companyId: serializer.fromJson<String>(json['companyId']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'companyId': serializer.toJson<String>(companyId),
      'revision': serializer.toJson<int>(revision),
    };
  }

  CompanyScope copyWith({String? companyId, int? revision}) => CompanyScope(
    companyId: companyId ?? this.companyId,
    revision: revision ?? this.revision,
  );
  CompanyScope copyWithCompanion(CompanyScopesCompanion data) {
    return CompanyScope(
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CompanyScope(')
          ..write('companyId: $companyId, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(companyId, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CompanyScope &&
          other.companyId == this.companyId &&
          other.revision == this.revision);
}

class CompanyScopesCompanion extends UpdateCompanion<CompanyScope> {
  final Value<String> companyId;
  final Value<int> revision;
  final Value<int> rowid;
  const CompanyScopesCompanion({
    this.companyId = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CompanyScopesCompanion.insert({
    required String companyId,
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId);
  static Insertable<CompanyScope> custom({
    Expression<String>? companyId,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (companyId != null) 'company_id': companyId,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CompanyScopesCompanion copyWith({
    Value<String>? companyId,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return CompanyScopesCompanion(
      companyId: companyId ?? this.companyId,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CompanyScopesCompanion(')
          ..write('companyId: $companyId, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredRowsTable extends StoredRows
    with TableInfo<$StoredRowsTable, StoredRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES company_scopes (company_id)',
    ),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<Uint8List> body = GeneratedColumn<Uint8List>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    companyId,
    id,
    category,
    kind,
    revision,
    body,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {companyId, id};
  @override
  StoredRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredRow(
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  $StoredRowsTable createAlias(String alias) {
    return $StoredRowsTable(attachedDatabase, alias);
  }
}

class StoredRow extends DataClass implements Insertable<StoredRow> {
  final String companyId;
  final String id;
  final String category;
  final String kind;
  final int revision;
  final Uint8List body;
  const StoredRow({
    required this.companyId,
    required this.id,
    required this.category,
    required this.kind,
    required this.revision,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['company_id'] = Variable<String>(companyId);
    map['id'] = Variable<String>(id);
    map['category'] = Variable<String>(category);
    map['kind'] = Variable<String>(kind);
    map['revision'] = Variable<int>(revision);
    map['body'] = Variable<Uint8List>(body);
    return map;
  }

  StoredRowsCompanion toCompanion(bool nullToAbsent) {
    return StoredRowsCompanion(
      companyId: Value(companyId),
      id: Value(id),
      category: Value(category),
      kind: Value(kind),
      revision: Value(revision),
      body: Value(body),
    );
  }

  factory StoredRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredRow(
      companyId: serializer.fromJson<String>(json['companyId']),
      id: serializer.fromJson<String>(json['id']),
      category: serializer.fromJson<String>(json['category']),
      kind: serializer.fromJson<String>(json['kind']),
      revision: serializer.fromJson<int>(json['revision']),
      body: serializer.fromJson<Uint8List>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'companyId': serializer.toJson<String>(companyId),
      'id': serializer.toJson<String>(id),
      'category': serializer.toJson<String>(category),
      'kind': serializer.toJson<String>(kind),
      'revision': serializer.toJson<int>(revision),
      'body': serializer.toJson<Uint8List>(body),
    };
  }

  StoredRow copyWith({
    String? companyId,
    String? id,
    String? category,
    String? kind,
    int? revision,
    Uint8List? body,
  }) => StoredRow(
    companyId: companyId ?? this.companyId,
    id: id ?? this.id,
    category: category ?? this.category,
    kind: kind ?? this.kind,
    revision: revision ?? this.revision,
    body: body ?? this.body,
  );
  StoredRow copyWithCompanion(StoredRowsCompanion data) {
    return StoredRow(
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      id: data.id.present ? data.id.value : this.id,
      category: data.category.present ? data.category.value : this.category,
      kind: data.kind.present ? data.kind.value : this.kind,
      revision: data.revision.present ? data.revision.value : this.revision,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredRow(')
          ..write('companyId: $companyId, ')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('kind: $kind, ')
          ..write('revision: $revision, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    companyId,
    id,
    category,
    kind,
    revision,
    $driftBlobEquality.hash(body),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredRow &&
          other.companyId == this.companyId &&
          other.id == this.id &&
          other.category == this.category &&
          other.kind == this.kind &&
          other.revision == this.revision &&
          $driftBlobEquality.equals(other.body, this.body));
}

class StoredRowsCompanion extends UpdateCompanion<StoredRow> {
  final Value<String> companyId;
  final Value<String> id;
  final Value<String> category;
  final Value<String> kind;
  final Value<int> revision;
  final Value<Uint8List> body;
  final Value<int> rowid;
  const StoredRowsCompanion({
    this.companyId = const Value.absent(),
    this.id = const Value.absent(),
    this.category = const Value.absent(),
    this.kind = const Value.absent(),
    this.revision = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredRowsCompanion.insert({
    required String companyId,
    required String id,
    required String category,
    required String kind,
    required int revision,
    required Uint8List body,
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       id = Value(id),
       category = Value(category),
       kind = Value(kind),
       revision = Value(revision),
       body = Value(body);
  static Insertable<StoredRow> custom({
    Expression<String>? companyId,
    Expression<String>? id,
    Expression<String>? category,
    Expression<String>? kind,
    Expression<int>? revision,
    Expression<Uint8List>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (companyId != null) 'company_id': companyId,
      if (id != null) 'id': id,
      if (category != null) 'category': category,
      if (kind != null) 'kind': kind,
      if (revision != null) 'revision': revision,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredRowsCompanion copyWith({
    Value<String>? companyId,
    Value<String>? id,
    Value<String>? category,
    Value<String>? kind,
    Value<int>? revision,
    Value<Uint8List>? body,
    Value<int>? rowid,
  }) {
    return StoredRowsCompanion(
      companyId: companyId ?? this.companyId,
      id: id ?? this.id,
      category: category ?? this.category,
      kind: kind ?? this.kind,
      revision: revision ?? this.revision,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (body.present) {
      map['body'] = Variable<Uint8List>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredRowsCompanion(')
          ..write('companyId: $companyId, ')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('kind: $kind, ')
          ..write('revision: $revision, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OperationRowsTable extends OperationRows
    with TableInfo<$OperationRowsTable, OperationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OperationRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES company_scopes (company_id)',
    ),
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<Uint8List> body = GeneratedColumn<Uint8List>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    companyId,
    operationId,
    status,
    revision,
    body,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'operation_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<OperationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {companyId, operationId};
  @override
  OperationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OperationRow(
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  $OperationRowsTable createAlias(String alias) {
    return $OperationRowsTable(attachedDatabase, alias);
  }
}

class OperationRow extends DataClass implements Insertable<OperationRow> {
  final String companyId;
  final String operationId;
  final String status;
  final int? revision;
  final Uint8List body;
  const OperationRow({
    required this.companyId,
    required this.operationId,
    required this.status,
    this.revision,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['company_id'] = Variable<String>(companyId);
    map['operation_id'] = Variable<String>(operationId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    map['body'] = Variable<Uint8List>(body);
    return map;
  }

  OperationRowsCompanion toCompanion(bool nullToAbsent) {
    return OperationRowsCompanion(
      companyId: Value(companyId),
      operationId: Value(operationId),
      status: Value(status),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      body: Value(body),
    );
  }

  factory OperationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OperationRow(
      companyId: serializer.fromJson<String>(json['companyId']),
      operationId: serializer.fromJson<String>(json['operationId']),
      status: serializer.fromJson<String>(json['status']),
      revision: serializer.fromJson<int?>(json['revision']),
      body: serializer.fromJson<Uint8List>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'companyId': serializer.toJson<String>(companyId),
      'operationId': serializer.toJson<String>(operationId),
      'status': serializer.toJson<String>(status),
      'revision': serializer.toJson<int?>(revision),
      'body': serializer.toJson<Uint8List>(body),
    };
  }

  OperationRow copyWith({
    String? companyId,
    String? operationId,
    String? status,
    Value<int?> revision = const Value.absent(),
    Uint8List? body,
  }) => OperationRow(
    companyId: companyId ?? this.companyId,
    operationId: operationId ?? this.operationId,
    status: status ?? this.status,
    revision: revision.present ? revision.value : this.revision,
    body: body ?? this.body,
  );
  OperationRow copyWithCompanion(OperationRowsCompanion data) {
    return OperationRow(
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      status: data.status.present ? data.status.value : this.status,
      revision: data.revision.present ? data.revision.value : this.revision,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OperationRow(')
          ..write('companyId: $companyId, ')
          ..write('operationId: $operationId, ')
          ..write('status: $status, ')
          ..write('revision: $revision, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    companyId,
    operationId,
    status,
    revision,
    $driftBlobEquality.hash(body),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OperationRow &&
          other.companyId == this.companyId &&
          other.operationId == this.operationId &&
          other.status == this.status &&
          other.revision == this.revision &&
          $driftBlobEquality.equals(other.body, this.body));
}

class OperationRowsCompanion extends UpdateCompanion<OperationRow> {
  final Value<String> companyId;
  final Value<String> operationId;
  final Value<String> status;
  final Value<int?> revision;
  final Value<Uint8List> body;
  final Value<int> rowid;
  const OperationRowsCompanion({
    this.companyId = const Value.absent(),
    this.operationId = const Value.absent(),
    this.status = const Value.absent(),
    this.revision = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OperationRowsCompanion.insert({
    required String companyId,
    required String operationId,
    required String status,
    this.revision = const Value.absent(),
    required Uint8List body,
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       operationId = Value(operationId),
       status = Value(status),
       body = Value(body);
  static Insertable<OperationRow> custom({
    Expression<String>? companyId,
    Expression<String>? operationId,
    Expression<String>? status,
    Expression<int>? revision,
    Expression<Uint8List>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (companyId != null) 'company_id': companyId,
      if (operationId != null) 'operation_id': operationId,
      if (status != null) 'status': status,
      if (revision != null) 'revision': revision,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OperationRowsCompanion copyWith({
    Value<String>? companyId,
    Value<String>? operationId,
    Value<String>? status,
    Value<int?>? revision,
    Value<Uint8List>? body,
    Value<int>? rowid,
  }) {
    return OperationRowsCompanion(
      companyId: companyId ?? this.companyId,
      operationId: operationId ?? this.operationId,
      status: status ?? this.status,
      revision: revision ?? this.revision,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (body.present) {
      map['body'] = Variable<Uint8List>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OperationRowsCompanion(')
          ..write('companyId: $companyId, ')
          ..write('operationId: $operationId, ')
          ..write('status: $status, ')
          ..write('revision: $revision, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RevisionJournalTable extends RevisionJournal
    with TableInfo<$RevisionJournalTable, RevisionJournalData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevisionJournalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [companyId, revision, operationId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revision_journal';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevisionJournalData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {companyId, revision};
  @override
  RevisionJournalData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevisionJournalData(
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
    );
  }

  @override
  $RevisionJournalTable createAlias(String alias) {
    return $RevisionJournalTable(attachedDatabase, alias);
  }
}

class RevisionJournalData extends DataClass
    implements Insertable<RevisionJournalData> {
  final String companyId;
  final int revision;
  final String operationId;
  const RevisionJournalData({
    required this.companyId,
    required this.revision,
    required this.operationId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['company_id'] = Variable<String>(companyId);
    map['revision'] = Variable<int>(revision);
    map['operation_id'] = Variable<String>(operationId);
    return map;
  }

  RevisionJournalCompanion toCompanion(bool nullToAbsent) {
    return RevisionJournalCompanion(
      companyId: Value(companyId),
      revision: Value(revision),
      operationId: Value(operationId),
    );
  }

  factory RevisionJournalData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevisionJournalData(
      companyId: serializer.fromJson<String>(json['companyId']),
      revision: serializer.fromJson<int>(json['revision']),
      operationId: serializer.fromJson<String>(json['operationId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'companyId': serializer.toJson<String>(companyId),
      'revision': serializer.toJson<int>(revision),
      'operationId': serializer.toJson<String>(operationId),
    };
  }

  RevisionJournalData copyWith({
    String? companyId,
    int? revision,
    String? operationId,
  }) => RevisionJournalData(
    companyId: companyId ?? this.companyId,
    revision: revision ?? this.revision,
    operationId: operationId ?? this.operationId,
  );
  RevisionJournalData copyWithCompanion(RevisionJournalCompanion data) {
    return RevisionJournalData(
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      revision: data.revision.present ? data.revision.value : this.revision,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevisionJournalData(')
          ..write('companyId: $companyId, ')
          ..write('revision: $revision, ')
          ..write('operationId: $operationId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(companyId, revision, operationId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionJournalData &&
          other.companyId == this.companyId &&
          other.revision == this.revision &&
          other.operationId == this.operationId);
}

class RevisionJournalCompanion extends UpdateCompanion<RevisionJournalData> {
  final Value<String> companyId;
  final Value<int> revision;
  final Value<String> operationId;
  final Value<int> rowid;
  const RevisionJournalCompanion({
    this.companyId = const Value.absent(),
    this.revision = const Value.absent(),
    this.operationId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevisionJournalCompanion.insert({
    required String companyId,
    required int revision,
    required String operationId,
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       revision = Value(revision),
       operationId = Value(operationId);
  static Insertable<RevisionJournalData> custom({
    Expression<String>? companyId,
    Expression<int>? revision,
    Expression<String>? operationId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (companyId != null) 'company_id': companyId,
      if (revision != null) 'revision': revision,
      if (operationId != null) 'operation_id': operationId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevisionJournalCompanion copyWith({
    Value<String>? companyId,
    Value<int>? revision,
    Value<String>? operationId,
    Value<int>? rowid,
  }) {
    return RevisionJournalCompanion(
      companyId: companyId ?? this.companyId,
      revision: revision ?? this.revision,
      operationId: operationId ?? this.operationId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevisionJournalCompanion(')
          ..write('companyId: $companyId, ')
          ..write('revision: $revision, ')
          ..write('operationId: $operationId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PersonalRecordsTable extends PersonalRecords
    with TableInfo<$PersonalRecordsTable, PersonalRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonalRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<String> personId = GeneratedColumn<String>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [personId, companyId, recordId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'personal_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonalRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {personId, companyId, recordId};
  @override
  PersonalRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonalRecord(
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
    );
  }

  @override
  $PersonalRecordsTable createAlias(String alias) {
    return $PersonalRecordsTable(attachedDatabase, alias);
  }
}

class PersonalRecord extends DataClass implements Insertable<PersonalRecord> {
  final String personId;
  final String companyId;
  final String recordId;
  const PersonalRecord({
    required this.personId,
    required this.companyId,
    required this.recordId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['person_id'] = Variable<String>(personId);
    map['company_id'] = Variable<String>(companyId);
    map['record_id'] = Variable<String>(recordId);
    return map;
  }

  PersonalRecordsCompanion toCompanion(bool nullToAbsent) {
    return PersonalRecordsCompanion(
      personId: Value(personId),
      companyId: Value(companyId),
      recordId: Value(recordId),
    );
  }

  factory PersonalRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonalRecord(
      personId: serializer.fromJson<String>(json['personId']),
      companyId: serializer.fromJson<String>(json['companyId']),
      recordId: serializer.fromJson<String>(json['recordId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'personId': serializer.toJson<String>(personId),
      'companyId': serializer.toJson<String>(companyId),
      'recordId': serializer.toJson<String>(recordId),
    };
  }

  PersonalRecord copyWith({
    String? personId,
    String? companyId,
    String? recordId,
  }) => PersonalRecord(
    personId: personId ?? this.personId,
    companyId: companyId ?? this.companyId,
    recordId: recordId ?? this.recordId,
  );
  PersonalRecord copyWithCompanion(PersonalRecordsCompanion data) {
    return PersonalRecord(
      personId: data.personId.present ? data.personId.value : this.personId,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonalRecord(')
          ..write('personId: $personId, ')
          ..write('companyId: $companyId, ')
          ..write('recordId: $recordId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(personId, companyId, recordId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonalRecord &&
          other.personId == this.personId &&
          other.companyId == this.companyId &&
          other.recordId == this.recordId);
}

class PersonalRecordsCompanion extends UpdateCompanion<PersonalRecord> {
  final Value<String> personId;
  final Value<String> companyId;
  final Value<String> recordId;
  final Value<int> rowid;
  const PersonalRecordsCompanion({
    this.personId = const Value.absent(),
    this.companyId = const Value.absent(),
    this.recordId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PersonalRecordsCompanion.insert({
    required String personId,
    required String companyId,
    required String recordId,
    this.rowid = const Value.absent(),
  }) : personId = Value(personId),
       companyId = Value(companyId),
       recordId = Value(recordId);
  static Insertable<PersonalRecord> custom({
    Expression<String>? personId,
    Expression<String>? companyId,
    Expression<String>? recordId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (personId != null) 'person_id': personId,
      if (companyId != null) 'company_id': companyId,
      if (recordId != null) 'record_id': recordId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PersonalRecordsCompanion copyWith({
    Value<String>? personId,
    Value<String>? companyId,
    Value<String>? recordId,
    Value<int>? rowid,
  }) {
    return PersonalRecordsCompanion(
      personId: personId ?? this.personId,
      companyId: companyId ?? this.companyId,
      recordId: recordId ?? this.recordId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (personId.present) {
      map['person_id'] = Variable<String>(personId.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonalRecordsCompanion(')
          ..write('personId: $personId, ')
          ..write('companyId: $companyId, ')
          ..write('recordId: $recordId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PersonalOperationsTable extends PersonalOperations
    with TableInfo<$PersonalOperationsTable, PersonalOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonalOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<String> personId = GeneratedColumn<String>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [personId, companyId, operationId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'personal_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonalOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {personId, companyId, operationId};
  @override
  PersonalOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonalOperation(
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
    );
  }

  @override
  $PersonalOperationsTable createAlias(String alias) {
    return $PersonalOperationsTable(attachedDatabase, alias);
  }
}

class PersonalOperation extends DataClass
    implements Insertable<PersonalOperation> {
  final String personId;
  final String companyId;
  final String operationId;
  const PersonalOperation({
    required this.personId,
    required this.companyId,
    required this.operationId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['person_id'] = Variable<String>(personId);
    map['company_id'] = Variable<String>(companyId);
    map['operation_id'] = Variable<String>(operationId);
    return map;
  }

  PersonalOperationsCompanion toCompanion(bool nullToAbsent) {
    return PersonalOperationsCompanion(
      personId: Value(personId),
      companyId: Value(companyId),
      operationId: Value(operationId),
    );
  }

  factory PersonalOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonalOperation(
      personId: serializer.fromJson<String>(json['personId']),
      companyId: serializer.fromJson<String>(json['companyId']),
      operationId: serializer.fromJson<String>(json['operationId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'personId': serializer.toJson<String>(personId),
      'companyId': serializer.toJson<String>(companyId),
      'operationId': serializer.toJson<String>(operationId),
    };
  }

  PersonalOperation copyWith({
    String? personId,
    String? companyId,
    String? operationId,
  }) => PersonalOperation(
    personId: personId ?? this.personId,
    companyId: companyId ?? this.companyId,
    operationId: operationId ?? this.operationId,
  );
  PersonalOperation copyWithCompanion(PersonalOperationsCompanion data) {
    return PersonalOperation(
      personId: data.personId.present ? data.personId.value : this.personId,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonalOperation(')
          ..write('personId: $personId, ')
          ..write('companyId: $companyId, ')
          ..write('operationId: $operationId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(personId, companyId, operationId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonalOperation &&
          other.personId == this.personId &&
          other.companyId == this.companyId &&
          other.operationId == this.operationId);
}

class PersonalOperationsCompanion extends UpdateCompanion<PersonalOperation> {
  final Value<String> personId;
  final Value<String> companyId;
  final Value<String> operationId;
  final Value<int> rowid;
  const PersonalOperationsCompanion({
    this.personId = const Value.absent(),
    this.companyId = const Value.absent(),
    this.operationId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PersonalOperationsCompanion.insert({
    required String personId,
    required String companyId,
    required String operationId,
    this.rowid = const Value.absent(),
  }) : personId = Value(personId),
       companyId = Value(companyId),
       operationId = Value(operationId);
  static Insertable<PersonalOperation> custom({
    Expression<String>? personId,
    Expression<String>? companyId,
    Expression<String>? operationId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (personId != null) 'person_id': personId,
      if (companyId != null) 'company_id': companyId,
      if (operationId != null) 'operation_id': operationId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PersonalOperationsCompanion copyWith({
    Value<String>? personId,
    Value<String>? companyId,
    Value<String>? operationId,
    Value<int>? rowid,
  }) {
    return PersonalOperationsCompanion(
      personId: personId ?? this.personId,
      companyId: companyId ?? this.companyId,
      operationId: operationId ?? this.operationId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (personId.present) {
      map['person_id'] = Variable<String>(personId.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonalOperationsCompanion(')
          ..write('personId: $personId, ')
          ..write('companyId: $companyId, ')
          ..write('operationId: $operationId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentRowsTable extends AttachmentRows
    with TableInfo<$AttachmentRowsTable, AttachmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<Uint8List> body = GeneratedColumn<Uint8List>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [companyId, recordId, sha256, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachment_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttachmentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {companyId, recordId, sha256};
  @override
  AttachmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttachmentRow(
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  $AttachmentRowsTable createAlias(String alias) {
    return $AttachmentRowsTable(attachedDatabase, alias);
  }
}

class AttachmentRow extends DataClass implements Insertable<AttachmentRow> {
  final String companyId;
  final String recordId;
  final String sha256;
  final Uint8List body;
  const AttachmentRow({
    required this.companyId,
    required this.recordId,
    required this.sha256,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['company_id'] = Variable<String>(companyId);
    map['record_id'] = Variable<String>(recordId);
    map['sha256'] = Variable<String>(sha256);
    map['body'] = Variable<Uint8List>(body);
    return map;
  }

  AttachmentRowsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentRowsCompanion(
      companyId: Value(companyId),
      recordId: Value(recordId),
      sha256: Value(sha256),
      body: Value(body),
    );
  }

  factory AttachmentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttachmentRow(
      companyId: serializer.fromJson<String>(json['companyId']),
      recordId: serializer.fromJson<String>(json['recordId']),
      sha256: serializer.fromJson<String>(json['sha256']),
      body: serializer.fromJson<Uint8List>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'companyId': serializer.toJson<String>(companyId),
      'recordId': serializer.toJson<String>(recordId),
      'sha256': serializer.toJson<String>(sha256),
      'body': serializer.toJson<Uint8List>(body),
    };
  }

  AttachmentRow copyWith({
    String? companyId,
    String? recordId,
    String? sha256,
    Uint8List? body,
  }) => AttachmentRow(
    companyId: companyId ?? this.companyId,
    recordId: recordId ?? this.recordId,
    sha256: sha256 ?? this.sha256,
    body: body ?? this.body,
  );
  AttachmentRow copyWithCompanion(AttachmentRowsCompanion data) {
    return AttachmentRow(
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentRow(')
          ..write('companyId: $companyId, ')
          ..write('recordId: $recordId, ')
          ..write('sha256: $sha256, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(companyId, recordId, sha256, $driftBlobEquality.hash(body));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttachmentRow &&
          other.companyId == this.companyId &&
          other.recordId == this.recordId &&
          other.sha256 == this.sha256 &&
          $driftBlobEquality.equals(other.body, this.body));
}

class AttachmentRowsCompanion extends UpdateCompanion<AttachmentRow> {
  final Value<String> companyId;
  final Value<String> recordId;
  final Value<String> sha256;
  final Value<Uint8List> body;
  final Value<int> rowid;
  const AttachmentRowsCompanion({
    this.companyId = const Value.absent(),
    this.recordId = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentRowsCompanion.insert({
    required String companyId,
    required String recordId,
    required String sha256,
    required Uint8List body,
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       recordId = Value(recordId),
       sha256 = Value(sha256),
       body = Value(body);
  static Insertable<AttachmentRow> custom({
    Expression<String>? companyId,
    Expression<String>? recordId,
    Expression<String>? sha256,
    Expression<Uint8List>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (companyId != null) 'company_id': companyId,
      if (recordId != null) 'record_id': recordId,
      if (sha256 != null) 'sha256': sha256,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentRowsCompanion copyWith({
    Value<String>? companyId,
    Value<String>? recordId,
    Value<String>? sha256,
    Value<Uint8List>? body,
    Value<int>? rowid,
  }) {
    return AttachmentRowsCompanion(
      companyId: companyId ?? this.companyId,
      recordId: recordId ?? this.recordId,
      sha256: sha256 ?? this.sha256,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (body.present) {
      map['body'] = Variable<Uint8List>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentRowsCompanion(')
          ..write('companyId: $companyId, ')
          ..write('recordId: $recordId, ')
          ..write('sha256: $sha256, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CheckDatabase extends GeneratedDatabase {
  _$CheckDatabase(QueryExecutor e) : super(e);
  $CheckDatabaseManager get managers => $CheckDatabaseManager(this);
  late final $CompanyScopesTable companyScopes = $CompanyScopesTable(this);
  late final $StoredRowsTable storedRows = $StoredRowsTable(this);
  late final $OperationRowsTable operationRows = $OperationRowsTable(this);
  late final $RevisionJournalTable revisionJournal = $RevisionJournalTable(
    this,
  );
  late final $PersonalRecordsTable personalRecords = $PersonalRecordsTable(
    this,
  );
  late final $PersonalOperationsTable personalOperations =
      $PersonalOperationsTable(this);
  late final $AttachmentRowsTable attachmentRows = $AttachmentRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    companyScopes,
    storedRows,
    operationRows,
    revisionJournal,
    personalRecords,
    personalOperations,
    attachmentRows,
  ];
}

typedef $$CompanyScopesTableCreateCompanionBuilder =
    CompanyScopesCompanion Function({
      required String companyId,
      Value<int> revision,
      Value<int> rowid,
    });
typedef $$CompanyScopesTableUpdateCompanionBuilder =
    CompanyScopesCompanion Function({
      Value<String> companyId,
      Value<int> revision,
      Value<int> rowid,
    });

final class $$CompanyScopesTableReferences
    extends BaseReferences<_$CheckDatabase, $CompanyScopesTable, CompanyScope> {
  $$CompanyScopesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$StoredRowsTable, List<StoredRow>>
  _storedRowsRefsTable(_$CheckDatabase db) => MultiTypedResultKey.fromTable(
    db.storedRows,
    aliasName: 'company_scopes__company_id__stored_rows__company_id',
  );

  $$StoredRowsTableProcessedTableManager get storedRowsRefs {
    final manager = $$StoredRowsTableTableManager($_db, $_db.storedRows).filter(
      (f) =>
          f.companyId.companyId.sqlEquals($_itemColumn<String>('company_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_storedRowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OperationRowsTable, List<OperationRow>>
  _operationRowsRefsTable(_$CheckDatabase db) => MultiTypedResultKey.fromTable(
    db.operationRows,
    aliasName: 'company_scopes__company_id__operation_rows__company_id',
  );

  $$OperationRowsTableProcessedTableManager get operationRowsRefs {
    final manager = $$OperationRowsTableTableManager($_db, $_db.operationRows)
        .filter(
          (f) => f.companyId.companyId.sqlEquals(
            $_itemColumn<String>('company_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_operationRowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CompanyScopesTableFilterComposer
    extends Composer<_$CheckDatabase, $CompanyScopesTable> {
  $$CompanyScopesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> storedRowsRefs(
    Expression<bool> Function($$StoredRowsTableFilterComposer f) f,
  ) {
    final $$StoredRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.storedRows,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoredRowsTableFilterComposer(
            $db: $db,
            $table: $db.storedRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> operationRowsRefs(
    Expression<bool> Function($$OperationRowsTableFilterComposer f) f,
  ) {
    final $$OperationRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.operationRows,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationRowsTableFilterComposer(
            $db: $db,
            $table: $db.operationRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CompanyScopesTableOrderingComposer
    extends Composer<_$CheckDatabase, $CompanyScopesTable> {
  $$CompanyScopesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CompanyScopesTableAnnotationComposer
    extends Composer<_$CheckDatabase, $CompanyScopesTable> {
  $$CompanyScopesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  Expression<T> storedRowsRefs<T extends Object>(
    Expression<T> Function($$StoredRowsTableAnnotationComposer a) f,
  ) {
    final $$StoredRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.storedRows,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StoredRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.storedRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> operationRowsRefs<T extends Object>(
    Expression<T> Function($$OperationRowsTableAnnotationComposer a) f,
  ) {
    final $$OperationRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.operationRows,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.operationRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CompanyScopesTableTableManager
    extends
        RootTableManager<
          _$CheckDatabase,
          $CompanyScopesTable,
          CompanyScope,
          $$CompanyScopesTableFilterComposer,
          $$CompanyScopesTableOrderingComposer,
          $$CompanyScopesTableAnnotationComposer,
          $$CompanyScopesTableCreateCompanionBuilder,
          $$CompanyScopesTableUpdateCompanionBuilder,
          (CompanyScope, $$CompanyScopesTableReferences),
          CompanyScope,
          PrefetchHooks Function({bool storedRowsRefs, bool operationRowsRefs})
        > {
  $$CompanyScopesTableTableManager(
    _$CheckDatabase db,
    $CompanyScopesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CompanyScopesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CompanyScopesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CompanyScopesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> companyId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CompanyScopesCompanion(
                companyId: companyId,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String companyId,
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CompanyScopesCompanion.insert(
                companyId: companyId,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CompanyScopesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({storedRowsRefs = false, operationRowsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (storedRowsRefs) db.storedRows,
                    if (operationRowsRefs) db.operationRows,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (storedRowsRefs)
                        await $_getPrefetchedData<
                          CompanyScope,
                          $CompanyScopesTable,
                          StoredRow
                        >(
                          currentTable: table,
                          referencedTable: $$CompanyScopesTableReferences
                              ._storedRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CompanyScopesTableReferences(
                                db,
                                table,
                                p0,
                              ).storedRowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.companyId == item.companyId,
                              ),
                          typedResults: items,
                        ),
                      if (operationRowsRefs)
                        await $_getPrefetchedData<
                          CompanyScope,
                          $CompanyScopesTable,
                          OperationRow
                        >(
                          currentTable: table,
                          referencedTable: $$CompanyScopesTableReferences
                              ._operationRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CompanyScopesTableReferences(
                                db,
                                table,
                                p0,
                              ).operationRowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.companyId == item.companyId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CompanyScopesTableProcessedTableManager =
    ProcessedTableManager<
      _$CheckDatabase,
      $CompanyScopesTable,
      CompanyScope,
      $$CompanyScopesTableFilterComposer,
      $$CompanyScopesTableOrderingComposer,
      $$CompanyScopesTableAnnotationComposer,
      $$CompanyScopesTableCreateCompanionBuilder,
      $$CompanyScopesTableUpdateCompanionBuilder,
      (CompanyScope, $$CompanyScopesTableReferences),
      CompanyScope,
      PrefetchHooks Function({bool storedRowsRefs, bool operationRowsRefs})
    >;
typedef $$StoredRowsTableCreateCompanionBuilder =
    StoredRowsCompanion Function({
      required String companyId,
      required String id,
      required String category,
      required String kind,
      required int revision,
      required Uint8List body,
      Value<int> rowid,
    });
typedef $$StoredRowsTableUpdateCompanionBuilder =
    StoredRowsCompanion Function({
      Value<String> companyId,
      Value<String> id,
      Value<String> category,
      Value<String> kind,
      Value<int> revision,
      Value<Uint8List> body,
      Value<int> rowid,
    });

final class $$StoredRowsTableReferences
    extends BaseReferences<_$CheckDatabase, $StoredRowsTable, StoredRow> {
  $$StoredRowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CompanyScopesTable _companyIdTable(_$CheckDatabase db) => db
      .companyScopes
      .createAlias('stored_rows__company_id__company_scopes__company_id');

  $$CompanyScopesTableProcessedTableManager get companyId {
    final $_column = $_itemColumn<String>('company_id')!;

    final manager = $$CompanyScopesTableTableManager(
      $_db,
      $_db.companyScopes,
    ).filter((f) => f.companyId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_companyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StoredRowsTableFilterComposer
    extends Composer<_$CheckDatabase, $StoredRowsTable> {
  $$StoredRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  $$CompanyScopesTableFilterComposer get companyId {
    final $$CompanyScopesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companyScopes,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompanyScopesTableFilterComposer(
            $db: $db,
            $table: $db.companyScopes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StoredRowsTableOrderingComposer
    extends Composer<_$CheckDatabase, $StoredRowsTable> {
  $$StoredRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  $$CompanyScopesTableOrderingComposer get companyId {
    final $$CompanyScopesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companyScopes,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompanyScopesTableOrderingComposer(
            $db: $db,
            $table: $db.companyScopes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StoredRowsTableAnnotationComposer
    extends Composer<_$CheckDatabase, $StoredRowsTable> {
  $$StoredRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<Uint8List> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  $$CompanyScopesTableAnnotationComposer get companyId {
    final $$CompanyScopesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companyScopes,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompanyScopesTableAnnotationComposer(
            $db: $db,
            $table: $db.companyScopes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StoredRowsTableTableManager
    extends
        RootTableManager<
          _$CheckDatabase,
          $StoredRowsTable,
          StoredRow,
          $$StoredRowsTableFilterComposer,
          $$StoredRowsTableOrderingComposer,
          $$StoredRowsTableAnnotationComposer,
          $$StoredRowsTableCreateCompanionBuilder,
          $$StoredRowsTableUpdateCompanionBuilder,
          (StoredRow, $$StoredRowsTableReferences),
          StoredRow,
          PrefetchHooks Function({bool companyId})
        > {
  $$StoredRowsTableTableManager(_$CheckDatabase db, $StoredRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> companyId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<Uint8List> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredRowsCompanion(
                companyId: companyId,
                id: id,
                category: category,
                kind: kind,
                revision: revision,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String companyId,
                required String id,
                required String category,
                required String kind,
                required int revision,
                required Uint8List body,
                Value<int> rowid = const Value.absent(),
              }) => StoredRowsCompanion.insert(
                companyId: companyId,
                id: id,
                category: category,
                kind: kind,
                revision: revision,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StoredRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({companyId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (companyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.companyId,
                                referencedTable: $$StoredRowsTableReferences
                                    ._companyIdTable(db),
                                referencedColumn: $$StoredRowsTableReferences
                                    ._companyIdTable(db)
                                    .companyId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$StoredRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CheckDatabase,
      $StoredRowsTable,
      StoredRow,
      $$StoredRowsTableFilterComposer,
      $$StoredRowsTableOrderingComposer,
      $$StoredRowsTableAnnotationComposer,
      $$StoredRowsTableCreateCompanionBuilder,
      $$StoredRowsTableUpdateCompanionBuilder,
      (StoredRow, $$StoredRowsTableReferences),
      StoredRow,
      PrefetchHooks Function({bool companyId})
    >;
typedef $$OperationRowsTableCreateCompanionBuilder =
    OperationRowsCompanion Function({
      required String companyId,
      required String operationId,
      required String status,
      Value<int?> revision,
      required Uint8List body,
      Value<int> rowid,
    });
typedef $$OperationRowsTableUpdateCompanionBuilder =
    OperationRowsCompanion Function({
      Value<String> companyId,
      Value<String> operationId,
      Value<String> status,
      Value<int?> revision,
      Value<Uint8List> body,
      Value<int> rowid,
    });

final class $$OperationRowsTableReferences
    extends BaseReferences<_$CheckDatabase, $OperationRowsTable, OperationRow> {
  $$OperationRowsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CompanyScopesTable _companyIdTable(_$CheckDatabase db) => db
      .companyScopes
      .createAlias('operation_rows__company_id__company_scopes__company_id');

  $$CompanyScopesTableProcessedTableManager get companyId {
    final $_column = $_itemColumn<String>('company_id')!;

    final manager = $$CompanyScopesTableTableManager(
      $_db,
      $_db.companyScopes,
    ).filter((f) => f.companyId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_companyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OperationRowsTableFilterComposer
    extends Composer<_$CheckDatabase, $OperationRowsTable> {
  $$OperationRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  $$CompanyScopesTableFilterComposer get companyId {
    final $$CompanyScopesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companyScopes,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompanyScopesTableFilterComposer(
            $db: $db,
            $table: $db.companyScopes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OperationRowsTableOrderingComposer
    extends Composer<_$CheckDatabase, $OperationRowsTable> {
  $$OperationRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  $$CompanyScopesTableOrderingComposer get companyId {
    final $$CompanyScopesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companyScopes,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompanyScopesTableOrderingComposer(
            $db: $db,
            $table: $db.companyScopes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OperationRowsTableAnnotationComposer
    extends Composer<_$CheckDatabase, $OperationRowsTable> {
  $$OperationRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<Uint8List> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  $$CompanyScopesTableAnnotationComposer get companyId {
    final $$CompanyScopesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.companyId,
      referencedTable: $db.companyScopes,
      getReferencedColumn: (t) => t.companyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CompanyScopesTableAnnotationComposer(
            $db: $db,
            $table: $db.companyScopes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OperationRowsTableTableManager
    extends
        RootTableManager<
          _$CheckDatabase,
          $OperationRowsTable,
          OperationRow,
          $$OperationRowsTableFilterComposer,
          $$OperationRowsTableOrderingComposer,
          $$OperationRowsTableAnnotationComposer,
          $$OperationRowsTableCreateCompanionBuilder,
          $$OperationRowsTableUpdateCompanionBuilder,
          (OperationRow, $$OperationRowsTableReferences),
          OperationRow,
          PrefetchHooks Function({bool companyId})
        > {
  $$OperationRowsTableTableManager(
    _$CheckDatabase db,
    $OperationRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OperationRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OperationRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OperationRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> companyId = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> revision = const Value.absent(),
                Value<Uint8List> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OperationRowsCompanion(
                companyId: companyId,
                operationId: operationId,
                status: status,
                revision: revision,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String companyId,
                required String operationId,
                required String status,
                Value<int?> revision = const Value.absent(),
                required Uint8List body,
                Value<int> rowid = const Value.absent(),
              }) => OperationRowsCompanion.insert(
                companyId: companyId,
                operationId: operationId,
                status: status,
                revision: revision,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OperationRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({companyId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (companyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.companyId,
                                referencedTable: $$OperationRowsTableReferences
                                    ._companyIdTable(db),
                                referencedColumn: $$OperationRowsTableReferences
                                    ._companyIdTable(db)
                                    .companyId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OperationRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CheckDatabase,
      $OperationRowsTable,
      OperationRow,
      $$OperationRowsTableFilterComposer,
      $$OperationRowsTableOrderingComposer,
      $$OperationRowsTableAnnotationComposer,
      $$OperationRowsTableCreateCompanionBuilder,
      $$OperationRowsTableUpdateCompanionBuilder,
      (OperationRow, $$OperationRowsTableReferences),
      OperationRow,
      PrefetchHooks Function({bool companyId})
    >;
typedef $$RevisionJournalTableCreateCompanionBuilder =
    RevisionJournalCompanion Function({
      required String companyId,
      required int revision,
      required String operationId,
      Value<int> rowid,
    });
typedef $$RevisionJournalTableUpdateCompanionBuilder =
    RevisionJournalCompanion Function({
      Value<String> companyId,
      Value<int> revision,
      Value<String> operationId,
      Value<int> rowid,
    });

class $$RevisionJournalTableFilterComposer
    extends Composer<_$CheckDatabase, $RevisionJournalTable> {
  $$RevisionJournalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RevisionJournalTableOrderingComposer
    extends Composer<_$CheckDatabase, $RevisionJournalTable> {
  $$RevisionJournalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RevisionJournalTableAnnotationComposer
    extends Composer<_$CheckDatabase, $RevisionJournalTable> {
  $$RevisionJournalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );
}

class $$RevisionJournalTableTableManager
    extends
        RootTableManager<
          _$CheckDatabase,
          $RevisionJournalTable,
          RevisionJournalData,
          $$RevisionJournalTableFilterComposer,
          $$RevisionJournalTableOrderingComposer,
          $$RevisionJournalTableAnnotationComposer,
          $$RevisionJournalTableCreateCompanionBuilder,
          $$RevisionJournalTableUpdateCompanionBuilder,
          (
            RevisionJournalData,
            BaseReferences<
              _$CheckDatabase,
              $RevisionJournalTable,
              RevisionJournalData
            >,
          ),
          RevisionJournalData,
          PrefetchHooks Function()
        > {
  $$RevisionJournalTableTableManager(
    _$CheckDatabase db,
    $RevisionJournalTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevisionJournalTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RevisionJournalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RevisionJournalTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> companyId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevisionJournalCompanion(
                companyId: companyId,
                revision: revision,
                operationId: operationId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String companyId,
                required int revision,
                required String operationId,
                Value<int> rowid = const Value.absent(),
              }) => RevisionJournalCompanion.insert(
                companyId: companyId,
                revision: revision,
                operationId: operationId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RevisionJournalTableProcessedTableManager =
    ProcessedTableManager<
      _$CheckDatabase,
      $RevisionJournalTable,
      RevisionJournalData,
      $$RevisionJournalTableFilterComposer,
      $$RevisionJournalTableOrderingComposer,
      $$RevisionJournalTableAnnotationComposer,
      $$RevisionJournalTableCreateCompanionBuilder,
      $$RevisionJournalTableUpdateCompanionBuilder,
      (
        RevisionJournalData,
        BaseReferences<
          _$CheckDatabase,
          $RevisionJournalTable,
          RevisionJournalData
        >,
      ),
      RevisionJournalData,
      PrefetchHooks Function()
    >;
typedef $$PersonalRecordsTableCreateCompanionBuilder =
    PersonalRecordsCompanion Function({
      required String personId,
      required String companyId,
      required String recordId,
      Value<int> rowid,
    });
typedef $$PersonalRecordsTableUpdateCompanionBuilder =
    PersonalRecordsCompanion Function({
      Value<String> personId,
      Value<String> companyId,
      Value<String> recordId,
      Value<int> rowid,
    });

class $$PersonalRecordsTableFilterComposer
    extends Composer<_$CheckDatabase, $PersonalRecordsTable> {
  $$PersonalRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get personId => $composableBuilder(
    column: $table.personId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PersonalRecordsTableOrderingComposer
    extends Composer<_$CheckDatabase, $PersonalRecordsTable> {
  $$PersonalRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get personId => $composableBuilder(
    column: $table.personId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PersonalRecordsTableAnnotationComposer
    extends Composer<_$CheckDatabase, $PersonalRecordsTable> {
  $$PersonalRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get personId =>
      $composableBuilder(column: $table.personId, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);
}

class $$PersonalRecordsTableTableManager
    extends
        RootTableManager<
          _$CheckDatabase,
          $PersonalRecordsTable,
          PersonalRecord,
          $$PersonalRecordsTableFilterComposer,
          $$PersonalRecordsTableOrderingComposer,
          $$PersonalRecordsTableAnnotationComposer,
          $$PersonalRecordsTableCreateCompanionBuilder,
          $$PersonalRecordsTableUpdateCompanionBuilder,
          (
            PersonalRecord,
            BaseReferences<
              _$CheckDatabase,
              $PersonalRecordsTable,
              PersonalRecord
            >,
          ),
          PersonalRecord,
          PrefetchHooks Function()
        > {
  $$PersonalRecordsTableTableManager(
    _$CheckDatabase db,
    $PersonalRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonalRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonalRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonalRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> personId = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PersonalRecordsCompanion(
                personId: personId,
                companyId: companyId,
                recordId: recordId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String personId,
                required String companyId,
                required String recordId,
                Value<int> rowid = const Value.absent(),
              }) => PersonalRecordsCompanion.insert(
                personId: personId,
                companyId: companyId,
                recordId: recordId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PersonalRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CheckDatabase,
      $PersonalRecordsTable,
      PersonalRecord,
      $$PersonalRecordsTableFilterComposer,
      $$PersonalRecordsTableOrderingComposer,
      $$PersonalRecordsTableAnnotationComposer,
      $$PersonalRecordsTableCreateCompanionBuilder,
      $$PersonalRecordsTableUpdateCompanionBuilder,
      (
        PersonalRecord,
        BaseReferences<_$CheckDatabase, $PersonalRecordsTable, PersonalRecord>,
      ),
      PersonalRecord,
      PrefetchHooks Function()
    >;
typedef $$PersonalOperationsTableCreateCompanionBuilder =
    PersonalOperationsCompanion Function({
      required String personId,
      required String companyId,
      required String operationId,
      Value<int> rowid,
    });
typedef $$PersonalOperationsTableUpdateCompanionBuilder =
    PersonalOperationsCompanion Function({
      Value<String> personId,
      Value<String> companyId,
      Value<String> operationId,
      Value<int> rowid,
    });

class $$PersonalOperationsTableFilterComposer
    extends Composer<_$CheckDatabase, $PersonalOperationsTable> {
  $$PersonalOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get personId => $composableBuilder(
    column: $table.personId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PersonalOperationsTableOrderingComposer
    extends Composer<_$CheckDatabase, $PersonalOperationsTable> {
  $$PersonalOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get personId => $composableBuilder(
    column: $table.personId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PersonalOperationsTableAnnotationComposer
    extends Composer<_$CheckDatabase, $PersonalOperationsTable> {
  $$PersonalOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get personId =>
      $composableBuilder(column: $table.personId, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );
}

class $$PersonalOperationsTableTableManager
    extends
        RootTableManager<
          _$CheckDatabase,
          $PersonalOperationsTable,
          PersonalOperation,
          $$PersonalOperationsTableFilterComposer,
          $$PersonalOperationsTableOrderingComposer,
          $$PersonalOperationsTableAnnotationComposer,
          $$PersonalOperationsTableCreateCompanionBuilder,
          $$PersonalOperationsTableUpdateCompanionBuilder,
          (
            PersonalOperation,
            BaseReferences<
              _$CheckDatabase,
              $PersonalOperationsTable,
              PersonalOperation
            >,
          ),
          PersonalOperation,
          PrefetchHooks Function()
        > {
  $$PersonalOperationsTableTableManager(
    _$CheckDatabase db,
    $PersonalOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonalOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonalOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonalOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> personId = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PersonalOperationsCompanion(
                personId: personId,
                companyId: companyId,
                operationId: operationId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String personId,
                required String companyId,
                required String operationId,
                Value<int> rowid = const Value.absent(),
              }) => PersonalOperationsCompanion.insert(
                personId: personId,
                companyId: companyId,
                operationId: operationId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PersonalOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$CheckDatabase,
      $PersonalOperationsTable,
      PersonalOperation,
      $$PersonalOperationsTableFilterComposer,
      $$PersonalOperationsTableOrderingComposer,
      $$PersonalOperationsTableAnnotationComposer,
      $$PersonalOperationsTableCreateCompanionBuilder,
      $$PersonalOperationsTableUpdateCompanionBuilder,
      (
        PersonalOperation,
        BaseReferences<
          _$CheckDatabase,
          $PersonalOperationsTable,
          PersonalOperation
        >,
      ),
      PersonalOperation,
      PrefetchHooks Function()
    >;
typedef $$AttachmentRowsTableCreateCompanionBuilder =
    AttachmentRowsCompanion Function({
      required String companyId,
      required String recordId,
      required String sha256,
      required Uint8List body,
      Value<int> rowid,
    });
typedef $$AttachmentRowsTableUpdateCompanionBuilder =
    AttachmentRowsCompanion Function({
      Value<String> companyId,
      Value<String> recordId,
      Value<String> sha256,
      Value<Uint8List> body,
      Value<int> rowid,
    });

class $$AttachmentRowsTableFilterComposer
    extends Composer<_$CheckDatabase, $AttachmentRowsTable> {
  $$AttachmentRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AttachmentRowsTableOrderingComposer
    extends Composer<_$CheckDatabase, $AttachmentRowsTable> {
  $$AttachmentRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AttachmentRowsTableAnnotationComposer
    extends Composer<_$CheckDatabase, $AttachmentRowsTable> {
  $$AttachmentRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<Uint8List> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$AttachmentRowsTableTableManager
    extends
        RootTableManager<
          _$CheckDatabase,
          $AttachmentRowsTable,
          AttachmentRow,
          $$AttachmentRowsTableFilterComposer,
          $$AttachmentRowsTableOrderingComposer,
          $$AttachmentRowsTableAnnotationComposer,
          $$AttachmentRowsTableCreateCompanionBuilder,
          $$AttachmentRowsTableUpdateCompanionBuilder,
          (
            AttachmentRow,
            BaseReferences<
              _$CheckDatabase,
              $AttachmentRowsTable,
              AttachmentRow
            >,
          ),
          AttachmentRow,
          PrefetchHooks Function()
        > {
  $$AttachmentRowsTableTableManager(
    _$CheckDatabase db,
    $AttachmentRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> companyId = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<Uint8List> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentRowsCompanion(
                companyId: companyId,
                recordId: recordId,
                sha256: sha256,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String companyId,
                required String recordId,
                required String sha256,
                required Uint8List body,
                Value<int> rowid = const Value.absent(),
              }) => AttachmentRowsCompanion.insert(
                companyId: companyId,
                recordId: recordId,
                sha256: sha256,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AttachmentRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CheckDatabase,
      $AttachmentRowsTable,
      AttachmentRow,
      $$AttachmentRowsTableFilterComposer,
      $$AttachmentRowsTableOrderingComposer,
      $$AttachmentRowsTableAnnotationComposer,
      $$AttachmentRowsTableCreateCompanionBuilder,
      $$AttachmentRowsTableUpdateCompanionBuilder,
      (
        AttachmentRow,
        BaseReferences<_$CheckDatabase, $AttachmentRowsTable, AttachmentRow>,
      ),
      AttachmentRow,
      PrefetchHooks Function()
    >;

class $CheckDatabaseManager {
  final _$CheckDatabase _db;
  $CheckDatabaseManager(this._db);
  $$CompanyScopesTableTableManager get companyScopes =>
      $$CompanyScopesTableTableManager(_db, _db.companyScopes);
  $$StoredRowsTableTableManager get storedRows =>
      $$StoredRowsTableTableManager(_db, _db.storedRows);
  $$OperationRowsTableTableManager get operationRows =>
      $$OperationRowsTableTableManager(_db, _db.operationRows);
  $$RevisionJournalTableTableManager get revisionJournal =>
      $$RevisionJournalTableTableManager(_db, _db.revisionJournal);
  $$PersonalRecordsTableTableManager get personalRecords =>
      $$PersonalRecordsTableTableManager(_db, _db.personalRecords);
  $$PersonalOperationsTableTableManager get personalOperations =>
      $$PersonalOperationsTableTableManager(_db, _db.personalOperations);
  $$AttachmentRowsTableTableManager get attachmentRows =>
      $$AttachmentRowsTableTableManager(_db, _db.attachmentRows);
}
