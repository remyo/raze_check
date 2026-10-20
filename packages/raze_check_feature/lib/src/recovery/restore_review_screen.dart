import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'backup_screen.dart' show archiveError;
import '../guides/recovery_guide_bindings.dart';
import '../guides/guide_scene.dart';
import '../guides/guide_models.dart';
import '../guides/guide_target.dart';

class RestoreReviewScreen extends StatefulWidget {
  const RestoreReviewScreen({
    super.key,
    required this.identity,
    required this.session,
    required this.service,
    required this.preview,
  });
  final IdentityService identity;
  final SessionHandle session;
  final RestoreService service;
  final RestorePreview preview;
  @override
  State<RestoreReviewScreen> createState() => _RestoreReviewScreenState();
}

class _RestoreReviewScreenState extends State<RestoreReviewScreen>
    with WidgetsBindingObserver {
  bool _busy = false, _hidden = false;
  String? _message;
  RestoreChoice _choice = RestoreChoice.newInstallation;
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
    if (mounted) setState(() => _hidden = state != AppLifecycleState.resumed);
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      widget.identity.requireActor(widget.session);
      if (_hidden) throw const CheckException(CheckError.locked);
      final result = await widget.service.apply(widget.preview, _choice);
      if (mounted) {
        setState(
          () => _message = result.duplicate
              ? 'This backup was already restored. Activation is still required.'
              : 'Records restored passively. Management and new punches remain locked until authorized activation.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = archiveError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = GuideScene.maybeContextOf(context);
    bool restricted = true;
    try {
      restricted =
          widget.identity.requireActor(widget.session).restrictedCompanyId !=
          null;
    } catch (_) {}
    return RecoveryGuideScene(
      identity: (widget.session, widget.preview, _hidden),
      audience: GuideAudience(
        variants: {
          if (!restricted)
            'backup': parent?.audience.variants['backup'] ?? 'personal',
        },
      ),
      validate: () async {
        if (!mounted || _hidden) throw const CheckException(CheckError.locked);
        if (widget.identity.requireActor(widget.session).restrictedCompanyId !=
            null) {
          throw const CheckException(CheckError.unauthorized);
        }
      },
      guideId: 'backup',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review restore'),
          actions: const [RecoveryGuideSettings()],
        ),
        body: _hidden
            ? const Center(child: Text('Protected restore view'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RecoveryGuideInvitation(guideId: 'backup'),
                    Text('Archive: ${widget.preview.manifestId}'),
                    Text('Person: ${widget.preview.personId}'),
                    Text('Companies: ${widget.preview.companyIds.join(', ')}'),
                    Text('Verified files: ${widget.preview.hashes.length}'),
                    for (final e in widget.preview.counts.entries)
                      Text('${e.key}: ${e.value}'),
                    const Text(
                      'Existing identities and history will not be replaced. Old signing keys and local operator credentials are not activated. Keep your source backup until recovery is complete.',
                    ),
                    for (final conflict in widget.preview.conflicts)
                      Text(conflict),
                    DropdownButton<RestoreChoice>(
                      value: _choice,
                      items: const [
                        DropdownMenuItem(
                          value: RestoreChoice.newInstallation,
                          child: Text('New installation'),
                        ),
                        DropdownMenuItem(
                          value: RestoreChoice.mergeNonConflicting,
                          child: Text('Merge nonconflicting records'),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _choice = v!),
                    ),
                    GuideTarget(
                      id: 'backup-restore',
                      child: FilledButton(
                        onPressed:
                            _busy ||
                                widget.preview.conflicts.isNotEmpty ||
                                _message != null
                            ? null
                            : _apply,
                        child: const Text('Restore verified records'),
                      ),
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_message != null) Text(_message!),
                  ],
                ),
              ),
      ),
    );
  }
}
