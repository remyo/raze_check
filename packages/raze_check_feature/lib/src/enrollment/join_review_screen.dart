import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';

class JoinReviewScreen extends StatelessWidget {
  const JoinReviewScreen({
    super.key,
    required this.request,
    required this.busy,
    required this.onApprove,
    this.manualStaff = const [],
    this.existingEmployeeId,
    this.onLink,
  });
  final VerifiedMessage request;
  final bool busy;
  final VoidCallback onApprove;
  final List<StaffRecord> manualStaff;
  final String? existingEmployeeId;
  final ValueChanged<String?>? onLink;
  @override
  Widget build(BuildContext context) {
    final p = request.message.payload;
    return Column(
      children: [
        const Text('Review join request'),
        Text(p.field<String>('displayName')),
        Text('Installation ${p.field<String>('installationId')}'),
        const Text(
          'Approval creates a staff membership. Management access is assigned separately in Operator access.',
        ),
        if (onLink != null && manualStaff.isNotEmpty)
          DropdownButton<String>(
            value: existingEmployeeId,
            hint: const Text('Create a new staff record'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Create a new staff record'),
              ),
              for (final staff in manualStaff)
                DropdownMenuItem(
                  value: staff.employeeId,
                  child: Text('Link existing: ${staff.details.name}'),
                ),
            ],
            onChanged: busy ? null : onLink,
          ),
        if (existingEmployeeId != null)
          const Text(
            'As owner, confirm this is the same person. Their existing employee ID will be retained.',
          ),
        FilledButton(
          onPressed: busy ? null : onApprove,
          child: const Text('Approve and send membership'),
        ),
      ],
    );
  }
}
