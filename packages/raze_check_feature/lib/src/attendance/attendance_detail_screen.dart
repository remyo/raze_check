import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../enrollment/invitation_screen.dart';
import '../guides/guide_target.dart';

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
    final status = Text(
      'Attendance ${r.review.name}',
      style: Theme.of(context).textTheme.titleLarge,
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.canManage)
          status
        else
          GuideTarget(id: 'review-decision', child: status),
        Text('Employee ${r.employeeId}'),
        GuideTarget(
          id: 'review-hints',
          child: Text(
            r.source == AttendanceSource.manual
                ? 'Manual · local record'
                : 'Receipt · delivery ${r.delivery.name}',
          ),
        ),
        GuideTarget(
          id: 'review-details',
          child: Text(
            'Original: ${r.data['originalKind']} · offset ${r.data['originalOffsetMinutes']} min · ${DateTime.fromMillisecondsSinceEpoch(r.claimedUtcMs, isUtc: true).toIso8601String()}',
          ),
        ),
        Text(
          'Effective: ${r.effectiveKind.name} · ${DateTime.fromMillisecondsSinceEpoch(r.effectiveUtcMs, isUtc: true).toIso8601String()} · offset ${r.effectiveOffsetMinutes} min',
        ),
        if (r.receivedUtcMs != null)
          Text(
            'Received: ${DateTime.fromMillisecondsSinceEpoch(r.receivedUtcMs!, isUtc: true).toIso8601String()}',
          ),
        if (r.flags.isNotEmpty) ...[
          Text('Needs review: ${r.flags.map(attendanceHintLabel).join(', ')}'),
          const Text(
            'Hints use known receipts. Offline delivery may be incomplete; later receipts can resolve a hint.',
          ),
        ],
        if (r.source == AttendanceSource.manual) ...[
          Text('Entered by ${r.data['actorPersonId']} · ${r.data['reason']}'),
          const Text(
            'This local manual record has no staff-phone return exchange.',
          ),
        ],
        if (widget.canManage) ...[
          GuideTarget(
            id: 'review-decision',
            child: TextField(
              key: const Key('review-reason'),
              controller: reason,
              decoration: const InputDecoration(labelText: 'Review reason'),
            ),
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
          GuideTarget(
            id: 'review-correction',
            child: TextButton(
              onPressed: widget.busy ? null : widget.onCorrect,
              child: Text(
                widget.canManage ? 'Correct attendance' : 'Request correction',
              ),
            ),
          ),
        const GuideTarget(
          id: 'review-history',
          child: Text('Decision and correction history'),
        ),
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
            Builder(
              builder: (context) {
                final button = FilledButton(
                  onPressed: widget.busy ? null : widget.onShare,
                  child: Text(
                    widget.message!.kind == MessageKind.correctionRequest
                        ? 'Share correction request'
                        : 'Share selected return',
                  ),
                );
                return widget.message!.kind == MessageKind.correctionRequest
                    ? button
                    : GuideTarget(id: 'exchange-return', child: button);
              },
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
