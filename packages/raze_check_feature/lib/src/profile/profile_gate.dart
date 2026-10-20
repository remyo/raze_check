import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../../raze_check_feature.dart';
import '../host/check_feature_host.dart';
import '../guides/guide_scope.dart';
import '../guides/guide_controller.dart';
import '../guides/guide_models.dart';
import '../guides/guide_scene.dart';
import '../guides/guide_layer.dart';
import '../guides/welcome_screen.dart';
import '../guides/guide_library_screen.dart';
import '../settings/settings_screen.dart';

class CheckProfileGate extends StatefulWidget {
  const CheckProfileGate({
    super.key,
    required this.identity,
    this.companies,
    this.onRecovery,
    this.pickHistory,
    this.enrollment,
    this.messages,
    this.capture,
    this.attendance,
    this.attendanceMessages,
    this.services,
    this.host,
    this.initialCompanyId,
  });
  final CheckServices? services;
  final CheckFeatureHost? host;
  final String? initialCompanyId;
  final IdentityService identity;
  final Future<void> Function(SessionHandle)? onRecovery;
  final Future<Uint8List?> Function(TransferGuard)? pickHistory;
  final CompanyService? companies;
  final EnrollmentService? enrollment;
  final EnrollmentMessagePort? messages;
  final CaptureService? capture;
  final AttendanceService? attendance;
  final AttendanceMessagePort? attendanceMessages;
  @override
  State<CheckProfileGate> createState() => CheckProfileGateState();
}

class CheckProfileGateState extends State<CheckProfileGate>
    with WidgetsBindingObserver {
  late Future<List<LocalProfile>> _profiles;
  SessionHandle? _session;
  bool _setup = false;
  bool _operatorUnlock = false;
  bool _canCreateCompany = true;
  LocalProfile? _selected;
  Timer? _expiry;
  bool _obscured = false;
  final _lifetime = FeatureRouteLifetime();
  GuideController? _guides;
  GuideContext? _guideContext;
  bool _welcomeFinished = false;
  BuildContext? _routingContext;

  /// Context beneath the gate's live session boundary for feature-owned routes.
  BuildContext? get routingContext =>
      mounted && _lifetime.alive && (_routingContext?.mounted ?? false)
      ? _routingContext
      : null;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _guides = GuideScope.maybeOf(context);
    _guideContext ??= _makeGuideContext();
  }

  GuideContext _makeGuideContext() {
    final generation = _lifetime.generation, session = _session;
    return GuideContext(
      token: Object(),
      authorityToken: generation,
      audience: GuideAudience(variants: const {'welcome': 'public'}),
      validateCurrent: () async {
        if (!mounted ||
            !_lifetime.accepts(generation) ||
            !identical(_session, session)) {
          throw StateError('Expired guide session');
        }
        if (session != null) widget.identity.requireActor(session);
      },
    );
  }

  void _invalidateGuides() {
    final oldAuthority = _guideContext?.authorityToken;
    final activeAuthority = _guides?.currentContext?.authorityToken;
    _lifetime.invalidate();
    if (activeAuthority != null) _guides?.invalidateAuthority(activeAuthority);
    if (oldAuthority != null) _guides?.invalidateAuthority(oldAuthority);
    _guideContext = null;
  }

  Future<void> _openGuidePage(
    BuildContext source,
    WidgetBuilder builder,
    String name,
  ) async {
    final origin =
        _guides?.currentContext ??
        GuideScene.maybeContextOf(source) ??
        _guideContext;
    if (origin == null) return;
    final generation = _lifetime.generation;
    try {
      await origin.validateCurrent();
    } catch (_) {
      return;
    }
    if (!mounted || !source.mounted || !_lifetime.accepts(generation)) return;
    ModalRoute<dynamic>? openedRoute;
    NavigatorState? openedNavigator;
    final originReturn =
        origin.originReturn ??
        GuideOriginReturn(
          token: origin.token,
          returnToOrigin: () async {
            await origin.validateCurrent();
            final route = openedRoute, navigator = openedNavigator;
            if (!mounted ||
                !_lifetime.accepts(generation) ||
                route == null ||
                !route.isActive ||
                navigator == null ||
                !navigator.mounted) {
              throw StateError('Expired guide origin');
            }
            navigator.popUntil((candidate) => identical(candidate, route));
            navigator.pop();
            await route.completed;
            await WidgetsBinding.instance.endOfFrame;
          },
        );
    final scene = GuideContext(
      token: Object(),
      authorityToken: origin.authorityToken,
      audience: origin.audience,
      validateCurrent: origin.validateCurrent,
      navigation: origin.navigation,
      originReturn: originReturn,
    );
    final page = Builder(
      builder: (pageContext) {
        openedRoute = ModalRoute.of(pageContext);
        openedNavigator = Navigator.of(pageContext);
        return GuideScene(
          context: scene,
          child: Builder(builder: builder),
        );
      },
    );
    final host = widget.host ?? CheckFeatureHost(onExit: () {});
    await host.open(source, page, name, guideLayer: false);
  }

  void _settings(BuildContext source) {
    _openGuidePage(
      source,
      (settingsContext) => SettingsScreen(
        onOpenGuides: () {
          _openGuidePage(
            settingsContext,
            (_) => GuideLibraryScreen(brandBuilder: widget.host?.iconBuilder),
            'help-guides',
          );
        },
      ),
      'settings',
    );
  }

  void _exit() {
    _invalidateGuides();
    _lifetime.end();
    _expiry?.cancel();
    widget.identity.lock();
    widget.host!.onExit();
    if (mounted) setState(() {});
  }

  final _workspace = GlobalKey<CompanyWorkspaceState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profiles = widget.identity.profiles();
  }

  @override
  void dispose() {
    _invalidateGuides();
    _lifetime.end();
    _expiry?.cancel();
    widget.identity.lock();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _lock() {
    _invalidateGuides();
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.identity.lock();
    _expiry?.cancel();
    setState(() {
      _session = null;
      _setup = false;
      _operatorUnlock = false;
      _selected = null;
      _profiles = widget.identity.profiles();
    });
  }

  void _opened(SessionHandle session) {
    _invalidateGuides();
    try {
      _canCreateCompany =
          widget.identity.requireActor(session).restrictedCompanyId == null;
    } on CheckException {
      _lock();
      return;
    }
    setState(() {
      _session = session;
      _setup = false;
      _operatorUnlock = false;
      _selected = null;
    });
    _expiry?.cancel();
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    final identity = widget.identity;
    final remaining = identity is ActivityIdentityService
        ? (identity as ActivityIdentityService).remainingIdleTime(_session!)
        : const Duration(minutes: 5);
    _expiry = Timer(remaining, _lock);
  }

  void _checkSession() {
    if (!mounted || _session == null) return;
    try {
      widget.identity.requireActor(_session!);
      _expiry?.cancel();
      _scheduleExpiry();
    } on CheckException {
      _lock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hide protected content in the switcher; check the original handle on resume.
    setState(() {
      _obscured = state != AppLifecycleState.resumed;
    });
    if (state == AppLifecycleState.resumed) _checkSession();
  }

  @override
  Widget build(BuildContext context) {
    _guideContext ??= _makeGuideContext();
    return FeatureRouteScope(
      lifetime: _lifetime,
      generation: _lifetime.generation,
      child: Visibility(
        visible: !_obscured && _lifetime.alive,
        maintainState: true,
        replacement: const Scaffold(
          body: Center(child: Text('Raze Check locked view')),
        ),
        child: GuideScene(
          context: _guideContext!,
          child: Builder(
            builder: (sceneContext) {
              _routingContext = sceneContext;
              final guides = _guides;
              if (guides == null) return _content(sceneContext);
              return GuideStateBuilder(
                controller: guides,
                builder: (_) {
                  final welcome =
                      widget.host?.guides.automaticWelcome == true &&
                      !_welcomeFinished &&
                      !guides.progress.welcomeDismissed &&
                      _session == null;
                  if (welcome && !guides.ready) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (welcome) {
                    return WelcomeScreen(
                      brandBuilder: widget.host?.iconBuilder,
                      onFinished: () => setState(() => _welcomeFinished = true),
                    );
                  }
                  return GuideLayer(child: _content(sceneContext));
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_session != null) {
      final compactActions =
          MediaQuery.sizeOf(context).width < 500 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      Future<void> recovery() async {
        final originalSession = _session!;
        final refresh = _workspace.currentState?.prepareRecoveryRefresh();
        await widget.onRecovery!(originalSession);
        if (!mounted || !identical(_session, originalSession)) return;
        _checkSession();
        if (identical(_session, originalSession)) refresh?.call();
      }

      return Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child:
                      widget.host?.iconBuilder?.call(context) ??
                      Image.asset(
                        'packages/raze_check_feature/assets/branding/raze_check_logo_master.png',
                        semanticLabel: 'Raze Check mascot',
                      ),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(child: Text('Raze Check')),
            ],
          ),
          leading: widget.host == null
              ? null
              : IconButton(
                  tooltip: 'Exit Raze Check',
                  onPressed: _exit,
                  icon: const Icon(Icons.close),
                ),
          actions: [
            IconButton(
              tooltip: 'Settings',
              onPressed: () => _settings(context),
              icon: const Icon(Icons.settings_outlined),
            ),
            if (widget.onRecovery != null)
              compactActions
                  ? IconButton(
                      tooltip: 'Backup / recovery',
                      onPressed: recovery,
                      icon: const Icon(Icons.settings_backup_restore),
                    )
                  : TextButton(
                      onPressed: recovery,
                      child: const Text('Backup / recovery'),
                    ),
            compactActions
                ? IconButton(
                    tooltip: 'Lock',
                    onPressed: _lock,
                    icon: const Icon(Icons.lock_outline),
                  )
                : TextButton(onPressed: _lock, child: const Text('Lock')),
          ],
        ),
        body: widget.companies == null
            ? const Center(child: Text('Profile unlocked'))
            : CompanyWorkspace(
                services: widget.services,
                key: _workspace,
                host: widget.host,
                initialCompanyId: widget.initialCompanyId,
                onSettings: () => _settings(context),
                onRecovery: widget.onRecovery == null ? null : recovery,
                companies: widget.companies!,
                enrollment: widget.enrollment,
                capture: widget.capture,
                attendance: widget.attendance,
                attendanceMessages: widget.attendanceMessages,
                messages: widget.messages,
                pickHistory: widget.pickHistory,
                session: _session!,
                ids: SecureIds(),
                onAuthorizedActivity: _checkSession,
                canCreateCompany: _canCreateCompany,
                onSessionChanged: _opened,
                onLocked: _lock,
              ),
      );
    }
    if (_operatorUnlock && widget.companies != null) {
      return OperatorUnlockScreen(
        companies: widget.companies!,
        onUnlocked: _opened,
        onCancel: () => setState(() => _operatorUnlock = false),
      );
    }
    if (_setup) {
      return ProfileSetupScreen(
        identity: widget.identity,
        onCreated: _opened,
        onCancel: () => setState(() {
          _setup = false;
        }),
      );
    }
    if (_selected != null) {
      return UnlockScreen(
        identity: widget.identity,
        profile: _selected!,
        onUnlocked: _opened,
        onCancel: () => setState(() {
          _selected = null;
        }),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raze Check'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _settings(context),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      width: 88,
                      height: 88,
                      child:
                          widget.host?.iconBuilder?.call(context) ??
                          Image.asset(
                            'packages/raze_check_feature/assets/branding/raze_check_logo_master.png',
                            semanticLabel: 'Raze Check mascot',
                          ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Attendance, made simple',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Create a local profile or unlock one to continue.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FutureBuilder<List<LocalProfile>>(
                    future: _profiles,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Column(
                          children: [
                            Text(
                              profileError(
                                snapshot.error is CheckException
                                    ? (snapshot.error as CheckException).code
                                    : CheckError.storageFailure,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _profiles = widget.identity.profiles();
                              }),
                              child: const Text('Retry'),
                            ),
                          ],
                        );
                      }
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }
                      return Column(
                        children: [
                          for (final profile in snapshot.data!)
                            ListTile(
                              title: Text('Unlock ${profile.displayName}'),
                              trailing: const Icon(Icons.lock_outline),
                              onTap: () => setState(() {
                                _selected = profile;
                              }),
                            ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => setState(() {
                                _setup = true;
                              }),
                              child: const Text('Create local profile'),
                            ),
                          ),
                          if (widget.companies != null)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _operatorUnlock = true),
                              child: const Text('Unlock company operator'),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
