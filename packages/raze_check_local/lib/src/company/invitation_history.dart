part of 'local_enrollment_service.dart';

final class _InvitationCandidate implements InvitationCandidate {
  _InvitationCandidate(
    this.session,
    this.actor,
    this.message,
    this.root,
    this.fingerprint,
    this.created,
    this.chain,
  );
  final SessionHandle session;
  final ActorIdentity actor;
  final SignedMessage message;
  final Uint8List root;
  final String fingerprint;
  final DateTime created;
  List<AuthorityCertificate> chain;
  int stagedBytes = 0;
  bool busy = false;
}

extension _InvitationHistory on LocalEnrollmentService {
  _InvitationCandidate _candidate(
    SessionHandle session,
    InvitationCandidate opaque,
  ) {
    final c = _candidates[opaque];
    if (c == null || !identical(session, c.session)) {
      throw const CheckException(CheckError.unauthorized);
    }
    final a = _personal(session);
    if (a.personId != c.actor.personId ||
        a.installationId != c.actor.installationId ||
        clock.nowUtc().difference(c.created).isNegative ||
        clock.nowUtc().difference(c.created) >= const Duration(minutes: 5)) {
      _candidates.remove(opaque);
      throw const CheckException(CheckError.locked);
    }
    return c;
  }

  Future<InvitationCandidate> _beginInvitation(
    SessionHandle session,
    Uint8List bytes,
    String fingerprint,
  ) async {
    final actor = _personal(session),
        message = codec.decode(bytes, maxBytes: MessageLimits.fileBytes);
    if (message.kind != MessageKind.invitation) {
      throw const CheckException(CheckError.malformed);
    }
    final p = message.payload,
        root = base64Url.decode(
          message.payload.field<String>('rootPublicKeyBase64Url'),
        );
    if (await _fingerprint(root) != fingerprint) {
      throw const CheckException(CheckError.unauthorized);
    }
    // A new selected invitation replaces previous in-memory consent for this session.
    _candidates.removeWhere((_, c) => identical(c.session, session));
    final view = RepositoryReadView(repository, p.companyId);
    final pin = await view.read('enrollment-trust:${actor.personId}');
    var chain = <AuthorityCertificate>[];
    if (pin != null) {
      if (LocalEnrollmentService._json(pin)['rootFingerprint'] != fingerprint) {
        throw const CheckException(CheckError.invalidSignature);
      }
      chain = (await pinTrust(
        p.companyId,
        LocalEnrollmentService._json(pin),
        view,
      )).authorities;
    }
    final company = await view.read(p.companyId);
    if (company != null) {
      final c = Company.fromJson(LocalEnrollmentService._json(company));
      if (c.rootFingerprint != fingerprint) {
        throw const CheckException(CheckError.invalidSignature);
      }
      chain = (await companyTrust(c, view)).authorities;
    }
    final issuer = AuthorityCertificate(p.field<List<Object?>>('authority'));
    if (issuer.parentGenerationId == null && chain.isEmpty) {
      chain =
          await AuthorityHistoryFile.decode(
            AuthorityHistoryFile.batches(p.companyId, fingerprint, [
              issuer,
            ]).single,
          ).verify(
            signing,
            TrustContext(
              companyId: p.companyId,
              rootPublicKey: root,
              authorities: [],
            ),
          );
    }
    _personal(session);
    final c = _InvitationCandidate(
      session,
      actor,
      message,
      root,
      fingerprint,
      clock.nowUtc(),
      chain,
    );
    _candidates[c] = c;
    return c;
  }

  Future<void> _stageHistory(
    SessionHandle session,
    InvitationCandidate opaque,
    Uint8List bytes,
  ) async {
    final c = _candidate(session, opaque);
    if (c.busy) throw const CheckException(CheckError.invalidTransition);
    c.busy = true;
    try {
      if (c.stagedBytes + bytes.length > 64 * 1024 * 1024 ||
          c.chain.length + 128 > 64 * 1024 * 1024 ~/ 128) {
        throw const CheckException(CheckError.limitExceeded);
      }
      final file = AuthorityHistoryFile.decode(bytes);
      final chain = await file.verify(
        signing,
        TrustContext(
          companyId: c.message.payload.companyId,
          rootPublicKey: c.root,
          authorities: c.chain,
        ),
      );
      _candidate(session, opaque);
      c.chain = chain;
      c.stagedBytes += bytes.length;
    } finally {
      c.busy = false;
    }
  }

  Future<VerifiedMessage> _finishInvitation(
    SessionHandle session,
    InvitationCandidate opaque,
  ) async {
    final c = _candidate(session, opaque);
    if (c.busy) throw const CheckException(CheckError.invalidTransition);
    c.busy = true;
    try {
      final p = c.message.payload,
          issuer = AuthorityCertificate(
            c.message.payload.field<List<Object?>>('authority'),
          );
      final trust = TrustContext(
        companyId: p.companyId,
        rootPublicKey: c.root,
        authorities: c.chain,
      );
      final verified = await MessageVerifier(signing).verify(c.message, trust);
      if (!c.chain.any(
        (a) => jsonEncode(a.values) == jsonEncode(issuer.values),
      )) {
        throw const CheckException(CheckError.unknownIssuer);
      }
      _candidate(session, opaque);
      if (await keys.read('vault:${p.companyId}') == null) {
        await VaultKeys(keys).create(p.companyId);
      }
      final pinId = 'enrollment-trust:${c.actor.personId}';
      final context = CommandContext(
        companyId: p.companyId,
        session: session,
        operationId: 'pin:${p.messageId}:${c.actor.personId}',
        authorityGenerationId: issuer.generationId,
      );
      final result = await _commit(
        context,
        ['pin', c.actor.personId, base64UrlEncode(codec.encode(c.message))],
        (view) async {
          final row = _row(p.companyId, pinId, 'enrollmentTrust', {
            'personId': c.actor.personId,
            'rootPublicKey': base64UrlEncode(c.root),
            'rootFingerprint': c.fingerprint,
            'authority': issuer.values,
          });
          final invitation = _messageRow(
            c.message,
            'accepted-invitation:${p.messageId}:${c.actor.personId}',
            'acceptedInvitation',
          );
          final history = <StoredRecord>[];
          for (final a in c.chain) {
            if (await view.read(a.generationId) == null) {
              history.add(
                _row(p.companyId, a.generationId, 'authority', a.values),
              );
            }
          }
          return Mutation(
            [if (await view.read(pinId) == null) row, invitation],
            [],
            [],
            row,
            authorityHistory: history,
            personalRecords: [
              PersonalRecordAssociation(c.actor.personId, pinId),
              PersonalRecordAssociation(c.actor.personId, invitation.id),
              for (final a in c.chain)
                PersonalRecordAssociation(c.actor.personId, a.generationId),
            ],
            personalOperationOwners: {c.actor.personId},
          );
        },
        (view) async {
          _candidate(session, opaque);
          final pin = await view.read(pinId),
              company = await view.read(p.companyId);
          if ((pin != null &&
                  LocalEnrollmentService._json(pin)['rootFingerprint'] !=
                      c.fingerprint) ||
              (company != null &&
                  Company.fromJson(
                        LocalEnrollmentService._json(company),
                      ).rootFingerprint !=
                      c.fingerprint)) {
            throw const CheckException(CheckError.invalidSignature);
          }
          final current = await view.list('authority');
          var known =
              current
                  .map(
                    (r) => AuthorityCertificate(
                      List<Object?>.from(
                        jsonDecode(utf8.decode(r.payload)) as List,
                      ),
                    ),
                  )
                  .toList()
                ..sort((a, b) => a.sequence.compareTo(b.sequence));
          for (final batch in AuthorityHistoryFile.batches(
            p.companyId,
            c.fingerprint,
            c.chain,
          )) {
            known = await AuthorityHistoryFile.decode(batch).verify(
              signing,
              TrustContext(
                companyId: p.companyId,
                rootPublicKey: c.root,
                authorities: known,
              ),
            );
          }
          await MessageVerifier(signing).verify(
            c.message,
            TrustContext(
              companyId: p.companyId,
              rootPublicKey: c.root,
              authorities: known,
            ),
          );
        },
        (r) => r,
      );
      await _value(result);
      _candidates.remove(opaque);
      return verified;
    } finally {
      c.busy = false;
    }
  }
}
