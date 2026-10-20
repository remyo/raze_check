import 'package:flutter/material.dart';
import 'guide_scope.dart';

class GuideInvitation extends StatelessWidget {
  const GuideInvitation({super.key, required this.guideId});
  final String guideId;
  @override
  Widget build(BuildContext context) {
    final controller = GuideScope.maybeOf(context);
    if (controller == null || !GuideScope.isVisibleOf(context)) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.shouldInvite(guideId) || controller.paused) {
          return const SizedBox.shrink();
        }
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => controller.start(guideId),
              icon: const Icon(Icons.help_outline),
              label: const Text('Show me how'),
            ),
            IconButton(
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              tooltip: 'Dismiss guide invitation',
              icon: const Icon(Icons.close),
              onPressed: () => controller.dismissInvitation(guideId),
            ),
          ],
        );
      },
    );
  }
}
