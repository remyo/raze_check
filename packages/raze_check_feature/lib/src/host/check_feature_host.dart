import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../guides/guide_layer.dart';
import '../guides/guide_models.dart';
import '../guides/guide_scene.dart';
import '../guides/guide_scope.dart';

final class CheckFeatureHost {
  const CheckFeatureHost({
    required this.onExit,
    this.themeBuilder,
    this.iconBuilder,
    this.navigate,
    this.guideProgress,
    this.guides = const GuidePresentationConfig(),
  });
  final VoidCallback onExit;
  final GuideProgressStore? guideProgress;
  final GuidePresentationConfig guides;

  /// Returning the inherited host theme preserves the host's typography.
  final ThemeData Function(BuildContext, Brightness)? themeBuilder;
  final Widget Function(BuildContext)? iconBuilder;
  final Future<void> Function(BuildContext, Widget, String)? navigate;
  Future<void> open(
    BuildContext context,
    Widget page,
    String name, {
    bool guideLayer = true,
  }) {
    final scope = GuideScope.capture(context);
    final boundary = FeatureRouteScope.maybeOf(context);
    final origin =
        GuideScene.maybeContextOf(context) ?? scope?.controller.currentContext;
    Widget protectedPage = guideLayer ? GuideLayer(child: page) : page;
    if (scope != null) protectedPage = scope.wrap(protectedPage);
    if (boundary != null) {
      protectedPage = _ProtectedHostPage(
        lifetime: boundary.lifetime,
        generation: boundary.generation,
        validate: origin?.validateCurrent,
        child: protectedPage,
      );
    }
    protectedPage = InheritedTheme.captureAll(context, protectedPage);
    final routedPage = protectedPage;
    return navigate?.call(context, routedPage, name) ??
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => routedPage,
            settings: RouteSettings(name: name),
          ),
        );
  }
}

/// Internal gate lifetime. Scene handoff may clear a controller context without
/// invalidating this generation; a lock/replacement/exit always replaces it.
class FeatureRouteLifetime extends ChangeNotifier {
  Object generation = Object();
  bool alive = true;
  void invalidate() {
    generation = Object();
    notifyListeners();
  }

  void end() {
    alive = false;
    invalidate();
  }

  bool accepts(Object value) => alive && identical(value, generation);
}

class FeatureRouteScope extends InheritedWidget {
  const FeatureRouteScope({
    super.key,
    required this.lifetime,
    required this.generation,
    required super.child,
  });
  final FeatureRouteLifetime lifetime;
  final Object generation;
  static FeatureRouteScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeatureRouteScope>();
  @override
  bool updateShouldNotify(FeatureRouteScope oldWidget) =>
      !identical(generation, oldWidget.generation) ||
      lifetime != oldWidget.lifetime;
}

class _ProtectedHostPage extends StatefulWidget {
  const _ProtectedHostPage({
    required this.lifetime,
    required this.generation,
    required this.validate,
    required this.child,
  });
  final FeatureRouteLifetime lifetime;
  final Object generation;
  final Future<void> Function()? validate;
  final Widget child;
  @override
  State<_ProtectedHostPage> createState() => _ProtectedHostPageState();
}

class _ProtectedHostPageState extends State<_ProtectedHostPage>
    with WidgetsBindingObserver {
  bool _foreground = true, _valid = true;
  int _validation = 0;
  @override
  void initState() {
    super.initState();
    widget.lifetime.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _validate();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _validate() async {
    final generation = ++_validation;
    try {
      await widget.validate?.call();
    } catch (_) {
      if (mounted && generation == _validation) setState(() => _valid = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    if (_foreground) _validate();
  }

  @override
  void dispose() {
    widget.lifetime.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FeatureRouteScope(
    lifetime: widget.lifetime,
    generation: widget.generation,
    child: Visibility(
      visible:
          _foreground && _valid && widget.lifetime.accepts(widget.generation),
      maintainState: true,
      replacement: Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Protected Raze Check view')),
      ),
      child: widget.child,
    ),
  );
}
