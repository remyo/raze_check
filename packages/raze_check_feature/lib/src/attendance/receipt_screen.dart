import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:raze_check_core/raze_check_core.dart';

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({
    super.key,
    required this.receipt,
    required this.busy,
    this.onShare,
    required this.onNewPunch,
  });
  final AttendanceReceipt receipt;
  final bool busy;
  final VoidCallback? onShare;
  final VoidCallback onNewPunch;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        receipt.delivery == DeliveryStatus.localOnly
            ? 'Saved on this device'
            : receipt.delivery.name,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Manager receipt and approval are separate from local saving.',
      ),
      SelectableText(receipt.eventId),
      Text(
        '${receipt.kind == PunchKind.checkIn ? 'Check in' : 'Check out'} · ${DateTime.fromMillisecondsSinceEpoch(receipt.claimedUtcMs, isUtc: true).toIso8601String()} · offset ${receipt.offsetMinutes} min',
      ),
      if (receipt.flags.isNotEmpty)
        const Text(
          'Review hints; these do not establish working time or misconduct.',
        ),
      for (final flag in receipt.flags)
        Text(switch (flag) {
          AttendanceFlag.possibleDuplicate =>
            'Possible duplicate within two minutes',
          AttendanceFlag.unexpectedOrder => 'Unexpected punch order',
          AttendanceFlag.missingCheckIn => 'No known check-in',
          AttendanceFlag.missingCheckOut =>
            'Previous check-in has no known check-out',
        }),
      if (MessageCodec().fitsQr(receipt.message))
        SizedBox(
          width: 240,
          height: 240,
          child: QrImageView(data: utf8.decode(receipt.bytes)),
        )
      else
        const Text(
          'This receipt needs file transfer to preserve its complete signed bytes.',
        ),
      if (onShare != null)
        FilledButton(
          onPressed: busy ? null : onShare,
          child: const Text('Share receipt'),
        ),
      TextButton(
        onPressed: busy ? null : onNewPunch,
        child: const Text('New punch'),
      ),
    ],
  );
}
