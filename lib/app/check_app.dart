import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'local_composition.dart';
import 'native_transfer.dart';
import 'package:raze_check_local/raze_check_local.dart';

/// Standalone composition entry; reusable features live in their own package.
class CheckApp extends StatefulWidget {
  const CheckApp({
    super.key,
    this.identity,
    this.composition,
    this.companies,
    this.enrollment,
    this.messages,
    this.capture,
    this.attendance,
    this.attendanceMessages,
  });
  final Future<LocalComposition>? composition;
  final Future<IdentityService>? identity;
  final Future<CompanyService>? companies;
  final Future<EnrollmentService>? enrollment;
  final EnrollmentMessagePort? messages;
  final Future<CaptureService>? capture;
  final Future<AttendanceService>? attendance;
  final AttendanceMessagePort? attendanceMessages;
  @override
  State<CheckApp> createState() => _CheckAppState();
}

class _CheckAppState extends State<CheckApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _documents = DocumentPort();
  final _sharing = SharePort();
  late final _messages = FeatureMessagePort(
    context: () => _navigator.currentContext!,
    create: (guard) => NativeTransfer(
      context: () => _navigator.currentContext!,
      guard: guard,
      documents: _documents,
      qr: MobileQrPort(_documents),
      sharing: _sharing,
    ),
  );
  late final Future<LocalComposition>? _composition =
      widget.composition ??
      (widget.identity == null ? LocalComposition.open() : null);
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

  late final Future<AttendanceService?> _attendance =
      widget.attendance ??
      (_composition?.then((s) => s.attendance) ?? Future.value(null));

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
    navigatorKey: _navigator,
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
                    return FutureBuilder<AttendanceService?>(
                      future: _attendance,
                      builder: (context, attendance) {
                        if (attendance.hasError) {
                          return const Scaffold(
                            body: Center(
                              child: Text('Could not open review storage.'),
                            ),
                          );
                        }
                        if (attendance.connectionState !=
                            ConnectionState.done) {
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _ProfileGate(
                          onRecovery: _composition == null
                              ? null
                              : (session) async {
                                  final services = await _composition;
                                  if (!context.mounted) {
                                    return;
                                  }
                                  services.identity.requireActor(session);
                                  Future<void> openBackup() async {
                                    await Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (routeContext) => BackupScreen(
                                          identity: services.identity,
                                          session: session,
                                          backups: services.archives,
                                          restores: services.archives,
                                          companies: services.companies,
                                          pickArchive: (guard) async {
                                            await guard();
                                            final file = await _documents.pick(
                                              DocumentPurpose.archive,
                                            );
                                            if (file == null) return null;
                                            try {
                                              await guard();
                                              return file.path;
                                            } catch (_) {
                                              await file.delete();
                                              rethrow;
                                            }
                                          },
                                          releaseArchive: (path) async {
                                            await File(path).delete();
                                          },
                                          shareArchive: (bytes, guard) =>
                                              _sharing.share(
                                                bytes,
                                                'backup.razecheck-backup',
                                                'application/octet-stream',
                                                guard: guard,
                                                anchor: () {
                                                  final box = routeContext
                                                      .findRenderObject();
                                                  if (box is! RenderBox ||
                                                      !box.hasSize) {
                                                    throw const TransferException(
                                                      'Share position unavailable.',
                                                    );
                                                  }
                                                  return box.localToGlobal(
                                                        Offset.zero,
                                                      ) &
                                                      box.size;
                                                },
                                              ),
                                        ),
                                      ),
                                    );
                                  }

                                  final files = RecoveryFiles(
                                    pickBytes: (guard) async {
                                      await guard();
                                      final b = await _documents.pickMessage();
                                      await guard();
                                      return b;
                                    },
                                    pickArchive: (guard) async {
                                      await guard();
                                      final f = await _documents.pick(
                                        DocumentPurpose.archive,
                                      );
                                      if (f == null) return null;
                                      try {
                                        await guard();
                                        return f.path;
                                      } catch (_) {
                                        await f.delete();
                                        rethrow;
                                      }
                                    },
                                    releaseArchive: (path) async =>
                                        File(path).delete(),
                                    share: (bytes, name, guard) =>
                                        _sharing.share(
                                          bytes,
                                          name,
                                          'application/octet-stream',
                                          guard: guard,
                                          anchor: () {
                                            final box = _navigator
                                                .currentContext!
                                                .findRenderObject();
                                            if (box is! RenderBox ||
                                                !box.hasSize) {
                                              throw const TransferException(
                                                'Share position unavailable.',
                                              );
                                            }
                                            return box.localToGlobal(
                                                  Offset.zero,
                                                ) &
                                                box.size;
                                          },
                                        ),
                                  );
                                  if (!context.mounted) return;
                                  await Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => RecoveryWorkspace(
                                        identity: services.identity,
                                        recoveryIdentity: services.identity,
                                        session: session,
                                        companies: services.companies,
                                        enrollment: services.enrollment,
                                        replacement: services.replacement,
                                        handover: services.handover,
                                        history: services.history,
                                        backups: services.archives,
                                        staffBackups: services.archives,
                                        restores: services.archives,
                                        files: files,
                                        openBackup: openBackup,
                                      ),
                                    ),
                                  );
                                },
                          pickHistory: _composition == null
                              ? null
                              : (guard) async {
                                  await guard();
                                  final bytes = await _documents.pickMessage();
                                  await guard();
                                  return bytes;
                                },
                          attendance: attendance.data,
                          capture: capture.data,
                          attendanceMessages:
                              widget.attendanceMessages ??
                              (_composition == null ? null : _messages),
                          identity: snapshot.data!,
                          companies: companies.data,
                          enrollment: enrollment.data,
                          messages:
                              widget.messages ??
                              (_composition == null ? null : _messages),
                        );
                      },
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
    this.onRecovery,
    this.pickHistory,
    this.enrollment,
    this.messages,
    this.capture,
    this.attendance,
    this.attendanceMessages,
  });
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
          actions: [
            if (widget.onRecovery != null)
              TextButton(
                onPressed: () async {
                  await widget.onRecovery!(_session!);
                  _checkSession();
                },
                child: const Text('Backup / recovery'),
              ),
            TextButton(onPressed: _lock, child: const Text('Lock')),
          ],
        ),
        body: widget.companies == null
            ? const Center(child: Text('Profile unlocked'))
            : CompanyWorkspace(
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
