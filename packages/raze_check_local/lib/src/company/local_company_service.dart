import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../database/local_check_repository.dart';
import '../security/local_identity_service.dart';
import '../security/local_key_service.dart';
import '../security/secure_key_store.dart';
import '../recovery/local_authority_history.dart';

/// Domain commands over the real encrypted journal. No UI role is trusted.
final class LocalCompanyService implements CompanyService {
  LocalCompanyService({
    required this.repository,
    required this.identity,
    required this.keys,
    required this.clock,
    required this.ids,
  }) : policy = AccessPolicy(identity);
  final LocalCheckRepository repository;
  final LocalIdentityService identity;
  final SecureKeyStore keys;
  final CheckClock clock;
  final IdGenerator ids;
  final AccessPolicy policy;
  Future<void> _creationTail = Future.value();
  static Uint8List _bytes(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));
  static Map<String, dynamic> _json(StoredRecord row) =>
      jsonDecode(utf8.decode(row.payload)) as Map<String, dynamic>;
  Future<Uint8List> _digest(Object value) async =>
      Uint8List.fromList((await Sha256().hash(_bytes(value))).bytes);
  StoredRecord _row(
    String company,
    String id,
    String kind,
    Object value, [
    int revision = 1,
  ]) => StoredRecord(id, company, kind, revision, _bytes(value));
  String _index(String person) => 'member-index:$person';
  void _companyRestriction(ActorIdentity actor, String company) {
    actor.requireCompany(company);
    if (actor.restrictedCompanyId != null &&
        actor.restrictedCompanyId != company) {
      throw const CheckException(CheckError.wrongCompany);
    }
  }

  Future<Membership?> _membership(
    SessionHandle session,
    String company, [
    ReadView? view,
  ]) async {
    final actor = identity.requireActor(session);
    _companyRestriction(actor, company);
    final index = await (view == null
        ? repository.read(company, _index(actor.personId))
        : view.read(_index(actor.personId)));
    if (index == null) return null;
    final id = _json(index)['membershipId'] as String;
    final row = await (view == null
        ? repository.read(company, id)
        : view.read(id));
    if (row == null) return null;
    final member = Membership.fromJson(_json(row));
    if (actor.restrictedCompanyId != null) {
      final credentialRow = await (view == null
          ? repository.read(company, 'operator:${member.id}')
          : view.read('operator:${member.id}'));
      if (credentialRow == null ||
          _json(credentialRow)['signingKeyId'] != actor.signingKeyId) {
        throw const CheckException(CheckError.revokedCredential);
      }
    }
    policy.requireMembership(identity.requireActor(session), member);
    return member;
  }

  @override
  Future<Membership?> membership(SessionHandle session, String companyId) =>
      _membership(session, companyId);
  Future<Membership> _authorize(
    CommandContext context,
    Capability capability, [
    ReadView? view,
  ]) async {
    final member = await _membership(context.session, context.companyId, view);
    if (member == null) throw const CheckException(CheckError.unauthorized);
    policy.require(context.session, member, capability);
    final row = await (view == null
        ? repository.read(context.companyId, context.companyId)
        : view.read(context.companyId));
    if (row == null ||
        Company.fromJson(_json(row)).authorityGenerationId !=
            context.authorityGenerationId) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    await requireCurrentManagement(
      Company.fromJson(_json(row)),
      view ?? RepositoryReadView(repository, context.companyId),
    );
    return member;
  }

  Future<CommandResult<T>> _convert<T>(
    Future<CommandResult<StoredRecord>> action,
    T Function(Map<String, dynamic>) decode,
    SessionHandle session,
  ) async {
    final result = await action;
    switch (result) {
      case Committed<StoredRecord>():
        // Acceptance already occurred. A later lock hides the UI but cannot
        // relabel the durable command as rejected. Failed commits do not touch
        // activity; a live successful result does.
        try {
          identity.recordActivity(session);
        } on CheckException catch (e) {
          if (e.code != CheckError.locked) rethrow;
        }
        return Committed(
          decode(_json(result.value)),
          result.revision,
          result.duplicate,
        );
      case Rejected<StoredRecord>():
        return Rejected(result.error);
      case VersionConflict<StoredRecord>():
        return VersionConflict(result.currentRevision);
    }
  }

  Future<CommandResult<T>> _guard<T>(
    Future<CommandResult<T>> Function() action,
  ) async {
    try {
      return await action();
    } on CheckException catch (e) {
      return Rejected(e.code);
    } catch (_) {
      return const Rejected(CheckError.storageFailure);
    }
  }

  @override
  Future<CommandResult<Company>> createCompany(
    SessionHandle session,
    CompanyDraft draft,
    String operationId,
  ) => _guard(() async {
    final previous = _creationTail;
    final done = Completer<void>();
    _creationTail = done.future;
    await previous;
    try {
      final actor = identity.requireActor(session);
      if (actor.restrictedCompanyId != null) {
        throw const CheckException(CheckError.unauthorized);
      }
      if (draft.name.trim().isEmpty ||
          draft.name.runes.length > 200 ||
          !CompanyTimeZones.all.contains(draft.timeZoneId) ||
          operationId.isEmpty) {
        throw const CheckException(CheckError.malformed);
      }
      final digest = await _digest([
        'createCompany',
        actor.personId,
        draft.name.trim(),
        draft.timeZoneId,
      ]);
      final reservation = await repository.reserveCompanyCreation(
        personId: actor.personId,
        operationId: operationId,
        requestDigest: digest,
        ids: ids,
      );
      final companyId = reservation.companyId;
      await identity.completeCreatedCompanyBinding(actor, companyId);
      if (await keys.read('vault:$companyId') == null) {
        await VaultKeys(keys).create(companyId);
      }
      identity.requireActor(session);
      final context = CommandContext(
        companyId: companyId,
        session: session,
        operationId: operationId,
        authorityGenerationId: reservation.authorityGenerationId,
      );
      final accepted = await _convert(
        repository.commit(
          context,
          requestDigest: digest,
          authorize: (view) async {
            final current = identity.requireActor(session);
            if (current.restrictedCompanyId != null) {
              throw const CheckException(CheckError.unauthorized);
            }
            if (await view.read(companyId) != null) {
              await _authorize(context, Capability.manageCompany, view);
            }
          },
          beforeCommit: () => identity.requireActor(session),
          build: (view) async {
            if (await view.read(companyId) != null) {
              throw const CheckException(CheckError.duplicateConflict);
            }
            final current = identity.requireActor(session);
            if (current.restrictedCompanyId != null) {
              throw const CheckException(CheckError.unauthorized);
            }
            final rootKeyId = 'company-root:$companyId';
            final signing = LocalKeyService(keys);
            Uint8List rootPublic;
            final seed = await keys.read(rootKeyId);
            if (seed == null) {
              rootPublic = await signing.create(rootKeyId);
            } else {
              rootPublic = Uint8List.fromList(
                (await (await Ed25519().newKeyPairFromSeed(
                  seed,
                )).extractPublicKey()).bytes,
              );
            }
            final generation = reservation.authorityGenerationId;
            final employee = ids.next();
            final memberId = ids.next();
            final authority = <Object?>[
              generation,
              null,
              1,
              current.installationId,
              base64UrlEncode(current.publicKey),
              clock.nowUtc().millisecondsSinceEpoch,
            ];
            final signature = await signing.sign(
              Uint8List.fromList(
                utf8.encode(
                  'RAZE_CHECK_AUTHORITY_V1\n${jsonEncode(authority)}',
                ),
              ),
              rootKeyId,
            );
            authority.add(base64UrlEncode(signature));
            final fingerprint = (await Sha256().hash(
              rootPublic,
            )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
            final company = Company(
              id: companyId,
              name: draft.name.trim(),
              timeZoneId: draft.timeZoneId,
              workplaceId: ids.next(),
              authorityGenerationId: generation,
              authoritySigningKeyId: current.signingKeyId,
              rootPublicKey: base64UrlEncode(rootPublic),
              rootFingerprint: fingerprint,
              authority: List.unmodifiable(authority),
              creationPersonId: current.personId,
              creationOperationId: operationId,
              creationDigest: base64Encode(digest),
            );
            final owner = Membership(
              id: memberId,
              companyId: companyId,
              personId: current.personId,
              employeeId: employee,
              owner: true,
              active: true,
              capabilities: Capability.values.toSet(),
              revision: 1,
            );
            final profiles = await identity.profiles();
            final ownerName = profiles
                .firstWhere((p) => p.personId == current.personId)
                .displayName;
            final staff = StaffRecord(
              employeeId: employee,
              companyId: companyId,
              personId: current.personId,
              membershipId: memberId,
              details: StaffDraft(name: ownerName),
              revision: 1,
            );
            final result = _row(
              companyId,
              companyId,
              'company',
              company.toJson(),
            );
            final authorityRecord = _row(
              companyId,
              generation,
              'authority',
              authority,
            );
            final recovery = _row(
              companyId,
              'recovery-root:$companyId',
              'companyRootRecovery',
              {
                'keyId': rootKeyId,
                'seed': base64Encode((await keys.read(rootKeyId))!),
                'publicKey': base64UrlEncode(rootPublic),
              },
            );
            identity.requireActor(session);
            return Mutation(
              [
                result,
                _row(companyId, owner.id, 'membership', owner.toJson()),
                _row(companyId, _index(owner.personId), 'membershipIndex', {
                  'membershipId': owner.id,
                }),
                _row(companyId, employee, 'staff', staff.toJson()),
              ],
              [
                _row(
                  companyId,
                  'installation-binding:${current.installationId}',
                  'installationBinding',
                  {
                    'reason': 'createdCompany',
                    'personId': current.personId,
                    'installationId': current.installationId,
                    'publicKey': base64UrlEncode(current.publicKey),
                    'operationId': operationId,
                    'digest': base64Encode(digest),
                    'generationId': generation,
                    'signature': base64UrlEncode(
                      await signing.sign(
                        Uint8List.fromList(
                          utf8.encode(
                            'RAZE_CHECK_LOCAL_COMPANY_BINDING_V1\n${jsonEncode([companyId, current.personId, current.installationId, base64UrlEncode(current.publicKey), operationId, base64Encode(digest), generation])}',
                          ),
                        ),
                        current.signingKeyId,
                      ),
                    ),
                  },
                ),
              ],
              [],
              result,
              authorityHistory: [authorityRecord],
              recovery: [recovery],
              personalRecords: [
                PersonalRecordAssociation(owner.personId, companyId),
                PersonalRecordAssociation(
                  owner.personId,
                  'installation-binding:${current.installationId}',
                ),
                PersonalRecordAssociation(owner.personId, owner.id),
                PersonalRecordAssociation(owner.personId, employee),
                PersonalRecordAssociation(owner.personId, authorityRecord.id),
              ],
            );
          },
        ),
        Company.fromJson,
        session,
      );
      if (accepted is Committed<Company>) {
        await identity.completeCreatedCompanyBinding(actor, companyId);
      }
      return accepted;
    } finally {
      done.complete();
    }
  });
  @override
  Future<Company?> readCompany(SessionHandle session, String companyId) async {
    try {
      if (await _membership(session, companyId) == null) return null;
      final row = await repository.read(companyId, companyId);
      if (await _membership(session, companyId) == null) return null;
      if (row == null) return null;
      identity.recordActivity(session);
      return Company.fromJson(_json(row));
    } on CheckException catch (e) {
      if (e.code == CheckError.wrongCompany ||
          e.code == CheckError.unauthorized) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<List<Company>> listCompanies(SessionHandle session) async {
    final actor = identity.requireActor(session);
    final companyIds = actor.restrictedCompanyId == null
        ? await repository.listCompanyIds()
        : [actor.restrictedCompanyId!];
    final companies = <Company>[];
    for (final id in companyIds) {
      if (actor.authorizedCompanyIds != null &&
          !actor.authorizedCompanyIds!.contains(id)) {
        continue;
      }
      final company = await readCompany(session, id);
      if (company != null) companies.add(company);
    }
    identity.requireActor(session);
    return List.unmodifiable(companies);
  }

  Future<List<StoredRecord>> _list(
    SessionHandle session,
    String companyId,
    String kind,
  ) async {
    final member = await _membership(session, companyId);
    if (member == null) throw const CheckException(CheckError.unauthorized);
    policy.require(session, member, Capability.manageStaff);
    final rows = await repository.listRecords(companyId, kind);
    final fresh = await _membership(session, companyId);
    if (fresh == null) throw const CheckException(CheckError.unauthorized);
    policy.require(session, fresh, Capability.manageStaff);
    identity.recordActivity(session);
    return rows;
  }

  @override
  Future<List<StaffRecord>> listStaff(
    SessionHandle session,
    String companyId,
  ) async => (await _list(
    session,
    companyId,
    'staff',
  )).map((r) => StaffRecord.fromJson(_json(r))).toList(growable: false);
  @override
  Future<List<Membership>> listMemberships(
    SessionHandle session,
    String companyId,
  ) async => (await _list(
    session,
    companyId,
    'membership',
  )).map((r) => Membership.fromJson(_json(r))).toList(growable: false);
  void _validateStaff(StaffDraft draft) {
    if (draft.name.trim().isEmpty ||
        draft.name.runes.length > 200 ||
        draft.toJson().values.whereType<String>().any(
          (s) => s.runes.length > 1000,
        )) {
      throw const CheckException(CheckError.malformed);
    }
    for (final text in [draft.birthday, draft.joiningDate]) {
      if (text == null || text.isEmpty) continue;
      final date = DateTime.tryParse(text);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
          date == null ||
          date.toIso8601String().substring(0, 10) != text) {
        throw const CheckException(CheckError.malformed);
      }
    }
  }

  Future<CommandResult<T>> _command<T>(
    CommandContext context,
    Capability capability,
    Object intent,
    T Function(Map<String, dynamic>) decode,
    Future<Mutation> Function(ReadView, Membership) build,
  ) => _guard(() async {
    final actor = identity.requireActor(context.session);
    await _authorize(context, capability);
    final digest = await _digest([
      actor.personId,
      actor.restrictedCompanyId,
      actor.restrictedMembershipId,
      intent,
    ]);
    late Membership authorizedMember;
    return _convert(
      repository.commit(
        context,
        requestDigest: digest,
        authorize: (view) async {
          authorizedMember = await _authorize(context, capability, view);
        },
        beforeCommit: () => identity.requireActor(context.session),
        build: (view) async {
          final mutation = await build(view, authorizedMember);
          await _authorize(context, capability, view);
          return mutation;
        },
      ),
      decode,
      context.session,
    );
  });
  @override
  Future<CommandResult<StaffRecord>> createStaff(
    CommandContext context,
    StaffDraft draft,
  ) => _command(
    context,
    Capability.manageStaff,
    ['createStaff', draft.toJson()],
    StaffRecord.fromJson,
    (view, actor) async {
      _validateStaff(draft);
      final staff = StaffRecord(
        employeeId: ids.next(),
        companyId: context.companyId,
        personId: ids.next(),
        membershipId: ids.next(),
        details: StaffDraft.fromJson(draft.toJson()),
        revision: 1,
      );
      final member = Membership(
        id: staff.membershipId,
        companyId: context.companyId,
        personId: staff.personId,
        employeeId: staff.employeeId,
        owner: false,
        active: true,
        capabilities: {},
        revision: 1,
      );
      final result = _row(
        context.companyId,
        staff.employeeId,
        'staff',
        staff.toJson(),
      );
      return Mutation(
        [
          result,
          _row(context.companyId, member.id, 'membership', member.toJson()),
          _row(context.companyId, _index(staff.personId), 'membershipIndex', {
            'membershipId': member.id,
          }),
        ],
        [],
        [],
        result,
        personalRecords: [
          PersonalRecordAssociation(staff.personId, staff.employeeId),
          PersonalRecordAssociation(staff.personId, member.id),
        ],
      );
    },
  );
  @override
  Future<CommandResult<StaffRecord>> updateStaff(
    CommandContext context,
    StaffUpdate update,
  ) => _command(
    context,
    Capability.manageStaff,
    ['updateStaff', update.employeeId, update.draft.toJson()],
    StaffRecord.fromJson,
    (view, actor) async {
      _validateStaff(update.draft);
      final row = await view.read(update.employeeId);
      if (row == null || row.kind != 'staff') {
        throw const CheckException(CheckError.unauthorized);
      }
      final old = StaffRecord.fromJson(_json(row));
      final edited = StaffRecord(
        employeeId: old.employeeId,
        companyId: old.companyId,
        personId: old.personId,
        membershipId: old.membershipId,
        details: StaffDraft.fromJson(update.draft.toJson()),
        revision: old.revision + 1,
      );
      final result = _row(
        context.companyId,
        old.employeeId,
        'staff',
        edited.toJson(),
        edited.revision,
      );
      return Mutation([result], [], [], result);
    },
  );
  Future<Membership> _target(ReadView view, String id) async {
    final row = await view.read(id);
    if (row == null || row.kind != 'membership') {
      throw const CheckException(CheckError.unauthorized);
    }
    return Membership.fromJson(_json(row));
  }

  StoredRecord _history(
    CommandContext context,
    Membership actor,
    String kind,
    Membership target,
    Object detail,
  ) => _row(context.companyId, ids.next(), 'permissionChange', {
    'action': kind,
    'actorPersonId': actor.personId,
    'membershipId': target.id,
    'utcMs': clock.nowUtc().millisecondsSinceEpoch,
    'previous': target.toJson(),
    'detail': detail,
  });
  @override
  Future<CommandResult<Membership>> grantCapabilities(
    CommandContext context,
    String membershipId,
    Set<Capability> capabilities,
  ) {
    final caps = Set<Capability>.of(capabilities);
    return _command(
      context,
      Capability.manageCompany,
      [
        'grantCapabilities',
        membershipId,
        (caps.map((c) => c.name).toList()..sort()),
      ],
      Membership.fromJson,
      (view, actor) async {
        final old = await _target(view, membershipId);
        if (!old.active ||
            old.owner ||
            caps.any(AccessPolicy.ownerOnly.contains)) {
          throw const CheckException(CheckError.unauthorized);
        }
        final next = Membership(
          id: old.id,
          companyId: old.companyId,
          personId: old.personId,
          employeeId: old.employeeId,
          owner: false,
          active: old.active,
          capabilities: caps,
          revision: old.revision + 1,
        );
        final result = _row(
          context.companyId,
          old.id,
          'membership',
          next.toJson(),
          next.revision,
        );
        return Mutation(
          [result],
          [_history(context, actor, 'grant', old, next.toJson())],
          [],
          result,
        );
      },
    );
  }

  @override
  Future<CommandResult<OperatorCredential>> activateOperator(
    CommandContext context,
    String membershipId,
    String passphrase,
  ) => _guard(() async {
    if (passphrase.runes.length < 12) {
      throw const CheckException(CheckError.wrongSecret);
    }
    // Digest includes a salted-by-context cryptographic commitment, never a stored passphrase.
    final secretDigest = base64Encode(
      await _digest([
        'operatorSecret',
        context.companyId,
        context.operationId,
        passphrase,
      ]),
    );
    String? allocatedKeyId;
    final commandResult = await _command(
      context,
      Capability.manageCompany,
      ['activateOperator', membershipId, secretDigest],
      OperatorCredential.fromJson,
      (view, actor) async {
        final member = await _target(view, membershipId);
        if (!member.active || member.owner) {
          throw const CheckException(CheckError.unauthorized);
        }
        final salt = secureRandomBytes(16);
        final verifier = await operatorVerifier(passphrase, salt);
        final keyId = 'operator-signing:${ids.next()}';
        final publicKey = await LocalKeyService(keys).create(keyId);
        allocatedKeyId = keyId;
        final credential = OperatorCredential(
          id: 'operator:$membershipId',
          companyId: context.companyId,
          membershipId: membershipId,
          personId: member.personId,
        );
        final old = await view.read(credential.id);
        final company = Company.fromJson(
          _json((await view.read(context.companyId))!),
        );
        final result = _row(
          context.companyId,
          credential.id,
          'operatorCredential',
          {
            ...credential.toJson(),
            'salt': base64Encode(salt),
            'verifier': base64Encode(verifier),
            'signingKeyId': keyId,
            'publicKey': base64UrlEncode(publicKey),
            'installationId': company.authority[3],
          },
          (old?.revision ?? 0) + 1,
        );
        return Mutation(
          [result],
          [
            _history(context, actor, 'activateOperator', member, {
              'credentialId': credential.id,
            }),
          ],
          [],
          result,
        );
      },
    );
    if (commandResult is! Committed<OperatorCredential> &&
        allocatedKeyId != null) {
      try {
        await keys.delete(allocatedKeyId!);
      } catch (_) {
        // Cleanup cannot change the original command outcome. An uncommitted
        // orphan key grants no access; preserve the rejection for safe retry.
      }
    }
    return commandResult;
  });
  @override
  Future<List<OperatorChoice>> operatorChoices() async {
    final choices = <OperatorChoice>[];
    for (final companyId in await repository.listCompanyIds()) {
      final credentials = await repository.listRecords(
        companyId,
        'operatorCredential',
      );
      if (credentials.isEmpty) continue;
      final companyRow = await repository.read(companyId, companyId);
      if (companyRow == null) continue;
      final company = Company.fromJson(_json(companyRow));
      for (final credentialRow in credentials) {
        final credential = OperatorCredential.fromJson(_json(credentialRow));
        final memberRow = await repository.read(
          companyId,
          credential.membershipId,
        );
        if (memberRow == null) continue;
        final member = Membership.fromJson(_json(memberRow));
        if (!member.active) continue;
        final staffRow = await repository.read(companyId, member.employeeId);
        if (staffRow == null) continue;
        final staff = StaffRecord.fromJson(_json(staffRow));
        choices.add(
          OperatorChoice(
            companyId: companyId,
            companyName: company.name,
            membershipId: member.id,
            displayName: staff.details.name,
          ),
        );
      }
    }
    return List.unmodifiable(choices);
  }

  @override
  Future<SessionHandle> unlockOperator(
    String companyId,
    String membershipId,
    String passphrase,
  ) => identity.unlockOperator(companyId, membershipId, passphrase);
  @override
  Future<CommandResult<Membership>> deactivateStaff(
    CommandContext context,
    String employeeId,
    String reason,
  ) => _command(
    context,
    Capability.manageStaff,
    ['deactivateStaff', employeeId, reason.trim()],
    Membership.fromJson,
    (view, actor) async {
      if (reason.trim().isEmpty || reason.runes.length > 1000) {
        throw const CheckException(CheckError.malformed);
      }
      final staffRow = await view.read(employeeId);
      if (staffRow == null || staffRow.kind != 'staff') {
        throw const CheckException(CheckError.unauthorized);
      }
      final staff = StaffRecord.fromJson(_json(staffRow));
      final old = await _target(view, staff.membershipId);
      if (old.owner || !old.active) {
        throw const CheckException(CheckError.unauthorized);
      }
      final next = Membership(
        id: old.id,
        companyId: old.companyId,
        personId: old.personId,
        employeeId: old.employeeId,
        owner: false,
        active: false,
        capabilities: old.capabilities,
        revision: old.revision + 1,
      );
      final result = _row(
        context.companyId,
        old.id,
        'membership',
        next.toJson(),
        next.revision,
      );
      return Mutation(
        [result],
        [
          _history(context, actor, 'deactivate', old, {
            'reason': reason.trim(),
            'next': next.toJson(),
          }),
        ],
        [],
        result,
      );
    },
  );
}
