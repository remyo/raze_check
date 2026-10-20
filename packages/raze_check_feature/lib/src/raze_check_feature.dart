import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'host/check_services.dart';
import 'host/check_feature_host.dart';
import 'profile/profile_gate.dart';
import 'attendance/message_import_sheet.dart';
import 'recovery/backup_screen.dart';
import 'recovery/recovery_workspace.dart';
import 'theme/check_theme.dart';

/// Mount beneath any MaterialApp. Owns only feature navigation and session UI.
class RazeCheckFeature extends StatefulWidget {
  const RazeCheckFeature({
    super.key,
    required this.services,
    required this.host,
    this.initialCompanyId,
  });
  final CheckServices services;
  final CheckFeatureHost host;
  final String? initialCompanyId;
  @override
  State<RazeCheckFeature> createState() => _RazeCheckFeatureState();
}

class _RazeCheckFeatureState extends State<RazeCheckFeature>
    with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  bool hidden = false;
  late final messages = FeatureMessagePort(
    context: () => navigator.currentContext!,
    create: widget.services.transfer,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => hidden = state != AppLifecycleState.resumed);
  }

  Future<void> recovery(SessionHandle session) async {
    final s = widget.services;
    s.identity.requireActor(session);
    final context = navigator.currentContext!;
    Future<void> backup() => widget.host.open(
      context,
      BackupScreen(
        identity: s.identity,
        session: session,
        backups: s.backups,
        restores: s.restores,
        companies: s.companies,
        pickArchive: s.files.pickArchive,
        releaseArchive: s.files.releaseArchive,
        shareArchive: (bytes, guard) =>
            s.files.share(bytes, 'backup.razecheck-backup', guard),
      ),
      'backup',
    );
    await widget.host.open(
      context,
      RecoveryWorkspace(
        identity: s.identity,
        recoveryIdentity: s.recoveryIdentity,
        session: session,
        companies: s.companies,
        enrollment: s.enrollment,
        replacement: s.replacement,
        handover: s.handover,
        history: s.history,
        backups: s.backups,
        staffBackups: s.staffBackups,
        restores: s.restores,
        files: s.files,
        openBackup: backup,
      ),
      'recovery',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final brightness = Theme.of(context).brightness;
    final theme =
        widget.host.themeBuilder?.call(context, brightness) ??
        (brightness == Brightness.dark
            ? CheckTheme.dark()
            : CheckTheme.light());
    return Theme(
      data: theme,
      child: Visibility(
        visible: !hidden,
        maintainState: true,
        replacement: const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              'Protected Raze Check view',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        child: Navigator(
          key: navigator,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => CheckProfileGate(
              identity: s.identity,
              companies: s.companies,
              enrollment: s.enrollment,
              capture: s.capture,
              attendance: s.attendance,
              messages: messages,
              attendanceMessages: messages,
              pickHistory: s.files.pickBytes,
              onRecovery: recovery,
              services: s,
              host: widget.host,
              initialCompanyId: widget.initialCompanyId,
            ),
          ),
        ),
      ),
    );
  }
}
