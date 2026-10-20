import 'package:flutter/material.dart';
import 'guide_artwork.dart';
import 'guide_controller.dart';
import 'guide_scope.dart';
import 'guide_scene.dart';

/// Full-page presentation of the same persisted welcome run.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.brandBuilder, required this.onFinished});
  final WidgetBuilder? brandBuilder;
  final VoidCallback onFinished;
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  GuideController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = GuideScope.maybeOf(context);
    if (_controller == controller) return;
    _controller?.removeListener(_changed);
    _controller = controller;
    controller?.addListener(_changed);
    _changed();
  }

  void _changed() {
    // Binding and initialization complete independently of the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _controller;
      if (c != null &&
          c.ready &&
          c.active == null &&
          c.currentContext != null &&
          !c.paused &&
          Visibility.of(context) &&
          GuideScope.isVisibleOf(context) &&
          (ModalRoute.isCurrentOf(context) ?? true) &&
          identical(
            c.currentContext?.token,
            GuideScene.maybeContextOf(context)?.token,
          )) {
        c.start('welcome');
      }
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final run = c?.active;
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Raze Check')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: run == null
                ? const CircularProgressIndicator()
                : SingleChildScrollView(
                    key: ValueKey(run.stepIndex),
                    padding: const EdgeInsets.all(24),
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: GuideArtwork(
                              guideId: 'welcome',
                              stepIndex: run.stepIndex,
                              brandBuilder: widget.brandBuilder,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              'Step ${run.stepIndex + 1} of ${run.definition.steps.length}',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Semantics(
                            header: true,
                            child: Text(
                              run.definition.steps[run.stepIndex].title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(run.definition.steps[run.stepIndex].body),
                          if (c!.persistenceFailed)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(c.notice!),
                            ),
                          const SizedBox(height: 24),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              onPressed: run.stepIndex == 0 ? null : c.back,
                              child: const Text('Back'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(2),
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              onPressed: () {
                                final last =
                                    run.stepIndex ==
                                    run.definition.steps.length - 1;
                                c.next();
                                if (last) widget.onFinished();
                              },
                              child: Text(
                                run.stepIndex == run.definition.steps.length - 1
                                    ? 'Get started'
                                    : 'Next',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(3),
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              onPressed: () {
                                c.skip();
                                widget.onFinished();
                              },
                              child: const Text('Skip'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Controller invalidation may occur during another scene's build. Refresh the
/// UI after that frame while leaving the authority invalidation synchronous.
class GuideStateBuilder extends StatefulWidget {
  const GuideStateBuilder({
    super.key,
    required this.controller,
    required this.builder,
  });
  final GuideController controller;
  final WidgetBuilder builder;
  @override
  State<GuideStateBuilder> createState() => _GuideStateBuilderState();
}

class _GuideStateBuilderState extends State<GuideStateBuilder> {
  bool _queued = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(GuideStateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
