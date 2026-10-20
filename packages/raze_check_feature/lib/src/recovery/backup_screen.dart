import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'restore_review_screen.dart';
import '../guides/recovery_guide_bindings.dart';
import '../guides/guide_target.dart';

String archiveError(Object error) => error is CheckException
    ? switch (error.code) {
        CheckError.incompatibleCompanyName =>
          'The company name exceeds 120 characters. The owner must use More → Correct company name before issuing a replacement grant.',
        CheckError.invalidSignature => 'Wrong passphrase or damaged backup',
        CheckError.limitExceeded =>
          'Backup exceeds the supported limit: 64 MiB encrypted and expanded, 8 MiB per attachment, 10,000 files. Previous backups and source data are unchanged.',
        CheckError.locked => 'Unlock your profile and try again.',
        CheckError.unauthorized =>
          'Company recovery backups require the owner. Personal backups contain only your linked data.',
        CheckError.duplicateConflict =>
          'Conflicting local history prevents this restore. Existing data is unchanged.',
        CheckError.recoveryRequired =>
          'Required recovery information is missing or requires activation.',
        CheckError.incompleteArchive =>
          'Backup files, hashes, or recovery information are incomplete.',
        CheckError.unsupportedVersion =>
          'This backup format or key derivation setting is unsupported.',
        _ =>
          'Could not complete the backup operation. Your source and previous backup are retained.',
      }
    : error is TransferException
    ? error.message
    : 'Could not complete the backup operation. Retry when storage is available.';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.identity,
    required this.session,
    required this.backups,
    required this.restores,
    required this.pickArchive,
    required this.releaseArchive,
    required this.shareArchive,
    this.companies,
  });
  final IdentityService identity;
  final SessionHandle session;
  final BackupService backups;
  final RestoreService restores;
  final CompanyService? companies;
  final Future<String?> Function(TransferGuard) pickArchive;
  final Future<void> Function(String) releaseArchive;
  final Future<ShareOutcome> Function(Uint8List, TransferGuard) shareArchive;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen>
    with WidgetsBindingObserver {
  final _pass = TextEditingController(), _confirm = TextEditingController();
  final _scopes = <String, ExportScope>{};
  String? _selected, _error, _message;
  ArchiveDescriptor? _last;
  bool _busy = false, _hidden = false;
  BuildContext? _guideSource;
  Membership? _guideMember;
  int _selectionGeneration = 0;
  Future<void> _validateGuide() async {
    final selection = _selected, member = _guideMember;
    void check() {
      if (!mounted ||
          _hidden ||
          selection != _selected ||
          !identical(member, _guideMember)) {
        throw StateError('Expired backup scope');
      }
      if (widget.identity.requireActor(widget.session).restrictedCompanyId !=
          null) {
        throw const CheckException(CheckError.unauthorized);
      }
    }

    check();
    final scope = _scopes[selection];
    if (scope is CompanyScope) {
      final current = await widget.companies?.membership(
        widget.session,
        scope.companyId,
      );
      check();
      if (current?.owner != true ||
          current?.active != true ||
          !sameRecoveryMembership(member, current)) {
        throw const CheckException(CheckError.unauthorized);
      }
    }
  }

  Future<void> _select(String? value) async {
    final generation = ++_selectionGeneration;
    setState(() {
      _selected = value;
      _guideMember = null;
      _error = null;
    });
    final scope = _scopes[value];
    try {
      if (scope is CompanyScope) {
        final member = await widget.companies?.membership(
          widget.session,
          scope.companyId,
        );
        if (mounted &&
            generation == _selectionGeneration &&
            _selected == value) {
          setState(() => _guideMember = member);
        }
      }
    } catch (error) {
      if (mounted && generation == _selectionGeneration && _selected == value) {
        setState(() => _error = archiveError(error));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final actor = widget.identity.requireActor(widget.session);
      _scopes['My personal records'] = PersonalScope(actor.personId);
      final companies = widget.companies;
      if (companies != null) {
        for (final company in await companies.listCompanies(widget.session)) {
          if ((await companies.membership(widget.session, company.id))?.owner ==
              true) {
            _scopes['Company: ${company.name} (${company.id})'] = CompanyScope(
              company.id,
            );
          }
        }
      }
      _selected = _scopes.keys.first;
      _last = await widget.backups.last(widget.session);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = archiveError(e));
    }
  }

  Future<void> _guard() async {
    widget.identity.requireActor(widget.session);
    if (!mounted || _hidden || ModalRoute.of(context)?.isCurrent != true) {
      throw const TransferException(
        'Return to the original backup screen to continue.',
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await _guard();
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = archiveError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
    if (_pass.text.runes.length < 12 || _pass.text != _confirm.text) {
      setState(
        () => _error = 'Use at least 12 characters and matching passphrases.',
      );
      return;
    }
    final scope = _scopes[_selected];
    if (scope == null) return;
    final result = await widget.backups.create(
      widget.session,
      scope,
      _pass.text,
    );
    await _guard();
    setState(() => _last = result);
    _pass.clear();
    _confirm.clear();
  });
  Future<void> _inspect() => _run(() async {
    final path = await withRecoveryGuidePaused(
      _guideSource ?? context,
      () => widget.pickArchive(_guard),
      _guard,
    );
    if (path == null) return;
    RestorePreview? preview;
    try {
      await _guard();
      preview = await widget.restores.inspect(widget.session, path, _pass.text);
      await _guard();
    } catch (_) {
      if (preview != null) await widget.restores.discard(preview);
      rethrow;
    } finally {
      await widget.releaseArchive(path);
      _pass.clear();
      _confirm.clear();
    }
    if (!mounted) return;
    final selected = preview;
    try {
      await openRecoveryPage(
        _guideSource ?? context,
        RestoreReviewScreen(
          identity: widget.identity,
          session: widget.session,
          service: widget.restores,
          preview: selected,
        ),
        'restore-review',
      );
    } finally {
      await widget.restores.discard(selected);
    }
  });
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _hidden = state != AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool restricted = true;
    try {
      restricted =
          widget.identity.requireActor(widget.session).restrictedCompanyId !=
          null;
    } catch (_) {}
    return RecoveryGuideScene(
      identity: (
        widget.session,
        _selected,
        _guideMember,
        _last,
        _hidden,
        restricted,
      ),
      audience: recoveryGuideAudience(
        restrictedOperator: restricted,
        owner:
            _scopes[_selected] is CompanyScope &&
            _guideMember?.owner == true &&
            _guideMember?.active == true,
        canExportStaffRecovery: false,
        recoveryVariant: '',
      ),
      validate: _validateGuide,
      guideId: 'backup',
      child: Builder(
        builder: (source) {
          _guideSource = source;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Backup and restore'),
              actions: const [RecoveryGuideSettings()],
            ),
            body: _hidden
                ? const Center(child: Text('Protected backup view'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const RecoveryGuideInvitation(guideId: 'backup'),
                        const Text(
                          'Encrypted backups preserve records and verification history. Restored profiles and companies require separate activation. Local device keys and operator sign-in credentials require fresh setup.',
                        ),
                        if (_scopes.isNotEmpty)
                          GuideTarget(
                            id: 'backup-scope',
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selected,
                              items: [
                                for (final label in _scopes.keys)
                                  DropdownMenuItem(
                                    value: label,
                                    child: Text(
                                      label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: _busy ? null : _select,
                            ),
                          ),
                        GuideTarget(
                          id: 'backup-passphrase',
                          child: TextField(
                            key: const Key('archive-passphrase'),
                            controller: _pass,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Backup passphrase (12+ characters)',
                            ),
                          ),
                        ),
                        TextField(
                          key: const Key('archive-confirm'),
                          controller: _confirm,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Confirm passphrase for a new backup',
                          ),
                        ),
                        const Text(
                          'Keep this passphrase separately. It is not saved with the backup.',
                        ),
                        GuideTarget(
                          id: 'backup-create',
                          child: FilledButton(
                            onPressed: _busy ? null : _create,
                            child: const Text('Create encrypted backup'),
                          ),
                        ),
                        GuideTarget(
                          id: 'backup-restore',
                          child: OutlinedButton(
                            onPressed: _busy ? null : _inspect,
                            child: const Text('Choose backup to inspect'),
                          ),
                        ),
                        if (_busy) const LinearProgressIndicator(),
                        if (_error != null)
                          Text(_error!, key: const Key('archive-error')),
                        if (_message != null) Text(_message!),
                        if (_last case final last?) ...[
                          Text(
                            'Created in this app: ${DateTime.fromMillisecondsSinceEpoch(last.createdUtcMs).toLocal()}',
                          ),
                          Text(widget.backups.storageDescription),
                          const Text(
                            'An internal backup will not survive uninstall. Save a copy outside this app.',
                          ),
                          Text(
                            last.externalCopyConfirmed
                                ? 'External saved copy confirmed by you.'
                                : 'No external saved copy has been confirmed.',
                          ),
                          GuideTarget(
                            id: 'backup-external',
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                      final bytes = await widget.backups
                                          .shareBytes(
                                            widget.session,
                                            last.artifactId,
                                          );
                                      final result =
                                          await withRecoveryGuidePaused(
                                            _guideSource ?? context,
                                            () => widget.shareArchive(
                                              bytes,
                                              _guard,
                                            ),
                                            _guard,
                                          );
                                      await _guard();
                                      setState(
                                        () => _message =
                                            result == ShareOutcome.opened
                                            ? 'Share sheet opened. Verify your saved file before confirming an external copy.'
                                            : 'No external save confirmed.',
                                      );
                                    }),
                              child: const Text(
                                'Save or share encrypted backup',
                              ),
                            ),
                          ),
                          GuideTarget(
                            id: 'backup-verify',
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                      await widget.backups.confirmExternalCopy(
                                        widget.session,
                                        last.artifactId,
                                      );
                                      await _load();
                                    }),
                              child: const Text(
                                'I verified a saved copy outside this app',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}
