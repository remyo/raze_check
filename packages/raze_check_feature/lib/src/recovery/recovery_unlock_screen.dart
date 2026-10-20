import 'dart:async';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'recovery_shared.dart';
import '../guides/guide_target.dart';

class RecoveryUnlockScreen extends StatefulWidget {
  const RecoveryUnlockScreen({
    super.key,
    required this.identity,
    required this.recoveryIdentity,
    required this.session,
    required this.replacement,
    required this.handover,
    required this.restores,
    required this.files,
  });
  final IdentityService identity;
  final RecoveryIdentityService recoveryIdentity;
  final SessionHandle session;
  final DeviceReplacementService replacement;
  final HandoverService handover;
  final RestoreService restores;
  final RecoveryFiles files;
  @override
  State<RecoveryUnlockScreen> createState() => _RecoveryUnlockState();
}

class _RecoveryUnlockState extends RecoveryState<RecoveryUnlockScreen> {
  @override
  IdentityService get identity => widget.identity;
  @override
  SessionHandle get session => widget.session;
  final company = TextEditingController(),
      person = TextEditingController(),
      root = TextEditingController(),
      name = TextEditingController(),
      local = TextEditingController(),
      confirm = TextEditingController(),
      archivePass = TextEditingController();
  bool consent = false, missing = false, activated = false;
  bool lostSource = false;
  @override
  String get recoveryVariant => lostSource ? 'owner-recovery' : 'owner-target';
  @override
  Object get recoverySceneIdentity => (
    session,
    recoveryVariant,
    candidate,
    preview,
    transfer,
    activated,
    hidden,
  );
  bool continuation = false;
  RecoveryIdentityCandidate? candidate;
  SignedMessage? request, transfer, ack;
  RestorePreview? preview;
  @override
  void dispose() {
    if (preview != null) {
      unawaited(widget.restores.discard(preview!).catchError((Object _) {}));
    }
    if (candidate != null && !activated) {
      unawaited(
        widget.recoveryIdentity
            .cancelRecoveryIdentity(session, candidate!)
            .catchError((Object _) {}),
      );
    }
    for (final c in [
      company,
      person,
      root,
      name,
      local,
      confirm,
      archivePass,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> inspect() async {
    final path = await nativeTransfer(() => widget.files.pickArchive(guard));
    if (path == null) return;
    try {
      await guard();
      final passphrase = archivePass.text;
      archivePass.clear();
      final incoming = await widget.restores.inspect(session, path, passphrase);
      if (incoming.companyIds.length != 1 ||
          candidate != null &&
              (incoming.personId != person.text.trim() ||
                  incoming.companyIds.single != company.text.trim() ||
                  incoming.companyRootFingerprints[company.text.trim()] !=
                      root.text.trim())) {
        await widget.restores.discard(incoming);
        throw const CheckException(CheckError.wrongCompany);
      }
      if (preview != null) await widget.restores.discard(preview!);
      preview = incoming;
      if (candidate == null) {
        company.text = incoming.companyIds.single;
        person.text = incoming.personId;
        root.text = incoming.companyRootFingerprints[company.text] ?? '';
        consent = false;
      }
      await guard();
      setState(() => missing = false);
    } finally {
      await widget.files.releaseArchive(path);
    }
  }

  Future<void> prepare() async {
    if (continuation) {
      if (identity.requireActor(session).personId != person.text.trim()) {
        throw const CheckException(CheckError.unauthorized);
      }
      candidate = await widget.recoveryIdentity.continueRecoveryIdentity(
        session,
        companyId: company.text.trim(),
        rootFingerprint: root.text.trim(),
      );
    } else {
      confirmedPassphrase(local, confirm);
      final secret = local.text;
      local.clear();
      confirm.clear();
      candidate = await widget.recoveryIdentity.stageRecoveryIdentity(
        session,
        companyId: company.text.trim(),
        personId: person.text.trim(),
        displayName: name.text.trim(),
        rootFingerprint: root.text.trim(),
        passphrase: secret,
      );
    }
    request = await widget.replacement.createRequest(
      session,
      company.text.trim(),
      null,
      candidate: candidate!,
    );
    await guard();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => frame('Activate owner on this device', [
    GuideTarget(
      id: 'new-device-path',
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Source device available')),
          ButtonSegment(value: true, label: Text('Source device lost')),
        ],
        selected: {lostSource},
        onSelectionChanged: busy
            ? null
            : (values) => setState(() => lostSource = values.single),
      ),
    ),
    if (lostSource)
      const Text(
        'Lost-source recovery requires a usable company backup. Inspect your real backup to continue; guidance cannot recreate missing records.',
      ),
    const Text(
      'Use this for the same owner on a replacement device. Enter public identifiers from the source device, or inspect your company recovery backup first. Ordinary login does not restore offline data.',
    ),
    field(company, 'Company ID', enabled: candidate == null),
    CheckboxListTile(
      value: continuation,
      onChanged: busy || candidate != null
          ? null
          : (value) => run(() async {
              final actor = identity.requireActor(session);
              if (value == true && actor.authorizedCompanyIds == null) {
                throw const CheckException(CheckError.unauthorized);
              }
              setState(() {
                continuation = value ?? false;
                if (continuation) person.text = actor.personId;
                local.clear();
                confirm.clear();
              });
            }),
      title: const Text(
        'Recover another company for this already unlocked person',
      ),
      subtitle: const Text(
        'Keeps this device key, local passphrase and existing company access. The selected company still requires its own proof.',
      ),
    ),
    field(
      person,
      'Original owner person ID',
      enabled: candidate == null && !continuation,
    ),
    field(root, 'Full company root fingerprint', enabled: candidate == null),
    if (!continuation) field(name, 'Display name', enabled: candidate == null),
    CheckboxListTile(
      value: consent,
      onChanged: busy || candidate != null
          ? null
          : (v) => setState(() => consent = v ?? false),
      title: const Text(
        'I confirmed this company root and my original identity',
      ),
    ),
    if (!continuation)
      field(
        local,
        'New local passphrase',
        secret: true,
        enabled: candidate == null,
      ),
    if (!continuation)
      field(
        confirm,
        'Confirm local passphrase',
        secret: true,
        enabled: candidate == null,
      ),
    button(
      continuation
          ? 'Prepare company recovery with current identity'
          : 'Prepare fresh owner installation',
      prepare,
      enabled: consent && candidate == null,
    ),
    if (request != null)
      button(
        'Share target request with source device',
        () async => send(
          widget.files,
          MessageCodec().encode(request!),
          'owner-target.razecheck-message',
        ),
      ),
    field(archivePass, 'Encrypted archive passphrase', secret: true),
    button(
      'Inspect company recovery or handover archive',
      inspect,
      enabled: !activated,
    ),
    const Text(
      'Without a usable company recovery backup and its passphrase, a lost owner device cannot be recovered here. Records created after the backup or never synchronized are unavailable.',
    ),
    if (preview != null) ...[
      Text(
        'Verified checkpoint: ${preview!.manifestId}\nExact manifest SHA-256: ${preview!.manifestSha256Base64Url}',
      ),
      for (final e in preview!.counts.entries) Text('${e.key}: ${e.value}'),
      for (final conflict in preview!.conflicts) Text(conflict),
      CheckboxListTile(
        value: missing,
        onChanged: busy ? null : (v) => setState(() => missing = v ?? false),
        title: const Text(
          'I accept this checkpoint and understand newer or unsynchronized records may be missing',
        ),
      ),
      button('Read signed source handover offer', () async {
        final bytes = await nativeTransfer(() => widget.files.pickBytes(guard));
        if (bytes == null) return;
        await guard();
        final m = MessageCodec().decode(
          bytes,
          maxBytes: MessageLimits.fileBytes,
        );
        if (m.kind != MessageKind.authorityTransfer) {
          throw const CheckException(CheckError.malformed);
        }
        setState(() => transfer = m);
      }, enabled: !activated),
      if (transfer != null)
        button(
          'Verify and activate handover',
          () async {
            final p = preview!,
                offer = HandoverOffer(
                  transfer!,
                  ArchiveDescriptor(
                    artifactId: p.manifestId,
                    createdUtcMs: 0,
                    scope: CompanyScope(company.text.trim()),
                    counts: p.counts,
                    manifestSha256Base64Url: p.manifestSha256Base64Url,
                  ),
                );
            ack = await widget.handover.activate(
              session,
              p,
              offer,
              candidate: candidate!,
            );
            activated = true;
            message = continuation
                ? 'This company is authorized. Send the acknowledgment, then lock and unlock with your existing local passphrase.'
                : 'Owner activated. Send the acknowledgment, then lock and unlock your original identity with the new local passphrase.';
          },
          enabled: missing && candidate != null && !activated,
        ),
      button(
        'Recover when source device is lost',
        () async {
          final p = preview!;
          await widget.handover.recover(
            session,
            p,
            RecoveryAcknowledgment(
              manifestId: p.manifestId,
              manifestSha256Base64Url: p.manifestSha256Base64Url,
              acceptsMissingData: missing,
            ),
            candidate: candidate!,
          );
          activated = true;
          message = continuation
              ? 'This company is authorized. Lock and unlock with your existing local passphrase. A returning old device requires reconciliation.'
              : 'Owner recovery activated. Lock and unlock your original identity with the new local passphrase. A returning old device requires reconciliation.';
        },
        enabled: missing && candidate != null && !activated && transfer == null,
      ),
    ],
    if (ack != null)
      button(
        'Share activation acknowledgment',
        () async => send(
          widget.files,
          MessageCodec().encode(ack!),
          'transfer-ack.razecheck-message',
        ),
      ),
  ]);
}
