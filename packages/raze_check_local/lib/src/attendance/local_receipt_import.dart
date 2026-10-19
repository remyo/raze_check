part of 'local_attendance_service.dart';

extension _ReceiptImport on LocalAttendanceService {
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
          final flags = <String>[];
          if (verified.historicalCredential) flags.add('historicalCredential');
          if (p.field<int>('claimedUtcMs') > now + 300000) {
            flags.add('clockAnomaly');
          }
          for (final r in await view.list('attendanceState')) {
            final d = _json(r);
            if (d['employeeId'] == p.field<String>('employeeId') &&
                d['eventId'] != p.messageId &&
                d['originalKind'] == p.field<String>('kind') &&
                ((d['claimedUtcMs'] as int) - p.field<int>('claimedUtcMs'))
                        .abs() <=
                    120000) {
              flags.add('possibleDuplicate');
              break;
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
          final prior = await view.read('attendance-state:${p.messageId}');
          final state = _row(
            c.id,
            'attendance-state:${p.messageId}',
            'attendanceState',
            {
              ...(prior == null ? _receiptState(message) : _json(prior)),
              'delivery': 'received',
              'receivedUtcMs': now,
              'flags': flags,
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
          final existingReceipt = await view.read('receipt:${p.messageId}');
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
