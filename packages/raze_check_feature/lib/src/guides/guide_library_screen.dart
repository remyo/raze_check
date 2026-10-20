import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'guide_layer.dart';
import 'guide_scope.dart';
import 'welcome_screen.dart';

class GuideLibraryScreen extends StatefulWidget {
  const GuideLibraryScreen({super.key, this.brandBuilder});
  final WidgetBuilder? brandBuilder;
  @override
  State<GuideLibraryScreen> createState() => _GuideLibraryScreenState();
}

class _GuideLibraryScreenState extends State<GuideLibraryScreen> {
  bool _replay = false;
  @override
  Widget build(BuildContext context) {
    final controller = GuideScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return GuideStateBuilder(
      controller: controller,
      builder: (context) {
        if (_replay) {
          return WelcomeScreen(
            brandBuilder: widget.brandBuilder,
            onFinished: () => setState(() => _replay = false),
          );
        }
        return GuideLayer(
          child: Scaffold(
            appBar: AppBar(title: const Text('Help & Guides')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Guide progress is shared on this device.'),
                if (controller.sessionOnly)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Progress is kept for this session.'),
                  ),
                if (controller.persistenceFailed) Text(controller.notice!),
                for (final guide in controller.catalog.available(
                  controller.audience,
                ))
                  Builder(
                    builder: (context) {
                      GuideProgress? progress;
                      for (final e in controller.progress.entries) {
                        if (e.guideId == guide.id &&
                            e.variantId == guide.variantId) {
                          progress = e;
                        }
                      }
                      final saved = progress?.stepId != null;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  guide.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(guide.description),
                              const SizedBox(height: 8),
                              Text(
                                progress?.viewed == true
                                    ? 'Viewed'
                                    : saved
                                    ? 'In progress'
                                    : 'Not started',
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (guide.id == 'welcome')
                                    TextButton(
                                      onPressed: () {
                                        controller.start(
                                          'welcome',
                                          restart: true,
                                        );
                                        setState(() => _replay = true);
                                      },
                                      child: const Text('Replay introduction'),
                                    )
                                  else ...[
                                    TextButton(
                                      onPressed: () =>
                                          controller.start(guide.id),
                                      child: Text(saved ? 'Continue' : 'Start'),
                                    ),
                                    if (saved)
                                      TextButton(
                                        onPressed: () => controller.start(
                                          guide.id,
                                          restart: true,
                                        ),
                                        child: const Text('Restart'),
                                      ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
