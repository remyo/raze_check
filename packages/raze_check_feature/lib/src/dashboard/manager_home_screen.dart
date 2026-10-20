import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'staff_home_screen.dart';
import '../guides/guide_target.dart';
import '../guides/guide_invitation.dart';

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = <(String, IconData, VoidCallback, String?)>[
      if (onWorkplace != null)
        ('Workplace QR', Icons.qr_code, onWorkplace!, 'capture-open'),
      if (onInvite != null)
        ('Invite staff', Icons.person_add_alt, onInvite!, 'membership-open'),
      if (onManual != null) ('Manual entry', Icons.edit_note, onManual!, null),
    ];
    return DashboardLayout(
      children: [
        if (showContext)
          Text(
            '${overview.company.name} · Management',
            style: theme.textTheme.titleMedium,
          ),
        const DashboardHeading(
          title: 'Company attendance',
          subtitle: 'Records held on this device.',
        ),
        const GuideInvitation(guideId: 'review'),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final label = Text(
                    overview.pending > 0
                        ? 'Needs your attention'
                        : 'Attendance review',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                  if (overview.pending == 0) return label;
                  const badge = DashboardStatusBadge(
                    label: 'Awaiting review',
                    attention: true,
                  );
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
              Text(
                overview.pending > 0
                    ? '${overview.pending} ${overview.pending == 1 ? "record" : "records"} to review'
                    : 'Nothing awaiting review',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Last received: ${attendanceTime(overview.lastReceivedUtcMs, overview.company.timeZoneId)}',
                key: const Key('last-received'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GuideTarget(
                  id: 'review-details',
                  child: FilledButton.icon(
                    onPressed: onAttendance,
                    icon: const Icon(Icons.inbox_outlined, size: 19),
                    label: const Text('Import and review'),
                  ),
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardSectionHeading(
              title: 'Attendance overview',
              detail:
                  '${overview.total} ${overview.total == 1 ? "record" : "records"} total',
            ),
            DashboardStats(
              tones: const {
                0: DashboardStatTone.approved,
                1: DashboardStatTone.attention,
              },
              values: [
                ('Approved', overview.approved),
                ('Awaiting review', overview.pending),
                ('Received receipts', overview.received),
                ('Saved on this device', overview.savedOnDevice),
              ],
            ),
          ],
        ),
        if (actions.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardSectionHeading(title: 'Quick actions'),
              LayoutBuilder(
                builder: (context, box) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final columns = scale >= 1.5 || box.maxWidth < 280
                      ? 1
                      : box.maxWidth < 330
                      ? 2
                      : actions.length;
                  final width = (box.maxWidth - (columns - 1) * 10) / columns;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final action in actions)
                        SizedBox(
                          width: width,
                          child: Builder(
                            builder: (context) {
                              final button = OutlinedButton(
                                onPressed: action.$3,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.onSurface,
                                  backgroundColor: theme.colorScheme.surface,
                                  side: BorderSide(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 14,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(action.$2, size: 22),
                                    const SizedBox(height: 8),
                                    Text(
                                      action.$1,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(fontSize: 11),
                                    ),
                                  ],
                                ),
                              );
                              return action.$4 == null
                                  ? button
                                  : GuideTarget(id: action.$4!, child: button);
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        const DashboardSupportCard(
          icon: Icons.receipt_long_outlined,
          title: 'Some records may be missing',
          body:
              'Staff may still have receipts on their phones. Ask them to send their saved records.',
        ),
        if (backupLabel != null)
          DashboardBackupNote(label: backupLabel!, onBackup: onBackup),
      ],
    );
  }
}
