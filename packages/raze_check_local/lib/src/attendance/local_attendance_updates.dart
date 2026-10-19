part of 'local_attendance_service.dart';

extension _AttendanceUpdates on LocalAttendanceService {
  Future<CommandResult<AttendanceRecord>> _accept(
    SessionHandle session,
    VerifiedMessage update,
  ) async {
    try {
      final actor = AttendanceAuthorization(identity).requirePersonal(session),
          msg = update.message,
          p = msg.payload;
      final companyId = p.companyId;
      final c = await _company(companyId, _QueryView(repository, companyId));
      final context = CommandContext(
        companyId: companyId,
        session: session,
        operationId: 'attendance-update:${actor.personId}:${p.messageId}',
        authorityGenerationId: c.authorityGenerationId,
      );
      late String eventId;
      late StoredRecord prior;
      return _commit(
        context,
        ['accept', actor.personId, base64UrlEncode(codec.encode(msg))],
        (view) async {
          await _membership(session, companyId, view);
          if (msg.kind != MessageKind.receiptAck &&
              msg.kind != MessageKind.attendanceDecision) {
            throw const CheckException(CheckError.malformed);
          }
          await _verify(msg, await _company(companyId, view), view);
          eventId = p.field<String>('eventId');
          prior = await _projection(eventId, view);
          if (_json(prior)['source'] != 'staticQr' ||
              _json(prior)['personId'] != actor.personId ||
              await _subject(prior, view) != actor.personId) {
            throw const CheckException(CheckError.unauthorized);
          }
          final original = await view.read(eventId);
          if (original == null || original.kind != 'attendance') {
            throw const CheckException(CheckError.malformed);
          }
          final originalMessage = _decodeMessage(original.payload);
          await _verify(originalMessage, await _company(companyId, view), view);
          if (await _hash(originalMessage.payloadBytes) !=
              p.field<String>('eventPayloadSha256Base64Url')) {
            throw const CheckException(CheckError.invalidSignature);
          }
          if (msg.kind == MessageKind.attendanceDecision) {
            // IDs identify immutable decisions/corrections across all events,
            // not merely a slot in one event's revision sequence.
            for (final history in await view.list('attendanceDecisionRecord')) {
              final known = _json(history);
              final sameDecision =
                  known['decisionId'] == p.field<String>('decisionId');
              final correctionId = p.field<String?>('correctionIdOrNull');
              final sameCorrection =
                  correctionId != null && known['correctionId'] == correctionId;
              if ((sameDecision || sameCorrection) &&
                  known['wire'] != base64UrlEncode(codec.encode(msg))) {
                throw const CheckException(CheckError.duplicateConflict);
              }
            }
            final priorDecision = await view.read(
              'decision:$eventId:${p.field<int>('decisionRevision')}',
            );
            if (priorDecision != null &&
                _json(priorDecision)['wire'] !=
                    base64UrlEncode(codec.encode(msg))) {
              throw const CheckException(CheckError.duplicateConflict);
            }
            final requestId = p.field<String?>('correctionRequestIdOrNull');
            if (requestId != null) {
              final request = await view.read('correction-request:$requestId');
              if (request != null) {
                final r = _decodeMessage(request.payload);
                await _verify(r, await _company(companyId, view), view);
                if (r.payload.field<String>('eventId') != eventId ||
                    r.payload.field<String>('employeeId') !=
                        _json(prior)['employeeId']) {
                  throw const CheckException(CheckError.duplicateConflict);
                }
                if (p.field<String?>('correctionOutcomeOrNull') == 'approved' &&
                    (r.payload.field<String>('proposedKind') !=
                            p.field<String>('effectiveKind') ||
                        r.payload.field<int>('proposedUtcMs') !=
                            p.field<int>('effectiveUtcMs') ||
                        r.payload.field<int>('proposedOffsetMinutes') !=
                            p.field<int>('effectiveOffsetMinutes'))) {
                  throw const CheckException(CheckError.invalidTransition);
                }
              }
              final resolution = await view.read('resolution:$requestId');
              if (resolution != null &&
                  (_json(resolution)['decision'] as Map)['decisionId'] !=
                      p.field<String>('decisionId')) {
                throw const CheckException(CheckError.duplicateConflict);
              }
            }
          }
        },
        (view) async {
          final d = _json(prior),
              records = <StoredRecord>[],
              events = <StoredRecord>[];
          final observation = await observeBusinessAuthority(
            companyId,
            actor.personId,
            AuthorityCertificate(p.field<List<Object?>>('authority')),
            view,
          );
          if (observation != null) records.add(observation);
          if (msg.kind == MessageKind.receiptAck) {
            d['delivery'] = 'received';
            final received = p.field<int>('receivedUtcMs');
            d['receivedUtcMs'] = d['receivedUtcMs'] == null
                ? received
                : ((d['receivedUtcMs'] as int) < received
                      ? d['receivedUtcMs']
                      : received);
            final receipt = (await view.read('receipt:$eventId'))!;
            if (_json(receipt)['delivery'] != 'received') {
              records.add(
                _row(companyId, receipt.id, receipt.kind, {
                  ..._json(receipt),
                  'delivery': 'received',
                }, receipt.revision + 1),
              );
            }
          } else {
            final rev = p.field<int>('decisionRevision');
            if (rev > (d['decisionRevision'] as int)) {
              d.addAll({
                'decisionRevision': rev,
                'review': p.field<String>('outcome'),
                'effectiveKind': p.field<String>('effectiveKind'),
                'effectiveUtcMs': p.field<int>('effectiveUtcMs'),
                'effectiveOffsetMinutes': p.field<int>(
                  'effectiveOffsetMinutes',
                ),
              });
            }
            final requestId = p.field<String?>('correctionRequestIdOrNull'),
                correctionId = p.field<String?>('correctionIdOrNull');
            final detail = {
              'companyId': companyId,
              'employeeId': d['employeeId'],
              'eventId': eventId,
              'decisionId': p.field<String>('decisionId'),
              'decisionRevision': rev,
              'outcome': p.field<String>('outcome'),
              'reason': p.field<String>('reason'),
              'correctionId': correctionId,
              'requestId': requestId,
              'correctionOutcome': p.field<String?>('correctionOutcomeOrNull'),
              'source': correctionId == null
                  ? 'review'
                  : (requestId == null ? 'managerCorrection' : 'staffRequest'),
              'effectiveKind': p.field<String>('effectiveKind'),
              'effectiveUtcMs': p.field<int>('effectiveUtcMs'),
              'effectiveOffsetMinutes': p.field<int>('effectiveOffsetMinutes'),
              'actorPersonId': p.field<String>('actorPersonId'),
              'issuedAtUtcMs': p.issuedAtUtcMs,
              'originalHash': p.field<String>('eventPayloadSha256Base64Url'),
              'wire': base64UrlEncode(codec.encode(msg)),
            };
            final history = _row(
              companyId,
              'decision:$eventId:$rev',
              'attendanceDecisionRecord',
              detail,
            );
            if (await view.read(history.id) == null) events.add(history);
            if (requestId != null &&
                await view.read('resolution:$requestId') == null) {
              records.add(
                _row(
                  companyId,
                  'resolution:$requestId',
                  'correctionResolution',
                  {
                    'eventId': eventId,
                    'employeeId': d['employeeId'],
                    'decision': detail,
                  },
                ),
              );
            }
          }
          final state = _row(
            companyId,
            prior.id,
            'attendanceState',
            d,
            prior.revision + 1,
          );
          records.add(state);
          final updateRow = StoredRecord(
            'received-update:${p.messageId}',
            companyId,
            'attendanceUpdate',
            1,
            codec.encode(msg),
          );
          if (await view.read(updateRow.id) == null) events.add(updateRow);
          return Mutation(
            records,
            events,
            [],
            state,
            personalRecords: [
              for (final r in [...records, ...events])
                PersonalRecordAssociation(actor.personId, r.id),
            ],
            personalOperationOwners: {actor.personId},
          );
        },
        (r) => AttendanceRecord(_json(r)),
      );
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }
}
