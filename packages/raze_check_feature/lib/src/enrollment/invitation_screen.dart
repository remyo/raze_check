import 'package:flutter/material.dart';
import '../attendance/message_qr.dart';
import 'package:raze_check_core/raze_check_core.dart';

class EnrollmentMessageView extends StatelessWidget {
  const EnrollmentMessageView({super.key, required this.message});
  final SignedMessage message;
  @override
  Widget build(BuildContext context) => MessageCodec().fitsQr(message)
      ? SizedBox(
          width: 320,
          height: 320,
          child: ExactMessageQr(bytes: MessageCodec().encode(message)),
        )
      : const Text(
          'This message needs file transfer. Use Send to share the complete message.',
        );
}

class InvitationScreen extends StatelessWidget {
  const InvitationScreen({
    super.key,
    required this.company,
    required this.message,
    required this.busy,
    required this.onSend,
  });
  final Company company;
  final SignedMessage message;
  final bool busy;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(company.name, style: Theme.of(context).textTheme.titleLarge),
      const Text('Confirm this root fingerprint with the joining person:'),
      SelectableText(company.rootFingerprint),
      EnrollmentMessageView(message: message),
      FilledButton(
        onPressed: busy ? null : onSend,
        child: const Text('Send invitation'),
      ),
    ],
  );
}
