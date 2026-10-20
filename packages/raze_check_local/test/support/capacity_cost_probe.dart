import 'package:drift/drift.dart';
import 'package:raze_check_local/raze_check_local.dart';

final class CostProbe extends QueryInterceptor implements PayloadCipher {
  CostProbe(this.real);
  final PayloadCipher real;
  final metrics = <String, int>{};
  var active = 0;
  var activeSealedBytes = 0;
  void add(String key, int value) =>
      metrics.update(key, (v) => v + value, ifAbsent: () => value);
  void maximum(String key, int value) {
    if (value > (metrics[key] ?? 0)) {
      metrics[key] = value;
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    final family = statement.contains('SELECT r.* FROM stored_rows r')
        ? 'history'
        : statement.contains('stored_rows')
        ? 'stored'
        : statement.contains('personal_operations')
        ? 'owners'
        : statement.contains('revision_journal')
        ? 'journal'
        : statement.contains('operation_rows')
        ? 'operations'
        : 'other';
    add('sql.$family.calls', 1);
    add('sql.$family.rows', rows.length);
    maximum('sql.$family.maxRows', rows.length);
    var bodyBytes = 0;
    for (final row in rows) {
      for (final value in row.values) {
        if (value is Uint8List) {
          bodyBytes += value.length;
        }
      }
    }
    add('sql.$family.bodyBytes', bodyBytes);
    maximum('sql.$family.maxBodyBytes', bodyBytes);
    return rows;
  }

  @override
  Future<Uint8List> open({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List sealed,
  }) async {
    active++;
    activeSealedBytes += sealed.length;
    maximum('aes.maxConcurrentOpens', active);
    maximum('aes.maxConcurrentSealedBytes', activeSealedBytes);
    add('aes.opens', 1);
    add('aes.sealedBytes', sealed.length);
    if (recordId.startsWith('record:attendance-state:')) {
      add('aes.attendanceStateOpens', 1);
    }
    if (recordId.startsWith('operation:')) {
      add('aes.operationOpens', 1);
    }
    try {
      final value = await real.open(
        scopeId: scopeId,
        recordId: recordId,
        revision: revision,
        sealed: sealed,
      );
      add('aes.plainBytes', value.length);
      maximum('aes.maxSinglePlainBytes', value.length);
      return value;
    } finally {
      active--;
      activeSealedBytes -= sealed.length;
    }
  }

  @override
  Future<Uint8List> seal({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List plain,
  }) async {
    add('aes.seals', 1);
    add('aes.sealPlainBytes', plain.length);
    return real.seal(
      scopeId: scopeId,
      recordId: recordId,
      revision: revision,
      plain: plain,
    );
  }
}
