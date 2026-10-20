import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:timezone/timezone.dart' as tz;

String attendanceTime(int? utc, String zone) {
  if (utc == null) return 'No receipts received yet';
  CompanyTimeZones.all;
  final d = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.getLocation(zone), utc);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $zone';
}

TextStyle? dashboardHeadline(BuildContext context) {
  final narrowLargeText =
      MediaQuery.sizeOf(context).width < 360 &&
      MediaQuery.textScalerOf(context).scale(1) > 1.5;
  return narrowLargeText
      ? Theme.of(context).textTheme.headlineSmall
      : Theme.of(context).textTheme.headlineMedium;
}

class StaffHomeScreen extends StatelessWidget {
  const StaffHomeScreen({
    super.key,
    required this.overview,
    required this.onCapture,
    required this.onAttendance,
    this.backupLabel,
    this.onBackup,
    this.showContext = true,
  });
  final StaffOverview overview;
  final VoidCallback onCapture, onAttendance;
  final String? backupLabel;
  final bool showContext;
  final VoidCallback? onBackup;
  @override
  Widget build(BuildContext context) => DashboardLayout(
    children: [
      if (showContext)
        Text(
          '${overview.company.name} · Staff',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      Text(
        'Your attendance, on this device',
        style: dashboardHeadline(context),
      ),
      const Text('Save a punch offline, then send your receipt to management.'),
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Latest attendance'),
            const SizedBox(height: 8),
            Text(
              overview.latest == null
                  ? 'No attendance saved yet'
                  : overview.latest!.record.effectiveKind == PunchKind.checkIn
                  ? 'Checked in'
                  : 'Checked out',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (overview.latest != null)
              Text(
                attendanceTime(
                  overview.latest!.record.effectiveUtcMs,
                  overview.company.timeZoneId,
                ),
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCapture,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Record attendance'),
            ),
          ],
        ),
      ),
      const Text('All attendance records · receipt and review status'),
      DashboardStats(
        values: [
          ('Saved on this device', overview.savedOnDevice),
          ('Received by management', overview.received),
          ('Awaiting review', overview.pending),
          ('Approved', overview.approved),
        ],
      ),
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              overview.savedOnDevice > 0
                  ? '${overview.savedOnDevice} ${overview.savedOnDevice == 1 ? "receipt" : "receipts"} ready to send'
                  : 'No receipts waiting to send',
            ),
            const Text(
              'Send your receipts, then receive confirmation from management.',
            ),
            TextButton(
              onPressed: onAttendance,
              child: const Text('Open attendance and requests'),
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

class DashboardLayout extends StatelessWidget {
  const DashboardLayout({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 18), child: child),
          ],
        ),
      ),
    ),
  );
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class DashboardStats extends StatelessWidget {
  const DashboardStats({super.key, required this.values});
  final List<(String, int)> values;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = box.maxWidth >= 600
          ? 4
          : box.maxWidth >= 330 && scale < 1.5
          ? 2
          : 1;
      final width = (box.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final value in values)
            SizedBox(
              width: width,
              child: DashboardCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${value.$2}', style: dashboardHeadline(context)),
                    Text(value.$1),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
