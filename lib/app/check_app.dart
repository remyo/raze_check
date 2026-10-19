import 'dart:async';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'local_composition.dart';

/// Standalone composition entry; reusable features live in their own package.
class CheckApp extends StatefulWidget {
  const CheckApp({
    super.key,
    this.identity,
    this.companies,
    this.enrollment,
    this.messages,
    this.capture,
    this.attendanceMessages,
  });
  final Future<IdentityService>? identity;
  final Future<CompanyService>? companies;
  final Future<EnrollmentService>? enrollment;
  final EnrollmentMessagePort? messages;
  final Future<CaptureService>? capture;
  final AttendanceMessagePort? attendanceMessages;
  @override
  State<CheckApp> createState() => _CheckAppState();
}

class _CheckAppState extends State<CheckApp> {
  late final Future<LocalComposition>? _composition = widget.identity == null
      ? LocalComposition.open()
      : null;
  late final Future<IdentityService> _identity =
      widget.identity ?? _composition!.then((services) => services.identity);

  late final Future<CompanyService?> _companies =
      widget.companies ??
      (_composition?.then((services) => services.companies) ??
          Future.value(null));

  late final Future<EnrollmentService?> _enrollment =
      widget.enrollment ??
      (_composition?.then((services) => services.enrollment) ??
          Future.value(null));

  late final Future<CaptureService?> _capture =
      widget.capture ??
      (_composition?.then((services) => services.capture) ??
          Future.value(null));

  @override
  void dispose() {
    final composition = _composition;
    if (composition != null) {
      unawaited(
        composition.then(
          (services) => services.close(),
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Raze Check',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f8c)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff087f8c),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: FutureBuilder<IdentityService>(
      future: _identity,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                profileError(
                  snapshot.error is CheckException
                      ? (snapshot.error as CheckException).code
                      : CheckError.storageFailure,
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return FutureBuilder<CompanyService?>(
          future: _companies,
          builder: (context, companies) {
            if (companies.hasError) {
              return const Scaffold(
                body: Center(
                  child: Text('Could not open local company storage.'),
                ),
              );
            }
            if (companies.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return FutureBuilder<EnrollmentService?>(
              future: _enrollment,
              builder: (context, enrollment) {
                if (enrollment.hasError) {
                  return const Scaffold(
                    body: Center(
                      child: Text('Could not open enrollment storage.'),
                    ),
                  );
                }
                if (enrollment.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                return FutureBuilder<CaptureService?>(
                  future: _capture,
                  builder: (context, capture) {
                    if (capture.hasError) {
                      return const Scaffold(
                        body: Center(
                          child: Text('Could not open attendance storage.'),
                        ),
                      );
                    }
                    if (capture.connectionState != ConnectionState.done) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _ProfileGate(
                      capture: capture.data,
                      attendanceMessages: widget.attendanceMessages,
                      identity: snapshot.data!,
                      companies: companies.data,
                      enrollment: enrollment.data,
                      messages: widget.messages,
                    );
                  },
                );
              },
            );
          },
        );
      },
    ),
  );
}

class _ProfileGate extends StatefulWidget {
  const _ProfileGate({
    required this.identity,
    this.companies,
    this.enrollment,
    this.messages,
    this.capture,
    this.attendanceMessages,
  });
  final IdentityService identity;
  final CompanyService? companies;
  final EnrollmentService? enrollment;
  final EnrollmentMessagePort? messages;
  final CaptureService? capture;
  final AttendanceMessagePort? attendanceMessages;
  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate>
    with WidgetsBindingObserver {
  late Future<List<LocalProfile>> _profiles;
  SessionHandle? _session;
  bool _setup = false;
  bool _operatorUnlock = false;
  bool _canCreateCompany = true;
  LocalProfile? _selected;
  Timer? _expiry;
  bool _obscured = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profiles = widget.identity.profiles();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    widget.identity.lock();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _lock() {
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
  Widget build(BuildContext context) => Visibility(
    visible: !_obscured,
    maintainState: true,
    replacement: const Scaffold(
      body: Center(child: Text('Raze Check locked view')),
    ),
    child: _content(context),
  );

  Widget _content(BuildContext context) {
    if (_session != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Raze Check'),
          actions: [TextButton(onPressed: _lock, child: const Text('Lock'))],
        ),
        body: widget.companies == null
            ? const Center(child: Text('Profile unlocked'))
            : CompanyWorkspace(
                companies: widget.companies!,
                enrollment: widget.enrollment,
                capture: widget.capture,
                attendanceMessages: widget.attendanceMessages,
                messages: widget.messages,
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
      appBar: AppBar(title: const Text('Raze Check')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/raze_check_logo_master.png',
                    width: 144,
                    height: 144,
                    semanticLabel: 'Raze Check mascot',
                  ),
                  const SizedBox(height: 24),
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
                          FilledButton(
                            onPressed: () => setState(() {
                              _setup = true;
                            }),
                            child: const Text('Create local profile'),
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
