import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'staff_home_screen.dart';

class ManagerHomeScreen extends StatelessWidget {
  const ManagerHomeScreen({
    super.key,
    required this.overview,
    required this.onAttendance,
    this.onManual,
    this.onInvite,
    this.onWorkplace,
    this.backupLabel,
    this.onBackup,
    this.showContext = true,
  });
  final ManagerOverview overview;
  final VoidCallback onAttendance;
  final VoidCallback? onManual, onInvite, onWorkplace, onBackup;
  final String? backupLabel;
  final bool showContext;
  @override
  Widget build(BuildContext context) => DashboardLayout(
    children: [
      if (showContext)
        Text(
          '${overview.company.name} · Management',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      Text('A clear view of attendance', style: dashboardHeadline(context)),
      const Text(
        'Review the records held on this device. Staff may still have unsent receipts.',
      ),
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('All attendance records'),
            Text(
              '${overview.total}',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text(
              'Last received: ${attendanceTime(overview.lastReceivedUtcMs, overview.company.timeZoneId)}',
              key: const Key('last-received'),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onAttendance,
                  icon: const Icon(Icons.inbox_outlined),
                  label: const Text('Import and review'),
                ),
                if (onWorkplace != null)
                  OutlinedButton.icon(
                    onPressed: onWorkplace,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Workplace QR'),
                  ),
              ],
            ),
          ],
        ),
      ),
      DashboardStats(
        values: [
          ('Approved', overview.approved),
          ('Awaiting review', overview.pending),
          ('Received receipts', overview.received),
          ('Saved on this device', overview.savedOnDevice),
        ],
      ),
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Records not received'),
            const Text(
              'Some staff may still have receipts on their phones. Ask them to send their saved receipts.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (onManual != null)
                  TextButton.icon(
                    onPressed: onManual,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Manual entry'),
                  ),
                if (onInvite != null)
                  TextButton.icon(
                    onPressed: onInvite,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Invite staff'),
                  ),
              ],
            ),
          ],
        ),
      ),
      if (backupLabel != null)
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Backup'),
              Text(backupLabel!),
              if (onBackup != null)
                TextButton(
                  onPressed: onBackup,
                  child: const Text('Backup and recovery'),
                ),
            ],
          ),
        ),
    ],
  );
}
