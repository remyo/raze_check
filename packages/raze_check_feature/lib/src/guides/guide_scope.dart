import 'package:flutter/widgets.dart';
import 'guide_anchor_registry.dart';
import 'guide_controller.dart';

class GuideScope extends StatefulWidget {
  const GuideScope({super.key, required this.controller, required this.child});
  final GuideController controller;
  final Widget child;

  static _GuideEnvironment? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GuideEnvironment>();
  static GuideController? maybeOf(BuildContext context) =>
      _of(context)?.controller;
  static GuideAnchorRegistry? registryOf(BuildContext context) =>
      _of(context)?.registry;
  static bool isVisibleOf(BuildContext context) =>
      _of(context)?.visible ?? false;

  /// Capture before calling a custom host navigator. The borrowed page gets its
  /// own route visibility, but shares the original controller and registry.
  static GuideScopeHandle? capture(BuildContext context) {
    final scope = _of(context);
    return scope == null
        ? null
        : GuideScopeHandle._(scope.controller, scope.registry);
  }

  @override
  State<GuideScope> createState() => _GuideScopeState();
}

class _GuideScopeState extends State<GuideScope> {
  final registry = GuideAnchorRegistry();
  @override
  Widget build(BuildContext context) => _GuideEnvironment(
    controller: widget.controller,
    registry: registry,
    visible:
        Visibility.of(context) && (ModalRoute.isCurrentOf(context) ?? true),
    child: widget.child,
  );
  @override
  void dispose() {
    registry.dispose();
    super.dispose();
  }
}

/// Internal feature integration handle, not an owner or authority grant.
class GuideScopeHandle {
  GuideScopeHandle._(this.controller, this.registry);
  final GuideController controller;
  final GuideAnchorRegistry registry;
  Widget wrap(Widget child) => _BorrowedGuideScope(handle: this, child: child);
}

class _BorrowedGuideScope extends StatelessWidget {
  const _BorrowedGuideScope({required this.handle, required this.child});
  final GuideScopeHandle handle;
  final Widget child;
  @override
  Widget build(BuildContext context) => _GuideEnvironment(
    controller: handle.controller,
    registry: handle.registry,
    visible:
        Visibility.of(context) && (ModalRoute.isCurrentOf(context) ?? true),
    child: child,
  );
}

class _GuideEnvironment extends InheritedWidget {
  const _GuideEnvironment({
    required this.controller,
    required this.registry,
    required this.visible,
    required super.child,
  });
  final GuideController controller;
  final GuideAnchorRegistry registry;
  final bool visible;
  @override
  bool updateShouldNotify(_GuideEnvironment oldWidget) =>
      controller != oldWidget.controller ||
      registry != oldWidget.registry ||
      visible != oldWidget.visible;
}
