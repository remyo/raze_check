part of 'local_check_repository.dart';

/// Adapter-only view. The caller must authorize within this consistent snapshot.
/// Do not retain the view or recursively invoke repository methods.
final class AttendanceReadView implements ReadView {
  AttendanceReadView._(this._view, this.revision);
  final _TransactionReadView _view;
  final int revision;
  @override
  Future<StoredRecord?> read(String id) => _view.read(id);
  @override
  Future<List<StoredRecord>> list(String kind) => _view.list(kind);

  /// The immutable decision IDs are event-scoped. Range bounds use the existing
  /// company/id index; LIMIT bounds decoding even when revisions are sparse.
  Future<List<StoredRecord>> decisions(
    String eventId, {
    String? after,
    int limit = 50,
  }) async {
    _view._requireActive();
    if (limit < 1 || limit > 100) {
      throw const CheckException(CheckError.limitExceeded);
    }
    final prefix = 'decision:$eventId:';
    final rows = await _view.repository._db
        .customSelect(
          '''
      SELECT r.* FROM stored_rows r
      WHERE r.company_id = ? AND r.id >= ? AND r.id < ?
      AND r.category = 'event' AND r.kind = 'attendanceDecisionRecord'
      ${after == null ? '' : 'AND r.id > ?'}
      ORDER BY r.id LIMIT ?
    ''',
          variables: [
            Variable.withString(_view.companyId),
            Variable.withString(prefix),
            Variable.withString('$prefix~'),
            if (after != null) Variable.withString(after),
            Variable.withInt(limit),
          ],
        )
        .get();
    final result = <StoredRecord>[];
    for (final row in rows) {
      _view._requireActive();
      result.add(await _view.repository._decodeRecord(row));
    }
    return List.unmodifiable(result);
  }

  /// Stable event-ID order, not chronological order. LIMIT precedes decryption.
  Future<List<StoredRecord>> events({
    String? personId,
    String? after,
    int limit = 25,
    bool correctionRequests = false,
  }) async {
    _view._requireActive();
    if (limit < 1 || limit > 100) {
      throw const CheckException(CheckError.limitExceeded);
    }
    final variables = <Variable>[
      Variable.withString(_view.companyId),
      if (after != null) Variable.withString(after),
      if (personId != null) Variable.withString(personId),
      Variable.withInt(limit),
    ];
    final rows = await _view.repository._db.customSelect('''
      SELECT r.* FROM stored_rows r
      WHERE r.company_id = ? AND r.category = 'event'
      AND ${correctionRequests ? "r.kind = 'correctionRequest'" : "r.kind IN ('attendance','manualAttendance')"}
      ${after == null ? '' : 'AND r.id > ?'}
      ${personId == null ? '' : 'AND EXISTS (SELECT 1 FROM personal_records p WHERE p.person_id = ? AND p.company_id = r.company_id AND p.record_id = r.id)'}
      ORDER BY r.id LIMIT ?
    ''', variables: variables).get();
    final result = <StoredRecord>[];
    for (final row in rows) {
      _view._requireActive();
      result.add(await _view.repository._decodeRecord(row));
    }
    return List.unmodifiable(result);
  }
}

extension AttendanceReadRepository on LocalCheckRepository {
  Future<T> readAttendance<T>(
    String companyId,
    Future<T> Function(AttendanceReadView) read,
  ) => _exclusive(
    () => _storage(
      () => _readTransaction(() async {
        final view = _TransactionReadView(this, companyId);
        try {
          return await read(
            AttendanceReadView._(view, await _revision(companyId)),
          );
        } finally {
          view.active = false;
        }
      }),
    ),
  );
}
