import 'package:flutter/foundation.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'guide_catalog.dart';
import 'guide_models.dart';

final class _Intent {
  _Intent(this.run, this.destination, this.authority);
  final GuideRun run;
  final GuideDestination destination;
  final Object authority;
}

/// Owns explanatory progress; callbacks may only open guarded screens.
final class GuideController extends ChangeNotifier {
  // Keep the public optional store parameter independent of the private field.
  // ignore: prefer_initializing_formals
  GuideController({GuideProgressStore? store, required this.catalog})
    // ignore: prefer_initializing_formals
    : _store = store;
  final GuideCatalog catalog;
  final GuideProgressStore? _store;
  GuideProgressSnapshot _progress = GuideProgressSnapshot();
  GuideProgressSnapshot get progress => _progress;
  GuideRun? _active;
  GuideRun? get active => _active;
  GuideContext? _context;
  GuideContext? _binding;
  _Intent? _pending;
  int _generation = 0;
  bool _ready = false, _failed = false, _paused = false;
  bool get ready => _ready;
  bool get persistenceFailed => _failed;
  bool get sessionOnly => _store == null || _failed;
  bool get paused => _paused;
  String? _notice;
  String? get notice => _notice;
  GuideAudience get audience =>
      _context?.audience ??
      GuideAudience(variants: const {'welcome': 'public'});
  Future<void>? _initialization;
  Future<void> _writes = Future.value();
  void _failure() {
    _failed = true;
    _notice =
        'Guide progress could not be saved. Progress is kept for this session.';
  }

  Future<void> initialize() => _initialization ??= _load();
  Future<void> _load() async {
    try {
      final loaded = await _store?.read();
      if (loaded != null) {
        _progress = GuideProgressSnapshot(
          welcomeDismissed: loaded.welcomeDismissed,
          entries: loaded.entries.where((e) {
            try {
              catalog.resolve(e.guideId, e.variantId);
              return true;
            } on ArgumentError {
              return false;
            }
          }).toList(),
        );
      }
    } catch (_) {
      _failure();
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> bind(GuideContext context) async {
    final generation = ++_generation;
    _active = null;
    _context = null;
    _binding = context;
    try {
      await context.validateCurrent();
    } catch (_) {
      if (generation == _generation) {
        _pending = null;
        notifyListeners();
      }
      return;
    }
    if (generation != _generation) return;
    _binding = null;
    final intent = _pending;
    _pending = null;
    _context = context;
    if (intent != null &&
        identical(intent.authority, context.authorityToken) &&
        intent.destination == context.destination &&
        context.audience.variants[intent.run.definition.id] ==
            intent.run.definition.variantId) {
      _active = GuideRun(
        definition: intent.run.definition,
        stepIndex: intent.run.stepIndex,
        contextToken: context.token,
      );
    }
    notifyListeners();
  }

  void invalidateScene(Object token) {
    if (!identical(_context?.token, token) &&
        !identical(_binding?.token, token)) {
      return;
    }
    _binding = null;
    _generation++;
    _context = null;
    _active = null;
    notifyListeners();
  }

  void invalidateAuthority(Object authorityToken) {
    if (!identical(_context?.authorityToken, authorityToken) &&
        !identical(_pending?.authority, authorityToken) &&
        !identical(_binding?.authorityToken, authorityToken)) {
      return;
    }
    _generation++;
    _binding = null;
    _context = null;
    _active = null;
    _pending = null;
    notifyListeners();
  }

  void start(String guideId, {bool restart = false}) {
    if (!_ready || _context == null) return;
    final variant = audience.variants[guideId];
    if (variant == null) return;
    GuideDefinition definition;
    try {
      definition = catalog.resolve(guideId, variant);
    } on ArgumentError {
      return;
    }
    _pending = null;
    final saved = _entry(guideId, variant);
    var index = 0;
    if (!restart && saved?.stepId != null) {
      index = definition.steps.indexWhere((s) => s.id == saved!.stepId);
      if (index < 0) {
        index = 0;
        _notice = 'This guide changed. Restarting from the first step.';
      }
    }
    _active = GuideRun(
      definition: definition,
      stepIndex: index,
      contextToken: _context!.token,
    );
    _saveRun();
  }

  GuideProgress? _entry(String id, String variant) {
    for (final e in _progress.entries) {
      if (e.guideId == id && e.variantId == variant) return e;
    }
    return null;
  }

  void _saveRun({bool viewed = false, bool dismiss = false}) {
    final run = _active;
    if (run == null) return;
    final d = run.definition;
    _replace(
      GuideProgress(
        guideId: d.id,
        variantId: d.variantId,
        contentRevision: d.revision,
        stepId: d.steps[run.stepIndex].id,
        viewed: viewed || (_entry(d.id, d.variantId)?.viewed ?? false),
        invitationDismissed: true,
      ),
      welcomeDismissed:
          _progress.welcomeDismissed ||
          (d.id == 'welcome' && (viewed || dismiss)),
    );
  }

  void _replace(GuideProgress entry, {bool? welcomeDismissed}) {
    _progress = GuideProgressSnapshot(
      welcomeDismissed: welcomeDismissed ?? _progress.welcomeDismissed,
      entries: [
        ..._progress.entries.where(
          (e) => e.guideId != entry.guideId || e.variantId != entry.variantId,
        ),
        entry,
      ],
    );
    final snapshot = _progress;
    _writes = _writes.then((_) async {
      await initialize();
      if (!sessionOnly) {
        try {
          await _store!.write(snapshot);
        } catch (_) {
          _failure();
          notifyListeners();
        }
      }
    });
    notifyListeners();
  }

  void next() {
    final run = _active;
    if (run == null || paused) return;
    if (run.stepIndex == run.definition.steps.length - 1) {
      _saveRun(viewed: true);
      _notice = 'Viewed';
      _active = null;
      notifyListeners();
      return;
    }
    _active = GuideRun(
      definition: run.definition,
      stepIndex: run.stepIndex + 1,
      contextToken: run.contextToken,
    );
    _saveRun();
  }

  void back() {
    final run = _active;
    if (run == null || paused || run.stepIndex == 0) return;
    _active = GuideRun(
      definition: run.definition,
      stepIndex: run.stepIndex - 1,
      contextToken: run.contextToken,
    );
    _saveRun();
  }

  void skip() {
    _pending = null;
    _saveRun(dismiss: true);
    _active = null;
    notifyListeners();
  }

  void dismissInvitation(String guideId) {
    if (!ready) return;
    final variant = audience.variants[guideId];
    if (variant == null) return;
    GuideDefinition d;
    try {
      d = catalog.resolve(guideId, variant);
    } on ArgumentError {
      return;
    }
    final previous = _entry(guideId, variant);
    _replace(
      GuideProgress(
        guideId: guideId,
        variantId: variant,
        contentRevision: d.revision,
        stepId: previous?.stepId,
        viewed: previous?.viewed ?? false,
        invitationDismissed: true,
      ),
      welcomeDismissed: _progress.welcomeDismissed || guideId == 'welcome',
    );
  }

  bool shouldInvite(String guideId) =>
      ready &&
      audience.variants.containsKey(guideId) &&
      catalog.available(audience).any((g) => g.id == guideId) &&
      !_progress.entries.any(
        (e) =>
            e.guideId == guideId &&
            (e.invitationDismissed || e.viewed || e.stepId != null),
      ) &&
      (guideId != 'welcome' || !_progress.welcomeDismissed);
  bool get canShowDestination {
    final c = _context, r = _active;
    return !paused &&
        c != null &&
        r != null &&
        c.navigation.containsKey(r.definition.steps[r.stepIndex].destination);
  }

  Future<void> showDestination() async {
    if (!canShowDestination) return;
    final context = _context!, run = _active!, generation = _generation;
    final destination = run.definition.steps[run.stepIndex].destination!;
    _Intent? request;
    try {
      await context.validateCurrent();
      if (generation != _generation || !identical(_context, context)) return;
      final intent = _Intent(run, destination, context.authorityToken);
      request = intent;
      _pending = intent;
      await context.navigation[destination]!();
      // A mounted destination consumes the intent. A return without a mount
      // means canceled or unrelated navigation, and must not revive guidance.
      if (identical(_pending, intent)) _pending = null;
    } catch (_) {
      if (identical(_pending, request)) _pending = null;
    }
  }

  void setPaused(bool paused) {
    _paused = paused;
    notifyListeners();
  }

  Future<void> flush() async {
    await initialize();
    await _writes;
    if (!sessionOnly) {
      try {
        await _store!.flush();
      } catch (_) {
        _failure();
        notifyListeners();
      }
    }
  }
}
