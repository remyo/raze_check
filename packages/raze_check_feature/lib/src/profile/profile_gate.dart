import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../../raze_check_feature.dart';

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
  final _workspace = GlobalKey<CompanyWorkspaceState>();
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
          title: const Text('Raze Check'),
          leading: widget.host == null
              ? null
              : IconButton(
                  tooltip: 'Exit Raze Check',
                  onPressed: widget.host!.onExit,
                  icon: const Icon(Icons.close),
                ),
          actions: [
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
                  widget.host?.iconBuilder?.call(context) ??
                      Image.asset(
                        'packages/raze_check_feature/assets/branding/raze_check_logo_master.png',
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
