part of 'local_archive_service.dart';

extension _StaffRecoveryArchive on LocalArchiveService {
  LocalDeviceReplacementService get _replacement =>
      LocalDeviceReplacementService(
        repository: repository,
        identity: identity,
        keys: keys,
        clock: clock,
        ids: ids,
      );
  Future<void> _authorizeStaffExport(
    CommandContext context,
    SignedMessage request,
    SignedMessage grant,
  ) async {
    final view = RepositoryReadView(repository, context.companyId),
        service = _replacement;
    final company = await service.manage(context, view);
    await service.manage(
      context,
      view,
      capability: Capability.exportAttendance,
    );
    await MessageVerifier(
      service.signing,
    ).verify(request, await companyTrust(company, view));
    await MessageVerifier(
      service.signing,
    ).verify(grant, await companyTrust(company, view));
    final row = await view.read(
      'replacement-approved:${request.payload.messageId}',
    );
    if (row == null) archiveBad(CheckError.unauthorized);
    final approved = service.json(row);
    if (approved['request'] != base64UrlEncode(service.codec.encode(request)) ||
        approved['grant'] != base64UrlEncode(service.codec.encode(grant))) {
      archiveBad(CheckError.unauthorized);
    }
    final p = grant.payload,
        member = await view.read(p.field<String>('membershipId'));
    if (member == null ||
        !Membership.fromJson(service.json(member)).active ||
        Membership.fromJson(service.json(member)).revision !=
            p.field<int>('membershipRevision') ||
        p.companyId != context.companyId ||
        request.kind != MessageKind.replacementRequest ||
        grant.kind != MessageKind.membershipGrant ||
        p.field<String>('joinOrReplacementRequestId') !=
            request.payload.messageId ||
        p.field<String>('personId') !=
            request.payload.field<String>('personId') ||
        p.field<String>('employeeId') !=
            request.payload.field<String?>('employeeIdOrNull') ||
        p.field<String>('installationId') !=
            request.payload.field<String>('newInstallationId') ||
        p.field<String>('publicKeyBase64Url') !=
            request.payload.field<String>('newPublicKeyBase64Url')) {
      archiveBad(CheckError.unauthorized);
    }
    identity.requireActor(context.session);
  }

  Future<void> _authorizeCatalog(
    SessionHandle session,
    Map<String, dynamic> metadata,
  ) async {
    final projection = metadata['staffRecovery'];
    if (projection == null) {
      final actor = identity.requireActor(session);
      if (actor.authorizedCompanyIds != null) {
        final companies = metadata['companyIds'];
        if (companies is! List) archiveBad(CheckError.unauthorized);
        for (final company in companies) {
          actor.requireCompany(company as String);
        }
      }
      await _authorize(session, _scope(metadata));
      return;
    }
    final data = Map<String, dynamic>.from(projection as Map),
        codec = MessageCodec();
    await _authorizeStaffExport(
      CommandContext(
        companyId: data['companyId'] as String,
        session: session,
        operationId: 'share-staff-recovery',
        authorityGenerationId: data['generation'] as String,
      ),
      codec.decode(
        base64Url.decode(data['request'] as String),
        maxBytes: MessageLimits.fileBytes,
      ),
      codec.decode(
        base64Url.decode(data['grant'] as String),
        maxBytes: MessageLimits.fileBytes,
      ),
    );
  }

  Future<ArchiveDescriptor> _staffRecovery(
    CommandContext context,
    VerifiedMessage request,
    SignedMessage grant,
    String passphrase,
  ) => _serial(() async {
    await _authorizeStaffExport(context, request.message, grant);
    final service = _replacement,
        p = grant.payload,
        person = p.field<String>('personId'),
        companyId = context.companyId;
    final selected = <String, ArchiveRecord>{},
        attachments = <AttachmentManifestEntry>[];
    const allowed = {
      'membership',
      'staff',
      'trustedCredential',
      'attendance',
      'attendanceReceipt',
      'attendanceState',
      'attendanceReturn',
      'attendanceDecisionRecord',
      'correctionResolution',
      'correctionRequest',
      'manualAttendance',
      'membershipGrant',
    };
    await repository.visitArchive(
      PersonalScope(person),
      (kind, value) async {
        if (value is ArchiveRecord &&
            value.record.companyId == companyId &&
            allowed.contains(value.record.kind)) {
          selected[value.record.id] = value;
        }
        if (value is AttachmentManifestEntry && value.companyId == companyId) {
          attachments.add(value);
        }
      },
      cancelled: () {
        try {
          identity.requireActor(context.session);
          return false;
        } on CheckException {
          return true;
        }
      },
    );
    final company = Company.fromJson(
      service.json((await repository.read(companyId, companyId))!),
    );
    final publicCompany = Company(
      id: company.id,
      name: company.name,
      timeZoneId: company.timeZoneId,
      workplaceId: company.workplaceId,
      authorityGenerationId: company.authorityGenerationId,
      authoritySigningKeyId: '',
      rootPublicKey: company.rootPublicKey,
      rootFingerprint: company.rootFingerprint,
      authority: company.authority,
      creationPersonId: '',
      creationOperationId: '',
      creationDigest: '',
    );
    selected[companyId] = ArchiveRecord(
      'entity',
      service.row(companyId, companyId, 'company', publicCompany.toJson()),
    );
    final staff = (await repository.read(
      companyId,
      p.field<String>('employeeId'),
    ))!;
    selected[staff.id] = ArchiveRecord('entity', staff);
    final member = (await repository.read(
      companyId,
      p.field<String>('membershipId'),
    ))!;
    final m = Membership.fromJson(service.json(member));
    selected[member.id] = ArchiveRecord(
      'entity',
      service.row(
        companyId,
        member.id,
        'membership',
        Membership(
          id: m.id,
          companyId: companyId,
          personId: person,
          employeeId: m.employeeId,
          owner: false,
          active: m.active,
          capabilities: {},
          revision: m.revision,
        ).toJson(),
        m.revision,
      ),
    );
    for (final a in await repository.listRecords(companyId, 'authority')) {
      selected[a.id] = ArchiveRecord('authority', a);
    }
    final history = (await companyTrust(
      company,
      RepositoryReadView(repository, companyId),
    )).authorities;
    for (final a in history) {
      selected.putIfAbsent(
        a.generationId,
        () => ArchiveRecord(
          'authority',
          service.row(companyId, a.generationId, 'authority', a.values),
        ),
      );
    }
    final installations = <String, List<String>>{};
    for (final r in selected.values.where(
      (r) => r.record.kind == 'trustedCredential',
    )) {
      final c = service.json(r.record);
      if (c['personId'] != person || c['employeeId'] != m.employeeId) {
        archiveBad(CheckError.unauthorized);
      }
      installations[c['installationId'] as String] = [
        c['installationId'] as String,
        c['publicKey'] as String,
      ];
    }
    final encoder = await ArchiveRecordWorker.start();
    late Uint8List records;
    try {
      for (final r in selected.values) {
        await encoder.add('record', r);
        await encoder.add(
          'association',
          PersonalRecordAssociation(person, r.record.id, companyId: companyId),
        );
      }
      for (final a in attachments.where(
        (a) => selected.containsKey(a.recordId),
      )) {
        await encoder.add('attachment', a);
      }
      records = await encoder.finish();
    } finally {
      encoder.dispose();
    }
    final files = <String, Uint8List>{
      'records.json': records,
      'recovery.json': archiveJson({
        'version': 1,
        'profiles': [
          {
            'version': 1,
            'personId': person,
            'displayName': StaffRecord.fromJson(
              service.json(staff),
            ).details.name,
            'installations': installations.values.toList(),
          },
        ],
      }),
    };
    final store = ImmutableAttachmentStore(
      paths: paths,
      cipher: AesPayloadCipher(VaultKeys(keys)),
    );
    for (final a in attachments.where(
      (a) => selected.containsKey(a.recordId),
    )) {
      files['attachments/${a.sha256}'] = await store.read(a);
    }
    final counts = <String, int>{};
    for (final r in selected.values) {
      counts[r.record.kind] = (counts[r.record.kind] ?? 0) + 1;
    }
    final id = ids.next(), created = clock.nowUtc().millisecondsSinceEpoch;
    files['manifest.json'] = archiveJson({
      'formatVersion': 1,
      'archiveId': id,
      'createdUtcMs': created,
      'scopeKind': 'personal',
      'scopeId': person,
      'personId': person,
      'companyRootFingerprints': {companyId: company.rootFingerprint},
      'authorityHeads': {companyId: company.authorityGenerationId},
      'recordCountsByKind': counts,
      'files': [
        for (final e in files.entries)
          {
            'path': e.key,
            'byteLength': e.value.length,
            'sha256': await archiveHash(e.value),
          },
      ],
    });
    await validateArchive(files);
    final encrypted = await ArchiveCodec.seal(files, passphrase),
        hash = base64UrlEncode(
          (await Sha256().hash(files['manifest.json']!)).bytes,
        );
    await _authorizeStaffExport(context, request.message, grant);
    await catalog.publish(encrypted, {
      'artifactId': id,
      'createdUtcMs': created,
      'scopeKind': 'personal',
      'scopeId': person,
      'personId': person,
      'counts': counts,
      'externalCopyConfirmed': false,
      'manifestSha256Base64Url': hash,
      'staffRecovery': {
        'companyId': companyId,
        'generation': context.authorityGenerationId,
        'request': base64UrlEncode(service.codec.encode(request.message)),
        'grant': base64UrlEncode(service.codec.encode(grant)),
      },
    }, () => identity.requireActor(context.session));
    return ArchiveDescriptor(
      artifactId: id,
      createdUtcMs: created,
      scope: PersonalScope(person),
      counts: counts,
      manifestSha256Base64Url: hash,
    );
  });
}
