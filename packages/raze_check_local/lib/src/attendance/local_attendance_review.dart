part of 'local_attendance_service.dart';

extension _AttendanceReview on LocalAttendanceService {
  Future<CommandResult<AttendanceRecord>> _recordManual(
    CommandContext context,
    ManualPunch draft,
  ) async {
    try {
      final actor = identity.requireActor(context.session);
      late StaffRecord staff;
      return _commit(
        context,
        [
          'manual',
          actor.personId,
          draft.employeeId,
          draft.kind.name,
          draft.utcMs,
          draft.offsetMinutes,
          draft.reason,
        ],
        (view) async {
          await _manage(context, view);
          _validateChange(
            draft.kind,
            draft.utcMs,
            draft.offsetMinutes,
            draft.reason,
          );
          final s = await view.read(draft.employeeId);
          if (s == null || s.kind != 'staff') {
            throw const CheckException(CheckError.malformed);
          }
          staff = StaffRecord.fromJson(_json(s));
        },
        (view) async {
          final id = ids.next();
          final data = {
            'companyId': context.companyId,
            'eventId': id,
            'employeeId': staff.employeeId,
            'personId': staff.personId,
            'source': 'manual',
            'claimedUtcMs': draft.utcMs,
            'originalKind': draft.kind.name,
            'originalOffsetMinutes': draft.offsetMinutes,
            'effectiveKind': draft.kind.name,
            'effectiveUtcMs': draft.utcMs,
            'effectiveOffsetMinutes': draft.offsetMinutes,
            'review': 'pending',
            'delivery': 'localOnly',
            'receivedUtcMs': null,
            'decisionRevision': 0,
            'flags': <String>[],
            'actorPersonId': actor.personId,
            'reason': draft.reason,
            'recordedUtcMs': clock.nowUtc().millisecondsSinceEpoch,
          };
          final original = _row(
                context.companyId,
                id,
                'manualAttendance',
                data,
              ),
              state = _row(
                context.companyId,
                'attendance-state:$id',
                'attendanceState',
                data,
              );
          return Mutation(
            [state],
            [original],
            [],
            state,
            personalRecords: [
              PersonalRecordAssociation(staff.personId, state.id),
              PersonalRecordAssociation(staff.personId, original.id),
            ],
          );
        },
        (r) => AttendanceRecord(_json(r)),
      );
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }

  Future<Mutation> _snapshotDecision(
    CommandContext context,
    ReadView view,
    Company c,
    String eventId,
    String reason, {
    ReviewDecision? review,
    ProposedCorrection? change,
    bool approve = true,
    String? requestId,
    String? requestWire,
  }) async {
    final prior = await _projection(eventId, view), previous = _json(prior);
    final revision = (previous['decisionRevision'] as int) + 1;
    final correctionId = change == null ? null : ids.next();
    final effective = {
      ...previous,
      'decisionRevision': revision,
      if (review != null)
        'review': review == ReviewDecision.approve ? 'approved' : 'rejected',
      if (change != null && approve) ...{
        'effectiveKind': change.kind.name,
        'effectiveUtcMs': change.utcMs,
        'effectiveOffsetMinutes': change.offsetMinutes,
      },
    };
    final decisionId = ids.next(),
        actor = identity.requireActor(context.session);
    final data = <String, dynamic>{
      'companyId': c.id,
      'eventId': eventId,
      'employeeId': previous['employeeId'],
      'decisionId': decisionId,
      'decisionRevision': revision,
      'outcome': effective['review'],
      'reason': reason,
      'correctionId': correctionId,
      'requestId': requestId,
      'correctionOutcome': change == null
          ? null
          : (approve ? 'approved' : 'rejected'),
      'source': change == null
          ? 'review'
          : (requestId == null ? 'managerCorrection' : 'staffRequest'),
      'effectiveKind': effective['effectiveKind'],
      'effectiveUtcMs': effective['effectiveUtcMs'],
      'effectiveOffsetMinutes': effective['effectiveOffsetMinutes'],
      'actorPersonId': actor.personId,
      'issuedAtUtcMs': clock.nowUtc().millisecondsSinceEpoch,
      'wire': null,
    };
    final original = (await view.read(eventId))!;
    data['originalHash'] = await _hash(
      previous['source'] == 'staticQr'
          ? _decodeMessage(original.payload).payloadBytes
          : original.payload,
    );
    SignedMessage? signed;
    if (previous['source'] == 'staticQr') {
      signed = await _sign(
        MessageKind.attendanceDecision,
        [
          c.id,
          ids.next(),
          data['issuedAtUtcMs'],
          eventId,
          data['originalHash'],
          decisionId,
          revision,
          data['outcome'],
          reason,
          correctionId,
          requestId,
          data['correctionOutcome'],
          data['effectiveKind'],
          data['effectiveUtcMs'],
          data['effectiveOffsetMinutes'],
          actor.personId,
          c.authority,
        ],
        c.authoritySigningKeyId,
        AuthorityCertificate(c.authority).publicKey,
      );
      data['wire'] = base64UrlEncode(codec.encode(signed));
    }
    final decisionRow = _row(
      c.id,
      'decision:$eventId:$revision',
      'attendanceDecisionRecord',
      data,
    );
    final state = _row(
      c.id,
      prior.id,
      'attendanceState',
      effective,
      prior.revision + 1,
    );
    final requestResolution = requestId == null
        ? null
        : _row(c.id, 'resolution:$requestId', 'correctionResolution', {
            'eventId': eventId,
            'employeeId': previous['employeeId'],
            'requestWire': requestWire,
            'decision': data,
          });
    final outbox = signed == null
        ? null
        : StoredRecord(
            'outbox:${signed.payload.messageId}',
            c.id,
            'attendanceReturn',
            1,
            codec.encode(signed),
          );
    final person = await _subject(prior, view);
    return Mutation(
      [state, ?requestResolution],
      [decisionRow],
      [?outbox],
      decisionRow,
      personalRecords: [
        for (final r in [state, decisionRow, ?requestResolution, ?outbox])
          PersonalRecordAssociation(person, r.id),
      ],
    );
  }

  Future<CommandResult<DecisionRecord>> _decide(
    CommandContext context,
    String eventId,
    ReviewDecision outcome,
    String reason,
  ) async {
    try {
      late Company c;
      return _commit(
        context,
        [
          'decide',
          identity.requireActor(context.session).personId,
          eventId,
          outcome.name,
          reason,
        ],
        (view) async {
          c = await _manage(context, view);
          _validateChange(PunchKind.checkIn, 0, 0, reason);
          await _projection(eventId, view);
        },
        (view) => _snapshotDecision(
          context,
          view,
          c,
          eventId,
          reason,
          review: outcome,
        ),
        _decision,
      );
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }

  Future<CommandResult<CorrectionRecord>> _correct(
    CommandContext context,
    String eventId,
    ProposedCorrection change,
    String reason,
  ) async {
    try {
      late Company c;
      return _commit(
        context,
        [
          'correct',
          identity.requireActor(context.session).personId,
          eventId,
          change.toValues(),
          reason,
        ],
        (view) async {
          c = await _manage(context, view);
          _validateChange(
            change.kind,
            change.utcMs,
            change.offsetMinutes,
            change.reason,
          );
          _validateChange(
            change.kind,
            change.utcMs,
            change.offsetMinutes,
            reason,
          );
          await _projection(eventId, view);
        },
        (view) => _snapshotDecision(
          context,
          view,
          c,
          eventId,
          reason,
          change: change,
        ),
        (r) => CorrectionRecord(_decision(r)),
      );
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }

  Future<SignedMessage> _request(
    SessionHandle session,
    String companyId,
    String eventId,
    ProposedCorrection change,
    String operationId,
  ) async {
    final actor = AttendanceAuthorization(identity).requirePersonal(session);
    final c = (await AttendanceAuthorization(identity).require(
      session,
      companyId,
      (id) => repository.read(companyId, id),
    )).company;
    late Membership member;
    final context = CommandContext(
      companyId: companyId,
      session: session,
      operationId: operationId,
      authorityGenerationId: c.authorityGenerationId,
    );
    final result = await _commit<SignedMessage>(
      context,
      ['request', actor.personId, eventId, change.toValues()],
      (view) async {
        final a = await AttendanceAuthorization(identity).require(
          session,
          companyId,
          view.read,
          generation: c.authorityGenerationId,
        );
        member = a.member;
        _validateChange(
          change.kind,
          change.utcMs,
          change.offsetMinutes,
          change.reason,
        );
        final r = await _projection(eventId, view);
        if (await _subject(r, view) != actor.personId ||
            _json(r)['source'] != 'staticQr') {
          throw const CheckException(CheckError.unauthorized);
        }
      },
      (view) async {
        final signed = await _sign(
          MessageKind.correctionRequest,
          [
            companyId,
            ids.next(),
            clock.nowUtc().millisecondsSinceEpoch,
            member.employeeId,
            eventId,
            ...change.toValues(),
          ],
          actor.signingKeyId,
          actor.publicKey,
        );
        final request = StoredRecord(
          'correction-request:${signed.payload.messageId}',
          companyId,
          'correctionRequest',
          1,
          codec.encode(signed),
        );
        final outbox = StoredRecord(
          'outbox:${signed.payload.messageId}',
          companyId,
          'correctionOutbox',
          1,
          request.payload,
        );
        return Mutation(
          [],
          [request],
          [outbox],
          request,
          personalRecords: [
            PersonalRecordAssociation(actor.personId, request.id),
            PersonalRecordAssociation(actor.personId, outbox.id),
          ],
          personalOperationOwners: {actor.personId},
        );
      },
      (r) => _decodeMessage(r.payload),
    );
    return _value(result);
  }

  Future<CommandResult<CorrectionRecord>> _resolve(
    CommandContext context,
    VerifiedMessage request,
    bool approve,
    String reason,
  ) async {
    try {
      final msg = request.message, p = msg.payload;
      late Company c;
      late ProposedCorrection change;
      late String eventId;
      return _commit(
        context,
        [
          'resolve',
          identity.requireActor(context.session).personId,
          base64UrlEncode(codec.encode(msg)),
          approve,
          reason,
        ],
        (view) async {
          c = await _manage(context, view);
          if (msg.kind != MessageKind.correctionRequest) {
            throw const CheckException(CheckError.malformed);
          }
          final verified = await _verify(msg, c, view);
          if (verified.historicalCredential) {
            throw const CheckException(CheckError.revokedCredential);
          }
          eventId = p.field<String>('eventId');
          final state = _json(await _projection(eventId, view));
          if (state['source'] != 'staticQr' ||
              state['employeeId'] != p.field<String>('employeeId')) {
            throw const CheckException(CheckError.unauthorized);
          }
          change = ProposedCorrection(
            kind: PunchKind.values.byName(p.field<String>('proposedKind')),
            utcMs: p.field<int>('proposedUtcMs'),
            offsetMinutes: p.field<int>('proposedOffsetMinutes'),
            reason: p.field<String>('reason'),
          );
          _validateChange(
            change.kind,
            change.utcMs,
            change.offsetMinutes,
            reason,
          );
          final originalRequest = await view.read(
            'correction-request:${p.messageId}',
          );
          if (originalRequest != null &&
              (originalRequest.kind != 'correctionRequest' ||
                  base64UrlEncode(originalRequest.payload) !=
                      base64UrlEncode(codec.encode(msg)))) {
            throw const CheckException(CheckError.duplicateConflict);
          }
          final existing = await view.read('resolution:${p.messageId}');
          if (existing != null &&
              (_json(existing)['requestWire'] !=
                      base64UrlEncode(codec.encode(msg)) ||
                  (_json(existing)['decision'] as Map)['correctionOutcome'] !=
                      (approve ? 'approved' : 'rejected') ||
                  (_json(existing)['decision'] as Map)['reason'] != reason)) {
            throw const CheckException(CheckError.duplicateConflict);
          }
        },
        (view) async {
          final existing = await view.read('resolution:${p.messageId}');
          if (existing != null) {
            return Mutation(
              [],
              [],
              [],
              _row(
                c.id,
                'resolution-result:${p.messageId}',
                'attendanceDecisionRecord',
                _json(existing)['decision'] as Map,
              ),
            );
          }
          final mutation = await _snapshotDecision(
            context,
            view,
            c,
            eventId,
            reason,
            change: change,
            approve: approve,
            requestId: p.messageId,
            requestWire: base64UrlEncode(codec.encode(msg)),
          );
          final requestRow = StoredRecord(
            'correction-request:${p.messageId}',
            c.id,
            'correctionRequest',
            1,
            codec.encode(msg),
          );
          return Mutation(
            mutation.records,
            [
              ...mutation.events,
              if (await view.read(requestRow.id) == null) requestRow,
            ],
            mutation.outbox,
            mutation.result,
            personalRecords: [
              ...mutation.personalRecords,
              PersonalRecordAssociation(
                await _subject(await _projection(eventId, view), view),
                requestRow.id,
              ),
            ],
          );
        },
        (r) => CorrectionRecord(_decision(r)),
      );
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }
}
