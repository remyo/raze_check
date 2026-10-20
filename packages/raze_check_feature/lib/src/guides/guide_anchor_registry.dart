import 'dart:collection';
import 'package:flutter/widgets.dart';

/// Render registrations belong to a scene, never to a global textual ID.
class GuideAnchorRegistry extends ChangeNotifier {
  final _targets = HashMap<Object, Map<String, GlobalKey>>.identity();
  final _scenes = HashMap<Object, GlobalKey>.identity();
  Object? _currentSceneToken;
  Object? get currentSceneToken => _currentSceneToken;
  bool _scheduled = false, _disposed = false;
  int _activation = 0;

  void register(Object sceneToken, String id, GlobalKey key) {
    (_targets[sceneToken] ??= {})[id] = key;
    geometryChanged();
  }

  void unregister(Object sceneToken, String id, GlobalKey key) {
    final entries = _targets[sceneToken];
    if (!identical(entries?[id], key)) return;
    entries!.remove(id);
    if (entries.isEmpty) _targets.remove(sceneToken);
    geometryChanged();
  }

  // Internal presentation lifecycle shared by scene, target and layer.
  int activate(Object token, GlobalKey key) {
    _scenes[token] = key;
    _currentSceneToken = token;
    geometryChanged();
    return ++_activation;
  }

  bool isActivationCurrent(Object token, int activation) =>
      !_disposed &&
      activation == _activation &&
      identical(token, _currentSceneToken);

  void deactivate(Object token) {
    if (identical(_currentSceneToken, token)) {
      _currentSceneToken = null;
      _activation++;
    }
    geometryChanged();
  }

  void removeScene(Object token) {
    deactivate(token);
    _scenes.remove(token);
    _targets.remove(token);
  }

  bool sceneIsVisible(Object token, RenderBox layer) =>
      identical(token, _currentSceneToken) &&
      _visibleBounds(_scenes[token], layer, requireEntire: false) != null;

  Rect? bounds(Object sceneToken, String id, RenderBox layer) =>
      _visibleBounds(_targets[sceneToken]?[id], layer);

  Rect? _visibleBounds(
    GlobalKey? key,
    RenderBox layer, {
    bool requireEntire = true,
  }) {
    final target = key?.currentContext?.findRenderObject();
    if (target is! RenderBox ||
        !target.attached ||
        !target.hasSize ||
        !layer.attached ||
        !layer.hasSize ||
        target.size.isEmpty) {
      return null;
    }
    try {
      final transform = target.getTransformTo(layer);
      if (transform.determinant() == 0) return null;
      final rect = MatrixUtils.transformRect(
        transform,
        Offset.zero & target.size,
      );
      if (!rect.isFinite || rect.isEmpty) return null;
      var visible = rect.intersect(Offset.zero & layer.size);
      RenderObject child = target;
      for (
        RenderObject? parent = child.parent;
        parent != null;
        parent = child.parent
      ) {
        if (!parent.paintsChild(child)) return null;
        final clip = parent.describeApproximatePaintClip(child);
        if (clip != null) {
          final projected = MatrixUtils.transformRect(
            parent.getTransformTo(layer),
            clip,
          );
          if (!projected.isFinite) return null;
          visible = visible.intersect(projected);
        }
        child = parent;
      }
      if (visible.isEmpty || !visible.isFinite) return null;
      // Partial targets use the explanation fallback, rather than an inaccurate outline.
      if (requireEntire && !visible.inflate(.01).contains(rect.topLeft)) {
        return null;
      }
      if (requireEntire && !visible.inflate(.01).contains(rect.bottomRight)) {
        return null;
      }
      return requireEntire ? rect : visible;
    } on FlutterError {
      return null; // Disconnected render trees during route/target replacement.
    } on StateError {
      return null;
    }
  }

  /// Coalesces actual layout, paint and scroll events; never polls frames.
  void geometryChanged() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    _targets.clear();
    _scenes.clear();
    super.dispose();
  }
}
