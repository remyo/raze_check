import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'backup_screen.dart' show archiveError;
import '../guides/recovery_guide_bindings.dart';
import '../guides/guide_models.dart';
import '../guides/guide_target.dart';

final class RecoveryFiles {
  const RecoveryFiles({
    required this.pickBytes,
    required this.pickArchive,
    required this.releaseArchive,
    required this.share,
  });
  final Future<Uint8List?> Function(TransferGuard) pickBytes;
  final Future<String?> Function(TransferGuard) pickArchive;
  final Future<void> Function(String) releaseArchive;
  final Future<ShareOutcome> Function(Uint8List, String, TransferGuard) share;
}

abstract class RecoveryState<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  IdentityService get identity;
  SessionHandle get session;
  bool busy = false, hidden = false;
  BuildContext? guideSource;
  String? get recoveryVariant => null;
  Object get recoverySceneIdentity => (session, recoveryVariant, hidden);
  bool get guideOwner => false;
  bool get guideCanExport => false;
  Future<void> validateGuide() async {
    if (!mounted || hidden) throw const CheckException(CheckError.locked);
    identity.requireActor(session);
  }

  GuideAudience get recoveryAudience => recoveryGuideAudience(
    restrictedOperator:
        identity.requireActor(session).restrictedCompanyId != null,
    owner: guideOwner,
    canExportStaffRecovery: guideCanExport,
    recoveryVariant: recoveryVariant ?? '',
  );
  Timer? _expiry;
  String? error, message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleExpiry();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    var protected = state != AppLifecycleState.resumed;
    if (!protected) {
      try {
        identity.requireActor(session);
      } on CheckException {
        protected = true;
      }
    }
    setState(() => hidden = protected);
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    try {
      identity.requireActor(session);
      final service = identity;
      final remaining = service is ActivityIdentityService
          ? (service as ActivityIdentityService).remainingIdleTime(session)
          : const Duration(minutes: 5);
      _expiry = Timer(remaining, () {
        if (!mounted) return;
        try {
          identity.requireActor(session);
          _scheduleExpiry();
        } on CheckException {
          setState(() => hidden = true);
        }
      });
    } on CheckException {
      hidden = true;
    }
  }

  Future<void> guard() async {
    if (!mounted || hidden || ModalRoute.of(context)?.isCurrent == false) {
      throw const CheckException(CheckError.locked);
    }
    identity.requireActor(session);
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await guard();
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = archiveError(e);
          if (e is CheckException && e.code == CheckError.locked) hidden = true;
        });
      }
    } finally {
      if (mounted) {
        _scheduleExpiry();
        setState(() => busy = false);
      }
    }
  }

  Future<R> nativeTransfer<R>(Future<R> Function() action) =>
      withRecoveryGuidePaused(guideSource ?? context, action, guard);

  Future<void> send(RecoveryFiles files, Uint8List bytes, String name) async {
    await guard();
    final outcome = await nativeTransfer(() => files.share(bytes, name, guard));
    if (mounted) {
      setState(
        () => message = switch (outcome) {
          ShareOutcome.opened =>
            'Share sheet opened. Confirm delivery on the receiving device.',
          ShareOutcome.dismissed =>
            'Share dismissed. Your saved request or offer can be sent again.',
          _ => 'Sharing unavailable. Keep this screen and retry.',
        },
      );
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    bool enabled = true,
  }) => TextField(
    controller: controller,
    enabled: enabled && !busy,
    obscureText: secret,
    decoration: InputDecoration(labelText: label),
  );
  Widget button(
    String label,
    Future<void> Function() action, {
    bool enabled = true,
    String? guideTarget,
  }) => GuideTarget(
    id:
        guideTarget ??
        switch (label) {
          'Recover staff identity on this device' ||
          'Read company invitation' ||
          'Read target replacement request' => 'new-device-path',
          'Create fresh replacement request' ||
          'Prepare fresh owner installation' ||
          'Prepare company recovery with current identity' =>
            'new-device-identity',
          'Share replacement request' ||
          'Share target request with source device' ||
          'Freeze source and prepare handover' ||
          'Read staff replacement request' => 'new-device-request',
          'Apply received-record archive' ||
          'Inspect company recovery or handover archive' ||
          'Share exact handover archive' ||
          'Export selected staff recovery archive' => 'new-device-archive',
          'Receive replacement grant' ||
          'Receive target acknowledgment' ||
          'Authorize replacement' => 'new-device-activate',
          'Verify and activate handover' =>
            recoveryVariant == 'owner-target' ? 'new-device-activate' : label,
          'Recover when source device is lost' =>
            recoveryVariant == 'owner-recovery' ? 'new-device-activate' : label,
          'Share activation acknowledgment' => 'new-device-acknowledgment',
          'Share signed handover offer' => 'new-device-offer',
          _ => label,
        },
    child: FilledButton(
      onPressed: busy || !enabled ? null : () => run(action),
      child: Text(label),
    ),
  );
  Widget frame(String title, List<Widget> children) {
    Widget page = Builder(
      builder: (source) {
        guideSource = source;
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (recoveryVariant != null) const RecoveryGuideSettings(),
            ],
          ),
          body: hidden
              ? const Center(child: Text('Protected recovery view'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (busy) const LinearProgressIndicator(),
                      if (error != null)
                        Text(error!, key: const Key('recovery-error')),
                      if (message != null) Text(message!),
                      if (recoveryVariant != null)
                        const RecoveryGuideInvitation(guideId: 'new-device'),
                      ...children,
                    ],
                  ),
                ),
        );
      },
    );
    if (recoveryVariant != null) {
      GuideAudience audience;
      try {
        audience = recoveryAudience;
      } catch (_) {
        audience = GuideAudience(variants: const {});
      }
      page = RecoveryGuideScene(
        identity: recoverySceneIdentity,
        audience: audience,
        validate: validateGuide,
        guideId: 'new-device',
        child: page,
      );
    }
    return page;
  }

  void confirmedPassphrase(TextEditingController a, TextEditingController b) {
    if (a.text.runes.length < 12 || a.text != b.text) {
      throw const CheckException(CheckError.wrongSecret);
    }
  }
}
