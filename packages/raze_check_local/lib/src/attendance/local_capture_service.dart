import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../security/local_key_service.dart';
import 'attendance_authorization.dart';
import '../security/secure_key_store.dart';

/// All issuance authorization is inside the repository transaction, on both
/// fresh writes and journal replays. Incoming VerifiedMessage is never trusted.
final class LocalCaptureService implements CaptureService {
  LocalCaptureService({
    required this.repository,
    required this.identity,
    required SecureKeyStore keys,
    required this.clock,
    required this.ids,
    int Function()? offsetMinutes,
  }) : signing = LocalKeyService(keys),
       offsetMinutes =
           offsetMinutes ?? (() => DateTime.now().timeZoneOffset.inMinutes);
  final CheckRepository repository;
  final IdentityService identity;
  final CheckClock clock;
  final IdGenerator ids;
  final KeyService signing;
  final int Function() offsetMinutes;
  final codec = MessageCodec();
  static Uint8List _bytes(Object? v) =>
      Uint8List.fromList(utf8.encode(jsonEncode(v)));
  static Map<String, dynamic> _json(StoredRecord r) =>
      jsonDecode(utf8.decode(r.payload)) as Map<String, dynamic>;
  StoredRecord _row(
    String company,
    String id,
    String kind,
    Object? v, [
    int revision = 1,
  ]) => StoredRecord(id, company, kind, revision, _bytes(v));
  Future<Uint8List> _digest(Object v) async =>
      Uint8List.fromList((await Sha256().hash(_bytes(v))).bytes);
  late final authorization = AttendanceAuthorization(identity);
  ActorIdentity _actor(SessionHandle session) =>
      authorization.requirePersonal(session);

  void _live(SessionHandle session) => identity.requireActor(session);
  TrustContext _trust(Company c) => TrustContext(
    companyId: c.id,
    rootPublicKey: base64Url.decode(c.rootPublicKey),
    authorities: [AuthorityCertificate(c.authority)],
  );

  Future<void> _workplace(SignedMessage message, Company company) async {
    if (message.kind != MessageKind.workplace) {
      throw const CheckException(CheckError.malformed);
    }
    if (message.payload.companyId != company.id) {
      throw const CheckException(CheckError.wrongCompany);
    }
    await MessageVerifier(signing).verify(message, _trust(company));
    if (message.payload.field<String>('workplaceId') != company.workplaceId ||
        AuthorityCertificate(
              message.payload.field<List<Object?>>('authority'),
            ).generationId !=
            company.authorityGenerationId) {
      throw const CheckException(CheckError.recoveryRequired);
    }
  }

  Future<SignedMessage> _sign(
    MessageKind kind,
    List<Object?> values,
    String key,
    Uint8List public,
  ) async {
    final payload = _bytes(MessagePayload(kind, values).values);
    return SignedMessage(
      kind: kind,
      keyId: await messageKeyId(public),
      payloadBytes: payload,
      signature: await signing.sign(messageSigningBytes(kind, payload), key),
    );
  }

  Future<CommandResult<StoredRecord>> _commit(
    CommandContext context,
    Object intent,
    Future<Mutation> Function(ReadView) build,
    Future<void> Function(ReadView) authorize,
  ) async {
    try {
      final result = await repository.commit(
        context,
        requestDigest: await _digest(intent),
        build: build,
        authorize: authorize,
        beforeCommit: () => _live(context.session),
      );
      if (result is Committed && identity is ActivityIdentityService) {
        try {
          (identity as ActivityIdentityService).recordActivity(context.session);
        } on CheckException catch (e) {
          if (e.code != CheckError.locked) rethrow;
        }
      }
      return result;
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }

  StoredRecord _value(CommandResult<StoredRecord> result) => switch (result) {
    Committed<StoredRecord>() => result.value,
    Rejected<StoredRecord>() => throw CheckException(result.error),
    VersionConflict<StoredRecord>() => throw const CheckException(
      CheckError.invalidTransition,
    ),
  };
  AttendanceReceipt _receipt(StoredRecord r) {
    final data = _json(r);
    return AttendanceReceipt(
      bytes: base64Url.decode(data['bytes'] as String),
      delivery: DeliveryStatus.values.byName(data['delivery'] as String),
      flags: (data['flags'] as List)
          .map((f) => AttendanceFlag.values.byName(f as String))
          .toSet(),
    );
  }

  CaptureDraft _draft(StoredRecord row) {
    final d = _json(row);
    return CaptureDraft(
      companyId: row.companyId,
      authorityGenerationId: d['authorityGenerationId'] as String,
      operationId: d['operationId'] as String,
      kind: PunchKind.values.byName(d['kind'] as String),
      workplaceBytes: base64Url.decode(d['workplace'] as String),
      eventId: d['eventId'] as String?,
    );
  }

  @override
  Future<SignedMessage> createWorkplaceCode(CommandContext context) async {
    final actor = identity.requireActor(context.session);
    late Company company;
    final result = await _commit(
      context,
      ['workplace', actor.personId],
      (_) async {
        final id = ids.next();
        final signed = await _sign(
          MessageKind.workplace,
          [
            company.id,
            id,
            clock.nowUtc().millisecondsSinceEpoch,
            company.workplaceId,
            id,
            company.authority,
          ],
          company.authoritySigningKeyId,
          AuthorityCertificate(company.authority).publicKey,
        );
        final row = StoredRecord(
          'workplace:$id',
          company.id,
          'workplaceCode',
          1,
          codec.encode(signed),
        );
        return Mutation([row], [], [], row);
      },
      (view) async {
        // Management operators may display a code only with manageCompany (owner).
        final index = await view.read('member-index:${actor.personId}');
        final row = index == null
            ? null
            : await view.read(_json(index)['membershipId'] as String);
        if (row == null) throw const CheckException(CheckError.unauthorized);
        AccessPolicy(identity).require(
          context.session,
          Membership.fromJson(_json(row)),
          Capability.manageCompany,
        );
        final c = await view.read(context.companyId);
        if (c == null) throw const CheckException(CheckError.wrongCompany);
        company = Company.fromJson(_json(c));
        if (company.authorityGenerationId != context.authorityGenerationId ||
            company.authoritySigningKeyId.isEmpty ||
            AuthorityCertificate(company.authority).installationId !=
                actor.installationId) {
          throw const CheckException(CheckError.recoveryRequired);
        }
      },
    );
    return codec.decode(
      _value(result).payload,
      maxBytes: MessageLimits.fileBytes,
    );
  }

  @override
  Future<VerifiedMessage> verifyWorkplace(
    SessionHandle session,
    String companyId,
    Uint8List bytes,
  ) async {
    final a = await authorization.require(
      session,
      companyId,
      (id) => repository.read(companyId, id),
    );
    final signed = codec.decode(bytes, maxBytes: MessageLimits.fileBytes);
    await _workplace(signed, a.company);
    final result = await MessageVerifier(
      signing,
    ).verify(signed, _trust(a.company));
    _live(session);
    return result;
  }

  @override
  Future<CaptureDraft> beginDraft(
    SessionHandle session,
    String companyId,
    VerifiedMessage workplace,
    PunchKind kind,
  ) async {
    final actor = _actor(session);
    if (workplace.message.kind != MessageKind.workplace) {
      throw const CheckException(CheckError.malformed);
    }
    if (workplace.message.payload.companyId != companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final op = ids.next();
    final authority = AuthorityCertificate(
      workplace.message.payload.field<List<Object?>>('authority'),
    ).generationId;
    final context = CommandContext(
      companyId: companyId,
      session: session,
      operationId: 'begin:$op',
      authorityGenerationId: authority,
    );
    final wire = base64UrlEncode(codec.encode(workplace.message));
    final result = await _commit(
      context,
      ['begin-capture', actor.personId, kind.name, wire],
      (view) async {
        final slotId = 'capture-slot:${actor.personId}';
        final slot = await view.read(slotId);
        final previous = slot == null
            ? null
            : _json(slot)['operationId'] as String?;
        if (previous != null) {
          final row = (await view.read('capture-intent:$previous'))!;
          final d = _json(row);
          if (d['kind'] != kind.name ||
              d['workplace'] != wire ||
              d['installationId'] != actor.installationId) {
            throw const CheckException(CheckError.invalidTransition);
          }
          return Mutation(
            [],
            [],
            [],
            row,
            personalRecords: [
              PersonalRecordAssociation(actor.personId, row.id),
            ],
            personalOperationOwners: {actor.personId},
          );
        }
        final row = _row(companyId, 'capture-intent:$op', 'captureDraft', {
          'personId': actor.personId,
          'installationId': actor.installationId,
          'operationId': op,
          'authorityGenerationId': authority,
          'kind': kind.name,
          'workplace': wire,
          'eventId': null,
        });
        final slotRow = _row(companyId, slotId, 'captureSlot', {
          'operationId': op,
        }, (slot?.revision ?? 0) + 1);
        return Mutation(
          [row, slotRow],
          [],
          [],
          row,
          personalRecords: [
            PersonalRecordAssociation(actor.personId, row.id),
            PersonalRecordAssociation(actor.personId, slotId),
          ],
          personalOperationOwners: {actor.personId},
        );
      },
      (view) async {
        final a = await authorization.require(
          session,
          companyId,
          view.read,
          generation: authority,
        );
        await _workplace(workplace.message, a.company);
      },
    );
    return _draft(_value(result));
  }

  @override
  Future<CaptureDraft?> currentDraft(
    SessionHandle session,
    String companyId,
  ) async {
    final a = await authorization.require(
      session,
      companyId,
      (id) => repository.read(companyId, id),
      issue: false,
    );
    final slot = await repository.read(
      companyId,
      'capture-slot:${a.actor.personId}',
    );
    final op = slot == null ? null : _json(slot)['operationId'] as String?;
    final row = op == null
        ? null
        : await repository.read(companyId, 'capture-intent:$op');
    _live(session);
    if (row == null) return null;
    if (_json(row)['personId'] != a.actor.personId ||
        _json(row)['installationId'] != a.actor.installationId) {
      throw const CheckException(CheckError.revokedCredential);
    }
    return _draft(row);
  }

  @override
  Future<void> finishDraft(
    SessionHandle session,
    String companyId,
    String eventId,
  ) async {
    final actor = _actor(session);
    final receipt = await getReceipt(session, companyId, eventId);
    final a = await authorization.require(
      session,
      companyId,
      (id) => repository.read(companyId, id),
      issue: false,
    );
    final context = CommandContext(
      companyId: companyId,
      session: session,
      operationId: 'finish-capture:$eventId',
      authorityGenerationId: a.company.authorityGenerationId,
    );
    final result = await _commit(
      context,
      ['finish-capture', actor.personId, receipt.eventId],
      (view) async {
        final slotId = 'capture-slot:${actor.personId}';
        final slot = await view.read(slotId);
        final op = slot == null ? null : _json(slot)['operationId'] as String?;
        final intent = op == null
            ? null
            : await view.read('capture-intent:$op');
        if (intent == null || _json(intent)['eventId'] != eventId) {
          throw const CheckException(CheckError.invalidTransition);
        }
        final row = _row(companyId, slotId, 'captureSlot', {
          'operationId': null,
        }, slot!.revision + 1);
        return Mutation(
          [row],
          [],
          [],
          row,
          personalRecords: [PersonalRecordAssociation(actor.personId, row.id)],
          personalOperationOwners: {actor.personId},
        );
      },
      (view) async {
        await authorization.require(
          session,
          companyId,
          view.read,
          issue: false,
        );
      },
    );
    _value(result);
  }

  @override
  Future<CommandResult<AttendanceReceipt>> recordPunch(
    CommandContext context,
    VerifiedMessage workplace,
    PunchKind kind,
  ) async {
    try {
      final actor = _actor(context.session);
      final wire = base64UrlEncode(codec.encode(workplace.message));
      late Membership member;
      final result = await _commit(
        context,
        ['capture', actor.personId, actor.installationId, kind.name, wire],
        (view) async {
          final now = clock.nowUtc().millisecondsSinceEpoch;
          final eventId = ids.next();
          final offset = offsetMinutes();
          final message = await _sign(
            MessageKind.attendance,
            [
              context.companyId,
              eventId,
              now,
              actor.personId,
              member.employeeId,
              member.id,
              member.revision,
              actor.installationId,
              kind.name,
              now,
              offset,
              workplace.message.payload.field<String>('workplaceId'),
              workplace.message.payload.field<String>('codeId'),
              context.authorityGenerationId,
              'staticQr',
            ],
            actor.signingKeyId,
            actor.publicKey,
          );
          final history =
              (await view.list('attendanceReceipt'))
                  .map(_receipt)
                  .where((r) => r.personId == actor.personId)
                  .toList()
                ..sort((a, b) => a.claimedUtcMs.compareTo(b.claimedUtcMs));
          final flags = <AttendanceFlag>{};
          if (history.any(
            (r) => r.kind == kind && (now - r.claimedUtcMs).abs() <= 120000,
          )) {
            flags.add(AttendanceFlag.possibleDuplicate);
          }
          final prior = history.lastOrNull;
          if (prior != null &&
              (prior.kind == kind || now < prior.claimedUtcMs)) {
            flags.add(AttendanceFlag.unexpectedOrder);
          }
          if (kind == PunchKind.checkOut &&
              (prior == null || prior.kind != PunchKind.checkIn)) {
            flags.add(AttendanceFlag.missingCheckIn);
          }
          if (kind == PunchKind.checkIn && prior?.kind == PunchKind.checkIn) {
            flags.add(AttendanceFlag.missingCheckOut);
          }
          final event = StoredRecord(
            eventId,
            context.companyId,
            'attendance',
            1,
            codec.encode(message),
          );
          final receipt =
              _row(context.companyId, 'receipt:$eventId', 'attendanceReceipt', {
                'bytes': base64UrlEncode(event.payload),
                'delivery': DeliveryStatus.localOnly.name,
                'flags': flags.map((f) => f.name).toList(),
              });
          final outbox = StoredRecord(
            'outbox:$eventId',
            context.companyId,
            'attendanceOutbox',
            1,
            event.payload,
          );
          final draft = (await view.read(
            'capture-intent:${context.operationId}',
          ))!;
          final updated = _row(context.companyId, draft.id, 'captureDraft', {
            ..._json(draft),
            'eventId': eventId,
          }, draft.revision + 1);
          return Mutation(
            [receipt, updated],
            [event],
            [outbox],
            receipt,
            personalRecords: [
              for (final r in [receipt, updated, event, outbox])
                PersonalRecordAssociation(actor.personId, r.id),
            ],
            personalOperationOwners: {actor.personId},
          );
        },
        (view) async {
          final a = await authorization.require(
            context.session,
            context.companyId,
            view.read,
            generation: context.authorityGenerationId,
          );
          member = a.member;
          await _workplace(workplace.message, a.company);
          final draft = await view.read(
            'capture-intent:${context.operationId}',
          );
          if (draft == null) {
            throw const CheckException(CheckError.invalidTransition);
          }
          final d = _json(draft);
          if (d['personId'] != actor.personId ||
              d['installationId'] != actor.installationId ||
              d['kind'] != kind.name ||
              d['workplace'] != wire ||
              d['authorityGenerationId'] != context.authorityGenerationId) {
            throw const CheckException(CheckError.duplicateConflict);
          }
        },
      );
      return switch (result) {
        Committed<StoredRecord>() => Committed(
          _receipt(result.value),
          result.revision,
          result.duplicate,
        ),
        Rejected<StoredRecord>() => Rejected(result.error),
        VersionConflict<StoredRecord>() => VersionConflict(
          result.currentRevision,
        ),
      };
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }

  @override
  Future<AttendanceReceipt> getReceipt(
    SessionHandle session,
    String companyId,
    String eventId,
  ) async {
    final actor = _actor(session);
    final row = await repository.read(companyId, 'receipt:$eventId');
    if (row == null) throw const CheckException(CheckError.malformed);
    final receipt = _receipt(row);
    if (receipt.companyId != companyId || receipt.personId != actor.personId) {
      throw const CheckException(CheckError.unauthorized);
    }
    _live(session);
    return receipt;
  }

  @override
  Future<List<AttendanceReceipt>> listOutbox(
    SessionHandle session,
    String companyId,
  ) async {
    final actor = _actor(session);
    await authorization.require(
      session,
      companyId,
      (id) => repository.read(companyId, id),
      issue: false,
    );
    final snapshot = await repository.snapshot(PersonalScope(actor.personId));
    final result =
        snapshot.records
            .where(
              (r) => r.companyId == companyId && r.kind == 'attendanceReceipt',
            )
            .map(_receipt)
            .where(
              (r) =>
                  r.personId == actor.personId &&
                  r.delivery == DeliveryStatus.localOnly,
            )
            .toList()
          ..sort((a, b) => b.claimedUtcMs.compareTo(a.claimedUtcMs));
    _live(session);
    return List.unmodifiable(result);
  }
}
