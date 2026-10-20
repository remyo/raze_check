import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../guides/guide_target.dart';
import '../guides/guide_invitation.dart';

class ReceiptOutboxScreen extends StatelessWidget {
  const ReceiptOutboxScreen({
    super.key,
    required this.receipts,
    required this.onOpen,
  });
  final List<AttendanceReceipt> receipts;
  final ValueChanged<AttendanceReceipt> onOpen;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const GuideInvitation(guideId: 'exchange'),
      const GuideTarget(id: 'exchange-outbox', child: Text('Receipt outbox')),
      if (receipts.isEmpty) const Text('No local receipts awaiting delivery.'),
      for (final r in receipts)
        ListTile(
          title: Text(r.kind == PunchKind.checkIn ? 'Check in' : 'Check out'),
          subtitle: Text('${r.eventId} · Saved on this device'),
          onTap: () => onOpen(r),
        ),
    ],
  );
}
