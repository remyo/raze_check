import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'guide_anchor_registry.dart';
import 'guide_scene.dart';

class GuideTarget extends StatefulWidget {
  const GuideTarget({super.key, required this.id, required this.child});
  final String id;
  final Widget child;
  @override
  State<GuideTarget> createState() => _GuideTargetState();
}

class _GuideTargetState extends State<GuideTarget> {
  final _key = GlobalKey();
  GuideAnchorRegistry? _registry;
  Object? _token;
  Object? _guideContext;
  void _unregister(String id) {
    if (_token != null) _registry?.unregister(_token!, id, _key);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scene = GuideSceneBinding.maybeOf(context);
    if (scene?.registry != _registry ||
        !identical(scene?.guideContext, _guideContext)) {
      _unregister(widget.id);
      _registry = scene?.registry;
      _guideContext = scene?.guideContext;
      _token = scene?.guideContext.token;
      if (_token != null) _registry?.register(_token!, widget.id, _key);
    }
  }

  @override
  void didUpdateWidget(GuideTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id && _token != null) {
      _unregister(oldWidget.id);
      _registry?.register(_token!, widget.id, _key);
    }
  }

  @override
  void dispose() {
    _unregister(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _registry == null
      ? widget.child
      : _GuideGeometryObserver(
          key: _key,
          onGeometry: _registry!.geometryChanged,
          child: widget.child,
        );
}

class _GuideGeometryObserver extends SingleChildRenderObjectWidget {
  const _GuideGeometryObserver({
    super.key,
    required this.onGeometry,
    required super.child,
  });
  final VoidCallback onGeometry;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _GuideGeometryRender(onGeometry);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _GuideGeometryRender renderObject,
  ) {
    renderObject.onGeometry = onGeometry;
  }
}

class _GuideGeometryRender extends RenderProxyBox {
  _GuideGeometryRender(this.onGeometry);
  VoidCallback onGeometry;
  @override
  void performLayout() {
    super.performLayout();
    onGeometry();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onGeometry();
  }
}
