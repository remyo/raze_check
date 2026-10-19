import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../profile/profile_commands.dart';
import 'attendance_detail_screen.dart';
import 'message_import_sheet.dart';
import 'scan_screen.dart';
import 'manual_entry_screen.dart';
import 'correction_request_screen.dart';

class ReviewQueueScreen extends StatelessWidget {
  const ReviewQueueScreen({
    super.key,
    required this.records,
    required this.onSelect,
  });
  final List<AttendanceRecord> records;
  final ValueChanged<AttendanceRecord> onSelect;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      if (records.isEmpty)
        const ListTile(title: Text('No attendance saved here.')),
      for (final r in records)
        ListTile(
          title: Text('${r.effectiveKind.name} · ${r.review.name}'),
          subtitle: Text(
            '${r.employeeId}\n${r.source == AttendanceSource.manual ? 'Manual · local record' : 'Receipt · ${r.delivery.name}'}${r.flags.isEmpty ? '' : ' · needs review'}',
          ),
          trailing: TextButton(
            onPressed: () => onSelect(r),
            child: const Text('View attendance'),
          ),
        ),
    ],
  );
}

/// Company/session epochs guard every picker completion and command result.
class ReviewWorkspace extends StatefulWidget {
  const ReviewWorkspace({
    super.key,
    required this.service,
    required this.session,
    required this.company,
    required this.ids,
    required this.canManage,
    required this.staff,
    required this.onChanged,
    required this.onLocked,
    this.messages,
  });
  final AttendanceService service;
  final SessionHandle session;
  final Company company;
  final IdGenerator ids;
  final bool canManage;
  final List<StaffRecord> staff;
  final AttendanceMessagePort? messages;
  final VoidCallback onChanged, onLocked;
  @override
  State<ReviewWorkspace> createState() => _ReviewWorkspaceState();
}

class _ReviewWorkspaceState extends State<ReviewWorkspace> {
  bool busy = false, manual = false, correcting = false;
  int epoch = 0;
  List<AttendanceRecord> records = [];
  List<AttendanceSubject> subjects = [];
  AttendanceRecord? selected;
  List<DecisionRecord> history = [];
  SignedMessage? message;
  List<SignedMessage> availableMessages = [];
  VerifiedMessage? request;
  final reason = TextEditingController();
  String? error;
  late String operation = widget.ids.next();
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReviewWorkspace old) {
    super.didUpdateWidget(old);
    if (old.company.id != widget.company.id ||
        !identical(old.session, widget.session)) {
      epoch++;
      manual = false;
      correcting = false;
      selected = null;
      history = [];
      message = null;
      request = null;
      records = [];
      error = null;
      operation = widget.ids.next();
      reload();
    }
  }

  bool current(int e) => mounted && epoch == e;
  CommandContext contextFor(String op) => CommandContext(
    companyId: widget.company.id,
    session: widget.session,
    operationId: op,
    authorityGenerationId: widget.company.authorityGenerationId,
  );
  TransferGuard guard(int e) {
    final service = widget.service,
        session = widget.session,
        company = widget.company;
    return () async {
      if (!current(e)) {
        throw const TransferException(
          'Return to the original company to continue',
        );
      }
      await service.list(session, company.id);
      if (!current(e)) {
        throw const TransferException(
          'Return to the original company to continue',
        );
      }
    };
  }

  void failure(Object e) {
    if (e is CheckException && e.code == CheckError.locked) {
      widget.onLocked();
      return;
    }
    setState(
      () => error = e is TransferException
          ? transferError(e)
          : e is CheckException &&
                (e.code == CheckError.recoveryRequired ||
                    e.code == CheckError.unknownIssuer)
          ? 'Authority needs review. Accept its verified history before applying this update.'
          : profileError(
              e is CheckException ? e.code : CheckError.storageFailure,
            ),
    );
  }

  Future<void> run(Future<void> Function(int) work) async {
    if (busy) return;
    final e = epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work(e);
      if (current(e)) widget.onChanged();
    } catch (ex) {
      if (current(e) || (mounted && ex is TransferException)) failure(ex);
    } finally {
      if (current(e)) setState(() => busy = false);
    }
  }

  Future<void> reload() async {
    final e = epoch,
        service = widget.service,
        session = widget.session,
        company = widget.company;
    setState(() => busy = true);
    try {
      final next = await service.list(session, company.id);
      final choices = widget.canManage
          ? await service.subjects(session, company.id)
          : <AttendanceSubject>[];
      if (current(e)) subjects = choices;
      if (current(e)) setState(() => records = next);
    } catch (ex) {
      if (current(e) || (mounted && ex is TransferException)) failure(ex);
    } finally {
      if (current(e)) setState(() => busy = false);
    }
  }

  T committed<T>(CommandResult<T> r) => switch (r) {
    Committed<T>() => r.value,
    Rejected<T>() => throw CheckException(r.error),
    VersionConflict<T>() => throw const CheckException(
      CheckError.invalidTransition,
    ),
  };
  Future<void> open(String id, int e) async {
    final service = widget.service,
        session = widget.session,
        company = widget.company;
    final r = await service.get(session, company.id, id),
        h = await service.history(session, company.id, id),
        messages = await service.exchangeMessages(session, company.id, id);
    SignedMessage? latest;
    if (widget.canManage) {
      final decisions =
          messages
              .where((m) => m.kind == MessageKind.attendanceDecision)
              .toList()
            ..sort(
              (a, b) => a.payload
                  .field<int>('decisionRevision')
                  .compareTo(b.payload.field<int>('decisionRevision')),
            );
      latest =
          decisions.lastOrNull ??
          messages.where((m) => m.kind == MessageKind.receiptAck).lastOrNull;
    } else {
      latest = messages
          .where((m) => m.kind == MessageKind.correctionRequest)
          .lastOrNull;
    }
    if (current(e)) {
      setState(() {
        selected = r;
        history = h;
        message = latest;
        availableMessages = messages
            .where(
              (m) => widget.canManage
                  ? m.kind != MessageKind.correctionRequest
                  : m.kind == MessageKind.correctionRequest,
            )
            .toList();
        manual = false;
        correcting = false;
        operation = widget.ids.next();
      });
    }
  }

  Future<void> receive() => run((e) async {
    final service = widget.service,
        session = widget.session,
        company = widget.company,
        original = contextFor(operation),
        port = widget.messages!;
    final bytes = await receiveTransfer(
      port,
      widget.canManage
          ? {MessageKind.attendance, MessageKind.correctionRequest}
          : {MessageKind.receiptAck, MessageKind.attendanceDecision},
      guard(e),
    );
    if (!current(e) || bytes == null) return;
    final incoming = await service.verifyIncoming(session, company.id, bytes);
    if (!current(e)) return;
    if (widget.canManage && incoming.message.kind == MessageKind.attendance) {
      final result = await service.importReceipt(original, incoming);
      if (result.status == ImportStatus.rejected) {
        throw CheckException(result.error!);
      }
      if (!current(e)) return;
      final next = await service.list(session, company.id);
      if (current(e)) {
        setState(() {
          records = next;
          operation = widget.ids.next();
        });
      }
    } else if (widget.canManage &&
        incoming.message.kind == MessageKind.correctionRequest) {
      setState(() {
        request = incoming;
        reason.clear();
        operation = widget.ids.next();
      });
    } else {
      final r = committed(await service.accept(session, incoming));
      if (current(e)) await open(r.eventId, e);
    }
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (error != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
      if (busy) const LinearProgressIndicator(),
      Expanded(child: body()),
    ],
  );
  Widget body() {
    if (request != null) {
      final p = request!.message.payload;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Staff correction request'),
          Text('Event ${p.field<String>('eventId')}'),
          Text(
            '${p.field<String>('proposedKind')} · ${DateTime.fromMillisecondsSinceEpoch(p.field<int>('proposedUtcMs'), isUtc: true).toIso8601String()} · offset ${p.field<int>('proposedOffsetMinutes')}',
          ),
          Text(p.field<String>('reason')),
          TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Resolution reason'),
          ),
          for (final approve in [true, false])
            FilledButton(
              onPressed: busy
                  ? null
                  : () => run((e) async {
                      final original = contextFor(operation),
                          incoming = request!;
                      final result = committed(
                        await widget.service.resolve(
                          original,
                          incoming,
                          approve,
                          reason.text,
                        ),
                      );
                      if (current(e)) {
                        setState(() => request = null);
                        await open(result.decision.eventId, e);
                      }
                    }),
              child: Text(approve ? 'Approve correction' : 'Reject correction'),
            ),
          TextButton(
            onPressed: busy ? null : () => setState(() => request = null),
            child: const Text('Cancel'),
          ),
        ],
      );
    }
    if (manual) {
      return ManualEntryScreen(
        staff: subjects,
        busy: busy,
        onCancel: () => setState(() => manual = false),
        onSave: (draft) => run((e) async {
          final result = committed(
            await widget.service.recordManual(contextFor(operation), draft),
          );
          if (current(e)) await open(result.eventId, e);
        }),
      );
    }
    if (correcting) {
      return CorrectionRequestScreen(
        record: selected!,
        manager: widget.canManage,
        busy: busy,
        onCancel: () => setState(() => correcting = false),
        onSubmit: (change) => run((e) async {
          final original = contextFor(operation), id = selected!.eventId;
          if (widget.canManage) {
            committed(
              await widget.service.correct(original, id, change, change.reason),
            );
          } else {
            await widget.service.request(
              original.session,
              original.companyId,
              id,
              change,
              original.operationId,
            );
          }
          if (current(e)) await open(id, e);
        }),
      );
    }
    if (selected != null) {
      return AttendanceDetailScreen(
        record: selected!,
        history: history,
        busy: busy,
        canManage: widget.canManage,
        message: message,
        availableMessages: availableMessages,
        onSelectMessage: (selectedMessage) =>
            setState(() => message = selectedMessage),
        onShare: widget.messages == null
            ? null
            : () => run((e) async {
                final original = message!,
                    service = widget.service,
                    session = widget.session,
                    company = widget.company,
                    id = selected!.eventId,
                    port = widget.messages!;
                await service.get(session, company.id, id);
                if (!current(e)) return;
                await sendTransfer(
                  port,
                  MessageCodec().encode(original),
                  guard(e),
                );
              }),
        onBack: () {
          setState(() => selected = null);
          reload();
        },
        onCorrect: () => setState(() {
          correcting = true;
          operation = widget.ids.next();
        }),
        onReview: (outcome, reason) => run((e) async {
          final id = selected!.eventId;
          committed(
            await widget.service.decide(
              contextFor(operation),
              id,
              outcome,
              reason,
            ),
          );
          if (current(e)) await open(id, e);
        }),
      );
    }
    return Column(
      children: [
        Wrap(
          children: [
            if (widget.messages != null)
              TextButton(
                onPressed: busy ? null : receive,
                child: Text(
                  widget.canManage
                      ? 'Import receipt or correction'
                      : 'Receive attendance update',
                ),
              ),
            if (widget.canManage && subjects.isNotEmpty)
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        manual = true;
                        operation = widget.ids.next();
                      }),
                child: const Text('Manual entry'),
              ),
            TextButton(
              onPressed: busy ? null : reload,
              child: const Text('Refresh attendance'),
            ),
          ],
        ),
        Expanded(
          child: ReviewQueueScreen(
            records: records,
            onSelect: (r) => run((e) => open(r.eventId, e)),
          ),
        ),
      ],
    );
  }
}
