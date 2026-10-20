import 'package:flutter/material.dart';

/// Static artwork also respects reduced-motion preferences without a ticker.
class GuideArtwork extends StatelessWidget {
  const GuideArtwork({
    super.key,
    required this.guideId,
    required this.stepIndex,
    this.brandBuilder,
  });
  final String guideId;
  final int stepIndex;
  final WidgetBuilder? brandBuilder;
  @override
  Widget build(BuildContext context) {
    if (guideId == 'welcome' && brandBuilder != null) {
      return brandBuilder!(context);
    }
    final colors = Theme.of(context).colorScheme;
    final icon = switch (guideId) {
      'companies' => Icons.add_business,
      'capture' || 'exchange' => Icons.qr_code_scanner,
      'review' => Icons.fact_check_outlined,
      'membership' || 'team' => Icons.people_outline,
      'reports' => Icons.file_download_outlined,
      'backup' || 'new-device' => Icons.settings_backup_restore,
      _ => Icons.person_outline,
    };
    return ExcludeSemantics(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(8),
        child: guideId == 'welcome' && stepIndex == 0
            ? Image.asset(
                'packages/raze_check_feature/assets/branding/raze_check_logo_master.png',
                fit: BoxFit.contain,
              )
            : Icon(icon, color: colors.onPrimaryContainer, size: 32),
      ),
    );
  }
}
