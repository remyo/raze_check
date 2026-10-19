part of 'local_identity_service.dart';

/// Local-adapter object; core/UI only hold RecoveryIdentityCandidate.
final class PendingRecoveryIdentity implements RecoveryIdentityCandidate {
  PendingRecoveryIdentity(
    this.id,
    this.session,
    this.profile,
    this.companyId,
    this.rootFingerprint,
    this.credential,
    this.created, {
    this.continuation = false,
  });
  final bool continuation;
  final String id, companyId, rootFingerprint;
  final SessionHandle session;
  final LocalProfile profile;
  final Uint8List credential;
  final DateTime created;
  SignedMessage? request;
  TrustContext? publicTrust;
  void Function()? publicTrustGuard;
  SignedMessage? consentedInvitation;
  String? restoredManifestId, restoredManifestDigest;
}

extension RecoveryIdentityActivation on LocalIdentityService {
  Directory get _recoveryDirectory =>
      Directory('${catalog.paths.root.path}/identity-recovery');
  File _recoveryFile(String id) => File('${_recoveryDirectory.path}/$id.enc');
  Future<void> _saveIdentityJournal(
    String id,
    Map<String, dynamic> body,
  ) async {
    final file = _recoveryFile(id), tmp = File('${_recoveryFile(id).path}.tmp');
    await _recoveryDirectory.create(recursive: true);
    final encrypted = await AesPayloadCipher(VaultKeys(keys)).seal(
      scopeId: 'installation-catalog',
      recordId: 'identity-recovery:$id',
      revision: 1,
      plain: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );
    await tmp.writeAsBytes(encrypted, flush: true);
    await tmp.rename(file.path);
    DurableDirectory.through(_recoveryDirectory, catalog.paths.root);
  }

  PendingRecoveryIdentity requireRecoveryIdentity(
    SessionHandle session,
    RecoveryIdentityCandidate candidate,
  ) {
    final actor = requireActor(session), draft = recoveryCandidates[candidate];
    if (actor.restrictedCompanyId != null ||
        draft == null ||
        !identical(draft.session, session)) {
      throw const CheckException(CheckError.unauthorized);
    }
    final age = clock.nowUtc().difference(draft.created);
    if (age.isNegative || age >= const Duration(minutes: 5)) {
      throw const CheckException(CheckError.locked);
    }
    draft.publicTrustGuard?.call();
    return draft;
  }

  Future<RecoveryIdentityCandidate> stagePendingIdentity(
    SessionHandle session, {
    required String companyId,
    required String personId,
    required String displayName,
    required String rootFingerprint,
    required String passphrase,
  }) => _exclusive((epoch) async {
    final actor = requireActor(session);
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    if (actor.restrictedCompanyId != null) {
      throw const CheckException(CheckError.unauthorized);
    }
    if (!uuid.hasMatch(companyId) ||
        !uuid.hasMatch(personId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(rootFingerprint) ||
        displayName.trim().isEmpty ||
        displayName.runes.length > 100) {
      throw const CheckException(CheckError.malformed);
    }
    if (passphrase.runes.length < 12) {
      throw const CheckException(CheckError.wrongSecret);
    }
    final profiles = await catalog.read();
    if (profiles.any((p) => p.personId == personId)) {
      throw const CheckException(CheckError.duplicateConflict);
    }
    final id = ids.next(),
        installation = ids.next(),
        key = 'signing:${ids.next()}';
    if (await keys.read(key) != null ||
        await keys.read('credential:$personId') != null ||
        await _recoveryFile(id).exists()) {
      throw const CheckException(CheckError.duplicateConflict);
    }
    for (final prior
        in recoveryCandidates.values
            .where((d) => identical(d.session, session))
            .toList()) {
      await cancelPendingIdentity(session, prior);
    }
    final salt = secureRandomBytes(16),
        verifier = await operatorVerifier(passphrase, salt);
    requireActor(session);
    final public = await LocalKeyService(keys).create(key);
    final credential = Uint8List.fromList([1, ...salt, ...verifier]);
    final profile = LocalProfile(
      personId: personId,
      displayName: displayName.trim(),
      installationId: installation,
      signingKeyId: key,
      publicKey: public,
      authorizedCompanyIds: {companyId},
    );
    final candidate = PendingRecoveryIdentity(
      id,
      session,
      profile,
      companyId,
      rootFingerprint,
      credential,
      clock.nowUtc(),
    );
    await _saveIdentityJournal(id, {
      'version': 1,
      'id': id,
      'companyId': companyId,
      'rootFingerprint': rootFingerprint,
      'personId': personId,
      'displayName': profile.displayName,
      'installationId': installation,
      'signingKeyId': key,
      'publicKey': base64UrlEncode(public),
      'credential': base64Encode(credential),
    });
    requireActor(session);
    recoveryCandidates[candidate] = candidate;
    return candidate;
  });
  Future<RecoveryIdentityCandidate> stageContinuation(
    SessionHandle session,
    String companyId,
    String rootFingerprint,
  ) => _exclusive((_) async {
    final actor = requireActor(session);
    if (actor.restrictedCompanyId != null ||
        actor.authorizedCompanyIds == null) {
      throw const CheckException(CheckError.unauthorized);
    }
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(companyId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(rootFingerprint)) {
      throw const CheckException(CheckError.malformed);
    }
    if (actor.authorizedCompanyIds!.contains(companyId)) {
      throw const CheckException(CheckError.invalidTransition);
    }
    final profile = (await catalog.read())
        .where(
          (p) =>
              p.personId == actor.personId &&
              p.installationId == actor.installationId &&
              p.signingKeyId == actor.signingKeyId &&
              base64UrlEncode(p.publicKey) == base64UrlEncode(actor.publicKey),
        )
        .firstOrNull;
    if (profile == null || profile.authorizedCompanyIds == null) {
      throw const CheckException(CheckError.unauthorized);
    }
    for (final prior
        in recoveryCandidates.values
            .where((d) => identical(d.session, session))
            .toList()) {
      await cancelPendingIdentity(session, prior);
    }
    final id = ids.next();
    final candidate = PendingRecoveryIdentity(
      id,
      session,
      profile,
      companyId,
      rootFingerprint,
      Uint8List(0),
      clock.nowUtc(),
      continuation: true,
    );
    await _saveIdentityJournal(id, {
      'version': 1,
      'id': id,
      'continuation': true,
      'companyId': companyId,
      'rootFingerprint': rootFingerprint,
      'personId': profile.personId,
      'installationId': profile.installationId,
      'signingKeyId': profile.signingKeyId,
      'publicKey': base64UrlEncode(profile.publicKey),
    });
    requireActor(session);
    recoveryCandidates[candidate] = candidate;
    return candidate;
  });

  Future<void> cancelPendingIdentity(
    SessionHandle session,
    RecoveryIdentityCandidate candidate,
  ) async {
    requireActor(session);
    final draft = recoveryCandidates[candidate];
    if (draft == null || !identical(draft.session, session)) {
      throw const CheckException(CheckError.unauthorized);
    }
    final repo = repository;
    if (repo != null &&
        await repo.read(draft.companyId, 'identity-activation:${draft.id}') !=
            null) {
      throw const CheckException(CheckError.invalidTransition);
    }
    recoveryCandidates.remove(candidate);
    // Pending keys are uniquely allocated; no published catalog can reference
    // them before a content-bound activation receipt exists.
    if (!draft.continuation) await keys.delete(draft.profile.signingKeyId);
    if (await _recoveryFile(draft.id).exists()) {
      await _recoveryFile(draft.id).delete();
    }
  }

  StoredRecord recoveryIdentityReceipt(PendingRecoveryIdentity d) =>
      StoredRecord(
        'identity-activation:${d.id}',
        d.companyId,
        'identityActivation',
        1,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'continuation': d.continuation,
              'personId': d.profile.personId,
              'installationId': d.profile.installationId,
              'publicKey': base64UrlEncode(d.profile.publicKey),
              'rootFingerprint': d.rootFingerprint,
            }),
          ),
        ),
      );
  Future<void> publishRecoveryIdentity(
    SessionHandle session,
    RecoveryIdentityCandidate candidate,
  ) => _exclusive((_) async {
    final draft = recoveryCandidates[candidate];
    if (draft == null || !identical(draft.session, session)) {
      throw const CheckException(CheckError.unauthorized);
    }
    // The durable exact receipt is the authorization boundary. A late lock
    // must not revoke publication of an already accepted command.
    try {
      await _publishIdentityJournal(
        draft.id,
        authenticatedPerson: draft.continuation ? draft.profile.personId : null,
      );
      recoveryCandidates.remove(candidate);
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  });

  Future<void> _publishIdentityJournal(
    String id, {
    bool abandonUnaccepted = false,
    String? authenticatedPerson,
  }) async {
    final repo = repository;
    if (repo == null) throw const CheckException(CheckError.invalidTransition);
    final data =
        jsonDecode(
              utf8.decode(
                await AesPayloadCipher(VaultKeys(keys)).open(
                  scopeId: 'installation-catalog',
                  recordId: 'identity-recovery:$id',
                  revision: 1,
                  sealed: await _recoveryFile(id).readAsBytes(),
                ),
              ),
            )
            as Map<String, dynamic>;
    final continuation = data['continuation'] == true;
    final company = data['companyId'] as String,
        person = data['personId'] as String;
    final receipt = await repo.read(company, 'identity-activation:$id');
    if (receipt == null) {
      if (abandonUnaccepted) {
        final key = data['signingKeyId'] as String;
        if (!continuation &&
            (await catalog.read()).any((p) => p.signingKeyId == key)) {
          throw const CheckException(CheckError.recoveryRequired);
        }
        if (!continuation) await keys.delete(key);
        await _recoveryFile(id).delete();
        DurableDirectory.through(_recoveryDirectory, catalog.paths.root);
      }
      return; // Unaccepted drafts never publish on restart.
    }
    if (continuation && authenticatedPerson != person) return;
    final accepted = jsonDecode(utf8.decode(receipt.payload)) as Map;
    if ((accepted['continuation'] == true) != continuation) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    for (final field in [
      'personId',
      'installationId',
      'publicKey',
      'rootFingerprint',
    ]) {
      if (accepted[field] != data[field]) {
        throw const CheckException(CheckError.recoveryRequired);
      }
    }
    if (receipt.kind != 'identityActivation') {
      throw const CheckException(CheckError.recoveryRequired);
    }
    final profiles = await catalog.read();
    final public = base64Url.decode(data['publicKey'] as String),
        key = data['signingKeyId'] as String;
    final probe = Uint8List.fromList(
      utf8.encode('RAZE_CHECK_RECOVERY_ACTIVATION_V1'),
    );
    if (!await LocalKeyService(
      keys,
    ).verify(probe, await LocalKeyService(keys).sign(probe, key), public)) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    final existing = profiles.where((p) => p.personId == person).firstOrNull;
    if (existing != null &&
        (existing.installationId != data['installationId'] ||
            existing.signingKeyId != key ||
            base64UrlEncode(existing.publicKey) != data['publicKey'])) {
      throw const CheckException(CheckError.duplicateConflict);
    }
    if (continuation) {
      if (existing == null || existing.authorizedCompanyIds == null) {
        throw const CheckException(CheckError.unauthorized);
      }
      // Union with the current catalog, not the draft's stale binding snapshot.
      final updated = LocalProfile(
        personId: existing.personId,
        displayName: existing.displayName,
        installationId: existing.installationId,
        signingKeyId: existing.signingKeyId,
        publicKey: existing.publicKey,
        authorizedCompanyIds: {...existing.authorizedCompanyIds!, company},
      );
      await catalog.write([
        for (final p in profiles)
          if (p.personId == person) updated else p,
      ]);
    } else {
      final credential = base64Decode(data['credential'] as String),
          old = await keys.read('credential:$person');
      if (old != null && base64Encode(old) != base64Encode(credential)) {
        throw const CheckException(CheckError.duplicateConflict);
      }
      if (await keys.read('vault:$person') == null) {
        await VaultKeys(keys).create(person);
      }
      if (old == null) await keys.write('credential:$person', credential);
      if (existing == null) {
        await catalog.write([
          ...profiles,
          LocalProfile(
            personId: person,
            displayName: data['displayName'] as String,
            installationId: data['installationId'] as String,
            signingKeyId: key,
            publicKey: public,
            authorizedCompanyIds: {company},
          ),
        ]);
      }
    }
    // Publish catalog durably before removing its accepted recovery journal.
    DurableDirectory.through(catalog.paths.root, catalog.paths.root);
    try {
      await _recoveryFile(id).delete();
      DurableDirectory.through(_recoveryDirectory, catalog.paths.root);
    } on FileSystemException {
      // Activation is already durable; cleanup can replay from the receipt.
    } on CheckException catch (e) {
      if (e.code != CheckError.storageFailure) rethrow;
    }
  }

  // A binding receipt is inserted with an authorized new company creation or
  // exact first membership grant. It binds this installation, not person ID alone.
  Future<LocalProfile> _createdCompanyBindings(
    LocalProfile profile, {
    String? selectedCompany,
  }) async {
    final allowed = profile.authorizedCompanyIds, repo = repository;
    if (allowed == null || repo == null) return profile;
    if (repo is! LocalCheckRepository) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    final additions = <String>{};
    for (final companyId
        in selectedCompany == null
            ? await repo.listCompanyIds()
            : [selectedCompany]) {
      if (allowed.contains(companyId)) continue;
      final receipt = await repo.read(
        companyId,
        'installation-binding:${profile.installationId}',
      );
      if (receipt == null || receipt.kind != 'installationBinding') continue;
      late Map data;
      try {
        data = jsonDecode(utf8.decode(receipt.payload)) as Map;
        if (!{'createdCompany', 'joinedCompany'}.contains(data['reason']) ||
            data['personId'] != profile.personId ||
            data['installationId'] != profile.installationId ||
            data['publicKey'] != base64UrlEncode(profile.publicKey)) {
          continue;
        }
        final proof = Uint8List.fromList(
          utf8.encode(
            data['reason'] == 'createdCompany'
                ? 'RAZE_CHECK_LOCAL_COMPANY_BINDING_V1\n${jsonEncode([companyId, profile.personId, profile.installationId, base64UrlEncode(profile.publicKey), data['operationId'], data['digest'], data['generationId']])}'
                : 'RAZE_CHECK_LOCAL_ENROLLMENT_BINDING_V1\n${jsonEncode([companyId, profile.personId, profile.installationId, base64UrlEncode(profile.publicKey), data['grantId'], data['requestId'], data['grantHash']])}',
          ),
        );

        if (data['signature'] is! String ||
            !await LocalKeyService(keys).verify(
              proof,
              base64Url.decode(data['signature'] as String),
              profile.publicKey,
            )) {
          continue;
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
      final row = await repo.read(companyId, companyId);
      if (row == null) throw const CheckException(CheckError.recoveryRequired);
      final c = Company.fromJson(
        jsonDecode(utf8.decode(row.payload)) as Map<String, dynamic>,
      );
      if (data['reason'] == 'joinedCompany') {
        final accepted = await repo.read(
          companyId,
          'accepted-grant:${data['grantId']}',
        );
        final pending = await repo.read(
          companyId,
          'pending-join:${data['requestId']}',
        );
        if (accepted == null ||
            pending == null ||
            base64UrlEncode((await Sha256().hash(accepted.payload)).bytes) !=
                data['grantHash']) {
          throw const CheckException(CheckError.recoveryRequired);
        }
        final codec = MessageCodec(),
            grant = MessageCodec().decode(
              accepted.payload,
              maxBytes: MessageLimits.fileBytes,
            );
        final request = codec.decode(
          pending.payload,
          maxBytes: MessageLimits.fileBytes,
        );
        final p = grant.payload;
        if (grant.kind != MessageKind.membershipGrant ||
            request.kind != MessageKind.joinRequest ||
            p.companyId != companyId ||
            request.payload.companyId != companyId ||
            p.messageId != data['grantId'] ||
            request.payload.messageId != data['requestId'] ||
            p.field<String>('joinOrReplacementRequestId') !=
                request.payload.messageId ||
            p.field<String>('personId') != profile.personId ||
            request.payload.field<String>('personId') != profile.personId ||
            p.field<String>('installationId') != profile.installationId ||
            request.payload.field<String>('installationId') !=
                profile.installationId ||
            p.field<String>('publicKeyBase64Url') !=
                base64UrlEncode(profile.publicKey) ||
            request.payload.field<String>('publicKeyBase64Url') !=
                base64UrlEncode(profile.publicKey)) {
          throw const CheckException(CheckError.recoveryRequired);
        }
        final authorities = (await repo.listRecords(companyId, 'authority'))
            .map(
              (r) => AuthorityCertificate(
                List<Object?>.from(jsonDecode(utf8.decode(r.payload)) as List),
              ),
            )
            .toList();
        final trust = TrustContext(
          companyId: companyId,
          rootPublicKey: base64Url.decode(c.rootPublicKey),
          authorities: authorities,
        );
        await MessageVerifier(LocalKeyService(keys)).verify(grant, trust);
        await MessageVerifier(LocalKeyService(keys)).verify(request, trust);
        additions.add(companyId);
        continue;
      }
      if (c.creationPersonId != profile.personId ||
          c.creationOperationId != data['operationId'] ||
          c.creationDigest != data['digest']) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      final certRow = await repo.read(
        companyId,
        data['generationId'] as String,
      );
      if (certRow == null || certRow.kind != 'authority') {
        throw const CheckException(CheckError.recoveryRequired);
      }
      final cert = AuthorityCertificate(
        List<Object?>.from(jsonDecode(utf8.decode(certRow.payload)) as List),
      );
      if (cert.parentGenerationId != null ||
          cert.sequence != 1 ||
          cert.installationId != profile.installationId ||
          base64UrlEncode(cert.publicKey) !=
              base64UrlEncode(profile.publicKey) ||
          !await LocalKeyService(keys).verify(
            cert.signingBytes,
            cert.signature,
            base64Url.decode(c.rootPublicKey),
          )) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      additions.add(companyId);
    }
    if (additions.isEmpty) return profile;
    final updated = LocalProfile(
      personId: profile.personId,
      displayName: profile.displayName,
      installationId: profile.installationId,
      signingKeyId: profile.signingKeyId,
      publicKey: profile.publicKey,
      authorizedCompanyIds: {...allowed, ...additions},
    );
    final profiles = await catalog.read();
    await catalog.write([
      for (final p in profiles)
        if (p.personId == profile.personId) updated else p,
    ]);
    DurableDirectory.through(catalog.paths.root, catalog.paths.root);
    for (final live in _live.values) {
      final a = live.actor;
      if (a.personId == profile.personId &&
          a.installationId == profile.installationId &&
          a.restrictedCompanyId == null) {
        live.actor = ActorIdentity(
          personId: a.personId,
          installationId: a.installationId,
          signingKeyId: a.signingKeyId,
          publicKey: a.publicKey,
          authorizedCompanyIds: updated.authorizedCompanyIds,
        );
      }
    }
    return updated;
  }

  Future<void> completeCreatedCompanyBinding(
    ActorIdentity actor,
    String companyId,
  ) => _exclusive((_) async {
    if (actor.authorizedCompanyIds == null) return;
    final profile = (await catalog.read())
        .where(
          (p) =>
              p.personId == actor.personId &&
              p.installationId == actor.installationId &&
              p.signingKeyId == actor.signingKeyId,
        )
        .firstOrNull;
    if (profile == null) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    await _createdCompanyBindings(profile, selectedCompany: companyId);
  });

  /// Called during startup before exposing unlock or business services. Only a
  /// committed exact DB receipt can complete publication after interruption.
  Future<void> resumeRecoveryIdentities() =>
      _exclusive((_) => resumeIdentityJournals());

  Future<void> resumeIdentityJournals({String? authenticatedPerson}) async {
    if (!await _recoveryDirectory.exists()) return;
    await for (final f in _recoveryDirectory.list()) {
      if (f is File && f.path.endsWith('.enc')) {
        final id = f.uri.pathSegments.last.substring(
          0,
          f.uri.pathSegments.last.length - 4,
        );
        if (RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)) {
          await _publishIdentityJournal(
            id,
            abandonUnaccepted: true,
            authenticatedPerson: authenticatedPerson,
          );
        }
      }
    }
  }
}
