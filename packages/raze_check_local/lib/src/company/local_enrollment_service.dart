import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../security/local_key_service.dart';
import '../security/secure_key_store.dart';

/// Offline enrollment over encrypted, transactional local records. Neither
/// decoded messages nor self-signed requests confer company membership.
final class LocalEnrollmentService implements EnrollmentService {
  LocalEnrollmentService({
    required this.repository,
    required this.identity,
    required this.keys,
    required this.clock,
    required this.ids,
  }) : signing = LocalKeyService(keys),
       policy = AccessPolicy(identity);
  final CheckRepository repository;
  final IdentityService identity;
  final SecureKeyStore keys;
  final CheckClock clock;
  final IdGenerator ids;
  final KeyService signing;
  final AccessPolicy policy;
  final codec = MessageCodec();
  Future<void> _pinTail = Future.value();
  static Uint8List _bytes(Object? v) =>
      Uint8List.fromList(utf8.encode(jsonEncode(v)));
  static Map<String, dynamic> _json(StoredRecord r) =>
      jsonDecode(utf8.decode(r.payload)) as Map<String, dynamic>;
  Future<Uint8List> _digest(Object? v) async =>
      Uint8List.fromList((await Sha256().hash(_bytes(v))).bytes);
  Future<String> _fingerprint(Uint8List key) async => (await Sha256().hash(
    key,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  StoredRecord _row(
    String company,
    String id,
    String kind,
    Object? v, [
    int revision = 1,
  ]) => StoredRecord(id, company, kind, revision, _bytes(v));
  StoredRecord _messageRow(SignedMessage m, String id, String kind) =>
      StoredRecord(id, m.payload.companyId, kind, 1, codec.encode(m));
  SignedMessage _decode(StoredRecord r) =>
      codec.decode(r.payload, maxBytes: MessageLimits.fileBytes);
  ActorIdentity _personal(SessionHandle session) {
    final actor = identity.requireActor(session);
    if (actor.restrictedCompanyId != null) {
      throw const CheckException(CheckError.unauthorized);
    }
    return actor;
  }

  @override
  void requireTransferSession(SessionHandle session, {String? companyId}) {
    final actor = identity.requireActor(session);
    if (actor.restrictedCompanyId != null &&
        actor.restrictedCompanyId != companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
  }

  void _live(SessionHandle session) => identity.requireActor(session);
  void _activity(SessionHandle session) {
    if (identity case final ActivityIdentityService activity) {
      try {
        activity.recordActivity(session);
      } on CheckException catch (e) {
        if (e.code != CheckError.locked) rethrow;
      }
    }
  }

  TrustContext _companyTrust(Company company) => TrustContext(
    companyId: company.id,
    rootPublicKey: base64Url.decode(company.rootPublicKey),
    authorities: [AuthorityCertificate(company.authority)],
  );
  TrustContext _pinTrust(String companyId, Map<String, dynamic> pin) =>
      TrustContext(
        companyId: companyId,
        rootPublicKey: base64Url.decode(pin['rootPublicKey'] as String),
        authorities: [
          AuthorityCertificate(List<Object?>.from(pin['authority'] as List)),
        ],
      );
  Future<SignedMessage> _sign(
    MessageKind kind,
    List<Object?> values,
    String keyId,
    Uint8List publicKey,
  ) async {
    final payload = MessagePayload(kind, values);
    final bytes = _bytes(payload.values);
    return SignedMessage(
      kind: kind,
      keyId: await messageKeyId(publicKey),
      payloadBytes: bytes,
      signature: await signing.sign(messageSigningBytes(kind, bytes), keyId),
    );
  }

  Future<Company> _authorize(CommandContext context, ReadView view) async {
    final actor = identity.requireActor(context.session);
    if (actor.restrictedCompanyId != null &&
        actor.restrictedCompanyId != context.companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final index = await view.read('member-index:${actor.personId}');
    final memberRow = index == null
        ? null
        : await view.read(_json(index)['membershipId'] as String);
    if (memberRow == null) throw const CheckException(CheckError.unauthorized);
    final member = Membership.fromJson(_json(memberRow));
    policy.require(context.session, member, Capability.manageStaff);
    if (actor.restrictedCompanyId != null) {
      final credential = await view.read('operator:${member.id}');
      if (credential == null ||
          _json(credential)['signingKeyId'] != actor.signingKeyId) {
        throw const CheckException(CheckError.revokedCredential);
      }
    }
    final row = await view.read(context.companyId);
    if (row == null) throw const CheckException(CheckError.wrongCompany);
    final company = Company.fromJson(_json(row));
    if (company.authorityGenerationId != context.authorityGenerationId ||
        company.authoritySigningKeyId.isEmpty) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    return company;
  }

  Future<T> _value<T>(CommandResult<T> result) async => switch (result) {
    Committed<T>() => result.value,
    Rejected<T>() => throw CheckException(result.error),
    VersionConflict<T>() => throw const CheckException(
      CheckError.invalidTransition,
    ),
  };
  Future<CommandResult<T>> _commit<T>(
    CommandContext context,
    Object intent,
    Future<Mutation> Function(ReadView) build,
    Future<void> Function(ReadView) authorize,
    T Function(StoredRecord) decode,
  ) async {
    try {
      final result = await repository.commit(
        context,
        requestDigest: await _digest(intent),
        build: build,
        authorize: authorize,
        beforeCommit: () => _live(context.session),
      );
      return switch (result) {
        Committed<StoredRecord>() => () {
          _activity(context.session);
          return Committed<T>(
            decode(result.value),
            result.revision,
            result.duplicate,
          );
        }(),
        Rejected<StoredRecord>() => Rejected<T>(result.error),
        VersionConflict<StoredRecord>() => VersionConflict<T>(
          result.currentRevision,
        ),
      };
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }

  @override
  Future<SignedMessage> createInvitation(CommandContext context) async {
    final actor = identity.requireActor(context.session);
    late Company company;
    final result = await _commit(
      context,
      ['invite', actor.personId],
      (view) async {
        final certificate = AuthorityCertificate(company.authority);
        final message = await _sign(
          MessageKind.invitation,
          [
            company.id,
            ids.next(),
            clock.nowUtc().millisecondsSinceEpoch,
            String.fromCharCodes(
              company.name.runes.take(MessageLimits.invitationLabelCharacters),
            ),
            company.timeZoneId,
            company.workplaceId,
            company.rootPublicKey,
            company.authority,
          ],
          company.authoritySigningKeyId,
          certificate.publicKey,
        );
        final row = _messageRow(
          message,
          'invitation:${message.payload.messageId}',
          'enrollmentInvitation',
        );
        return Mutation(
          [row],
          [],
          [
            _messageRow(
              message,
              'outbox:${message.payload.messageId}',
              'message',
            ),
          ],
          row,
        );
      },
      (view) async {
        company = await _authorize(context, view);
      },
      _decode,
    );
    return _value(result);
  }

  @override
  Future<VerifiedMessage> acceptInvitation(
    SessionHandle session,
    Uint8List bytes, {
    required String acceptedRootFingerprint,
  }) async {
    final prior = _pinTail;
    final work = () async {
      await prior;
      final actor = _personal(session);
      final message = codec.decode(bytes, maxBytes: MessageLimits.fileBytes);
      if (message.kind != MessageKind.invitation) {
        throw const CheckException(CheckError.malformed);
      }
      final p = message.payload;
      final root = base64Url.decode(p.field<String>('rootPublicKeyBase64Url'));
      final fingerprint = await _fingerprint(root);
      if (acceptedRootFingerprint != fingerprint) {
        throw const CheckException(CheckError.unauthorized);
      }
      final candidate = TrustContext(
        companyId: p.companyId,
        rootPublicKey: root,
        authorities: [
          AuthorityCertificate(p.field<List<Object?>>('authority')),
        ],
      );
      final verified = await MessageVerifier(
        signing,
      ).verify(message, candidate);
      _personal(session);
      // Provision only after explicit acceptance and cryptographic validation.
      if (await keys.read('vault:${p.companyId}') == null) {
        await VaultKeys(keys).create(p.companyId);
      }
      final context = CommandContext(
        companyId: p.companyId,
        session: session,
        operationId: 'pin:${p.messageId}:${actor.personId}',
        authorityGenerationId: candidate.authorities.single.generationId,
      );
      final pinId = 'enrollment-trust:${actor.personId}';
      final result = await _commit(
        context,
        ['pin', actor.personId, base64UrlEncode(bytes)],
        (_) async {
          final row = _row(p.companyId, pinId, 'enrollmentTrust', {
            'personId': actor.personId,
            'rootPublicKey': base64UrlEncode(root),
            'rootFingerprint': fingerprint,
            'authority': candidate.authorities.single.values,
          });
          final invitation = _messageRow(
            message,
            'accepted-invitation:${p.messageId}:${actor.personId}',
            'acceptedInvitation',
          );
          return Mutation(
            [row, invitation],
            [],
            [],
            row,
            personalRecords: [
              PersonalRecordAssociation(actor.personId, row.id),
              PersonalRecordAssociation(actor.personId, invitation.id),
            ],
            personalOperationOwners: {actor.personId},
          );
        },
        (view) async {
          _personal(session);
          final pin = await view.read(pinId);
          if (pin != null && _json(pin)['rootFingerprint'] != fingerprint) {
            throw const CheckException(CheckError.invalidSignature);
          }
          if (pin != null) {
            await MessageVerifier(
              signing,
            ).verify(message, _pinTrust(p.companyId, _json(pin)));
          }
          final company = await view.read(p.companyId);
          if (company != null &&
              Company.fromJson(_json(company)).rootFingerprint != fingerprint) {
            throw const CheckException(CheckError.invalidSignature);
          }
        },
        (r) => r,
      );
      await _value(result);
      return verified;
    }();
    _pinTail = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }

  @override
  Future<VerifiedMessage> verifyIncoming(
    SessionHandle session,
    Uint8List bytes,
  ) async {
    final actor = identity.requireActor(session);
    final message = codec.decode(bytes, maxBytes: MessageLimits.fileBytes);
    final companyId = message.payload.companyId;
    if (actor.restrictedCompanyId != null &&
        actor.restrictedCompanyId != companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final pin = await repository.read(
      companyId,
      'enrollment-trust:${actor.personId}',
    );
    TrustContext trust;
    if (pin != null) {
      trust = _pinTrust(companyId, _json(pin));
    } else {
      final index = await repository.read(
        companyId,
        'member-index:${actor.personId}',
      );
      final row = index == null
          ? null
          : await repository.read(
              companyId,
              _json(index)['membershipId'] as String,
            );
      if (row == null) throw const CheckException(CheckError.unknownIssuer);
      policy.requireMembership(
        identity.requireActor(session),
        Membership.fromJson(_json(row)),
      );
      final companyRow = await repository.read(companyId, companyId);
      if (companyRow == null) {
        throw const CheckException(CheckError.unknownIssuer);
      }
      trust = _companyTrust(Company.fromJson(_json(companyRow)));
    }
    final verified = await MessageVerifier(signing).verify(message, trust);
    _live(session);
    return verified;
  }

  @override
  Future<SignedMessage> requestJoin(
    SessionHandle session,
    VerifiedMessage invitation,
    String operationId,
  ) async {
    final actor = _personal(session);
    final message = invitation.message;
    if (message.kind != MessageKind.invitation) {
      throw const CheckException(CheckError.malformed);
    }
    final p = message.payload;
    final profile = (await identity.profiles()).firstWhere(
      (p) => p.personId == actor.personId,
    );
    final context = CommandContext(
      companyId: p.companyId,
      session: session,
      operationId: operationId,
      authorityGenerationId: AuthorityCertificate(
        p.field<List<Object?>>('authority'),
      ).generationId,
    );
    final result = await _commit(
      context,
      [
        'join',
        operationId,
        actor.personId,
        actor.installationId,
        base64UrlEncode(actor.publicKey),
        profile.displayName,
        base64UrlEncode(codec.encode(message)),
      ],
      (_) async {
        final join = await _sign(
          MessageKind.joinRequest,
          [
            p.companyId,
            operationId,
            clock.nowUtc().millisecondsSinceEpoch,
            p.messageId,
            actor.personId,
            profile.displayName,
            actor.installationId,
            base64UrlEncode(actor.publicKey),
          ],
          actor.signingKeyId,
          actor.publicKey,
        );
        final pending = _messageRow(
          join,
          'pending-join:$operationId',
          'pendingJoin',
        );
        final outbox = _messageRow(join, 'outbox:$operationId', 'message');
        return Mutation(
          [pending],
          [],
          [outbox],
          pending,
          personalRecords: [
            PersonalRecordAssociation(actor.personId, pending.id),
            PersonalRecordAssociation(actor.personId, outbox.id),
          ],
          personalOperationOwners: {actor.personId},
        );
      },
      (view) async {
        _personal(session);
        final pin = await view.read('enrollment-trust:${actor.personId}');
        final accepted = await view.read(
          'accepted-invitation:${p.messageId}:${actor.personId}',
        );
        if (pin == null ||
            accepted == null ||
            base64UrlEncode(accepted.payload) !=
                base64UrlEncode(codec.encode(message))) {
          throw const CheckException(CheckError.unauthorized);
        }
        await MessageVerifier(
          signing,
        ).verify(message, _pinTrust(p.companyId, _json(pin)));
        if (await view.read('member-index:${actor.personId}') != null) {
          throw const CheckException(CheckError.invalidTransition);
        }
      },
      _decode,
    );
    return _value(result);
  }

  @override
  Future<CommandResult<SignedMessage>> approveJoin(
    CommandContext context,
    VerifiedMessage joinRequest, {
    String? existingEmployeeId,
  }) async {
    try {
      final actor = identity.requireActor(context.session);
      final message = joinRequest.message;
      if (message.kind != MessageKind.joinRequest) {
        return const Rejected(CheckError.malformed);
      }
      final p = message.payload;
      if (p.companyId != context.companyId) {
        return const Rejected(CheckError.wrongCompany);
      }
      final requestHash = base64UrlEncode(
        await _digest([
          base64UrlEncode(codec.encode(message)),
          existingEmployeeId,
        ]),
      );
      final approvalId = 'approved-join:${p.messageId}:${message.keyId}';
      late Company company;
      return _commit(
        context,
        ['approve', actor.personId, requestHash],
        (view) async {
          final previous = await view.read(approvalId);
          if (previous != null) {
            final data = _json(previous);
            if (data['requestHash'] != requestHash) {
              throw const CheckException(CheckError.duplicateConflict);
            }
            return Mutation(
              [],
              [],
              [],
              StoredRecord(
                'grant-result:${p.messageId}',
                context.companyId,
                'message',
                1,
                base64Url.decode(data['grant'] as String),
              ),
            );
          }
          final person = p.field<String>('personId');
          if (await view.read('member-index:$person') != null) {
            throw const CheckException(CheckError.invalidTransition);
          }
          StaffRecord? manual;
          Membership? prior;
          if (existingEmployeeId != null) {
            final index = await view.read('member-index:${actor.personId}');
            final approver = Membership.fromJson(
              _json(
                (await view.read(_json(index!)['membershipId'] as String))!,
              ),
            );
            if (!approver.owner) {
              throw const CheckException(CheckError.unauthorized);
            }
            final staffRow = await view.read(existingEmployeeId);
            if (staffRow == null || staffRow.kind != 'staff') {
              throw const CheckException(CheckError.malformed);
            }
            manual = StaffRecord.fromJson(_json(staffRow));
            prior = Membership.fromJson(
              _json((await view.read(manual.membershipId))!),
            );
            if (prior.owner ||
                !prior.active ||
                prior.capabilities.isNotEmpty ||
                await view.read('operator:${prior.id}') != null ||
                (await view.list(
                  'trustedCredential',
                )).any((r) => _json(r)['membershipId'] == prior!.id)) {
              throw const CheckException(CheckError.invalidTransition);
            }
          }
          final member = Membership(
            id: prior?.id ?? ids.next(),
            companyId: context.companyId,
            personId: person,
            employeeId: manual?.employeeId ?? ids.next(),
            owner: false,
            active: true,
            capabilities: {},
            revision: prior == null ? 1 : prior.revision + 1,
          );
          final staff = StaffRecord(
            employeeId: member.employeeId,
            companyId: context.companyId,
            personId: person,
            membershipId: member.id,
            details:
                manual?.details ??
                StaffDraft(name: p.field<String>('displayName')),
            revision: manual == null ? 1 : manual.revision + 1,
          );
          final grant = await _sign(
            MessageKind.membershipGrant,
            [
              context.companyId,
              ids.next(),
              clock.nowUtc().millisecondsSinceEpoch,
              p.messageId,
              member.id,
              member.revision,
              person,
              member.employeeId,
              p.field<String>('installationId'),
              p.field<String>('publicKeyBase64Url'),
              company.name,
              company.timeZoneId,
              company.workplaceId,
              company.authority,
            ],
            company.authoritySigningKeyId,
            AuthorityCertificate(company.authority).publicKey,
          );
          final result = _messageRow(
            grant,
            'grant-result:${p.messageId}',
            'message',
          );
          final membership = _row(
            context.companyId,
            member.id,
            'membership',
            member.toJson(),
            member.revision,
          );
          final employee = _row(
            context.companyId,
            staff.employeeId,
            'staff',
            staff.toJson(),
            staff.revision,
          );
          final credential = _credentialRow(grant);
          // Only explicit employee linkage transfers manual attendance ownership.
          // Original actor/person/event bytes remain immutable historical evidence.
          final manualHistory = <StoredRecord>[];
          if (manual != null) {
            final manualIds = (await view.list('manualAttendance'))
                .where((r) => _json(r)['employeeId'] == manual!.employeeId)
                .map((r) => r.id)
                .toSet();
            for (final kind in [
              'manualAttendance',
              'attendanceState',
              'attendanceDecisionRecord',
              'correctionResolution',
            ]) {
              for (final r in await view.list(kind)) {
                final data = _json(r);
                if (data['employeeId'] == manual.employeeId &&
                    manualIds.contains(data['eventId'])) {
                  manualHistory.add(r);
                }
              }
            }
          }
          return Mutation(
            [
              membership,
              employee,
              credential,
              _row(
                context.companyId,
                'member-index:$person',
                'membershipIndex',
                {'membershipId': member.id},
              ),
              _row(context.companyId, approvalId, 'approvedJoin', {
                'requestHash': requestHash,
                'grant': base64UrlEncode(codec.encode(grant)),
              }),
            ],
            [
              _messageRow(
                message,
                'approved-request:${p.messageId}:${message.keyId}',
                'enrollmentApproval',
              ),
            ],
            [
              _messageRow(
                grant,
                'outbox:${grant.payload.messageId}',
                'message',
              ),
            ],
            result,
            removePersonalRecords: [
              if (manual != null) ...[
                PersonalRecordAssociation(manual.personId, manual.employeeId),
                PersonalRecordAssociation(manual.personId, manual.membershipId),
                for (final r in manualHistory)
                  PersonalRecordAssociation(manual.personId, r.id),
              ],
            ],
            personalRecords: [
              PersonalRecordAssociation(person, member.id),
              PersonalRecordAssociation(person, employee.id),
              PersonalRecordAssociation(person, credential.id),
              for (final r in manualHistory)
                PersonalRecordAssociation(person, r.id),
            ],
          );
        },
        (view) async {
          company = await _authorize(context, view);
          await MessageVerifier(
            signing,
          ).verify(message, _companyTrust(company));
          final invite = await view.read(
            'invitation:${p.field<String>('invitationId')}',
          );
          if (invite == null ||
              _decode(invite).payload.companyId != context.companyId ||
              AuthorityCertificate(
                    _decode(invite).payload.field<List<Object?>>('authority'),
                  ).generationId !=
                  company.authorityGenerationId) {
            throw const CheckException(CheckError.invalidTransition);
          }
          final prior = await view.read(approvalId);
          if (prior != null && _json(prior)['requestHash'] != requestHash) {
            throw const CheckException(CheckError.duplicateConflict);
          }
        },
        _decode,
      );
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }

  StoredRecord _credentialRow(SignedMessage grant) {
    final p = grant.payload;
    return _row(
      p.companyId,
      'credential:${p.field<String>('membershipId')}:${p.field<int>('membershipRevision')}',
      'trustedCredential',
      {
        'companyId': p.companyId,
        'personId': p.field<String>('personId'),
        'employeeId': p.field<String>('employeeId'),
        'installationId': p.field<String>('installationId'),
        'membershipId': p.field<String>('membershipId'),
        'membershipRevision': p.field<int>('membershipRevision'),
        'authorityGenerationId': AuthorityCertificate(
          p.field<List<Object?>>('authority'),
        ).generationId,
        'publicKey': p.field<String>('publicKeyBase64Url'),
        'retired': false,
      },
    );
  }

  // This plan is built during transaction authorization for fresh commands
  // and replays. Only immutable row data leaves the scoped ReadView callback.
  Future<Mutation> _grantMutation(
    ReadView view,
    ActorIdentity actor,
    SignedMessage message,
    Map<String, dynamic> pin,
    MessagePayload request,
  ) async {
    final p = message.payload;
    final authority = AuthorityCertificate(p.field<List<Object?>>('authority'));
    final member = Membership(
      id: p.field<String>('membershipId'),
      companyId: p.companyId,
      personId: actor.personId,
      employeeId: p.field<String>('employeeId'),
      owner: false,
      active: true,
      capabilities: {},
      revision: p.field<int>('membershipRevision'),
    );
    final company = Company(
      id: p.companyId,
      name: p.field<String>('companyLabel'),
      timeZoneId: p.field<String>('timeZoneId'),
      workplaceId: p.field<String>('workplaceId'),
      authorityGenerationId: authority.generationId,
      authoritySigningKeyId: '',
      rootPublicKey: pin['rootPublicKey'] as String,
      rootFingerprint: pin['rootFingerprint'] as String,
      authority: authority.values,
      creationPersonId: '',
      creationOperationId: '',
      creationDigest: '',
    );
    final memberRow = _row(
      p.companyId,
      member.id,
      'membership',
      member.toJson(),
      member.revision,
    );
    final staff = StaffRecord(
      employeeId: member.employeeId,
      companyId: p.companyId,
      personId: actor.personId,
      membershipId: member.id,
      details: StaffDraft(name: request.field<String>('displayName')),
      revision: 1,
    );

    final records = <StoredRecord>[];
    final historyRows = <StoredRecord>[];
    final events = <StoredRecord>[];
    Future<StoredRecord> reuse(
      StoredRecord candidate,
      List<StoredRecord> additions, {
      void Function(StoredRecord)? validate,
    }) async {
      final stored = await view.read(candidate.id);
      if (stored == null) {
        additions.add(candidate);
        return candidate;
      }
      if (stored.kind != candidate.kind) {
        throw const CheckException(CheckError.duplicateConflict);
      }
      if (validate != null) {
        validate(stored);
      } else if (stored.revision != candidate.revision ||
          !_sameJson(
            jsonDecode(utf8.decode(stored.payload)),
            jsonDecode(utf8.decode(candidate.payload)),
          )) {
        throw const CheckException(CheckError.duplicateConflict);
      }
      return stored;
    }

    final retainedMember = await reuse(memberRow, records);
    final retainedCompany = await reuse(
      _row(p.companyId, company.id, 'company', company.toJson()),
      records,
      validate: (stored) {
        final existing = Company.fromJson(_json(stored));
        if (existing.id != company.id ||
            existing.rootPublicKey != company.rootPublicKey ||
            existing.rootFingerprint != company.rootFingerprint ||
            existing.authorityGenerationId != company.authorityGenerationId ||
            !_sameJson(existing.authority, company.authority) ||
            existing.name != company.name ||
            existing.timeZoneId != company.timeZoneId ||
            existing.workplaceId != company.workplaceId) {
          throw const CheckException(CheckError.recoveryRequired);
        }
        // Keep the local issuer key reference and creation provenance intact.
      },
    );
    final retainedStaff = await reuse(
      _row(p.companyId, staff.employeeId, 'staff', staff.toJson()),
      records,
      validate: (stored) {
        final existing = StaffRecord.fromJson(_json(stored));
        if (existing.employeeId != staff.employeeId ||
            existing.companyId != staff.companyId ||
            existing.personId != staff.personId ||
            existing.membershipId != staff.membershipId ||
            existing.revision != stored.revision) {
          throw const CheckException(CheckError.invalidTransition);
        }
        // Manual record details/revisions are management data, not join input.
      },
    );
    final retainedCredential = await reuse(_credentialRow(message), records);
    final retainedIndex = await reuse(
      _row(p.companyId, 'member-index:${actor.personId}', 'membershipIndex', {
        'membershipId': member.id,
      }),
      records,
    );
    final retainedGrant = await reuse(
      _messageRow(message, 'accepted-grant:${p.messageId}', 'membershipGrant'),
      events,
    );
    final retainedAuthority = await reuse(
      _row(p.companyId, authority.generationId, 'authority', authority.values),
      historyRows,
    );
    return Mutation(
      records,
      events,
      [],
      retainedMember,
      authorityHistory: historyRows,
      personalRecords: [
        for (final row in [
          retainedMember,
          retainedCompany,
          retainedStaff,
          retainedCredential,
          retainedIndex,
          retainedGrant,
          retainedAuthority,
        ])
          PersonalRecordAssociation(actor.personId, row.id),
      ],
      personalOperationOwners: {actor.personId},
    );
  }

  static bool _sameJson(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && _sameJson(a[key], b[key]),
          );
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(
            a.length,
            (i) => _sameJson(a[i], b[i]),
          ).every((equal) => equal);
    }
    return a.runtimeType == b.runtimeType && a == b;
  }

  @override
  Future<CommandResult<Membership>> acceptGrant(
    SessionHandle session,
    VerifiedMessage grant,
  ) async {
    try {
      final actor = _personal(session);
      final message = grant.message;
      if (message.kind != MessageKind.membershipGrant) {
        return const Rejected(CheckError.malformed);
      }
      final p = message.payload;
      final authority = AuthorityCertificate(
        p.field<List<Object?>>('authority'),
      );
      final context = CommandContext(
        companyId: p.companyId,
        session: session,
        operationId:
            'accept-grant:${p.field<String>('joinOrReplacementRequestId')}:${actor.personId}',
        authorityGenerationId: authority.generationId,
      );
      late Map<String, dynamic> pin;
      late Mutation mutation;
      return _commit(
        context,
        [
          'accept-grant',
          actor.personId,
          base64UrlEncode(codec.encode(message)),
        ],
        (_) async => mutation,
        (view) async {
          _personal(session);
          final pinRow = await view.read('enrollment-trust:${actor.personId}');
          if (pinRow == null) {
            throw const CheckException(CheckError.unknownIssuer);
          }
          pin = _json(pinRow);
          await MessageVerifier(
            signing,
          ).verify(message, _pinTrust(p.companyId, pin));
          if (jsonEncode(pin['authority']) != jsonEncode(authority.values)) {
            throw const CheckException(CheckError.recoveryRequired);
          }
          final pending = await view.read(
            'pending-join:${p.field<String>('joinOrReplacementRequestId')}',
          );
          if (pending == null) {
            throw const CheckException(CheckError.invalidTransition);
          }
          final request = _decode(pending).payload;
          if (p.field<String>('personId') != actor.personId ||
              p.field<String>('installationId') != actor.installationId ||
              p.field<String>('publicKeyBase64Url') !=
                  base64UrlEncode(actor.publicKey) ||
              request.field<String>('personId') != actor.personId ||
              request.field<String>('installationId') != actor.installationId ||
              request.field<String>('publicKeyBase64Url') !=
                  base64UrlEncode(actor.publicKey)) {
            throw const CheckException(CheckError.unauthorized);
          }
          final existingIndex = await view.read(
            'member-index:${actor.personId}',
          );
          if (existingIndex != null) {
            final old = Membership.fromJson(
              _json(
                (await view.read(
                  _json(existingIndex)['membershipId'] as String,
                ))!,
              ),
            );
            if (old.id != p.field<String>('membershipId') ||
                old.employeeId != p.field<String>('employeeId') ||
                !old.active ||
                old.revision != p.field<int>('membershipRevision')) {
              throw const CheckException(CheckError.invalidTransition);
            }
          }
          mutation = await _grantMutation(view, actor, message, pin, request);
        },
        (r) => Membership.fromJson(_json(r)),
      );
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }

  @override
  Future<List<SignedMessage>> pendingJoins(SessionHandle session) async {
    final actor = _personal(session);
    final snapshot = await repository.snapshot(PersonalScope(actor.personId));
    final pending = <SignedMessage>[];
    for (final row in snapshot.records.where(
      (row) => row.kind == 'pendingJoin',
    )) {
      final request = _decode(row);
      if (request.payload.field<String>('personId') != actor.personId ||
          request.payload.field<String>('installationId') !=
              actor.installationId ||
          request.payload.field<String>('publicKeyBase64Url') !=
              base64UrlEncode(actor.publicKey)) {
        continue;
      }
      if (await repository.read(
            row.companyId,
            'member-index:${actor.personId}',
          ) ==
          null) {
        pending.add(request);
      }
    }
    _live(session);
    pending.sort(
      (a, b) => b.payload.issuedAtUtcMs.compareTo(a.payload.issuedAtUtcMs),
    );
    return List.unmodifiable(pending);
  }

  @override
  Future<bool> canIssueAttendance(
    SessionHandle session,
    String companyId,
  ) async {
    final actor = _personal(session);
    final index = await repository.read(
      companyId,
      'member-index:${actor.personId}',
    );
    if (index == null) {
      _live(session);
      return false;
    }
    final row = await repository.read(
      companyId,
      _json(index)['membershipId'] as String,
    );
    if (row == null) {
      _live(session);
      return false;
    }
    final member = Membership.fromJson(_json(row));
    if (!member.active || member.personId != actor.personId) return false;
    final credential = await repository.read(
      companyId,
      'credential:${member.id}:${member.revision}',
    );
    if (credential == null && member.owner) {
      final companyRow = await repository.read(companyId, companyId);
      _live(session);
      if (companyRow == null) return false;
      final company = Company.fromJson(_json(companyRow));
      final authority = AuthorityCertificate(company.authority);
      return authority.installationId == actor.installationId &&
          company.authoritySigningKeyId == actor.signingKeyId &&
          base64UrlEncode(authority.publicKey) ==
              base64UrlEncode(actor.publicKey);
    }
    _live(session);
    if (credential == null) return false;
    final c = _json(credential);
    return c['retired'] == false &&
        c['installationId'] == actor.installationId &&
        c['publicKey'] == base64UrlEncode(actor.publicKey);
  }
}
