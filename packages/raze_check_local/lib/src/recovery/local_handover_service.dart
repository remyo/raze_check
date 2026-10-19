import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../database/local_check_repository.dart';
import '../security/local_identity_service.dart';
import '../security/local_key_service.dart';
import '../security/secure_key_store.dart';
import 'local_archive_service.dart';
import 'local_authority_history.dart';
import 'handover_journal.dart';
import 'local_device_replacement_service.dart';

final class LocalHandoverService implements HandoverService {
  LocalHandoverService({
    required this.repository,
    required this.identity,
    required this.keys,
    required this.clock,
    required this.ids,
    required this.archives,
  }) : helper = LocalDeviceReplacementService(
         repository: repository,
         identity: identity,
         keys: keys,
         clock: clock,
         ids: ids,
       );
  final LocalCheckRepository repository;
  final LocalIdentityService identity;
  final SecureKeyStore keys;
  final CheckClock clock;
  final IdGenerator ids;
  final LocalArchiveService archives;
  final LocalDeviceReplacementService helper;
  Future<Uint8List> digest(Object v) async =>
      Uint8List.fromList((await Sha256().hash(helper.bytes(v))).bytes);
  Future<Company> owner(CommandContext c, ReadView view) async {
    final company = await helper.manage(
      c,
      view,
      capability: Capability.recoverCompany,
    );
    final a = identity.requireActor(c.session),
        cert = AuthorityCertificate(company.authority);
    if (a.restrictedCompanyId != null ||
        cert.installationId != a.installationId ||
        company.authoritySigningKeyId != a.signingKeyId ||
        base64UrlEncode(cert.publicKey) != base64UrlEncode(a.publicKey)) {
      throw const CheckException(CheckError.unauthorized);
    }
    return company;
  }

  Future<AuthorityCertificate> child(Company c, PendingRecoveryIdentity d) =>
      childKey(c, d.profile.installationId, d.profile.publicKey);
  Future<AuthorityCertificate> childKey(
    Company c,
    String installation,
    Uint8List public,
  ) async {
    final parent = AuthorityCertificate(c.authority),
        fields = <Object?>[
          ids.next(),
          parent.generationId,
          parent.sequence + 1,
          installation,
          base64UrlEncode(public),
          clock.nowUtc().millisecondsSinceEpoch,
        ];
    final signed = await LocalKeyService(keys).sign(
      Uint8List.fromList(
        utf8.encode('RAZE_CHECK_AUTHORITY_V1\n${jsonEncode(fields)}'),
      ),
      'company-root:${c.id}',
    );
    return AuthorityCertificate([...fields, base64UrlEncode(signed)]);
  }

  Future<List<StoredRecord>> preserveOwnerCredentials(
    Company company,
    ReadView view,
  ) async {
    final rows = <StoredRecord>[], a = AuthorityCertificate(company.authority);
    for (final r in await view.list('membership')) {
      final m = Membership.fromJson(helper.json(r));
      if (!m.owner) continue;
      final id = 'credential:${m.id}:${m.revision}';
      if (await view.read(id) == null) {
        rows.add(
          helper.row(company.id, id, 'trustedCredential', {
            'companyId': company.id,
            'personId': m.personId,
            'employeeId': m.employeeId,
            'installationId': a.installationId,
            'membershipId': m.id,
            'membershipRevision': m.revision,
            'authorityGenerationId': a.generationId,
            'publicKey': base64UrlEncode(a.publicKey),
            'retired': false,
          }),
        );
      }
    }
    return rows;
  }

  HandoverOffer offerFrom(Map<String, dynamic> state) {
    final transfer = helper.codec.decode(
      base64Url.decode(state['transfer'] as String),
      maxBytes: MessageLimits.fileBytes,
    );
    return HandoverOffer(
      transfer,
      ArchiveDescriptor(
        artifactId: state['artifactId'] as String,
        createdUtcMs: state['createdUtcMs'] as int,
        scope: CompanyScope(transfer.payload.companyId),
        counts: Map<String, int>.from(state['counts'] as Map),
        manifestSha256Base64Url: state['manifestHash'] as String,
      ),
    );
  }

  @override
  Future<HandoverOffer?> pendingOffer(
    SessionHandle session,
    String companyId,
  ) async {
    final view = RepositoryReadView(repository, companyId);
    final row = await view.read(companyId);
    if (row == null) throw const CheckException(CheckError.wrongCompany);
    final company = Company.fromJson(helper.json(row));
    await owner(
      CommandContext(
        companyId: companyId,
        session: session,
        operationId: 'pending-handover',
        authorityGenerationId: company.authorityGenerationId,
      ),
      view,
    );
    final state = await view.read('authority-lifecycle');
    identity.requireActor(session);
    if (state == null ||
        !['offered', 'retired'].contains(helper.json(state)['state'])) {
      return null;
    }
    return offerFrom(helper.json(state));
  }

  @override
  Future<SignedMessage?> activationAcknowledgment(
    SessionHandle session,
    String companyId,
  ) async {
    final view = RepositoryReadView(repository, companyId);
    final row = await view.read(companyId);
    if (row == null) throw const CheckException(CheckError.wrongCompany);
    final company = Company.fromJson(helper.json(row));
    await owner(
      CommandContext(
        companyId: companyId,
        session: session,
        operationId: 'activation-ack',
        authorityGenerationId: company.authorityGenerationId,
      ),
      view,
    );
    final activation = await view.read(
      'authority-activation:${company.authorityGenerationId}',
    );
    identity.requireActor(session);
    final wire = activation == null
        ? null
        : helper.json(activation)['ack'] as String?;
    return wire == null
        ? null
        : helper.codec.decode(
            base64Url.decode(wire),
            maxBytes: MessageLimits.fileBytes,
          );
  }

  @override
  Future<HandoverOffer> begin(
    CommandContext context,
    VerifiedMessage targetRequest, {
    required String archivePassphrase,
  }) async {
    final request = targetRequest.message, p = request.payload;
    if (request.kind != MessageKind.replacementRequest ||
        p.field<String?>('employeeIdOrNull') != null) {
      throw const CheckException(CheckError.malformed);
    }
    if (p.companyId != context.companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final wire = base64UrlEncode(helper.codec.encode(request));
    late Company company;
    final prepared = await repository.commitRecovery(
      context,
      requestDigest: await digest(['handover', wire]),
      authorize: (view) async {
        company = await owner(context, view);
        final a = identity.requireActor(context.session);
        await MessageVerifier(
          helper.signing,
        ).verify(request, await companyTrust(company, view));
        if (p.field<String>('personId') != a.personId ||
            p.field<String>('newInstallationId') == a.installationId ||
            p.field<String>('newPublicKeyBase64Url') ==
                base64UrlEncode(a.publicKey)) {
          throw const CheckException(CheckError.unauthorized);
        }
        final old = await view.read('authority-lifecycle');
        if (old != null &&
            helper.json(old)['state'] != 'active' &&
            helper.json(old)['request'] != wire) {
          throw const CheckException(CheckError.recoveryRequired);
        }
      },
      beforeCommit: () => identity.requireActor(context.session),
      build: (view) async {
        final old = await view.read('authority-lifecycle');
        if (old != null && helper.json(old)['state'] != 'active') {
          return Mutation([], [], [], old);
        }
        final history = await preserveOwnerCredentials(company, view);
        final state = helper.row(
          context.companyId,
          'authority-lifecycle',
          'authorityLifecycle',
          {'state': 'preparing', 'request': wire},
          (old?.revision ?? 0) + 1,
        );
        return Mutation(
          [state, ...history],
          [],
          [],
          state,
          personalRecords: [
            for (final r in history)
              PersonalRecordAssociation(p.field<String>('personId'), r.id),
          ],
        );
      },
    );
    helper.value(prepared);
    final current = helper.json(
      (await repository.read(context.companyId, 'authority-lifecycle'))!,
    );
    if (current['state'] == 'offered') return offerFrom(current);
    if (current['state'] != 'preparing') {
      throw const CheckException(CheckError.recoveryRequired);
    }
    // Freeze is already durable. Failure leaves a cancellable preparing source.
    final archive = await archives.create(
      context.session,
      CompanyScope(context.companyId),
      archivePassphrase,
    );
    final next = await childKey(
      company,
      p.field<String>('newInstallationId'),
      base64Url.decode(p.field<String>('newPublicKeyBase64Url')),
    );
    final transfer = await helper.sign(
      MessageKind.authorityTransfer,
      [
        company.id,
        ids.next(),
        clock.nowUtc().millisecondsSinceEpoch,
        p.messageId,
        archive.artifactId,
        archive.manifestSha256Base64Url,
        next.values,
        company.authority,
      ],
      company.authoritySigningKeyId,
      AuthorityCertificate(company.authority).publicKey,
    );
    final result = await repository.commitRecovery(
      CommandContext(
        companyId: context.companyId,
        session: context.session,
        operationId: 'offer:${archive.artifactId}',
        authorityGenerationId: context.authorityGenerationId,
      ),
      requestDigest: await digest(['offer', wire, archive.artifactId]),
      authorize: (view) async {
        await owner(context, view);
        final state = await view.read('authority-lifecycle');
        if (state == null ||
            helper.json(state)['state'] != 'preparing' ||
            helper.json(state)['request'] != wire) {
          throw const CheckException(CheckError.invalidTransition);
        }
      },
      beforeCommit: () => identity.requireActor(context.session),
      build: (view) async {
        final old = (await view.read('authority-lifecycle'))!;
        final state = helper.row(context.companyId, old.id, old.kind, {
          'state': 'offered',
          'request': wire,
          'transfer': base64UrlEncode(helper.codec.encode(transfer)),
          'artifactId': archive.artifactId,
          'createdUtcMs': archive.createdUtcMs,
          'counts': archive.counts,
          'manifestHash': archive.manifestSha256Base64Url,
        }, old.revision + 1);
        return Mutation(
          [state],
          [],
          [
            StoredRecord(
              'outbox:${transfer.payload.messageId}',
              context.companyId,
              'message',
              1,
              helper.codec.encode(transfer),
            ),
          ],
          state,
        );
      },
    );
    return offerFrom(helper.json(helper.value(result)));
  }

  @override
  Future<Uint8List> exportArtifact(
    SessionHandle session,
    HandoverOffer offer,
  ) async {
    final c = offer.transfer.payload.companyId,
        view = RepositoryReadView(repository, c);
    final state = await view.read('authority-lifecycle');
    if (state == null ||
        !['offered', 'retired'].contains(helper.json(state)['state']) ||
        helper.json(state)['transfer'] !=
            base64UrlEncode(helper.codec.encode(offer.transfer))) {
      throw const CheckException(CheckError.unauthorized);
    }
    final company = Company.fromJson(helper.json((await view.read(c))!));
    await helper.manage(
      CommandContext(
        companyId: c,
        session: session,
        operationId: 'resend',
        authorityGenerationId: company.authorityGenerationId,
      ),
      view,
      capability: Capability.backupCompany,
    );
    if (helper.json(state)['artifactId'] != offer.archive.artifactId ||
        offer.archive.artifactId !=
            offer.transfer.payload.field<String>('snapshotManifestId')) {
      throw const CheckException(CheckError.unauthorized);
    }
    final file = archives.catalog.artifact(
      helper.json(state)['artifactId'] as String,
    );
    if (await file.length() > 64 * 1024 * 1024) {
      throw const CheckException(CheckError.limitExceeded);
    }
    final bytes = await file.readAsBytes();
    identity.requireActor(session);
    return bytes;
  }

  @override
  Future<void> cancel(CommandContext context) async {
    final result = await repository.commitRecovery(
      context,
      requestDigest: await digest(['cancel-handover']),
      authorize: (view) async {
        await owner(context, view);
        final state = await view.read('authority-lifecycle');
        if (state == null || !HandoverJournal.read(state).mayCancel) {
          throw const CheckException(CheckError.invalidTransition);
        }
      },
      beforeCommit: () => identity.requireActor(context.session),
      build: (view) async {
        final old = (await view.read('authority-lifecycle'))!,
            state = helper.row(
              context.companyId,
              'authority-lifecycle',
              'authorityLifecycle',
              {'state': 'active'},
              old.revision + 1,
            );
        return Mutation([state], [], [], state);
      },
    );
    helper.value(result);
  }

  @override
  Future<void> finish(
    CommandContext context,
    VerifiedMessage transferAck,
  ) async {
    final ack = transferAck.message;
    final result = await repository.commitRecovery(
      context,
      requestDigest: await digest(base64UrlEncode(helper.codec.encode(ack))),
      authorize: (view) async {
        final c = await owner(context, view),
            state = await view.read('authority-lifecycle');
        if (state == null ||
            !['offered', 'retired'].contains(helper.json(state)['state'])) {
          throw const CheckException(CheckError.invalidTransition);
        }
        final offer = offerFrom(helper.json(state)),
            next = AuthorityCertificate(
              offer.transfer.payload.field<List<Object?>>('nextAuthority'),
            );
        final trust = await companyTrust(c, view);
        await MessageVerifier(helper.signing).verify(
          ack,
          TrustContext(
            companyId: c.id,
            rootPublicKey: trust.rootPublicKey,
            authorities: [...trust.authorities, next],
          ),
        );
        if (ack.kind != MessageKind.transferAck ||
            ack.payload.field<String>('transferMessageId') !=
                offer.transfer.payload.messageId ||
            ack.payload.field<String>('snapshotManifestId') !=
                offer.archive.artifactId ||
            ack.payload.field<String>('snapshotSha256Base64Url') !=
                offer.archive.manifestSha256Base64Url ||
            jsonEncode(ack.payload.field<List<Object?>>('authority')) !=
                jsonEncode(next.values)) {
          throw const CheckException(CheckError.unauthorized);
        }
      },
      beforeCommit: () => identity.requireActor(context.session),
      build: (view) async {
        final old = (await view.read('authority-lifecycle'))!,
            state = helper.row(context.companyId, old.id, old.kind, {
              ...helper.json(old),
              'state': 'retired',
              'ack': base64UrlEncode(helper.codec.encode(ack)),
            }, old.revision + 1);
        return Mutation([state], [], [], state);
      },
    );
    helper.value(result);
  }

  @override
  Future<SignedMessage> activate(
    SessionHandle session,
    RestorePreview preview,
    HandoverOffer offer, {
    required RecoveryIdentityCandidate candidate,
  }) async {
    final activated = await _activate(
      session,
      preview,
      candidate,
      offer: offer,
    );
    return activated.ack!;
  }

  @override
  Future<RecoveryResult> recover(
    SessionHandle session,
    RestorePreview preview,
    RecoveryAcknowledgment acknowledgment, {
    required RecoveryIdentityCandidate candidate,
  }) async {
    if (!acknowledgment.acceptsMissingData ||
        acknowledgment.manifestId != preview.manifestId ||
        acknowledgment.manifestSha256Base64Url !=
            preview.manifestSha256Base64Url) {
      throw const CheckException(CheckError.unauthorized);
    }
    final result = await _activate(session, preview, candidate);
    return RecoveryResult(result.person, result.company, result.generation);
  }

  Future<
    ({String person, String company, String generation, SignedMessage? ack})
  >
  _activate(
    SessionHandle session,
    RestorePreview preview,
    RecoveryIdentityCandidate candidate, {
    HandoverOffer? offer,
  }) => archives.consumeRecoveryPreview(session, preview, (
    validated,
    files,
    apply,
  ) async {
    final d = identity.requireRecoveryIdentity(session, candidate);
    if (validated.scope is! CompanyScope ||
        (validated.scope as CompanyScope).companyId != d.companyId ||
        validated.manifest['personId'] != d.profile.personId ||
        validated.roots[d.companyId] == null) {
      throw const CheckException(CheckError.unauthorized);
    }
    final company = validated.companies[d.companyId]!;
    if (company.rootFingerprint != d.rootFingerprint) {
      throw const CheckException(CheckError.invalidSignature);
    }
    final manifestHash = base64UrlEncode(
      (await Sha256().hash(files['manifest.json']!)).bytes,
    );
    final history =
        validated.authorities[d.companyId]!
            .map(AuthorityCertificate.new)
            .toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
    late AuthorityCertificate next;
    if (offer != null) {
      final transfer = offer.transfer,
          p = transfer.payload,
          request = d.request;
      await MessageVerifier(helper.signing).verify(
        transfer,
        TrustContext(
          companyId: d.companyId,
          rootPublicKey: base64Url.decode(company.rootPublicKey),
          authorities: history,
        ),
      );
      next = AuthorityCertificate(p.field<List<Object?>>('nextAuthority'));
      if (transfer.kind != MessageKind.authorityTransfer ||
          request == null ||
          p.field<String>('targetReplacementRequestId') !=
              request.payload.messageId ||
          request.payload.field<String>('personId') != d.profile.personId ||
          request.payload.field<String?>('employeeIdOrNull') != null ||
          p.field<String>('snapshotManifestId') !=
              validated.manifest['archiveId'] ||
          p.field<String>('snapshotSha256Base64Url') != manifestHash ||
          jsonEncode(p.field<List<Object?>>('sourceAuthority')) !=
              jsonEncode(company.authority) ||
          next.installationId != d.profile.installationId ||
          base64UrlEncode(next.publicKey) !=
              base64UrlEncode(d.profile.publicKey)) {
        throw const CheckException(CheckError.unauthorized);
      }
    }
    final existing = await repository.read(d.companyId, d.companyId);
    if (existing != null &&
        Company.fromJson(helper.json(existing)).authorityGenerationId !=
            company.authorityGenerationId) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    await apply();
    // Restore only publishes passive data/root material. Activation below is a
    // fresh authorized SQLite transaction with the original live setup handle.
    if (offer == null) next = await child(company, d);
    final authority = next;
    final context = CommandContext(
      companyId: d.companyId,
      session: session,
      operationId: 'owner-activation:${d.id}',
      authorityGenerationId: authority.generationId,
    );
    final result = await repository.commitRecovery(
      context,
      requestDigest: await digest([
        preview.manifestId,
        manifestHash,
        d.id,
        authority.values,
      ]),
      releasePassive: true,
      authorize: (view) async {
        identity.requireRecoveryIdentity(session, candidate);
        final current = await view.read(d.companyId);
        if (current == null ||
            Company.fromJson(helper.json(current)).authorityGenerationId !=
                company.authorityGenerationId) {
          throw const CheckException(CheckError.recoveryRequired);
        }
        final index = await view.read('member-index:${d.profile.personId}'),
            member = index == null
                ? null
                : await view.read(helper.json(index)['membershipId'] as String);
        if (member == null ||
            !Membership.fromJson(helper.json(member)).owner ||
            !Membership.fromJson(helper.json(member)).active) {
          throw const CheckException(CheckError.unauthorized);
        }
        if ((await view.list('authorityConflict')).isNotEmpty) {
          throw const CheckException(CheckError.recoveryRequired);
        }
        final probe = helper.bytes(['owner-activation', d.id, manifestHash]);
        if (!await helper.signing.verify(
          probe,
          await helper.signing.sign(probe, d.profile.signingKeyId),
          d.profile.publicKey,
        )) {
          throw const CheckException(CheckError.recoveryRequired);
        }
        await AuthorityHistoryFile.decode(
          AuthorityHistoryFile.batches(company.id, company.rootFingerprint, [
            authority,
          ]).single,
        ).verify(helper.signing, await companyTrust(company, view));
      },
      beforeCommit: () => identity.requireRecoveryIdentity(session, candidate),
      build: (view) async {
        final oldCompany = (await view.read(company.id))!,
            index = (await view.read('member-index:${d.profile.personId}'))!,
            oldMember = (await view.read(
              helper.json(index)['membershipId'] as String,
            ))!;
        final member = Membership.fromJson(helper.json(oldMember));
        final preserved = await preserveOwnerCredentials(company, view);
        final credentials = <StoredRecord>[];
        for (final r in [
          ...await view.list('trustedCredential'),
          ...preserved,
        ]) {
          final data = helper.json(r);
          if (data['personId'] == d.profile.personId &&
              data['retired'] != true) {
            credentials.add(
              helper.row(company.id, r.id, r.kind, {
                ...data,
                'retired': true,
              }, r.revision + (preserved.contains(r) ? 0 : 1)),
            );
          }
        }
        final newMember = Membership(
          id: member.id,
          companyId: company.id,
          personId: member.personId,
          employeeId: member.employeeId,
          owner: true,
          active: true,
          capabilities: member.capabilities,
          revision: member.revision + 1,
        );
        final updated = Company(
          id: company.id,
          name: company.name,
          timeZoneId: company.timeZoneId,
          workplaceId: company.workplaceId,
          authorityGenerationId: authority.generationId,
          authoritySigningKeyId: d.profile.signingKeyId,
          rootPublicKey: company.rootPublicKey,
          rootFingerprint: company.rootFingerprint,
          authority: authority.values,
          creationPersonId: company.creationPersonId,
          creationOperationId: company.creationOperationId,
          creationDigest: company.creationDigest,
        );
        final receipt = identity.recoveryIdentityReceipt(d),
            companyRow = helper.row(
              company.id,
              company.id,
              'company',
              updated.toJson(),
              oldCompany.revision + 1,
            ),
            memberRow = helper.row(
              company.id,
              member.id,
              'membership',
              newMember.toJson(),
              newMember.revision,
            ),
            authorityRow = helper.row(
              company.id,
              authority.generationId,
              'authority',
              authority.values,
            ),
            state = await view.read('authority-lifecycle');
        final ack = offer == null
            ? null
            : await helper.sign(
                MessageKind.transferAck,
                [
                  company.id,
                  ids.next(),
                  clock.nowUtc().millisecondsSinceEpoch,
                  offer.transfer.payload.messageId,
                  preview.manifestId,
                  manifestHash,
                  authority.values,
                ],
                d.profile.signingKeyId,
                d.profile.publicKey,
              );
        final activation = helper.row(
          company.id,
          'authority-activation:${authority.generationId}',
          'authorityActivation',
          {
            'reason': offer == null ? 'recovery' : 'transfer',
            'manifestId': preview.manifestId,
            'manifestHash': manifestHash,
            'personId': member.personId,
            'ack': ack == null
                ? null
                : base64UrlEncode(helper.codec.encode(ack)),
          },
        );
        return Mutation(
          [
            companyRow,
            memberRow,
            receipt,
            ...credentials,
            helper.row(
              company.id,
              'authority-lifecycle',
              'authorityLifecycle',
              {'state': 'active'},
              (state?.revision ?? 0) + 1,
            ),
          ],
          [activation],
          [],
          activation,
          authorityHistory: [authorityRow],
          personalRecords: [
            for (final r in [
              companyRow,
              memberRow,
              authorityRow,
              ...credentials,
            ])
              PersonalRecordAssociation(member.personId, r.id),
          ],
        );
      },
    );
    final accepted = helper.json(helper.value(result));
    await identity.publishRecoveryIdentity(session, candidate);
    return (
      person: d.profile.personId,
      company: d.companyId,
      generation: authority.generationId,
      ack: accepted['ack'] == null
          ? null
          : helper.codec.decode(
              base64Url.decode(accepted['ack'] as String),
              maxBytes: MessageLimits.fileBytes,
            ),
    );
  });
}
