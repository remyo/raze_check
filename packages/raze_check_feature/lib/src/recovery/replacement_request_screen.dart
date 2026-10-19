import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'recovery_shared.dart';

class ReplacementRequestScreen extends StatefulWidget {
  const ReplacementRequestScreen({
    super.key,
    required this.identity,
    required this.session,
    required this.recoveryIdentity,
    required this.enrollment,
    required this.service,
    required this.restores,
    required this.files,
  });
  final IdentityService identity;
  final RecoveryIdentityService recoveryIdentity;
  final SessionHandle session;
  final EnrollmentService enrollment;
  final DeviceReplacementService service;
  final RestoreService restores;
  final RecoveryFiles files;
  @override
  State<ReplacementRequestScreen> createState() => _ReplacementRequestState();
}

class _ReplacementRequestState extends RecoveryState<ReplacementRequestScreen> {
  @override
  IdentityService get identity => widget.identity;
  @override
  SessionHandle get session => widget.session;
  final person = TextEditingController(),
      employee = TextEditingController(),
      name = TextEditingController(),
      pass = TextEditingController(),
      confirm = TextEditingController(),
      archivePass = TextEditingController();
  SignedMessage? invitation, request;
  Uint8List? invitationBytes;
  String? fingerprint;
  bool consent = false, pinned = false, activated = false;
  InvitationCandidate? candidateRoot;
  bool continuation = false;
  RecoveryIdentityCandidate? candidate;
  @override
  void dispose() {
    if (candidateRoot != null &&
        widget.enrollment is InvitationHistoryService) {
      (widget.enrollment as InvitationHistoryService).cancelInvitation(
        candidateRoot!,
      );
    }
    if (candidate != null && !activated) {
      unawaited(
        widget.recoveryIdentity
            .cancelRecoveryIdentity(session, candidate!)
            .catchError((Object _) {}),
      );
    }
    for (final c in [person, employee, name, pass, confirm, archivePass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> readInvitation() async {
    final bytes = await widget.files.pickBytes(guard);
    if (bytes == null) return;
    await guard();
    final m = MessageCodec().decode(bytes, maxBytes: MessageLimits.fileBytes);
    if (m.kind != MessageKind.invitation) {
      throw const CheckException(CheckError.malformed);
    }
    final f = await invitationRootFingerprint(m);
    await guard();
    if (candidateRoot != null &&
        widget.enrollment is InvitationHistoryService) {
      (widget.enrollment as InvitationHistoryService).cancelInvitation(
        candidateRoot!,
      );
    }
    setState(() {
      invitation = m;
      invitationBytes = bytes;
      fingerprint = f;
      consent = false;
      pinned = false;
      candidateRoot = null;
    });
  }

  Future<void> acceptRoot() async {
    final service = widget.enrollment as InvitationHistoryService;
    candidateRoot ??= await service.beginInvitation(
      session,
      invitationBytes!,
      acceptedRootFingerprint: fingerprint!,
    );
    await service.verifyInvitationCandidate(session, candidateRoot!);
    await guard();
    setState(() => pinned = true);
  }

  Future<void> stageHistory() async {
    final service = widget.enrollment;
    if (service is! InvitationHistoryService) {
      throw const CheckException(CheckError.invalidTransition);
    }
    candidateRoot ??= await (service as InvitationHistoryService)
        .beginInvitation(
          session,
          invitationBytes!,
          acceptedRootFingerprint: fingerprint!,
        );
    final bytes = await widget.files.pickBytes(guard);
    if (bytes == null) return;
    await guard();
    await (service as InvitationHistoryService).stageHistory(
      session,
      candidateRoot!,
      bytes,
    );
    message =
        'Public ancestors staged. Finish company consent after all batches are added.';
  }

  Future<void> prepare() async {
    if (continuation) {
      if (identity.requireActor(session).personId != person.text.trim()) {
        throw const CheckException(CheckError.unauthorized);
      }
      candidate = await widget.recoveryIdentity.continueRecoveryIdentity(
        session,
        companyId: invitation!.payload.companyId,
        rootFingerprint: fingerprint!,
      );
    } else {
      confirmedPassphrase(pass, confirm);
      final secret = pass.text;
      pass.clear();
      confirm.clear();
      candidate = await widget.recoveryIdentity.stageRecoveryIdentity(
        session,
        companyId: invitation!.payload.companyId,
        personId: person.text.trim(),
        displayName: name.text.trim(),
        rootFingerprint: fingerprint!,
        passphrase: secret,
      );
    }
    await (widget.enrollment as RecoveryInvitationService)
        .bindRecoveryInvitation(session, candidateRoot!, candidate!);
    request = await widget.service.createRequest(
      session,
      invitation!.payload.companyId,
      employee.text.trim(),
      candidate: candidate!,
    );
    await guard();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => frame('Recover staff on this device', [
    const Text(
      'Ask your manager for your original person and employee IDs. These public identifiers alone do not unlock records. Ordinary login cannot recover unsynchronized records.',
    ),
    button(
      'Read company invitation',
      readInvitation,
      enabled: candidate == null,
    ),
    if (invitation != null) ...[
      Text(invitation!.payload.field<String>('companyLabel')),
      SelectableText(fingerprint!),
      CheckboxListTile(
        value: consent,
        onChanged: busy || candidate != null
            ? null
            : (v) => setState(() => consent = v ?? false),
        title: const Text(
          'I compared the full root fingerprint with management',
        ),
      ),
      button('Confirm company trust', acceptRoot, enabled: consent && !pinned),
      button(
        'Add missing public history file',
        stageHistory,
        enabled: consent && !pinned,
      ),
      const Text(
        'After authority changes, ask management for every missing .razecheck-history batch. A root key alone cannot recreate missing historical certificates.',
      ),
    ],
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
                pass.clear();
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
      'Original person ID',
      enabled: candidate == null && !continuation,
    ),
    field(employee, 'Employee ID', enabled: candidate == null),
    if (!continuation) field(name, 'Display name', enabled: candidate == null),
    if (!continuation)
      field(
        pass,
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
          : 'Create fresh replacement request',
      prepare,
      enabled: pinned && candidate == null,
    ),
    if (request != null) ...[
      const Text(
        'New attendance is disabled until the exact returned manager grant is accepted. Old records remain historical evidence.',
      ),
      button(
        'Share replacement request',
        () async => send(
          widget.files,
          MessageCodec().encode(request!),
          'replacement.razecheck-message',
        ),
      ),
      field(archivePass, 'Staff recovery archive passphrase', secret: true),
      button('Apply received-record archive', () async {
        final path = await widget.files.pickArchive(guard);
        if (path == null) return;
        RestorePreview? preview;
        try {
          await guard();
          final secret = archivePass.text;
          archivePass.clear();
          preview = await widget.restores.inspect(session, path, secret);
          if (preview.personId != person.text.trim() ||
              !preview.companyIds.contains(invitation!.payload.companyId)) {
            throw const CheckException(CheckError.wrongCompany);
          }
          await (widget.restores as StaffRecoveryRestoreService)
              .applyRecoveryPersonal(session, preview, candidate!);
          message =
              'Received records applied passively. Accept the exact replacement grant to activate this installation.';
        } finally {
          if (preview != null) await widget.restores.discard(preview);
          await widget.files.releaseArchive(path);
        }
      }, enabled: !activated),
      button('Receive replacement grant', () async {
        final bytes = await widget.files.pickBytes(guard);
        if (bytes == null) return;
        await guard();
        final grant = await widget.service.verifyPendingGrant(
              session,
              bytes,
              candidate: candidate!,
            ),
            result = await widget.service.accept(
              session,
              grant,
              candidate: candidate!,
            );
        switch (result) {
          case Rejected<Membership>():
            throw CheckException(result.error);
          case VersionConflict<Membership>():
            throw const CheckException(CheckError.invalidTransition);
          case Committed<Membership>():
            activated = true;
        }
        if (mounted) {
          setState(
            () => message = continuation
                ? 'This company is authorized. Close this screen, lock, and unlock with your existing local passphrase.'
                : 'Original identity activated for this company. Close this screen, lock, and unlock the original person using your new local passphrase.',
          );
        }
      }, enabled: !activated),
    ],
    const Text(
      'Without a personal backup, management can return only records it received. Receipts stored only on the lost phone cannot be recovered. Apply the selected staff archive before accepting the grant; backups remain passive until authorization.',
    ),
  ]);
}

class ReplacementApprovalScreen extends StatefulWidget {
  const ReplacementApprovalScreen({
    super.key,
    required this.identity,
    required this.session,
    required this.company,
    required this.companies,
    required this.enrollment,
    required this.service,
    required this.backups,
    required this.staffBackups,
    required this.files,
  });
  final IdentityService identity;
  final SessionHandle session;
  final Company company;
  final CompanyService companies;
  final EnrollmentService enrollment;
  final DeviceReplacementService service;
  final BackupService backups;
  final StaffRecoveryBackupService staffBackups;
  final RecoveryFiles files;
  @override
  State<ReplacementApprovalScreen> createState() => _ReplacementApprovalState();
}

class _ReplacementApprovalState
    extends RecoveryState<ReplacementApprovalScreen> {
  @override
  IdentityService get identity => widget.identity;
  @override
  SessionHandle get session => widget.session;
  List<StaffRecord> staff = [];
  StaffRecord? selected;
  VerifiedMessage? request;
  SignedMessage? grant;
  bool confirmed = false, exportAllowed = false;
  final pass = TextEditingController(), confirm = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      run(() async {
        staff = await widget.service.subjects(session, widget.company.id);
        final member = await widget.companies.membership(
          session,
          widget.company.id,
        );
        exportAllowed =
            member != null &&
            AccessPolicy.eligible(member, Capability.manageMemberships) &&
            AccessPolicy.eligible(member, Capability.exportAttendance);
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    pass.dispose();
    confirm.dispose();
    super.dispose();
  }

  CommandContext command() => CommandContext(
    companyId: widget.company.id,
    session: session,
    operationId: SecureIds().next(),
    authorityGenerationId: widget.company.authorityGenerationId,
  );
  @override
  Widget build(BuildContext context) => frame('Approve staff replacement', [
    DropdownButton<StaffRecord>(
      value: selected,
      hint: const Text('Select the original employee'),
      isExpanded: true,
      items: [
        for (final s in staff)
          DropdownMenuItem(value: s, child: Text(s.details.name)),
      ],
      onChanged: busy
          ? null
          : (s) => setState(() {
              selected = s;
              request = null;
              grant = null;
              confirmed = false;
            }),
    ),
    if (selected != null) ...[
      SelectableText(
        'Company ID: ${widget.company.id}\nOriginal person ID: ${selected!.personId}\nEmployee ID: ${selected!.employeeId}',
      ),
      const Text(
        'Give these public identifiers and a company invitation to the employee. Verify the person before approving their new installation.',
      ),
      button('Read staff replacement request', () async {
        final bytes = await widget.files.pickBytes(guard);
        if (bytes == null) return;
        await guard();
        final r = await widget.enrollment.verifyIncoming(session, bytes);
        if (r.message.kind != MessageKind.replacementRequest ||
            r.message.payload.companyId != widget.company.id ||
            r.message.payload.field<String>('personId') != selected!.personId ||
            r.message.payload.field<String?>('employeeIdOrNull') !=
                selected!.employeeId) {
          throw const CheckException(CheckError.unauthorized);
        }
        setState(() {
          request = r;
          confirmed = false;
        });
      }),
    ],
    if (request != null) ...[
      SelectableText(
        'New installation: ${request!.message.payload.field<String>('newInstallationId')}',
      ),
      CheckboxListTile(
        value: confirmed,
        onChanged: busy ? null : (v) => setState(() => confirmed = v ?? false),
        title: const Text('I verified this employee and replacement device'),
      ),
      button('Authorize replacement', () async {
        grant = await widget.service.authorize(command(), request!);
        if (mounted) setState(() {});
      }, enabled: confirmed && grant == null),
    ],
    if (grant != null) ...[
      button(
        'Share replacement grant',
        () async => send(
          widget.files,
          MessageCodec().encode(grant!),
          'replacement-grant.razecheck-message',
        ),
      ),
      if (exportAllowed) ...[
        const Text(
          'Received-record recovery requires both membership management and attendance export permissions. It excludes company recovery keys, other staff, and records never received by management.',
        ),
        field(pass, 'Staff archive passphrase', secret: true),
        field(confirm, 'Confirm staff archive passphrase', secret: true),
        button('Export selected staff recovery archive', () async {
          confirmedPassphrase(pass, confirm);
          final secret = pass.text;
          pass.clear();
          confirm.clear();
          final artifact = await widget.staffBackups.createStaffRecovery(
            command(),
            request!,
            grant!,
            secret,
          );
          await send(
            widget.files,
            await widget.backups.shareBytes(session, artifact.artifactId),
            'staff-recovery.razecheck-backup',
          );
        }),
      ],
    ],
  ]);
}
