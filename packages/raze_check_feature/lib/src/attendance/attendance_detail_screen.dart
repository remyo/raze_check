import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../enrollment/invitation_screen.dart';

class AttendanceDetailScreen extends StatefulWidget {
  const AttendanceDetailScreen({
    super.key,
    required this.record,
    required this.history,
    required this.busy,
    required this.canManage,
    required this.onBack,
    required this.onReview,
    required this.onCorrect,
    this.message,
    this.onShare,
    required this.availableMessages,
    required this.onSelectMessage,
  });
  final AttendanceRecord record;
  final List<DecisionRecord> history;
  final bool busy, canManage;
  final VoidCallback onBack, onCorrect;
  final Future<void> Function(ReviewDecision, String) onReview;
  final SignedMessage? message;
  final List<SignedMessage> availableMessages;
  final ValueChanged<SignedMessage> onSelectMessage;
  final VoidCallback? onShare;
  @override
  State<AttendanceDetailScreen> createState() => _AttendanceDetailScreenState();
}

class _AttendanceDetailScreenState extends State<AttendanceDetailScreen> {
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Attendance ${r.review.name}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text('Employee ${r.employeeId}'),
        Text(
          r.source == AttendanceSource.manual
              ? 'Manual · local record'
              : 'Receipt · delivery ${r.delivery.name}',
        ),
        Text(
          'Original: ${r.data['originalKind']} · offset ${r.data['originalOffsetMinutes']} min · ${DateTime.fromMillisecondsSinceEpoch(r.claimedUtcMs, isUtc: true).toIso8601String()}',
        ),
        Text(
          'Effective: ${r.effectiveKind.name} · ${DateTime.fromMillisecondsSinceEpoch(r.effectiveUtcMs, isUtc: true).toIso8601String()} · offset ${r.effectiveOffsetMinutes} min',
        ),
        if (r.receivedUtcMs != null)
          Text(
            'Received: ${DateTime.fromMillisecondsSinceEpoch(r.receivedUtcMs!, isUtc: true).toIso8601String()}',
          ),
        if (r.flags.isNotEmpty) Text('Needs review: ${r.flags.join(', ')}'),
        if (r.source == AttendanceSource.manual) ...[
          Text('Entered by ${r.data['actorPersonId']} · ${r.data['reason']}'),
          const Text(
            'This local manual record has no staff-phone return exchange.',
          ),
        ],
        if (widget.canManage) ...[
          TextField(
            key: const Key('review-reason'),
            controller: reason,
            decoration: const InputDecoration(labelText: 'Review reason'),
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: widget.busy
                    ? null
                    : () =>
                          widget.onReview(ReviewDecision.approve, reason.text),
                child: const Text('Approve attendance'),
              ),
              TextButton(
                onPressed: widget.busy
                    ? null
                    : () => widget.onReview(ReviewDecision.reject, reason.text),
                child: const Text('Reject attendance'),
              ),
            ],
          ),
        ],
        if (widget.canManage || r.returnEligible)
          TextButton(
            onPressed: widget.busy ? null : widget.onCorrect,
            child: Text(
              widget.canManage ? 'Correct attendance' : 'Request correction',
            ),
          ),
        const Text('Decision and correction history'),
        for (final d in widget.history)
          ListTile(
            title: Text(
              '${d.data['source']} · attendance ${d.data['outcome']}${d.correctionOutcome == null ? '' : ' · correction ${d.correctionOutcome!.name}'}',
            ),
            subtitle: Text(
              '${d.reason}\nActor ${d.actorPersonId}${d.requestId == null ? '' : '\nRequest ${d.requestId}'}',
            ),
          ),
        for (final available in widget.availableMessages)
          TextButton(
            onPressed: widget.busy
                ? null
                : () => widget.onSelectMessage(available),
            child: Text(switch (available.kind) {
              MessageKind.receiptAck => 'Show receipt acknowledgment',
              MessageKind.attendanceDecision =>
                'Show decision ${available.payload.field<int>('decisionRevision')}',
              _ =>
                'Show correction request ${available.payload.messageId.substring(0, 8)}',
            }),
          ),
        if (widget.message != null) ...[
          EnrollmentMessageView(message: widget.message!),
          if (widget.onShare != null)
            FilledButton(
              onPressed: widget.busy ? null : widget.onShare,
              child: Text(
                widget.message!.kind == MessageKind.correctionRequest
                    ? 'Share correction request'
                    : 'Share selected return',
              ),
            ),
        ],
        TextButton(
          onPressed: widget.busy ? null : widget.onBack,
          child: const Text('Back to attendance'),
        ),
      ],
    );
  }
}
