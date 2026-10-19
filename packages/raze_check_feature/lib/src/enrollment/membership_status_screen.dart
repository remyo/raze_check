import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../profile/profile_commands.dart';
import 'invitation_screen.dart';
import 'join_company_screen.dart';
import 'join_review_screen.dart';

class MembershipStatusScreen extends StatelessWidget {
  const MembershipStatusScreen({
    super.key,
    required this.active,
    required this.busy,
    required this.onReceive,
    this.request,
    this.onResend,
  });
  final bool active, busy;
  final SignedMessage? request;
  final VoidCallback onReceive;
  final VoidCallback? onResend;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(active ? 'Membership active' : 'Awaiting manager approval'),
      Text(
        active
            ? 'Your membership is saved on this installation.'
            : 'You cannot record attendance until your approved membership is received.',
      ),
      if (request != null) EnrollmentMessageView(message: request!),
      if (!active && onResend != null)
        TextButton(
          onPressed: busy ? null : onResend,
          child: const Text('Send join request again'),
        ),
      if (!active)
        FilledButton(
          onPressed: busy ? null : onReceive,
          child: const Text('Receive membership'),
        ),
    ],
  );
}

/// Shared workflow for camera/file adapters or deterministic byte ports. Every
/// completion retains the original session and company command context.
class EnrollmentWorkspace extends StatefulWidget {
  const EnrollmentWorkspace({
    super.key,
    required this.service,
    required this.session,
    required this.ids,
    required this.messages,
    this.company,
    this.canManage = false,
    this.owner = false,
    this.manualStaff = const [],
    required this.onChanged,
    required this.onLocked,
  });
  final EnrollmentService service;
  final SessionHandle session;
  final IdGenerator ids;
  final EnrollmentMessagePort messages;
  final Company? company;
  final bool canManage, owner;
  final List<StaffRecord> manualStaff;
  final VoidCallback onChanged, onLocked;
  @override
  State<EnrollmentWorkspace> createState() => _EnrollmentWorkspaceState();
}

class _EnrollmentWorkspaceState extends State<EnrollmentWorkspace> {
  bool _busy = false, _accepted = false, _active = false;
  String? _error, _fingerprint, _existingEmployeeId;
  SignedMessage? _invitation, _candidate, _pending, _grant;
  Uint8List? _candidateBytes;
  VerifiedMessage? _review;
  late String _operation = widget.ids.next();
  int _epoch = 0;
  bool _current(int epoch) => mounted && epoch == _epoch;
  List<SignedMessage> _savedPending = [];
  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    if (widget.canManage) return;
    await _run((epoch, session) async {
      final pending = await widget.service.pendingJoins(session);
      if (!_current(epoch)) return;
      setState(() {
        _savedPending = pending;
        _pending = pending.firstOrNull;
      });
    });
  }

  @override
  void didUpdateWidget(EnrollmentWorkspace old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session) ||
        old.company?.id != widget.company?.id) {
      _epoch++;
      _busy = false;
      _accepted = false;
      _active = false;
      _error = null;
      _fingerprint = null;
      _existingEmployeeId = null;
      _invitation = null;
      _candidate = null;
      _candidateBytes = null;
      _pending = null;
      _grant = null;
      _review = null;
      _operation = widget.ids.next();
      _savedPending = [];
      _loadPending();
    }
  }

  CommandContext _context() => CommandContext(
    companyId: widget.company!.id,
    session: widget.session,
    operationId: _operation,
    authorityGenerationId: widget.company!.authorityGenerationId,
  );
  Future<void> _run(
    Future<void> Function(int epoch, SessionHandle session) action,
  ) async {
    final epoch = _epoch, session = widget.session;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(epoch, session);
    } catch (e) {
      if (!_current(epoch)) return;
      if (e is CheckException && e.code == CheckError.locked) {
        widget.onLocked();
        return;
      }
      setState(
        () => _error = profileError(
          e is CheckException ? e.code : CheckError.storageFailure,
        ),
      );
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  T _committed<T>(CommandResult<T> result) => switch (result) {
    Committed<T>() => result.value,
    Rejected<T>() => throw CheckException(result.error),
    VersionConflict<T>() => throw const CheckException(
      CheckError.invalidTransition,
    ),
  };
  Future<void> _readInvitation() => _run((epoch, session) async {
    final bytes = await widget.messages.receive();
    if (bytes == null || !_current(epoch)) return;
    final candidate = MessageCodec().decode(
      bytes,
      maxBytes: MessageLimits.fileBytes,
    );
    final fingerprint = await invitationRootFingerprint(candidate);
    if (!_current(epoch)) return;
    setState(() {
      _candidate = candidate;
      _candidateBytes = Uint8List.fromList(bytes);
      _fingerprint = fingerprint;
      _accepted = false;
      _operation = widget.ids.next();
    });
  });
  Future<void> _confirm() => _run((epoch, session) async {
    final bytes = _candidateBytes!,
        fingerprint = _fingerprint!,
        operation = _operation;
    final invitation = await widget.service.acceptInvitation(
      session,
      bytes,
      acceptedRootFingerprint: fingerprint,
    );
    if (!_current(epoch)) return;
    final join = await widget.service.requestJoin(
      session,
      invitation,
      operation,
    );
    if (!_current(epoch)) return;
    setState(() {
      _pending = join;
      _candidate = null;
    });
    widget.onChanged();
    await widget.messages.send(MessageCodec().encode(join));
  });
  Future<void> _receiveGrant() => _run((epoch, session) async {
    final bytes = await widget.messages.receive();
    if (bytes == null || !_current(epoch)) return;
    final verified = await widget.service.verifyIncoming(session, bytes);
    if (!_current(epoch)) return;
    _committed(await widget.service.acceptGrant(session, verified));
    if (!_current(epoch)) return;
    setState(() {
      _active = true;
      _candidate = null;
      _review = null;
      _invitation = null;
    });
    widget.onChanged();
  });
  Future<void> _readJoin() {
    final original = _context();
    return _run((epoch, session) async {
      final bytes = await widget.messages.receive();
      if (bytes == null || !_current(epoch)) return;
      final verified = await widget.service.verifyIncoming(
        original.session,
        bytes,
      );
      if (verified.message.kind != MessageKind.joinRequest) {
        throw const CheckException(CheckError.malformed);
      }
      if (verified.message.payload.companyId != original.companyId) {
        throw const CheckException(CheckError.wrongCompany);
      }
      if (!_current(epoch)) return;
      setState(() {
        _review = verified;
        _invitation = null;
        _grant = null;
        _existingEmployeeId = null;
        _operation = widget.ids.next();
      });
    });
  }

  Future<void> _approve() {
    final original = _context(),
        request = _review!,
        existingEmployeeId = _existingEmployeeId;
    return _run((epoch, session) async {
      final grant = _committed(
        await widget.service.approveJoin(
          original,
          request,
          existingEmployeeId: existingEmployeeId,
        ),
      );
      if (!_current(epoch)) return;
      setState(() {
        _grant = grant;
        _review = null;
      });
      widget.onChanged();
      await widget.messages.send(MessageCodec().encode(grant));
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, key: const Key('enrollment-error')),
        if (_savedPending.length > 1 && _candidate == null)
          DropdownButton<SignedMessage>(
            value: _pending,
            items: [
              for (final pending in _savedPending)
                DropdownMenuItem(
                  value: pending,
                  child: Text('Pending company ${pending.payload.companyId}'),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _pending = value),
          ),
        if (_candidate != null)
          JoinCompanyScreen(
            companyLabel: _candidate!.payload.field<String>('companyLabel'),
            fingerprint: _fingerprint!,
            accepted: _accepted,
            busy: _busy,
            onAccepted: (value) => setState(() => _accepted = value),
            onConfirm: _confirm,
          )
        else if (_pending != null || _active)
          MembershipStatusScreen(
            active: _active,
            busy: _busy,
            request: _pending,
            onReceive: _receiveGrant,
            onResend: () => _run(
              (_, _) => widget.messages.send(MessageCodec().encode(_pending!)),
            ),
          )
        else if (_review != null)
          JoinReviewScreen(
            request: _review!,
            busy: _busy,
            onApprove: _approve,
            manualStaff: widget.manualStaff,
            existingEmployeeId: _existingEmployeeId,
            onLink: widget.owner
                ? (id) => setState(() => _existingEmployeeId = id)
                : null,
          )
        else if (_grant != null)
          Column(
            children: [
              const Text('Membership approved'),
              EnrollmentMessageView(message: _grant!),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        (_, _) => widget.messages.send(
                          MessageCodec().encode(_grant!),
                        ),
                      ),
                child: const Text('Send membership again'),
              ),
            ],
          )
        else if (_invitation != null)
          InvitationScreen(
            company: widget.company!,
            message: _invitation!,
            busy: _busy,
            onSend: () => _run(
              (_, _) =>
                  widget.messages.send(MessageCodec().encode(_invitation!)),
            ),
          ),
        if (widget.canManage && widget.company != null) ...[
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    final original = _context();
                    _run((epoch, session) async {
                      final message = await widget.service.createInvitation(
                        original,
                      );
                      if (!_current(epoch)) return;
                      setState(() {
                        _invitation = message;
                        _review = null;
                        _grant = null;
                        _operation = widget.ids.next();
                      });
                    });
                  },
            child: const Text('Create invitation'),
          ),
          TextButton(
            onPressed: _busy ? null : _readJoin,
            child: const Text('Read join request'),
          ),
        ] else if (_pending == null && !_active && _candidate == null) ...[
          FilledButton(
            onPressed: _busy ? null : _readInvitation,
            child: const Text('Read invitation'),
          ),
          TextButton(
            onPressed: _busy ? null : _receiveGrant,
            child: const Text('Receive membership'),
          ),
        ],
      ],
    ),
  );
}
