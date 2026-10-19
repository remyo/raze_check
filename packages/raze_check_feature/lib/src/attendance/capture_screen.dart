import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../profile/profile_commands.dart';
import '../enrollment/invitation_screen.dart';
import 'receipt_screen.dart';
import 'receipt_outbox_screen.dart';

/// Kept inside the host's protected session view. Async completions are scoped
/// to this company/session epoch, including camera, file and share completions.
class CaptureWorkspace extends StatefulWidget {
  const CaptureWorkspace({
    super.key,
    required this.service,
    required this.session,
    required this.company,
    required this.ids,
    required this.onChanged,
    required this.onLocked,
    this.messages,
    this.canCreateCode = false,
  });
  final CaptureService service;
  final SessionHandle session;
  final Company company;
  final IdGenerator ids;
  final AttendanceMessagePort? messages;
  final bool canCreateCode;
  final VoidCallback onChanged, onLocked;
  @override
  State<CaptureWorkspace> createState() => _CaptureWorkspaceState();
}

class _CaptureWorkspaceState extends State<CaptureWorkspace> {
  bool _busy = true, _outboxOpen = false;
  int _epoch = 0;
  CaptureDraft? _draft;
  AttendanceReceipt? _receipt;
  SignedMessage? _code;
  List<AttendanceReceipt> _receipts = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(CaptureWorkspace old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session) ||
        old.company.id != widget.company.id) {
      _epoch++;
      _draft = null;
      _receipt = null;
      _code = null;
      _receipts = [];
      _error = null;
      _outboxOpen = false;
      _reload();
    }
  }

  bool _current(int epoch) => mounted && epoch == _epoch;
  void _failure(Object e) {
    if (e is CheckException && e.code == CheckError.locked) {
      widget.onLocked();
      return;
    }
    setState(
      () => _error = profileError(
        e is CheckException ? e.code : CheckError.storageFailure,
      ),
    );
  }

  Future<void> _run(Future<void> Function(int epoch) action) async {
    if (_busy) return;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(epoch);
      if (_current(epoch)) widget.onChanged();
    } catch (e) {
      if (_current(epoch)) _failure(e);
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final epoch = _epoch;
    final service = widget.service,
        session = widget.session,
        company = widget.company;
    setState(() => _busy = true);
    try {
      final draft = await service.currentDraft(session, company.id);
      final receipt = draft?.eventId == null
          ? null
          : await service.getReceipt(session, company.id, draft!.eventId!);
      final receipts = await service.listOutbox(session, company.id);
      if (_current(epoch)) {
        setState(() {
          _draft = draft;
          _receipt = receipt;
          _receipts = receipts;
        });
      }
    } catch (e) {
      if (_current(epoch)) _failure(e);
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _punch(PunchKind kind) => _run((epoch) async {
    final service = widget.service,
        session = widget.session,
        company = widget.company;
    final bytes = await widget.messages!.receive();
    if (!_current(epoch) || bytes == null) return;
    final code = await service.verifyWorkplace(session, company.id, bytes);
    if (!_current(epoch)) return;
    final draft = await service.beginDraft(session, company.id, code, kind);
    if (!_current(epoch)) return;
    setState(() => _draft = draft);
    await _record(epoch, draft, code);
  });
  Future<void> _record(
    int epoch,
    CaptureDraft draft,
    VerifiedMessage code,
  ) async {
    final result = await widget.service.recordPunch(
      draft.context(widget.session),
      code,
      draft.kind,
    );
    if (!_current(epoch)) return;
    switch (result) {
      case Committed<AttendanceReceipt>():
        setState(() {
          _receipt = result.value;
          _draft = null;
        });
      case Rejected<AttendanceReceipt>():
        throw CheckException(result.error);
      case VersionConflict<AttendanceReceipt>():
        throw const CheckException(CheckError.invalidTransition);
    }
  }

  Future<void> _retry() => _run((epoch) async {
    final draft = _draft!;
    final code = await widget.service.verifyWorkplace(
      widget.session,
      widget.company.id,
      draft.workplaceBytes,
    );
    if (_current(epoch)) await _record(epoch, draft, code);
  });
  Future<void> _newPunch() => _run((epoch) async {
    final receipt = _receipt!;
    final service = widget.service,
        session = widget.session,
        company = widget.company;
    // A reopened historical receipt must not clear a newer draft.
    final draft = await service.currentDraft(session, company.id);
    if (!_current(epoch)) return;
    if (draft?.eventId == receipt.eventId) {
      await service.finishDraft(session, company.id, receipt.eventId);
    }
    if (_current(epoch)) {
      setState(() {
        _receipt = null;
        _draft = null;
      });
      await _reload();
    }
  });

  Future<void> _share() => _run((epoch) async {
    await widget.messages!.send(_receipt!.bytes);
  });
  Future<void> _createCode() => _run((epoch) async {
    final context = CommandContext(
      companyId: widget.company.id,
      session: widget.session,
      operationId: widget.ids.next(),
      authorityGenerationId: widget.company.authorityGenerationId,
    );
    final code = await widget.service.createWorkplaceCode(context);
    if (_current(epoch)) setState(() => _code = code);
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Text(
          'Attendance · ${widget.company.name}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (_error != null) Text(_error!),
        if (_busy) const LinearProgressIndicator(),
        if (_receipt != null)
          ReceiptScreen(
            receipt: _receipt!,
            busy: _busy,
            onShare: widget.messages == null ? null : _share,
            onNewPunch: _newPunch,
          )
        else if (_outboxOpen) ...[
          TextButton(
            onPressed: _busy ? null : () => setState(() => _outboxOpen = false),
            child: const Text('Back to capture'),
          ),
          ReceiptOutboxScreen(
            receipts: _receipts,
            onOpen: (r) => setState(() {
              _receipt = r;
              _outboxOpen = false;
            }),
          ),
        ] else ...[
          if (_draft != null)
            FilledButton(
              onPressed: _busy ? null : _retry,
              child: const Text('Retry saved punch'),
            )
          else if (widget.messages != null) ...[
            FilledButton(
              onPressed: _busy ? null : () => _punch(PunchKind.checkIn),
              child: const Text('Check in'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _punch(PunchKind.checkOut),
              child: const Text('Check out'),
            ),
          ],
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await _reload();
                    if (mounted) setState(() => _outboxOpen = true);
                  },
            child: const Text('Receipt outbox'),
          ),
          if (widget.canCreateCode)
            FilledButton(
              onPressed: _busy ? null : _createCode,
              child: const Text('Display workplace code'),
            ),
          if (_code != null) EnrollmentMessageView(message: _code!),
        ],
      ],
    ),
  );
}
