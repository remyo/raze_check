import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'recovery_shared.dart';
import 'replacement_request_screen.dart';
import 'recovery_unlock_screen.dart';
import 'handover_screen.dart';
import 'authority_history_screen.dart';

class RecoveryWorkspace extends StatefulWidget {
  const RecoveryWorkspace({
    super.key,
    required this.identity,
    required this.session,
    required this.recoveryIdentity,
    required this.companies,
    required this.enrollment,
    required this.replacement,
    required this.handover,
    required this.history,
    required this.backups,
    required this.staffBackups,
    required this.restores,
    required this.files,
    required this.openBackup,
  });
  final IdentityService identity;
  final RecoveryIdentityService recoveryIdentity;
  final SessionHandle session;
  final CompanyService companies;
  final EnrollmentService enrollment;
  final DeviceReplacementService replacement;
  final HandoverService handover;
  final AuthorityHistoryService history;
  final BackupService backups;
  final StaffRecoveryBackupService staffBackups;
  final RestoreService restores;
  final RecoveryFiles files;
  final Future<void> Function() openBackup;
  @override
  State<RecoveryWorkspace> createState() => _RecoveryWorkspaceState();
}

class _RecoveryWorkspaceState extends RecoveryState<RecoveryWorkspace> {
  @override
  IdentityService get identity => widget.identity;
  @override
  SessionHandle get session => widget.session;
  List<Company> companies = [];
  Company? selected;
  Membership? member;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      run(() async {
        companies = await widget.companies.listCompanies(session);
        if (mounted) setState(() {});
      });
    });
  }

  Future<void> open(Widget child) async {
    await guard();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => child));
  }

  @override
  Widget build(BuildContext context) => frame('Backup and device recovery', [
    button('Encrypted backup and passive restore', widget.openBackup),
    button(
      'Recover staff identity on this device',
      () async => open(
        ReplacementRequestScreen(
          identity: identity,
          recoveryIdentity: widget.recoveryIdentity,
          session: session,
          enrollment: widget.enrollment,
          service: widget.replacement,
          restores: widget.restores,
          files: widget.files,
        ),
      ),
    ),
    button(
      'Activate or recover owner on this device',
      () async => open(
        RecoveryUnlockScreen(
          identity: identity,
          recoveryIdentity: widget.recoveryIdentity,
          session: session,
          replacement: widget.replacement,
          handover: widget.handover,
          restores: widget.restores,
          files: widget.files,
        ),
      ),
    ),
    DropdownButton<Company>(
      value: selected,
      hint: const Text('Select company for export or source actions'),
      isExpanded: true,
      items: [
        for (final c in companies)
          DropdownMenuItem(value: c, child: Text(c.name)),
      ],
      onChanged: busy
          ? null
          : (c) => run(() async {
              final m = await widget.companies.membership(session, c!.id);
              if (mounted) {
                setState(() {
                  selected = c;
                  member = m;
                });
              }
            }),
    ),
    if (selected != null) ...[
      button(
        'Public authority history',
        () async => open(
          AuthorityHistoryScreen(
            identity: identity,
            session: session,
            company: selected!,
            service: widget.history,
            files: widget.files,
          ),
        ),
      ),
      if (member != null &&
          AccessPolicy.eligible(member!, Capability.manageMemberships))
        button(
          'Approve staff replacement and recovery export',
          () async => open(
            ReplacementApprovalScreen(
              identity: identity,
              session: session,
              company: selected!,
              companies: widget.companies,
              enrollment: widget.enrollment,
              service: widget.replacement,
              backups: widget.backups,
              staffBackups: widget.staffBackups,
              files: widget.files,
            ),
          ),
        ),
      if (member?.owner == true)
        button('Resend owner activation acknowledgment', () async {
          final ack = await widget.handover.activationAcknowledgment(
            session,
            selected!.id,
          );
          if (ack == null) {
            message = 'This device has no handover acknowledgment.';
            return;
          }
          await send(
            widget.files,
            MessageCodec().encode(ack),
            'transfer-ack.razecheck-message',
          );
        }),
      if (member?.owner == true)
        button(
          'Move this owner device',
          () async => open(
            HandoverScreen(
              identity: identity,
              session: session,
              company: selected!,
              enrollment: widget.enrollment,
              service: widget.handover,
              files: widget.files,
            ),
          ),
        ),
    ],
  ]);
}
