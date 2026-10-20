import 'dart:async';
import 'dart:convert';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:timezone/timezone.dart' as tz;
import '../database/local_check_repository.dart';

final class _Cursor implements AttendanceCursor {
  _Cursor(
    this.owner,
    this.session,
    this.company,
    this.scope,
    this.revision,
    this.after,
  );
  final Object owner;
  final SessionHandle session;
  final String company, after;
  final AttendanceScope scope;
  final int revision;
}

/// Authorized reads of encrypted attendance; no archive-shaped snapshots.
final class LocalAttendanceQueries implements AttendanceQueries {
  LocalAttendanceQueries({
    required this.repository,
    required this.identity,
    required this.clock,
  });
  final LocalCheckRepository repository;
  final IdentityService identity;
  final CheckClock clock;
  void _cancel(bool Function()? cancelled) {
    if (cancelled?.call() == true) {
      throw const CheckException(CheckError.invalidTransition);
    }
  }

  Map<String, dynamic> _json(StoredRecord r) =>
      jsonDecode(utf8.decode(r.payload)) as Map<String, dynamic>;

  Future<({Company company, String? person})> _access(
    AttendanceReadView view,
    SessionHandle session,
    String companyId,
    AttendanceScope scope, {
    bool exporting = false,
    String? generation,
  }) async {
    final actor = identity.requireActor(session);
    actor.requireCompany(companyId);
    final companyRow = await view.read(companyId);
    if (companyRow == null || companyRow.kind != 'company') {
      throw const CheckException(CheckError.wrongCompany);
    }
    final company = Company.fromJson(_json(companyRow));
    final index = await view.read('member-index:${actor.personId}');
    final row = index == null
        ? null
        : await view.read(_json(index)['membershipId'] as String);
    if (row == null || row.kind != 'membership') {
      throw const CheckException(CheckError.unauthorized);
    }
    final member = Membership.fromJson(_json(row));
    if (member.companyId != companyId || member.personId != actor.personId) {
      throw const CheckException(CheckError.unauthorized);
    }
    if (scope == AttendanceScope.management) {
      AccessPolicy(identity).require(
        session,
        member,
        exporting ? Capability.exportAttendance : Capability.reviewAttendance,
      );
      if (generation != null && generation != company.authorityGenerationId) {
        throw const CheckException(CheckError.recoveryRequired);
      }
    } else if (actor.restrictedCompanyId != null) {
      throw const CheckException(CheckError.unauthorized);
    }
    // Historical personal reads remain available without a current issuance credential.
    identity.requireActor(session).requireCompany(companyId);
    return (
      company: company,
      person: scope == AttendanceScope.personal ? actor.personId : null,
    );
  }

  @override
  Future<void> authorize(
    SessionHandle session,
    String companyId, {
    AttendanceScope scope = AttendanceScope.personal,
  }) => repository.readAttendance(companyId, (view) async {
    await _access(view, session, companyId, scope);
    identity.requireActor(session).requireCompany(companyId);
  });

  Future<AttendanceItem?> _item(
    AttendanceReadView view,
    StoredRecord original,
    String? person,
  ) async {
    final row = await view.read('attendance-state:${original.id}');
    late Map<String, dynamic> data;
    if (row != null) {
      if (row.kind != 'attendanceState') {
        throw const CheckException(CheckError.malformed);
      }
      data = _json(row);
    } else {
      final receipt = await view.read('receipt:${original.id}');
      if (receipt == null || receipt.kind != 'attendanceReceipt') {
        throw const CheckException(CheckError.malformed);
      }
      final r = _json(receipt);
      final message = MessageCodec().decode(
        base64Url.decode(r['bytes'] as String),
        maxBytes: MessageLimits.fileBytes,
      );
      final p = message.payload;
      data = {
        'companyId': p.companyId,
        'eventId': p.messageId,
        'employeeId': p.field<String>('employeeId'),
        'personId': p.field<String>('personId'),
        'source': 'staticQr',
        'claimedUtcMs': p.field<int>('claimedUtcMs'),
        'originalKind': p.field<String>('kind'),
        'originalOffsetMinutes': p.field<int>('offsetMinutes'),
        'effectiveKind': p.field<String>('kind'),
        'effectiveUtcMs': p.field<int>('claimedUtcMs'),
        'effectiveOffsetMinutes': p.field<int>('offsetMinutes'),
        'review': 'pending',
        'delivery': r['delivery'],
        'receivedUtcMs': null,
        'decisionRevision': 0,
        'flags': r['flags'],
      };
    }
    if (data['companyId'] != original.companyId ||
        data['eventId'] != original.id) {
      throw const CheckException(CheckError.malformed);
    }
    final staff = await view.read(data['employeeId'] as String);
    if (staff == null || staff.kind != 'staff') {
      throw const CheckException(CheckError.unauthorized);
    }
    final subject = StaffRecord.fromJson(_json(staff));
    if (person != null && subject.personId != person) return null;
    return AttendanceItem(AttendanceRecord(data), subject.details.name);
  }

  Future<List<DecisionRecord>> _decisions(
    AttendanceReadView view,
    CommandContext context,
    String eventId,
    bool Function()? cancelled,
  ) async {
    final result = <DecisionRecord>[];
    String? after;
    while (true) {
      _cancel(cancelled);
      identity.requireActor(context.session).requireCompany(context.companyId);
      final page = await view.decisions(eventId, after: after, limit: 50);
      for (final row in page) {
        _cancel(cancelled);
        identity
            .requireActor(context.session)
            .requireCompany(context.companyId);
        final decision = DecisionRecord(_json(row));
        if (decision.data['companyId'] != context.companyId ||
            decision.eventId != eventId) {
          throw const CheckException(CheckError.malformed);
        }
        result.add(decision);
      }
      if (page.length < 50) break;
      after = page.last.id;
    }
    _cancel(cancelled);
    identity.requireActor(context.session).requireCompany(context.companyId);
    result.sort((a, b) => a.revision.compareTo(b.revision));
    return result;
  }

  @override
  Future<AttendanceHistoryPage> historyPage(
    SessionHandle session,
    String companyId, {
    AttendanceScope scope = AttendanceScope.personal,
    AttendanceCursor? cursor,
    int pageSize = 25,
    bool Function()? cancelled,
  }) async {
    if (pageSize < 1 || pageSize > 100) {
      throw const CheckException(CheckError.limitExceeded);
    }
    if (cursor != null &&
        (cursor is! _Cursor ||
            !identical(cursor.owner, this) ||
            !identical(cursor.session, session) ||
            cursor.company != companyId ||
            cursor.scope != scope)) {
      throw const CheckException(CheckError.unauthorized);
    }
    _cancel(cancelled);
    return repository.readAttendance(companyId, (view) async {
      _cancel(cancelled);
      final access = await _access(view, session, companyId, scope);
      final previous = cursor as _Cursor?;
      if (previous != null && previous.revision != view.revision) {
        return AttendanceHistoryPage([], refreshRequired: true);
      }
      final originals = await view.events(
        personId: access.person,
        after: previous?.after,
        limit: pageSize,
      );
      final items = <AttendanceItem>[];
      for (final original in originals) {
        _cancel(cancelled);
        identity.requireActor(session).requireCompany(companyId);
        final item = await _item(view, original, access.person);
        if (item != null) items.add(item);
      }
      _cancel(cancelled);
      identity.requireActor(session).requireCompany(companyId);
      return AttendanceHistoryPage(
        items,
        next: originals.length == pageSize
            ? _Cursor(
                this,
                session,
                companyId,
                scope,
                view.revision,
                originals.last.id,
              )
            : null,
      );
    });
  }

  Future<void> _visit(
    AttendanceReadView view,
    SessionHandle session,
    String company,
    String? person,
    Future<void> Function(AttendanceItem) visit, {
    bool Function()? cancelled,
  }) async {
    String? after;
    while (true) {
      _cancel(cancelled);
      identity.requireActor(session).requireCompany(company);
      final originals = await view.events(
        personId: person,
        after: after,
        limit: 50,
      );
      for (final original in originals) {
        _cancel(cancelled);
        identity.requireActor(session).requireCompany(company);
        final item = await _item(view, original, person);
        if (item != null) await visit(item);
      }
      if (originals.length < 50) break;
      after = originals.last.id;
    }
    identity.requireActor(session).requireCompany(company);
  }

  Future<ManagerOverview> _overview(
    SessionHandle session,
    String company,
    AttendanceScope scope, {
    String? generation,
    bool Function()? cancelled,
  }) => repository.readAttendance(company, (view) async {
    final access = await _access(
      view,
      session,
      company,
      scope,
      generation: generation,
    );
    var total = 0,
        saved = 0,
        received = 0,
        pending = 0,
        approved = 0,
        rejected = 0;
    int? lastReceived;
    AttendanceItem? latest;
    await _visit(view, session, company, access.person, (item) async {
      final r = item.record;
      total++;
      if (r.returnEligible && r.delivery == DeliveryStatus.localOnly) saved++;
      if (r.delivery == DeliveryStatus.received) {
        received++;
        final time = r.receivedUtcMs;
        if (time != null && (lastReceived == null || time > lastReceived!)) {
          lastReceived = time;
        }
      }
      switch (r.review) {
        case ReviewStatus.pending:
          pending++;
        case ReviewStatus.approved:
          approved++;
        case ReviewStatus.rejected:
          rejected++;
      }
      if (latest == null ||
          r.effectiveUtcMs > latest!.record.effectiveUtcMs ||
          (r.effectiveUtcMs == latest!.record.effectiveUtcMs &&
              r.eventId.compareTo(latest!.record.eventId) > 0)) {
        latest = item;
      }
    }, cancelled: cancelled);
    return ManagerOverview(
      company: access.company,
      total: total,
      savedOnDevice: saved,
      received: received,
      pending: pending,
      approved: approved,
      rejected: rejected,
      latest: latest,
      lastReceivedUtcMs: lastReceived,
    );
  });

  /// Coalesce revisions while a read is pending. Cancellation suppresses emissions.
  Stream<T> _watch<T>(
    String company,
    Future<T> Function(bool Function()) read,
  ) {
    return Stream<T>.multi((controller) {
      var busy = false, dirty = false, cancelled = false;
      Future<void> refresh() async {
        dirty = true;
        if (busy) return;
        busy = true;
        try {
          while (dirty && !cancelled) {
            dirty = false;
            try {
              final value = await read(() => cancelled);
              if (!cancelled) controller.add(value);
            } catch (e, st) {
              if (!cancelled) controller.addError(e, st);
            }
          }
        } finally {
          busy = false;
        }
      }

      final subscription = repository.watchRevision(company).listen((_) {
        unawaited(refresh());
      }, onError: controller.addError);
      controller.onCancel = () async {
        cancelled = true;
        await subscription.cancel();
      };
    });
  }

  @override
  Stream<StaffOverview> forStaff(SessionHandle session, String companyId) =>
      _watch(
        companyId,
        (cancelled) => _overview(
          session,
          companyId,
          AttendanceScope.personal,
          cancelled: cancelled,
        ),
      );
  @override
  Stream<ManagerOverview> forManager(CommandContext context) => _watch(
    context.companyId,
    (cancelled) => _overview(
      context.session,
      context.companyId,
      AttendanceScope.management,
      generation: context.authorityGenerationId,
      cancelled: cancelled,
    ),
  );

  @override
  Future<void> authorizeReport(CommandContext context, AttendanceScope scope) =>
      repository.readAttendance(context.companyId, (view) async {
        await _access(
          view,
          context.session,
          context.companyId,
          scope,
          exporting: true,
          generation: context.authorityGenerationId,
        );
        identity
            .requireActor(context.session)
            .requireCompany(context.companyId);
      });
  @override
  Future<AttendanceReport> report(
    CommandContext context,
    DateRange range, {
    AttendanceScope scope = AttendanceScope.personal,
    bool Function()? cancelled,
  }) => repository.readAttendance(context.companyId, (view) async {
    final access = await _access(
      view,
      context.session,
      context.companyId,
      scope,
      exporting: true,
      generation: context.authorityGenerationId,
    );
    CompanyTimeZones.all;
    final zone = tz.getLocation(access.company.timeZoneId);
    final start = tz.TZDateTime(
      zone,
      range.start.year,
      range.start.month,
      range.start.day,
    ).millisecondsSinceEpoch;
    final end = tz.TZDateTime(
      zone,
      range.end.year,
      range.end.month,
      range.end.day + 1,
    ).millisecondsSinceEpoch;
    final rows = <AttendanceItem>[];
    await _visit(view, context.session, context.companyId, access.person, (
      item,
    ) async {
      final time = item.record.effectiveUtcMs;
      if (time >= start && time < end) {
        rows.add(
          AttendanceItem(
            item.record,
            item.employeeName,
            decisions: await _decisions(
              view,
              context,
              item.record.eventId,
              cancelled,
            ),
          ),
        );
      }
    }, cancelled: cancelled);
    final byEvent = {for (final item in rows) item.record.eventId: item};
    final requests = <String, List<AttendanceCorrectionRequest>>{};
    String? afterRequest;
    while (byEvent.isNotEmpty) {
      _cancel(cancelled);
      identity.requireActor(context.session).requireCompany(context.companyId);
      final page = await view.events(
        personId: access.person,
        after: afterRequest,
        limit: 50,
        correctionRequests: true,
      );
      for (final row in page) {
        _cancel(cancelled);
        final payload = MessageCodec()
            .decode(row.payload, maxBytes: MessageLimits.fileBytes)
            .payload;
        final eventId = payload.field<String>('eventId');
        if (!byEvent.containsKey(eventId)) continue;
        final resolution = await view.read('resolution:${payload.messageId}');
        final decision = resolution == null
            ? null
            : _json(resolution)['decision'] as Map<String, dynamic>?;
        final outcome = decision?['correctionOutcome'] as String?;
        (requests[eventId] ??= []).add(
          AttendanceCorrectionRequest(
            requestId: payload.messageId,
            reason: payload.field<String>('reason'),
            proposedKind: payload.field<String>('proposedKind'),
            proposedUtcMs: payload.field<int>('proposedUtcMs'),
            outcome: outcome == null
                ? null
                : CorrectionOutcome.values.byName(outcome),
          ),
        );
      }
      if (page.length < 50) break;
      afterRequest = page.last.id;
    }
    for (var i = 0; i < rows.length; i++) {
      final item = rows[i];
      rows[i] = AttendanceItem(
        item.record,
        item.employeeName,
        decisions: item.decisions,
        requests: requests[item.record.eventId] ?? const [],
      );
    }
    _cancel(cancelled);
    identity.requireActor(context.session).requireCompany(context.companyId);
    rows.sort((a, b) {
      final time = a.record.effectiveUtcMs.compareTo(b.record.effectiveUtcMs);
      return time == 0 ? a.record.eventId.compareTo(b.record.eventId) : time;
    });
    return AttendanceReport(
      company: access.company,
      range: range,
      scope: scope,
      generatedUtcMs: clock.nowUtc().millisecondsSinceEpoch,
      rows: rows,
    );
  });
}
