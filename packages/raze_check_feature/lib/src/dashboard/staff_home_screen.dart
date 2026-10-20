import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:timezone/timezone.dart' as tz;
import '../theme/check_theme.dart';
import '../guides/guide_target.dart';
import '../guides/guide_invitation.dart';

String attendanceTime(int? utc, String zone) {
  if (utc == null) return 'No receipts received yet';
  CompanyTimeZones.all;
  final d = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.getLocation(zone), utc);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $zone';
}

TextStyle? dashboardHeadline(BuildContext context) => Theme.of(context)
    .textTheme
    .headlineSmall
    ?.copyWith(fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: -.8);

String _attendanceClock(int utc, String zone) {
  CompanyTimeZones.all;
  final date = tz.TZDateTime.fromMillisecondsSinceEpoch(
    tz.getLocation(zone),
    utc,
  );
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final latest = overview.latest;
    return DashboardLayout(
      children: [
        if (showContext)
          Text(
            '${overview.company.name} · Staff',
            style: theme.textTheme.titleMedium,
          ),
        const DashboardHeading(
          title: 'Your attendance',
          subtitle: 'Your records, saved on this device.',
        ),
        const GuideInvitation(guideId: 'capture'),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final label = Text(
                    'Latest attendance',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  );
                  final badge = latest == null
                      ? null
                      : DashboardStatusBadge(
                          label:
                              latest.record.effectiveKind == PunchKind.checkIn
                              ? 'Checked in'
                              : 'Checked out',
                          icon: latest.record.effectiveKind == PunchKind.checkIn
                              ? Icons.login
                              : Icons.logout,
                        );
                  if (badge == null) return label;
                  if (MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                      box.maxWidth < 280) {
                    return Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [label, badge],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [label, badge],
                  );
                },
              ),
              const SizedBox(height: 14),
              if (latest == null)
                Text(
                  'No attendance saved yet',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                )
              else ...[
                Text(
                  _attendanceClock(
                    latest.record.effectiveUtcMs,
                    overview.company.timeZoneId,
                  ),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  attendanceTime(
                    latest.record.effectiveUtcMs,
                    overview.company.timeZoneId,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GuideTarget(
                  id: 'capture-open',
                  child: FilledButton.icon(
                    onPressed: onCapture,
                    icon: const Icon(Icons.qr_code_scanner, size: 19),
                    label: const Text('Record attendance'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Save a punch offline, then send your receipt.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionHeading(
              title: 'Your records',
              detail: 'All attendance',
            ),
            DashboardStats(
              tones: const {
                2: DashboardStatTone.attention,
                3: DashboardStatTone.approved,
              },
              values: [
                ('Saved on this device', overview.savedOnDevice),
                ('Received by management', overview.received),
                ('Awaiting review', overview.pending),
                ('Approved', overview.approved),
              ],
            ),
          ],
        ),
        GuideTarget(
          id: 'review-details',
          child: DashboardSupportCard(
            icon: Icons.receipt_long_outlined,
            title: overview.savedOnDevice > 0
                ? '${overview.savedOnDevice} ${overview.savedOnDevice == 1 ? "receipt" : "receipts"} ready to send'
                : 'No receipts waiting to send',
            body:
                'Send your receipts, then receive confirmation from management.',
            actionLabel: 'Open attendance and requests',
            onAction: onAttendance,
          ),
        ),
        if (backupLabel != null)
          DashboardBackupNote(label: backupLabel!, onBackup: onBackup),
      ],
    );
  }
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
              Padding(padding: const EdgeInsets.only(bottom: 16), child: child),
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
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
}

class DashboardHeading extends StatelessWidget {
  const DashboardHeading({
    super.key,
    required this.title,
    required this.subtitle,
  });
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: dashboardHeadline(context)),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class DashboardStatusBadge extends StatelessWidget {
  const DashboardStatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.attention = false,
  });
  final String label;
  final IconData? icon;
  final bool attention;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final status = theme.extension<CheckStatusColors>();
    final background = attention
        ? status?.attentionContainer ?? colors.surfaceContainerHighest
        : colors.primaryContainer;
    final foreground = attention
        ? status?.attention ?? colors.onSurface
        : colors.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardSectionHeading extends StatelessWidget {
  const DashboardSectionHeading({super.key, required this.title, this.detail});
  final String title;
  final String? detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: LayoutBuilder(
      builder: (context, box) {
        final titleWidget = Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        );
        final detailWidget = detail == null
            ? null
            : Text(
                detail!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
        if (detailWidget == null) return titleWidget;
        if (MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
            box.maxWidth < 280) {
          return Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [titleWidget, detailWidget],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [titleWidget, detailWidget],
        );
      },
    ),
  );
}

class DashboardSupportCard extends StatelessWidget {
  const DashboardSupportCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title, body;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (onAction != null && actionLabel != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          alignment: AlignmentDirectional.centerStart,
                        ),
                        child: Text(
                          actionLabel!,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardBackupNote extends StatelessWidget {
  const DashboardBackupNote({super.key, required this.label, this.onBackup});
  final String label;
  final VoidCallback? onBackup;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.shield_outlined,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backup',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (onBackup != null)
                  TextButton(
                    onPressed: onBackup,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: AlignmentDirectional.centerStart,
                    ),
                    child: const Text(
                      'Backup and recovery',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum DashboardStatTone { attention, approved }

class DashboardStats extends StatelessWidget {
  const DashboardStats({
    super.key,
    required this.values,
    this.tones = const {},
  });
  final List<(String, int)> values;
  final Map<int, DashboardStatTone> tones;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = box.maxWidth >= 600 && scale < 1.5
          ? 4
          : box.maxWidth >= 280 && scale < 1.5
          ? 2
          : 1;
      final theme = Theme.of(context);
      final attention =
          theme.extension<CheckStatusColors>()?.attention ??
          theme.colorScheme.onSurfaceVariant;
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(
              color: theme.colorScheme.outlineVariant,
            ),
            verticalInside: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          children: [
            for (var start = 0; start < values.length; start += columns)
              TableRow(
                children: [
                  for (var column = 0; column < columns; column++)
                    if (start + column < values.length)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${values[start + column].$2}',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                if (tones[start + column] != null) ...[
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          tones[start + column] ==
                                              DashboardStatTone.attention
                                          ? attention
                                          : theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Expanded(
                                  child: Text(
                                    values[start + column].$1,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                ],
              ),
          ],
        ),
      );
    },
  );
}
