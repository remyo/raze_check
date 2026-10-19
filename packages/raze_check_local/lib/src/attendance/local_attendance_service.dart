import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../security/local_key_service.dart';
import '../security/secure_key_store.dart';
import 'attendance_authorization.dart';
import '../recovery/local_authority_history.dart';

part 'local_receipt_import.dart';
part 'local_attendance_review.dart';
part 'local_attendance_updates.dart';

/// A shared transaction boundary for review, import and return exchange.
/// Every incoming proof is reverified against durable trust inside authorization.
final class LocalAttendanceService implements AttendanceService {
  LocalAttendanceService({
    required this.repository,
    required this.identity,
    required SecureKeyStore keys,
    required this.clock,
    required this.ids,
  }) : signing = LocalKeyService(keys);
  final CheckRepository repository;
  final IdentityService identity;
  final CheckClock clock;
  final IdGenerator ids;
  final KeyService signing;
  final codec = MessageCodec();
  @override
  Future<ImportOutcome> importReceipt(
    CommandContext context,
    VerifiedMessage receipt,
  ) => _importReceipt(context, receipt);
  @override
  Future<CommandResult<AttendanceRecord>> recordManual(
    CommandContext context,
    ManualPunch draft,
  ) => _recordManual(context, draft);
  @override
  Future<CommandResult<DecisionRecord>> decide(
    CommandContext context,
    String eventId,
    ReviewDecision decision,
    String reason,
  ) => _decide(context, eventId, decision, reason);
  @override
  Future<CommandResult<CorrectionRecord>> correct(
    CommandContext context,
    String eventId,
    ProposedCorrection change,
    String reason,
  ) => _correct(context, eventId, change, reason);
  @override
  Future<SignedMessage> request(
    SessionHandle session,
    String companyId,
    String eventId,
    ProposedCorrection change,
    String operationId,
  ) => _request(session, companyId, eventId, change, operationId);
  @override
  Future<CommandResult<CorrectionRecord>> resolve(
    CommandContext context,
    VerifiedMessage request,
    bool approve,
    String reason,
  ) => _resolve(context, request, approve, reason);
  @override
  Future<CommandResult<AttendanceRecord>> accept(
    SessionHandle session,
    VerifiedMessage update,
  ) => _accept(session, update);

  Uint8List _bytes(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));
  Map<String, dynamic> _json(StoredRecord row) =>
      jsonDecode(utf8.decode(row.payload)) as Map<String, dynamic>;
  StoredRecord _row(
    String company,
    String id,
    String kind,
    Object value, [
    int revision = 1,
  ]) => StoredRecord(id, company, kind, revision, _bytes(value));
  Future<String> _hash(Uint8List value) async =>
      base64UrlEncode((await Sha256().hash(value)).bytes);
  Future<Company> _company(String id, ReadView view) async {
    final r = await view.read(id);
    if (r == null || r.kind != 'company') {
      throw const CheckException(CheckError.wrongCompany);
    }
    return Company.fromJson(_json(r));
  }

  Future<Membership> _membership(
    SessionHandle session,
    String companyId,
    ReadView view,
  ) async {
    final a = identity.requireActor(session);
    a.requireCompany(companyId);
    if (a.restrictedCompanyId != null && a.restrictedCompanyId != companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final index = await view.read('member-index:${a.personId}');
    final r = index == null
        ? null
        : await view.read(_json(index)['membershipId'] as String);
    if (r == null) throw const CheckException(CheckError.unauthorized);
    final m = Membership.fromJson(_json(r));
    if (m.companyId != companyId || m.personId != a.personId) {
      throw const CheckException(CheckError.unauthorized);
    }
    return m;
  }

  Future<Company> _manage(CommandContext context, ReadView view) async {
    AccessPolicy(identity).require(
      context.session,
      await _membership(context.session, context.companyId, view),
      Capability.reviewAttendance,
    );
    final c = await _company(context.companyId, view);
    if (c.authorityGenerationId != context.authorityGenerationId ||
        c.authoritySigningKeyId.isEmpty) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    await requireCurrentManagement(c, view);
    // The local signing reference must still belong to the certified installation.
    if (!await signing.verify(
      _bytes(['attendance-authority', c.id]),
      await signing.sign(
        _bytes(['attendance-authority', c.id]),
        c.authoritySigningKeyId,
      ),
      AuthorityCertificate(c.authority).publicKey,
    )) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    return c;
  }

  Future<TrustContext> _trust(Company c, ReadView view) async {
    final credentials = <TrustedCredential>[];
    for (final r in await view.list('trustedCredential')) {
      final d = _json(r);
      final m = await view.read(d['membershipId'] as String);
      final member = m == null ? null : Membership.fromJson(_json(m));
      credentials.add(
        TrustedCredential(
          companyId: d['companyId'] as String,
          personId: d['personId'] as String,
          employeeId: d['employeeId'] as String,
          installationId: d['installationId'] as String,
          membershipId: d['membershipId'] as String,
          membershipRevision: d['membershipRevision'] as int,
          authorityGenerationId: d['authorityGenerationId'] as String,
          publicKey: base64Url.decode(d['publicKey'] as String),
          retired:
              d['retired'] == true ||
              member == null ||
              !member.active ||
              member.revision != d['membershipRevision'],
        ),
      );
    }
    // Owning-authority personal capture has no enrollment grant; derive its exact
    // credential from stored membership and authenticated authority, never wire data.
    for (final r in await view.list('membership')) {
      final m = Membership.fromJson(_json(r));
      if (m.owner &&
          !credentials.any(
            (v) => v.membershipId == m.id && v.membershipRevision == m.revision,
          )) {
        final a = AuthorityCertificate(c.authority);
        credentials.add(
          TrustedCredential(
            companyId: c.id,
            personId: m.personId,
            employeeId: m.employeeId,
            installationId: a.installationId,
            membershipId: m.id,
            membershipRevision: m.revision,
            authorityGenerationId: a.generationId,
            publicKey: a.publicKey,
            retired: !m.active,
          ),
        );
      }
    }
    final authorities = (await view.list('authority'))
        .map(
          (r) => AuthorityCertificate(
            List<Object?>.from(jsonDecode(utf8.decode(r.payload)) as List),
          ),
        )
        .toList();
    if (!authorities.any((a) => a.generationId == c.authorityGenerationId)) {
      authorities.add(AuthorityCertificate(c.authority));
    }
    return TrustContext(
      companyId: c.id,
      rootPublicKey: base64Url.decode(c.rootPublicKey),
      authorities: authorities,
      credentials: credentials,
    );
  }

  Future<VerifiedMessage> _verify(
    SignedMessage message,
    Company c,
    ReadView view,
  ) async {
    final verified = await MessageVerifier(
      signing,
    ).verify(message, await _trust(c, view));
    if ([
      MessageKind.receiptAck,
      MessageKind.attendanceDecision,
    ].contains(message.kind)) {
      final authority = AuthorityCertificate(
        message.payload.field<List<Object?>>('authority'),
      );
      final known = await view.read(authority.generationId);
      if (known == null ||
          known.kind != 'authority' ||
          jsonEncode(authority.values) != utf8.decode(known.payload)) {
        throw const CheckException(CheckError.recoveryRequired);
      }
    }
    return verified;
  }

  @override
  Future<VerifiedMessage> verifyIncoming(
    SessionHandle session,
    String companyId,
    Uint8List input,
  ) async {
    final view = _QueryView(repository, companyId);
    await _membership(session, companyId, view);
    final result = await _verify(
      codec.decode(input, maxBytes: MessageLimits.fileBytes),
      await _company(companyId, view),
      view,
    );
    identity.requireActor(session);
    return result;
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

  Future<CommandResult<T>> _commit<T>(
    CommandContext context,
    Object intent,
    Future<void> Function(ReadView) authorize,
    Future<Mutation> Function(ReadView) build,
    T Function(StoredRecord) decode,
  ) async {
    try {
      identity.requireActor(context.session);
      final result = await repository.commit(
        context,
        requestDigest: Uint8List.fromList(
          (await Sha256().hash(_bytes(intent))).bytes,
        ),
        authorize: authorize,
        build: build,
        beforeCommit: () => identity.requireActor(context.session),
      );
      if (result is Committed && identity is ActivityIdentityService) {
        try {
          (identity as ActivityIdentityService).recordActivity(context.session);
        } on CheckException catch (e) {
          if (e.code != CheckError.locked) rethrow;
        }
      }
      return switch (result) {
        Committed<StoredRecord>() => Committed(
          decode(result.value),
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

  T _value<T>(CommandResult<T> r) => switch (r) {
    Committed<T>() => r.value,
    Rejected<T>() => throw CheckException(r.error),
    VersionConflict<T>() => throw const CheckException(
      CheckError.invalidTransition,
    ),
  };
  SignedMessage _decodeMessage(Uint8List b) =>
      codec.decode(b, maxBytes: MessageLimits.fileBytes);
  DecisionRecord _decision(StoredRecord r) {
    final d = _json(r);
    return DecisionRecord(
      d,
      returnMessage: d['wire'] == null
          ? null
          : _decodeMessage(base64Url.decode(d['wire'] as String)),
    );
  }

  Future<StoredRecord> _projection(String eventId, ReadView view) async {
    final existing = await view.read('attendance-state:$eventId');
    if (existing != null) return existing;
    final receipt = await view.read('receipt:$eventId');
    if (receipt == null) throw const CheckException(CheckError.malformed);
    final d = _json(receipt),
        m = _decodeMessage(base64Url.decode(d['bytes'] as String));
    return _row(
      receipt.companyId,
      'attendance-state:$eventId',
      'attendanceState',
      _receiptState(
        m,
        delivery: d['delivery'] as String,
        flags: (d['flags'] as List).cast<String>(),
      ),
      0,
    );
  }

  Map<String, dynamic> _receiptState(
    SignedMessage m, {
    String delivery = 'localOnly',
    List<String> flags = const [],
    int? received,
  }) {
    final p = m.payload;
    return {
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
      'delivery': delivery,
      'receivedUtcMs': received,
      'decisionRevision': 0,
      'flags': flags.toSet().toList(),
    };
  }

  Future<String> _subject(StoredRecord projection, ReadView view) async {
    final d = _json(projection);
    final staff = await view.read(d['employeeId'] as String);
    if (staff == null || staff.kind != 'staff') {
      throw const CheckException(CheckError.unauthorized);
    }
    return StaffRecord.fromJson(_json(staff)).personId;
  }

  Future<void> _access(
    SessionHandle session,
    String companyId,
    StoredRecord r,
    ReadView view,
  ) async {
    final m = await _membership(session, companyId, view);
    final actor = identity.requireActor(session);
    if (actor.restrictedCompanyId == null &&
        await _subject(r, view) == actor.personId) {
      return;
    }
    AccessPolicy(identity).require(session, m, Capability.reviewAttendance);
  }

  @override
  Future<List<AttendanceSubject>> subjects(
    SessionHandle session,
    String companyId,
  ) async {
    final view = _QueryView(repository, companyId);
    AccessPolicy(identity).require(
      session,
      await _membership(session, companyId, view),
      Capability.reviewAttendance,
    );
    final result = (await view.list('staff')).map((r) {
      final s = StaffRecord.fromJson(_json(r));
      return AttendanceSubject(s.employeeId, s.details.name);
    }).toList();
    identity.requireActor(session);
    return List.unmodifiable(result);
  }

  @override
  Future<AttendanceRecord> get(
    SessionHandle session,
    String companyId,
    String eventId,
  ) async {
    final view = _QueryView(repository, companyId);
    final r = await _projection(eventId, view);
    await _access(session, companyId, r, view);
    identity.requireActor(session);
    return AttendanceRecord(_json(r));
  }

  @override
  Future<List<AttendanceRecord>> list(
    SessionHandle session,
    String companyId,
  ) async {
    final view = _QueryView(repository, companyId);
    final m = await _membership(session, companyId, view);
    final actor = identity.requireActor(session);
    var manager = false;
    try {
      AccessPolicy(identity).require(session, m, Capability.reviewAttendance);
      manager = true;
    } on CheckException {
      if (actor.restrictedCompanyId != null) rethrow;
    }
    final snapshot = await repository.snapshot(
      manager ? CompanyScope(companyId) : PersonalScope(actor.personId),
    );
    final records = <String, StoredRecord>{
      for (final r in snapshot.records.where(
        (r) => r.companyId == companyId && r.kind == 'attendanceState',
      ))
        _json(r)['eventId'] as String: r,
    };
    for (final r in snapshot.records.where(
      (r) => r.companyId == companyId && r.kind == 'attendanceReceipt',
    )) {
      final msg = _decodeMessage(base64Url.decode(_json(r)['bytes'] as String));
      records.putIfAbsent(
        msg.payload.messageId,
        () => _row(
          companyId,
          'attendance-state:${msg.payload.messageId}',
          'attendanceState',
          _receiptState(
            msg,
            delivery: _json(r)['delivery'] as String,
            flags: (_json(r)['flags'] as List).cast<String>(),
          ),
        ),
      );
    }
    final result = <AttendanceRecord>[];
    for (final r in records.values) {
      if (manager || await _subject(r, view) == actor.personId) {
        result.add(AttendanceRecord(_json(r)));
      }
    }
    identity.requireActor(session);
    return List.unmodifiable(
      result..sort((a, b) => b.claimedUtcMs.compareTo(a.claimedUtcMs)),
    );
  }

  @override
  Future<List<DecisionRecord>> history(
    SessionHandle session,
    String companyId,
    String eventId,
  ) async {
    final view = _QueryView(repository, companyId);
    await _access(session, companyId, await _projection(eventId, view), view);
    final records =
        (await view.list('attendanceDecisionRecord'))
            .where((r) => _json(r)['eventId'] == eventId)
            .map(_decision)
            .toList()
          ..sort((a, b) => a.revision.compareTo(b.revision));
    identity.requireActor(session);
    return List.unmodifiable(records);
  }

  void _validateChange(PunchKind kind, int utc, int offset, String reason) {
    if (reason.trim().isEmpty ||
        reason.runes.length > MessageLimits.reasonCharacters ||
        utc.abs() > MessageLimits.maxUtcMs ||
        offset < -840 ||
        offset > 840) {
      throw const CheckException(CheckError.malformed);
    }
  }

  @override
  Future<List<SignedMessage>> exchangeMessages(
    SessionHandle session,
    String companyId,
    String eventId,
  ) async {
    final view = _QueryView(repository, companyId);
    final state = await _projection(eventId, view);
    await _access(session, companyId, state, view);
    if (_json(state)['source'] != 'staticQr') return const [];
    final result = <SignedMessage>[];
    for (final kind in ['attendanceReturn', 'correctionRequest']) {
      for (final row in await view.list(kind)) {
        final message = _decodeMessage(row.payload);
        if (message.payload.field<String>('eventId') == eventId) {
          result.add(message);
        }
      }
    }
    result.sort(
      (a, b) => a.payload.issuedAtUtcMs.compareTo(b.payload.issuedAtUtcMs),
    );
    identity.requireActor(session);
    return List.unmodifiable(result);
  }
}

/// Query-only scoped view. Mutations always use the repository's live ReadView.
final class _QueryView implements ReadView {
  _QueryView(this.repository, this.companyId);
  final CheckRepository repository;
  final String companyId;
  @override
  Future<StoredRecord?> read(String id) => repository.read(companyId, id);
  @override
  Future<List<StoredRecord>> list(String kind) =>
      RepositoryReadView(repository, companyId).list(kind);
}
