import 'package:flutter/material.dart';

/// Untrusted preview: consent is explicit and does not itself grant membership.
class JoinCompanyScreen extends StatelessWidget {
  const JoinCompanyScreen({
    super.key,
    required this.companyLabel,
    required this.fingerprint,
    required this.accepted,
    required this.busy,
    required this.onAccepted,
    required this.onConfirm,
  });
  final String companyLabel, fingerprint;
  final bool accepted, busy;
  final ValueChanged<bool> onAccepted;
  final VoidCallback onConfirm;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('Join $companyLabel', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Compare the full fingerprint with the company owner before continuing.',
      ),
      SelectableText(fingerprint),
      CheckboxListTile(
        value: accepted,
        onChanged: busy ? null : (v) => onAccepted(v ?? false),
        title: const Text(
          'I confirmed this company root fingerprint with the owner',
        ),
      ),
      FilledButton(
        onPressed: accepted && !busy ? onConfirm : null,
        child: const Text('Confirm and request to join'),
      ),
    ],
  );
}
