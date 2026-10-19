import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../database/local_check_repository.dart';
import '../security/local_identity_service.dart';
import '../security/local_key_service.dart';
import '../security/secure_key_store.dart';
import 'local_authority_history.dart';

final class LocalDeviceReplacementService implements DeviceReplacementService {
  LocalDeviceReplacementService({
    required this.repository,
    required this.identity,
    required this.keys,
    required this.clock,
    required this.ids,
  }) : signing = LocalKeyService(keys);
  final LocalCheckRepository repository;
  final LocalIdentityService identity;
  final SecureKeyStore keys;
  final CheckClock clock;
  final IdGenerator ids;
  final KeyService signing;
  final codec = MessageCodec();
  Map<String, dynamic> json(StoredRecord r) =>
      jsonDecode(utf8.decode(r.payload)) as Map<String, dynamic>;
  Uint8List bytes(Object? v) => Uint8List.fromList(utf8.encode(jsonEncode(v)));
  StoredRecord row(
    String c,
    String id,
    String kind,
    Object? data, [
    int revision = 1,
  ]) => StoredRecord(id, c, kind, revision, bytes(data));
  T value<T>(CommandResult<T> r) => switch (r) {
    Committed<T>() => r.value,
    Rejected<T>() => throw CheckException(r.error),
    VersionConflict<T>() => throw const CheckException(
      CheckError.invalidTransition,
    ),
  };
  Future<SignedMessage> sign(
    MessageKind kind,
    List<Object?> fields,
    String key,
    Uint8List public,
  ) async {
    final b = bytes(MessagePayload(kind, fields).values);
    return SignedMessage(
      kind: kind,
      keyId: await messageKeyId(public),
      payloadBytes: b,
      signature: await signing.sign(messageSigningBytes(kind, b), key),
    );
  }

  Future<Company> manage(
    CommandContext c,
    ReadView view, {
    Capability capability = Capability.manageMemberships,
  }) async {
    final a = identity.requireActor(c.session);
    final index = await view.read('member-index:${a.personId}');
    final r = index == null
        ? null
        : await view.read(json(index)['membershipId'] as String);
    if (r == null) throw const CheckException(CheckError.unauthorized);
    final member = Membership.fromJson(json(r));
    AccessPolicy(identity).require(c.session, member, capability);
    if (a.restrictedCompanyId != null) {
      final operator = await view.read('operator:${member.id}');
      if (operator == null ||
          json(operator)['signingKeyId'] != a.signingKeyId) {
        throw const CheckException(CheckError.revokedCredential);
      }
    }
    final company = await view.read(c.companyId);
    if (company == null) throw const CheckException(CheckError.wrongCompany);
    final result = Company.fromJson(json(company));
    if (result.authorityGenerationId != c.authorityGenerationId ||
        result.authoritySigningKeyId.isEmpty) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    await requireCurrentManagement(result, view);
    return result;
  }

  Future<TrustContext> pendingTrust(
    SessionHandle session,
    PendingRecoveryIdentity d,
    ReadView view,
  ) async {
    identity.requireRecoveryIdentity(session, d);
    final actor = identity.requireActor(session);
    final pin = await view.read('enrollment-trust:${actor.personId}');
    final staged = d.publicTrust;
    if (staged == null && pin == null) {
      throw const CheckException(CheckError.unknownIssuer);
    }
    var trust = staged ?? await pinTrust(d.companyId, json(pin!), view);
    if (await rootFingerprint(trust.rootPublicKey) != d.rootFingerprint) {
      throw const CheckException(CheckError.invalidSignature);
    }
    // Revalidate current accepted history on every command, never a stale cache.
    final stored = await view.list('authority');
    for (final batch in AuthorityHistoryFile.batches(
      d.companyId,
      d.rootFingerprint,
      stored
          .map(
            (r) => AuthorityCertificate(
              jsonDecode(utf8.decode(r.payload)) as List<Object?>,
            ),
          )
          .toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence)),
    )) {
      trust = TrustContext(
        companyId: d.companyId,
        rootPublicKey: trust.rootPublicKey,
        authorities: await AuthorityHistoryFile.decode(
          batch,
        ).verify(signing, trust),
      );
    }
    if ((await view.list('authorityConflict')).isNotEmpty) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    return trust;
  }

  Future<String> rootFingerprint(Uint8List root) async => (await Sha256().hash(
    root,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  @override
  Future<VerifiedMessage> verifyPendingGrant(
    SessionHandle session,
    Uint8List bytes, {
    required RecoveryIdentityCandidate candidate,
  }) async {
    final d = identity.requireRecoveryIdentity(session, candidate);
    final message = codec.decode(bytes, maxBytes: MessageLimits.fileBytes);
    if (message.kind != MessageKind.membershipGrant ||
        message.payload.companyId != d.companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final verified = await MessageVerifier(signing).verify(
      message,
      await pendingTrust(
        session,
        d,
        RepositoryReadView(repository, d.companyId),
      ),
    );
    identity.requireRecoveryIdentity(session, candidate);
    return verified;
  }

  @override
  Future<List<StaffRecord>> subjects(
    SessionHandle session,
    String companyId,
  ) async {
    final view = RepositoryReadView(repository, companyId);
    final row = await view.read(companyId);
    if (row == null) throw const CheckException(CheckError.wrongCompany);
    final company = Company.fromJson(json(row));
    final context = CommandContext(
      companyId: companyId,
      session: session,
      operationId: 'replacement-subjects',
      authorityGenerationId: company.authorityGenerationId,
    );
    await manage(context, view);
    final subjects = (await view.list(
      'staff',
    )).map((r) => StaffRecord.fromJson(json(r))).toList();
    await manage(context, view);
    return subjects;
  }

  @override
  Future<SignedMessage> createRequest(
    SessionHandle session,
    String companyId,
    String? employeeId, {
    required RecoveryIdentityCandidate candidate,
  }) async {
    final d = identity.requireRecoveryIdentity(session, candidate);
    if (d.companyId != companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final actor = identity.requireActor(session);
    final pin = await repository.read(
      companyId,
      'enrollment-trust:${actor.personId}',
    );
    if ((employeeId != null && pin == null && d.publicTrust == null) ||
        (pin != null && json(pin)['rootFingerprint'] != d.rootFingerprint)) {
      throw const CheckException(CheckError.unknownIssuer);
    }
    if (d.request != null) {
      if (d.request!.payload.field<String?>('employeeIdOrNull') != employeeId) {
        throw const CheckException(CheckError.duplicateConflict);
      }
      return d.request!;
    }
    final request = await sign(
      MessageKind.replacementRequest,
      [
        companyId,
        ids.next(),
        clock.nowUtc().millisecondsSinceEpoch,
        d.profile.personId,
        employeeId,
        d.profile.installationId,
        base64UrlEncode(d.profile.publicKey),
      ],
      d.profile.signingKeyId,
      d.profile.publicKey,
    );
    identity.requireRecoveryIdentity(session, candidate);
    d.request = request;
    return request;
  }

  @override
  Future<SignedMessage> authorize(
    CommandContext context,
    VerifiedMessage request,
  ) async {
    final message = request.message, p = message.payload;
    if (message.kind != MessageKind.replacementRequest ||
        p.field<String?>('employeeIdOrNull') == null) {
      throw const CheckException(CheckError.malformed);
    }
    if (p.companyId != context.companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final digest = Uint8List.fromList(
          (await Sha256().hash(codec.encode(message))).bytes,
        ),
        approval = 'replacement-approved:${p.messageId}';
    late Company company;
    late Membership member;
    final result = await repository.commit(
      context,
      requestDigest: digest,
      beforeCommit: () => identity.requireActor(context.session),
      authorize: (view) async {
        company = await manage(context, view);
        await MessageVerifier(
          signing,
        ).verify(message, await companyTrust(company, view));
        final index = await view.read(
          'member-index:${p.field<String>('personId')}',
        );
        final r = index == null
            ? null
            : await view.read(json(index)['membershipId'] as String);
        if (r == null) throw const CheckException(CheckError.unauthorized);
        member = Membership.fromJson(json(r));
        if (member.owner ||
            !member.active ||
            member.employeeId != p.field<String>('employeeIdOrNull')) {
          throw const CheckException(CheckError.unauthorized);
        }
        final existing = await view.read(approval);
        if (existing != null) {
          final data = json(existing),
              grant = codec.decode(
                base64Url.decode(data['grant'] as String),
                maxBytes: MessageLimits.fileBytes,
              );
          if (data['request'] != base64UrlEncode(codec.encode(message))) {
            throw const CheckException(CheckError.duplicateConflict);
          }
          if (grant.payload.field<int>('membershipRevision') !=
                  member.revision ||
              AuthorityCertificate(
                    grant.payload.field<List<Object?>>('authority'),
                  ).generationId !=
                  company.authorityGenerationId) {
            throw const CheckException(CheckError.revokedCredential);
          }
        }
      },
      build: (view) async {
        final old = await view.read(approval);
        if (old != null) {
          return Mutation(
            [],
            [],
            [],
            StoredRecord(
              'replacement-result:${p.messageId}',
              context.companyId,
              'message',
              1,
              base64Url.decode(json(old)['grant'] as String),
            ),
          );
        }
        final next = Membership(
          id: member.id,
          companyId: member.companyId,
          personId: member.personId,
          employeeId: member.employeeId,
          owner: false,
          active: true,
          capabilities: member.capabilities,
          revision: member.revision + 1,
        );
        final grant = await sign(
          MessageKind.membershipGrant,
          [
            context.companyId,
            ids.next(),
            clock.nowUtc().millisecondsSinceEpoch,
            p.messageId,
            next.id,
            next.revision,
            next.personId,
            next.employeeId,
            p.field<String>('newInstallationId'),
            p.field<String>('newPublicKeyBase64Url'),
            company.name,
            company.timeZoneId,
            company.workplaceId,
            company.authority,
          ],
          company.authoritySigningKeyId,
          AuthorityCertificate(company.authority).publicKey,
        );
        final credentials = <StoredRecord>[];
        for (final old in await view.list('trustedCredential')) {
          final data = json(old);
          if (data['membershipId'] == next.id && data['retired'] != true) {
            credentials.add(
              row(context.companyId, old.id, old.kind, {
                ...data,
                'retired': true,
              }, old.revision + 1),
            );
          }
        }
        final credential = credentialRow(grant),
            membership = row(
              context.companyId,
              next.id,
              'membership',
              next.toJson(),
              next.revision,
            );
        final result = StoredRecord(
          'replacement-result:${p.messageId}',
          context.companyId,
          'message',
          1,
          codec.encode(grant),
        );
        return Mutation(
          [
            membership,
            ...credentials,
            credential,
            row(context.companyId, approval, 'replacementApproval', {
              'request': base64UrlEncode(codec.encode(message)),
              'grant': base64UrlEncode(codec.encode(grant)),
            }),
          ],
          [
            StoredRecord(
              'replacement-request:${p.messageId}',
              context.companyId,
              'replacementRequest',
              1,
              codec.encode(message),
            ),
          ],
          [
            StoredRecord(
              'outbox:${grant.payload.messageId}',
              context.companyId,
              'message',
              1,
              codec.encode(grant),
            ),
          ],
          result,
          personalRecords: [
            PersonalRecordAssociation(next.personId, membership.id),
            PersonalRecordAssociation(next.personId, credential.id),
          ],
        );
      },
    );
    return codec.decode(
      value(result).payload,
      maxBytes: MessageLimits.fileBytes,
    );
  }

  StoredRecord credentialRow(SignedMessage grant) {
    final p = grant.payload;
    return row(
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

  @override
  Future<CommandResult<Membership>> accept(
    SessionHandle session,
    VerifiedMessage grant, {
    required RecoveryIdentityCandidate candidate,
  }) async {
    try {
      final d = identity.requireRecoveryIdentity(session, candidate),
          message = grant.message,
          p = grant.message.payload;
      if (message.kind != MessageKind.membershipGrant) {
        return const Rejected(CheckError.malformed);
      }
      if (p.companyId != d.companyId) {
        return const Rejected(CheckError.wrongCompany);
      }
      final authority = AuthorityCertificate(
        p.field<List<Object?>>('authority'),
      );
      await MessageVerifier(signing).verify(
        message,
        await pendingTrust(
          session,
          d,
          RepositoryReadView(repository, p.companyId),
        ),
      );
      identity.requireRecoveryIdentity(session, candidate);
      if (await keys.read('vault:${p.companyId}') == null) {
        await VaultKeys(keys).create(p.companyId);
      }
      late Mutation mutation;
      final context = CommandContext(
        companyId: p.companyId,
        session: session,
        operationId: 'replacement-accept:${d.id}',
        authorityGenerationId: authority.generationId,
      );
      final result = await repository.commitRecovery(
        context,
        requestDigest: Uint8List.fromList(
          (await Sha256().hash(codec.encode(message))).bytes,
        ),
        releasePassive: true,
        beforeCommit: () =>
            identity.requireRecoveryIdentity(session, candidate),
        authorize: (view) async {
          identity.requireRecoveryIdentity(session, candidate);
          final lifecycle = await view.read('authority-lifecycle');
          if (lifecycle != null && json(lifecycle)['state'] != 'active') {
            throw const CheckException(CheckError.recoveryRequired);
          }
          final trust = await pendingTrust(session, d, view);
          final pinData = <String, dynamic>{
            'personId': d.profile.personId,
            'rootPublicKey': base64UrlEncode(trust.rootPublicKey),
            'rootFingerprint': d.rootFingerprint,
            'authority': authority.values,
          };
          await MessageVerifier(signing).verify(message, trust);
          if (!trust.authorities.any(
                (a) => jsonEncode(a.values) == jsonEncode(authority.values),
              ) ||
              trust.authorities.last.generationId != authority.generationId) {
            throw const CheckException(CheckError.recoveryRequired);
          }
          final request = d.request;
          if (request == null ||
              p.field<String>('joinOrReplacementRequestId') !=
                  request.payload.messageId ||
              p.field<String>('personId') != d.profile.personId ||
              p.field<String>('employeeId') !=
                  request.payload.field<String?>('employeeIdOrNull') ||
              p.field<String>('installationId') != d.profile.installationId ||
              p.field<String>('publicKeyBase64Url') !=
                  base64UrlEncode(d.profile.publicKey)) {
            throw const CheckException(CheckError.unauthorized);
          }
          final proof = bytes(['replacement-proof', d.id]);
          if (!await signing.verify(
            proof,
            await signing.sign(proof, d.profile.signingKeyId),
            d.profile.publicKey,
          )) {
            throw const CheckException(CheckError.recoveryRequired);
          }
          final member = Membership(
            id: p.field<String>('membershipId'),
            companyId: p.companyId,
            personId: d.profile.personId,
            employeeId: p.field<String>('employeeId'),
            owner: false,
            active: true,
            capabilities: {},
            revision: p.field<int>('membershipRevision'),
          );
          final old = await view.read(member.id),
              index = await view.read('member-index:${member.personId}');
          if (index != null && json(index)['membershipId'] != member.id) {
            throw const CheckException(CheckError.duplicateConflict);
          }
          if (old != null) {
            final prior = Membership.fromJson(json(old));
            if (prior.owner ||
                prior.personId != member.personId ||
                prior.employeeId != member.employeeId ||
                !prior.active ||
                prior.revision > member.revision) {
              throw const CheckException(CheckError.revokedCredential);
            }
            if (prior.revision == member.revision) {
              final c = await view.read(
                'credential:${member.id}:${member.revision}',
              );
              if (c == null ||
                  json(c)['installationId'] != d.profile.installationId ||
                  json(c)['publicKey'] !=
                      base64UrlEncode(d.profile.publicKey)) {
                throw const CheckException(CheckError.duplicateConflict);
              }
            }
          }
          final existingCompany = await view.read(p.companyId);
          final company = Company(
            id: p.companyId,
            name: p.field<String>('companyLabel'),
            timeZoneId: p.field<String>('timeZoneId'),
            workplaceId: p.field<String>('workplaceId'),
            authorityGenerationId: authority.generationId,
            authoritySigningKeyId: '',
            rootPublicKey: pinData['rootPublicKey'] as String,
            rootFingerprint: d.rootFingerprint,
            authority: authority.values,
            creationPersonId: '',
            creationOperationId: '',
            creationDigest: '',
          );
          if (existingCompany != null) {
            final c = Company.fromJson(json(existingCompany));
            if (c.rootFingerprint != d.rootFingerprint ||
                c.workplaceId != company.workplaceId ||
                c.timeZoneId != company.timeZoneId) {
              throw const CheckException(CheckError.duplicateConflict);
            }
            if (!trust.authorities.any(
                  (a) => jsonEncode(a.values) == jsonEncode(c.authority),
                ) ||
                AuthorityCertificate(c.authority).sequence >
                    authority.sequence) {
              throw const CheckException(CheckError.recoveryRequired);
            }
          }
          final staff = await view.read(member.employeeId);
          if (staff != null &&
              (json(staff)['personId'] != member.personId ||
                  json(staff)['membershipId'] != member.id)) {
            throw const CheckException(CheckError.duplicateConflict);
          }
          final credential = credentialRow(message),
              memberRow = row(
                p.companyId,
                member.id,
                'membership',
                member.toJson(),
                member.revision,
              ),
              receipt = identity.recoveryIdentityReceipt(d);
          final priorRemote = await view.read(
            'remote-authority:${member.personId}',
          );
          final rows = <StoredRecord>[
            row(
              p.companyId,
              'remote-authority:${member.personId}',
              'remoteAuthority',
              {'personId': member.personId, 'authority': authority.values},
              (priorRemote?.revision ?? 0) + 1,
            ),
            for (final a in trust.authorities)
              StoredRecord(
                a.generationId,
                p.companyId,
                'authority',
                1,
                bytes(a.values),
              ),
            if (d.consentedInvitation != null)
              StoredRecord(
                'accepted-invitation:${d.consentedInvitation!.payload.messageId}:${member.personId}',
                p.companyId,
                'acceptedInvitation',
                1,
                codec.encode(d.consentedInvitation!),
              ),
            memberRow,
            credential,
            receipt,
            row(
              p.companyId,
              'member-index:${member.personId}',
              'membershipIndex',
              {'membershipId': member.id},
            ),
            row(
              p.companyId,
              'enrollment-trust:${member.personId}',
              'enrollmentTrust',
              pinData,
            ),
            if (existingCompany == null ||
                Company.fromJson(
                  json(existingCompany),
                ).authoritySigningKeyId.isEmpty)
              row(
                p.companyId,
                p.companyId,
                'company',
                company.toJson(),
                (existingCompany?.revision ?? 0) + 1,
              ),
            if (staff == null)
              row(
                p.companyId,
                member.employeeId,
                'staff',
                StaffRecord(
                  employeeId: member.employeeId,
                  companyId: p.companyId,
                  personId: member.personId,
                  membershipId: member.id,
                  details: StaffDraft(name: d.profile.displayName),
                  revision: 1,
                ).toJson(),
              ),
          ];
          for (final c in await view.list('trustedCredential')) {
            if (json(c)['membershipId'] == member.id &&
                c.id != credential.id &&
                json(c)['retired'] != true) {
              rows.add(
                row(p.companyId, c.id, c.kind, {
                  ...json(c),
                  'retired': true,
                }, c.revision + 1),
              );
            }
          }
          final accepted = StoredRecord(
            'accepted-grant:${p.messageId}',
            p.companyId,
            'membershipGrant',
            1,
            codec.encode(message),
          );
          final additions = <StoredRecord>[];
          for (final r in rows) {
            final prior = await view.read(r.id);
            if (prior != null &&
                prior.kind == r.kind &&
                base64UrlEncode(prior.payload) == base64UrlEncode(r.payload)) {
              continue;
            }
            if (prior != null && r.revision <= prior.revision) {
              throw const CheckException(CheckError.duplicateConflict);
            }
            additions.add(r);
          }
          final previousGrant = await view.read(accepted.id);
          if (previousGrant != null &&
              base64UrlEncode(previousGrant.payload) !=
                  base64UrlEncode(accepted.payload)) {
            throw const CheckException(CheckError.duplicateConflict);
          }
          mutation = Mutation(
            additions.where((r) => r.kind != 'authority').toList(),
            [if (previousGrant == null) accepted],
            [],
            memberRow,
            authorityHistory: additions
                .where((r) => r.kind == 'authority')
                .toList(),
            personalRecords: [
              for (final id in {
                ...rows.map((r) => r.id),
                accepted.id,
                p.companyId,
                member.employeeId,
                ...trust.authorities.map((a) => a.generationId),
              })
                PersonalRecordAssociation(member.personId, id),
            ],
          );
        },
        build: (_) async => mutation,
      );
      if (result case Committed<StoredRecord>()) {
        await identity.publishRecoveryIdentity(session, candidate);
        return Committed(
          Membership.fromJson(json(result.value)),
          result.revision,
          result.duplicate,
        );
      }
      return switch (result) {
        Rejected<StoredRecord>() => Rejected(result.error),
        VersionConflict<StoredRecord>() => VersionConflict(
          result.currentRevision,
        ),
        _ => const Rejected(CheckError.storageFailure),
      };
    } on CheckException catch (e) {
      return Rejected(e.code);
    }
  }
}
