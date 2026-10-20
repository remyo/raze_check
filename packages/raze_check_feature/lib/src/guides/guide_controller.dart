import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'guide_catalog.dart';
import 'guide_models.dart';

final class _Intent {
  _Intent(this.run, this.destination, this.authority, this.originToken);
  final GuideRun run;
  final GuideDestination destination;
  final Object authority;
  final Object? originToken;
  bool returning = true;
  final completion = Completer<void>();

  bool acceptsOrigin(GuideContext context) =>
      returning &&
      originToken != null &&
      identical(originToken, context.token) &&
      identical(authority, context.authorityToken);

  bool acceptsDestination(GuideContext context) =>
      identical(authority, context.authorityToken) &&
      destination == context.destination &&
      context.audience.variants[run.definition.id] == run.definition.variantId;
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
  GuideContext? get currentContext => _context;
  GuideContext? _binding;
  (GuideRun, GuideContext)? _pausedRun;
  _Intent? _pendingValue;
  _Intent? get _pending => _pendingValue;
  set _pending(_Intent? value) {
    final previous = _pendingValue;
    _pendingValue = value;
    if (previous != null &&
        !identical(previous, value) &&
        !previous.completion.isCompleted) {
      previous.completion.complete();
    }
  }

  /// Internal panel/route handoff. Capture the original request before any
  /// extra domain validation; canceled callbacks cannot adopt a newer intent.
  /// Panels wait for a matching bind (or cancellation). Routes instead return
  /// their own future so Show me can discard an intent if no scene mounted.
  Future<void> navigateToScene(
    FutureOr<void> Function() navigate, {
    Future<void> Function()? validateCurrent,
    bool waitForSceneBinding = true,
  }) async {
    final intent = _pending, source = _context;
    final requestGeneration = _requestGeneration;
    if (intent == null || source == null || paused) return;
    await validateCurrent?.call();
    if (!identical(_pending, intent) ||
        requestGeneration != _requestGeneration ||
        !identical(_context, source) ||
        paused) {
      return;
    }
    await navigate();
    if (waitForSceneBinding) await intent.completion.future;
  }

  int _generation = 0;
  int _requestGeneration = 0;

  void _cancelNavigation() {
    _pausedRun = null;
    _requestGeneration++;
    _pending = null;
  }

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

  bool _matchesPause(GuideContext context) {
    final paused = _pausedRun;
    return paused != null &&
        identical(paused.$2.token, context.token) &&
        identical(paused.$2.authorityToken, context.authorityToken) &&
        context.audience.variants[paused.$1.definition.id] ==
            paused.$1.definition.variantId;
  }

  void _resumePausedRun() {
    final context = _context, paused = _pausedRun;
    if (_paused ||
        context == null ||
        paused == null ||
        !_matchesPause(context)) {
      return;
    }
    _pausedRun = null;
    _active = GuideRun(
      definition: paused.$1.definition,
      stepIndex: paused.$1.stepIndex,
      contextToken: context.token,
    );
  }

  Future<void> bind(GuideContext context) async {
    if (_pausedRun != null && !_matchesPause(context)) _pausedRun = null;
    final pending = _pending;
    if (pending != null &&
        !pending.acceptsOrigin(context) &&
        !pending.acceptsDestination(context)) {
      _cancelNavigation();
    }
    final generation = ++_generation;
    _active = null;
    _context = null;
    _binding = context;
    try {
      await context.validateCurrent();
    } catch (_) {
      if (generation == _generation) {
        _pausedRun = null;
        _pending = null;
        notifyListeners();
      }
      return;
    }
    if (generation != _generation) return;
    _binding = null;
    final intent = _pending;
    _context = context;
    // The captured origin is an intermediate route during explicit Show me.
    // Do not consume its intent before the guarded destination can mount.
    if (intent != null && intent.acceptsOrigin(context)) {
      notifyListeners();
      return;
    }
    _pending = null;
    if (intent != null && intent.acceptsDestination(context)) {
      _active = GuideRun(
        definition: intent.run.definition,
        stepIndex: intent.run.stepIndex,
        contextToken: context.token,
      );
    }
    _resumePausedRun();
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
        !identical(_pausedRun?.$2.authorityToken, authorityToken) &&
        !identical(_binding?.authorityToken, authorityToken)) {
      return;
    }
    _generation++;
    _binding = null;
    _context = null;
    _active = null;
    _pausedRun = null;
    _pending = null;
    notifyListeners();
  }

  void start(String guideId, {bool restart = false}) {
    _cancelNavigation();
    if (!_ready || _context == null) return;
    final variant = audience.variants[guideId];
    if (variant == null) return;
    GuideDefinition definition;
    try {
      definition = catalog.resolve(guideId, variant);
    } on ArgumentError {
      return;
    }
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
    _cancelNavigation();
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
    _cancelNavigation();
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
    _cancelNavigation();
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
    _cancelNavigation();
    final requestGeneration = _requestGeneration;
    final destination = run.definition.steps[run.stepIndex].destination!;
    _Intent? request;
    try {
      await context.validateCurrent();
      if (generation != _generation ||
          requestGeneration != _requestGeneration ||
          paused ||
          !identical(_active, run) ||
          !identical(_context, context)) {
        return;
      }
      final intent = _Intent(
        run,
        destination,
        context.authorityToken,
        context.originReturn?.token,
      );
      request = intent;
      _pending = intent;
      final originReturn = context.originReturn;
      if (originReturn != null) {
        await originReturn.returnToOrigin();
        if (!identical(_pending, intent) ||
            requestGeneration != _requestGeneration ||
            paused ||
            _context == null ||
            !intent.acceptsOrigin(_context!)) {
          return;
        }
        await context.validateCurrent();
        if (!identical(_pending, intent) ||
            requestGeneration != _requestGeneration ||
            paused ||
            _context == null ||
            !intent.acceptsOrigin(_context!)) {
          return;
        }
      }
      intent.returning = false;
      await context.navigation[destination]!();
      // A mounted destination consumes the intent. A return without a mount
      // means canceled or unrelated navigation, and must not revive guidance.
      if (identical(_pending, intent)) _pending = null;
    } catch (_) {
      if (identical(_pending, request)) _pending = null;
    }
  }

  void setPaused(bool paused) {
    if (paused && !_paused) {
      _cancelNavigation();
      if (_active != null && _context != null) {
        _pausedRun = (_active!, _context!);
      }
    }
    _paused = paused;
    if (!paused) _resumePausedRun();
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
