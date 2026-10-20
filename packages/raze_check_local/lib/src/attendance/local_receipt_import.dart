part of 'local_attendance_service.dart';

extension _ReceiptImport on LocalAttendanceService {
  static const _sequenceFlags = {
    'missingCheckIn',
    'missingCheckOut',
    'unexpectedOrder',
    'possibleDuplicate',
  };
  Future<ImportOutcome> _importReceipt(
    CommandContext context,
    VerifiedMessage receipt,
  ) async {
    try {
      final message = receipt.message, p = message.payload;
      late Company c;
      late VerifiedMessage verified;
      late TrustContext trusted;
      final result = await _commit<ImportOutcome>(
        context,
        [
          'import',
          identity.requireActor(context.session).personId,
          base64UrlEncode(codec.encode(message)),
        ],
        (view) async {
          c = await _manage(context, view);
          if (message.kind != MessageKind.attendance) {
            throw const CheckException(CheckError.malformed);
          }
          verified = await _verify(message, c, view);
          trusted = await _trust(c, view);
          final old = await view.read(p.messageId);
          if (old != null &&
              (old.kind != 'attendance' ||
                  base64UrlEncode(old.payload) !=
                      base64UrlEncode(codec.encode(message)))) {
            throw const CheckException(CheckError.duplicateConflict);
          }
        },
        (view) async {
          final existing = await view.read('import:${p.messageId}');
          if (existing != null) {
            return Mutation(
              [],
              [],
              [],
              _row(c.id, existing.id, existing.kind, {
                ..._json(existing),
                'status': 'alreadyReceived',
              }),
            );
          }
          final now = clock.nowUtc().millisecondsSinceEpoch;
          final prior = await view.read('attendance-state:${p.messageId}');
          final existingReceipt = await view.read('receipt:${p.messageId}');
          // Preserve non-sequence evidence. Sequence hints are derived afresh from
          // immutable original punch fields, never unsigned transferred flags.
          final flags = <String>{
            if (existingReceipt != null)
              ...(_json(existingReceipt)['flags'] as List).cast<String>(),
            if (prior != null)
              ...(_json(prior)['flags'] as List).cast<String>(),
          };
          flags.removeAll(_sequenceFlags);
          if (verified.historicalCredential) flags.add('historicalCredential');
          if (p.field<int>('claimedUtcMs') > now + 300000) {
            flags.add('clockAnomaly');
          }
          final staffStates = (await view.list('attendanceState')).where((r) {
            final d = _json(r);
            return d['employeeId'] == p.field<String>('employeeId') &&
                d['source'] == 'staticQr' &&
                d['eventId'] != p.messageId;
          }).toList();
          final currentData = <String, dynamic>{
            ...(prior == null ? _receiptState(message) : _json(prior)),
            'delivery': 'received',
            'receivedUtcMs': now,
            'flags': flags.toList(),
          };
          final sequence = [for (final r in staffStates) _json(r), currentData]
            ..sort((a, b) {
              final order = (a['claimedUtcMs'] as int).compareTo(
                b['claimedUtcMs'] as int,
              );
              return order != 0
                  ? order
                  : (a['eventId'] as String).compareTo(b['eventId'] as String);
            });
          final byEvent = {
            for (final r in staffStates) _json(r)['eventId'] as String: r,
          };
          final duplicateIds = <String>{};
          final previousByKind = <String, Map<String, dynamic>>{};
          for (final d in sequence) {
            final kind = d['originalKind'] as String;
            final previous = previousByKind[kind];
            if (previous != null &&
                (d['claimedUtcMs'] as int) -
                        (previous['claimedUtcMs'] as int) <=
                    120000) {
              duplicateIds
                ..add(d['eventId'] as String)
                ..add(previous['eventId'] as String);
            }
            previousByKind[kind] = d;
          }
          final reconciled = <StoredRecord>[];
          for (var i = 0; i < sequence.length; i++) {
            final d = sequence[i], previous = i == 0 ? null : sequence[i - 1];
            final hints = <String>{...(d['flags'] as List).cast<String>()}
              ..removeAll(_sequenceFlags);
            if (d['originalKind'] == previous?['originalKind']) {
              hints.add('unexpectedOrder');
            }
            if (d['originalKind'] == 'checkOut' &&
                previous?['originalKind'] != 'checkIn') {
              hints.add('missingCheckIn');
            }
            if (d['originalKind'] == 'checkIn' &&
                previous?['originalKind'] == 'checkIn') {
              hints.add('missingCheckOut');
            }
            if (duplicateIds.contains(d['eventId'])) {
              hints.add('possibleDuplicate');
            }
            if (d['eventId'] == p.messageId) {
              flags
                ..clear()
                ..addAll(hints);
            } else {
              final oldFlags = (d['flags'] as List).cast<String>().toSet();
              if (hints.length != oldFlags.length ||
                  !hints.containsAll(oldFlags)) {
                final old = byEvent[d['eventId']]!;
                reconciled.add(
                  _row(c.id, old.id, old.kind, {
                    ...d,
                    'flags': hints.toList(),
                  }, old.revision + 1),
                );
              }
            }
          }
          final ack = await _sign(
            MessageKind.receiptAck,
            [
              c.id,
              ids.next(),
              now,
              p.messageId,
              await _hash(message.payloadBytes),
              now,
              c.authority,
            ],
            c.authoritySigningKeyId,
            AuthorityCertificate(c.authority).publicKey,
          );
          final result = _row(c.id, 'import:${p.messageId}', 'receiptImport', {
            'eventId': p.messageId,
            'status': flags.isEmpty ? 'received' : 'needsReview',
            'wire': base64UrlEncode(codec.encode(ack)),
          });
          final state = _row(
            c.id,
            'attendance-state:${p.messageId}',
            'attendanceState',
            {
              ...(prior == null ? _receiptState(message) : _json(prior)),
              'delivery': 'received',
              'receivedUtcMs': now,
              'flags': flags.toList(),
            },
            (prior?.revision ?? 0) + 1,
          );
          final event = StoredRecord(
            p.messageId,
            c.id,
            'attendance',
            1,
            codec.encode(message),
          );
          final outbox = StoredRecord(
            'outbox:${ack.payload.messageId}',
            c.id,
            'attendanceReturn',
            1,
            codec.encode(ack),
          );
          final receiptRow = _row(
            c.id,
            'receipt:${p.messageId}',
            'attendanceReceipt',
            {
              'bytes': base64UrlEncode(event.payload),
              'delivery': 'received',
              'flags': flags
                  .where((f) => AttendanceFlag.values.any((v) => v.name == f))
                  .toList(),
            },
            (existingReceipt?.revision ?? 0) + 1,
          );
          final credential = trusted.credentials.firstWhere(
            (v) =>
                v.membershipId == p.field<String>('membershipId') &&
                v.membershipRevision == p.field<int>('membershipRevision'),
          );
          final credentialRow = _row(
            c.id,
            'credential:${credential.membershipId}:${credential.membershipRevision}',
            'trustedCredential',
            {
              'companyId': credential.companyId,
              'personId': credential.personId,
              'employeeId': credential.employeeId,
              'installationId': credential.installationId,
              'membershipId': credential.membershipId,
              'membershipRevision': credential.membershipRevision,
              'authorityGenerationId': credential.authorityGenerationId,
              'publicKey': base64UrlEncode(credential.publicKey),
              'retired': credential.retired,
            },
          );
          final person = p.field<String>('personId');
          return Mutation(
            [
              result,
              state,
              ...reconciled,
              receiptRow,
              if (await view.read(credentialRow.id) == null) credentialRow,
            ],
            [if (await view.read(event.id) == null) event],
            [outbox],
            result,
            personalRecords: [
              for (final r in [
                result,
                state,
                receiptRow,
                event,
                outbox,
                credentialRow,
              ])
                PersonalRecordAssociation(person, r.id),
            ],
          );
        },
        (r) {
          final d = _json(r);
          return ImportOutcome(
            ImportStatus.values.byName(d['status'] as String),
            p.messageId,
            returnMessage: _decodeMessage(
              base64Url.decode(d['wire'] as String),
            ),
          );
        },
      );
      if (result is Committed<ImportOutcome>) {
        // A prior import may be returned under a fresh operation as well as replay.
        final outcome = result.value;
        return ImportOutcome(
          result.duplicate ? ImportStatus.alreadyReceived : outcome.status,
          outcome.eventId,
          returnMessage: outcome.returnMessage,
        );
      }
      return ImportOutcome(
        ImportStatus.rejected,
        p.messageId,
        error: result is Rejected<ImportOutcome>
            ? result.error
            : CheckError.invalidTransition,
      );
    } on CheckException catch (e) {
      return ImportOutcome(
        ImportStatus.rejected,
        receipt.message.payload.messageId,
        error: e.code,
      );
    }
  }
}
