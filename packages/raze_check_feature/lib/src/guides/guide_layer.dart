import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'guide_anchor_registry.dart';
import 'guide_controller.dart';
import 'guide_models.dart';
import 'guide_panel.dart';
import 'guide_scope.dart';

class GuideLayer extends StatefulWidget {
  const GuideLayer({super.key, required this.child});
  final Widget child;
  @override
  State<GuideLayer> createState() => _GuideLayerState();
}

class _GuideLayerState extends State<GuideLayer> {
  final _layerKey = GlobalKey();
  GuideController? _controller;
  GuideAnchorRegistry? _registry;
  GuideRun? _run;
  String? _notice, _dismissedNotice;
  Rect? _target;
  bool _scheduled = false, _visible = false;
  bool _canShowDestination = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = GuideScope.maybeOf(context);
    final registry = GuideScope.registryOf(context);
    if (_controller != controller || _registry != registry) {
      _controller?.removeListener(_scheduleMeasure);
      _registry?.removeListener(_scheduleMeasure);
      _controller = controller;
      _registry = registry;
      _controller?.addListener(_scheduleMeasure);
      _registry?.addListener(_scheduleMeasure);
    }
    _visible =
        GuideScope.isVisibleOf(context) &&
        Visibility.of(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final layer = _layerKey.currentContext?.findRenderObject();
      var run = _controller?.active;
      if (!_visible ||
          _controller?.paused == true ||
          layer is! RenderBox ||
          run == null ||
          _registry?.sceneIsVisible(run.contextToken, layer) != true) {
        run = null;
      }
      final id = run?.definition.steps[run.stepIndex].targetId;
      final target = run != null && id != null && layer is RenderBox
          ? _registry?.bounds(run.contextToken, id, layer)
          : null;
      final notice =
          _visible &&
              _controller?.paused != true &&
              _controller?.currentContext != null
          ? _controller?.presentationNotice
          : null;
      final canShow = _controller?.canShowDestination ?? false;
      if (!identical(_run, run) ||
          _target != target ||
          _notice != notice ||
          _canShowDestination != canShow) {
        setState(() {
          _run = run;
          _notice = notice;
          _target = target;
          _canShowDestination = canShow;
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _controller?.removeListener(_scheduleMeasure);
    _registry?.removeListener(_scheduleMeasure);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return widget.child;
    final media = MediaQuery.of(context);
    final run = _visible ? _run : null;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleMeasure();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _scheduleMeasure();
          return false;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            _scheduleMeasure();
            return Stack(
              key: _layerKey,
              fit: StackFit.expand,
              children: [
                widget.child,
                if (run == null &&
                    _visible &&
                    _notice != null &&
                    _notice != _dismissedNotice)
                  Positioned.fill(
                    child: SafeArea(
                      minimum: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Material(
                            color: Theme.of(context).colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(_notice!),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                    ),
                                    onPressed: () => setState(
                                      () => _dismissedNotice = _notice,
                                    ),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (run != null)
                  Positioned.fill(
                    child: CustomMultiChildLayout(
                      delegate: _GuidePlacement(
                        target: _target,
                        padding: media.padding,
                        viewInsets: media.viewInsets,
                      ),
                      children: [
                        LayoutId(
                          id: 'highlight',
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: ClipRect(
                                child: DecoratedBox(
                                  key: const ValueKey('guide-highlight'),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        LayoutId(
                          id: 'panel',
                          child: GuidePanel(
                            run: run,
                            notice: _notice,
                            onBack: _controller!.back,
                            onNext: _controller!.next,
                            onSkip: _controller!.skip,
                            onShowDestination: _canShowDestination
                                ? () {
                                    _controller!.showDestination();
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GuidePlacement extends MultiChildLayoutDelegate {
  _GuidePlacement({
    required this.target,
    required this.padding,
    required this.viewInsets,
  });
  final Rect? target;
  final EdgeInsets padding, viewInsets;
  @override
  void performLayout(Size size) {
    final safe = Rect.fromLTRB(
      math.min(size.width, math.max(padding.left, viewInsets.left) + 12),
      math.min(size.height, math.max(padding.top, viewInsets.top) + 12),
      math.max(0, size.width - math.max(padding.right, viewInsets.right) - 12),
      math.max(
        0,
        size.height - math.max(padding.bottom, viewInsets.bottom) - 12,
      ),
    );
    final width = math.max(0.0, math.min(440.0, safe.width));
    final height = math.max(0.0, safe.height);
    final panel = layoutChild(
      'panel',
      BoxConstraints(maxWidth: width, minWidth: width, maxHeight: height),
    );
    final x = safe.left + math.max(0.0, (safe.width - panel.width) / 2);
    var position = Offset(x, math.max(safe.top, safe.bottom - panel.height));
    var spotlight = false;
    final anchor = target;
    if (anchor != null) {
      const gap = 16.0;
      final candidates = [
        Offset(x, anchor.bottom + gap),
        Offset(x, anchor.top - gap - panel.height),
        Offset(anchor.right + gap, safe.top + (height - panel.height) / 2),
        Offset(
          anchor.left - gap - panel.width,
          safe.top + (height - panel.height) / 2,
        ),
      ];
      for (final candidate in candidates) {
        final rect = candidate & panel;
        if (safe.inflate(.01).contains(rect.topLeft) &&
            safe.inflate(.01).contains(rect.bottomRight) &&
            !rect.overlaps(anchor.inflate(8))) {
          position = candidate;
          spotlight = true;
          break;
        }
      }
    }
    positionChild('panel', position);
    layoutChild(
      'highlight',
      BoxConstraints.tight(spotlight ? anchor!.size : Size.zero),
    );
    positionChild('highlight', spotlight ? anchor!.topLeft : Offset.zero);
  }

  @override
  bool shouldRelayout(_GuidePlacement oldDelegate) =>
      target != oldDelegate.target ||
      padding != oldDelegate.padding ||
      viewInsets != oldDelegate.viewInsets;
}
