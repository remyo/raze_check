import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'recovery_shared.dart';
import '../guides/recovery_guide_bindings.dart';
import '../guides/guide_target.dart';

class HandoverScreen extends StatefulWidget {
  const HandoverScreen({
    super.key,
    required this.identity,
    required this.session,
    required this.company,
    required this.enrollment,
    required this.service,
    required this.files,
    this.companies,
  });
  final IdentityService identity;
  final SessionHandle session;
  final Company company;
  final EnrollmentService enrollment;
  final HandoverService service;
  final RecoveryFiles files;
  final CompanyService? companies;
  @override
  State<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends RecoveryState<HandoverScreen> {
  @override
  IdentityService get identity => widget.identity;
  @override
  SessionHandle get session => widget.session;
  final pass = TextEditingController(), confirm = TextEditingController();
  VerifiedMessage? request;
  HandoverOffer? offer;
  @override
  String get recoveryVariant => 'owner-source';
  @override
  bool get guideOwner =>
      _guideMember?.owner == true && _guideMember?.active == true;
  Membership? _guideMember;
  @override
  Future<void> validateGuide() async {
    await super.validateGuide();
    final member = _guideMember;
    final current = await widget.companies?.membership(
      session,
      widget.company.id,
    );
    await super.validateGuide();
    if (current?.owner != true ||
        current?.active != true ||
        !identical(_guideMember, member) ||
        !sameRecoveryMembership(member, current)) {
      throw const CheckException(CheckError.unauthorized);
    }
  }

  @override
  Object get recoverySceneIdentity =>
      (session, widget.company.id, _guideMember, request, offer, hidden);
  bool samePerson = false;
  final operation = SecureIds().next();
  CommandContext contextFor(String id) => CommandContext(
    companyId: widget.company.id,
    session: session,
    operationId: id,
    authorityGenerationId: widget.company.authorityGenerationId,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      run(() async {
        _guideMember = await widget.companies?.membership(
          session,
          widget.company.id,
        );
        await guard();
        offer = await widget.service.pendingOffer(session, widget.company.id);
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

  Future<void> readRequest() async {
    final bytes = await nativeTransfer(() => widget.files.pickBytes(guard));
    if (bytes == null) return;
    await guard();
    final verified = await widget.enrollment.verifyIncoming(session, bytes);
    if (verified.message.kind != MessageKind.replacementRequest ||
        verified.message.payload.companyId != widget.company.id ||
        verified.message.payload.field<String?>('employeeIdOrNull') != null) {
      throw const CheckException(CheckError.malformed);
    }
    await guard();
    setState(() {
      request = verified;
      samePerson = false;
    });
  }

  Future<void> begin() async {
    confirmedPassphrase(pass, confirm);
    final secret = pass.text;
    pass.clear();
    confirm.clear();
    final result = await widget.service.begin(
      contextFor(operation),
      request!,
      archivePassphrase: secret,
    );
    if (mounted) setState(() => offer = result);
  }

  @override
  Widget build(BuildContext context) {
    return frame('Move owner to another device', [
      const Text(
        'This moves the same person to a fresh installation. It does not transfer company ownership.',
      ),
      GuideTarget(
        id: 'new-device-identity',
        child: SelectableText(
          'Company ID: ${widget.company.id}\nOriginal person ID: ${widget.company.creationPersonId}\nRoot fingerprint: ${widget.company.rootFingerprint}',
        ),
      ),
      const Text(
        'Copy these public identifiers to the new device. Keep both devices and your archive until the new device verifies activation.',
      ),
      button(
        'Read target replacement request',
        readRequest,
        enabled: offer == null,
      ),
      if (request != null) ...[
        SelectableText(
          'Requested person: ${request!.message.payload.field<String>('personId')}\nNew installation: ${request!.message.payload.field<String>('newInstallationId')}',
        ),
        CheckboxListTile(
          value: samePerson,
          onChanged: busy
              ? null
              : (v) => setState(() => samePerson = v ?? false),
          title: const Text(
            'I verified this is my replacement device for the same person',
          ),
        ),
        field(pass, 'Archive passphrase', secret: true),
        field(confirm, 'Confirm archive passphrase', secret: true),
        button(
          'Freeze source and prepare handover',
          begin,
          enabled: samePerson && offer == null,
        ),
      ],
      const Text(
        'Preparation freezes management before the final snapshot. After an offer is issued, a missing acknowledgment never unlocks the source automatically.',
      ),
      button('Cancel preparation before offer', () async {
        await widget.service.cancel(contextFor(SecureIds().next()));
        message = 'Preparation canceled. Management can resume.';
      }, enabled: offer == null),
      if (offer != null) ...[
        button(
          'Share exact handover archive',
          () async => send(
            widget.files,
            await widget.service.exportArtifact(session, offer!),
            'handover.razecheck-backup',
          ),
        ),
        button(
          'Share signed handover offer',
          () async => send(
            widget.files,
            MessageCodec().encode(offer!.transfer),
            'handover.razecheck-message',
          ),
        ),
        button('Receive target acknowledgment', () async {
          final bytes = await nativeTransfer(
            () => widget.files.pickBytes(guard),
          );
          if (bytes == null) return;
          await guard();
          final ack = await widget.enrollment.verifyIncoming(session, bytes);
          await widget.service.finish(contextFor(SecureIds().next()), ack);
          message =
              'Source authority retired. Historical records remain on this device.';
        }),
      ],
    ]);
  }
}
