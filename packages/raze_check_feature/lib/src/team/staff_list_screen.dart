import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';

class StaffListScreen extends StatelessWidget {
  const StaffListScreen({
    super.key,
    required this.staff,
    required this.memberships,
    required this.onSelect,
    required this.onAdd,
  });
  final List<StaffRecord> staff;
  final List<Membership> memberships;
  final ValueChanged<StaffRecord> onSelect;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Staff', style: Theme.of(context).textTheme.headlineSmall),
      FilledButton(onPressed: onAdd, child: const Text('Add staff')),
      if (staff.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No staff records yet.'),
        ),
      for (final record in staff)
        ListTile(
          title: Text(record.details.name),
          subtitle: Text(
            memberships.any((m) => m.id == record.membershipId && !m.active)
                ? 'Inactive'
                : record.details.department ?? 'Staff record',
          ),
          onTap: () => onSelect(record),
        ),
    ],
  );
}
