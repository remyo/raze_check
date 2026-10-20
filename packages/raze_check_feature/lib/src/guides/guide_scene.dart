import 'package:flutter/widgets.dart';
import 'guide_anchor_registry.dart';
import 'guide_controller.dart';
import 'guide_models.dart';
import 'guide_scope.dart';

class GuideScene extends StatefulWidget {
  const GuideScene({super.key, required this.context, required this.child});
  final GuideContext context;
  final Widget child;
  static GuideContext? maybeContextOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GuideSceneBinding>()
      ?.guideContext;
  @override
  State<GuideScene> createState() => _GuideSceneState();
}

class _GuideSceneState extends State<GuideScene> {
  final _key = GlobalKey();
  GuideController? _controller;
  GuideAnchorRegistry? _registry;
  ModalRoute<dynamic>? _route;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = GuideScope.maybeOf(context);
    final registry = GuideScope.registryOf(context);
    final route = ModalRoute.of(context);
    final visible =
        GuideScope.isVisibleOf(context) &&
        Visibility.of(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (_controller != controller || _registry != registry) {
      _unbind(widget.context.token);
      _controller = controller;
      _registry = registry;
      _visible = false;
    }
    if (_route != route) {
      _route?.animation?.removeListener(_geometryChanged);
      _route?.secondaryAnimation?.removeListener(_geometryChanged);
      _route = route;
      _route?.animation?.addListener(_geometryChanged);
      _route?.secondaryAnimation?.addListener(_geometryChanged);
    }
    if (_visible != visible) {
      _visible = visible;
      if (visible) {
        _bind();
      } else {
        _unbind(widget.context.token);
      }
    }
  }

  void _geometryChanged() => _registry?.geometryChanged();
  void _unbind(Object token) {
    _registry?.deactivate(token);
    _controller?.invalidateScene(token);
  }

  void _bind() {
    final registry = _registry,
        controller = _controller,
        guideContext = widget.context;
    if (registry == null || controller == null || !_visible) return;
    final activation = registry.activate(guideContext.token, _key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_visible ||
          !identical(widget.context, guideContext) ||
          !registry.isActivationCurrent(guideContext.token, activation)) {
        return;
      }
      // Domain/session validation is unchanged. Route visibility is presentation-only.
      controller.bind(guideContext);
    });
  }

  @override
  void didUpdateWidget(GuideScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.context, widget.context)) {
      _unbind(oldWidget.context.token);
      _registry?.removeScene(oldWidget.context.token);
      _bind();
    }
  }

  @override
  void dispose() {
    _route?.animation?.removeListener(_geometryChanged);
    _route?.secondaryAnimation?.removeListener(_geometryChanged);
    _unbind(widget.context.token);
    _registry?.removeScene(widget.context.token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GuideSceneBinding(
    guideContext: widget.context,
    registry: _registry,
    child: SizedBox(key: _key, child: widget.child),
  );
}

/// Internal inherited registration boundary; callers may inspect the original
/// context without borrowing its presentation visibility as business authority.
class GuideSceneBinding extends InheritedWidget {
  const GuideSceneBinding({
    super.key,
    required this.guideContext,
    required this.registry,
    required super.child,
  });
  final GuideContext guideContext;
  final GuideAnchorRegistry? registry;
  static GuideSceneBinding? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuideSceneBinding>();
  @override
  bool updateShouldNotify(GuideSceneBinding oldWidget) =>
      !identical(guideContext, oldWidget.guideContext) ||
      registry != oldWidget.registry;
}
