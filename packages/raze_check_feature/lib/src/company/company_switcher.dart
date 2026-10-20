import 'package:flutter/material.dart';
import '../guides/company_guide_bindings.dart';
import '../guides/guide_models.dart';
import '../guides/guide_scene.dart';
import '../guides/guide_scope.dart';
import '../guides/guide_controller.dart';
import '../guides/guide_target.dart';
import '../guides/guide_invitation.dart';
import 'dart:typed_data';
import 'package:raze_check_core/raze_check_core.dart';
import '../profile/profile_commands.dart';
import '../enrollment/membership_status_screen.dart';
import '../team/operator_access_screen.dart';
import '../team/staff_detail_screen.dart';
import '../team/staff_list_screen.dart';
import 'company_setup_screen.dart';
import '../attendance/capture_screen.dart';
import '../attendance/review_queue_screen.dart';
import '../host/check_services.dart';
import '../host/check_feature_host.dart';
import '../dashboard/staff_home_screen.dart';
import '../dashboard/manager_home_screen.dart';
import '../reports/attendance_report_screen.dart';

class CompanySwitcher extends StatelessWidget {
  const CompanySwitcher({
    super.key,
    required this.companies,
    required this.selected,
    required this.onSelected,
    this.subtitle,
  });
  final List<Company> companies;
  final Company? selected;
  final ValueChanged<Company> onSelected;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => GuideTarget(
    id: 'companies-switch',
    child: PopupMenuButton<Company>(
      key: const Key('company-switcher'),
      tooltip: 'Switch company',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final company in companies)
          PopupMenuItem(value: company, child: Text(company.name)),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected?.name ?? 'Select company',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Owns the selected company and captures the original context for every draft.
class CompanyWorkspace extends StatefulWidget {
  const CompanyWorkspace({
    super.key,
    required this.companies,
    required this.session,
    required this.ids,
    required this.onAuthorizedActivity,
    required this.onSessionChanged,
    required this.onLocked,
    this.canCreateCompany = true,
    this.services,
    this.host,
    this.initialCompanyId,
    this.onRecovery,
    this.onSettings,
    this.enrollment,
    this.messages,
    this.pickHistory,
    this.capture,
    this.attendance,
    this.attendanceMessages,
  });
  final CheckServices? services;
  final CheckFeatureHost? host;
  final String? initialCompanyId;
  final Future<void> Function()? onRecovery;
  final VoidCallback? onSettings;
  final CompanyService companies;
  final EnrollmentService? enrollment;
  final EnrollmentMessagePort? messages;
  final Future<Uint8List?> Function(TransferGuard)? pickHistory;
  final CaptureService? capture;
  final AttendanceService? attendance;
  final AttendanceMessagePort? attendanceMessages;
  final bool canCreateCompany;
  final SessionHandle session;
  final IdGenerator ids;
  final VoidCallback onAuthorizedActivity, onLocked;
  final ValueChanged<SessionHandle> onSessionChanged;
  @override
  CompanyWorkspaceState createState() => CompanyWorkspaceState();
}

class CompanyWorkspaceState extends State<CompanyWorkspace> {
  GuideController? _guides;
  GuideContext? _gateGuide, _companyGuide;
  Object _guideAuthority = Object();
  Object? _guideIdentity;
  BuildContext? _sceneContext;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _guides = GuideScope.maybeOf(context);
    final gate = GuideScene.maybeContextOf(context);
    if (!identical(gate, _gateGuide)) {
      _gateGuide = gate;
      _invalidateGuideAuthority();
    }
  }

  void _invalidateGuideAuthority() {
    _guides?.invalidateAuthority(_guideAuthority);
    _guideAuthority = Object();
    _companyGuide = null;
  }

  @override
  void dispose() {
    _guides?.invalidateAuthority(_guideAuthority);
    super.dispose();
  }

  Object get _panelIdentity => (
    _loading,
    _tab,
    _setup,
    _draft,
    _operator,
    _editing?.employeeId,
    _enrolling,
    _capturing,
    _reviewing,
    _manualEntry,
    (_setup || _draft || _operator) ? _operation : null,
  );

  GuideDestination? get _guideDestination => _setup
      ? GuideDestination.createCompany
      : _enrolling
      ? GuideDestination.joinCompany
      : _capturing
      ? GuideDestination.capture
      : _reviewing
      ? GuideDestination.attendance
      : (_tab == 2 && _managerMode) || (_draft || _operator)
      ? GuideDestination.team
      : null;

  bool get _hasGuideDraft =>
      _setup || _draft || _operator || _enrolling || _capturing || _reviewing;

  GuideContext _makeCompanyGuide() {
    final authority = _guideAuthority,
        session = widget.session,
        company = _selected,
        member = _membership,
        gate = _gateGuide,
        identity = _panelIdentity,
        token = Object();
    void check() {
      if (!mounted ||
          !identical(authority, _guideAuthority) ||
          !identical(session, widget.session) ||
          company?.id != _selected?.id ||
          identity != _panelIdentity ||
          !identical(_companyGuide?.token, token)) {
        throw StateError('Expired company guide context');
      }
    }

    Future<void> validate() async {
      check();
      await gate?.validateCurrent();
      check();
      if (company != null) {
        final current = await widget.companies.membership(session, company.id);
        check();
        if (current?.id != member?.id ||
            current?.revision != member?.revision ||
            current?.active != member?.active ||
            current?.owner != member?.owner ||
            current?.capabilities.length != member?.capabilities.length ||
            !(current?.capabilities.every(
                  (c) => member!.capabilities.contains(c),
                ) ??
                member == null)) {
          _invalidateGuideAuthority();
          throw StateError('Company guide permissions changed');
        }
      }
      await gate?.validateCurrent();
      check();
    }

    Future<void> navigate(
      GuideDestination destination,
      VoidCallback open,
    ) async {
      await validate();
      // Settings first restores this exact source. Existing live drafts remain
      // explanatory: guide navigation never chooses a discard decision.
      if (_hasGuideDraft || _loading || _busy) return;
      await _guides?.navigateToScene(open);
    }

    return GuideContext(
      token: token,
      authorityToken: authority,
      audience: companyGuideAudience(
        unlocked: true,
        canCreateCompany: widget.canCreateCompany,
        owner: _owner,
        operatorSession: !widget.canCreateCompany,
        activeMembership: _membership?.active == true,
        canInvite: _canInvite,
        canManageStaff: _canManage,
        canReview: _canReview,
        canExport: _canExport,
      ),
      destination: _guideDestination,
      validateCurrent: validate,
      navigation: !_loading && !_busy && !_hasGuideDraft
          ? {
              if (widget.canCreateCompany)
                GuideDestination.createCompany: () => navigate(
                  GuideDestination.createCompany,
                  () => _newDraft(setup: true),
                ),
              if (widget.enrollment != null &&
                  widget.messages != null &&
                  (_canInvite || widget.canCreateCompany))
                GuideDestination.joinCompany: () =>
                    navigate(GuideDestination.joinCompany, _openEnrollment),
              if (_membership?.active == true &&
                  (_owner || widget.canCreateCompany) &&
                  widget.capture != null &&
                  company != null)
                GuideDestination.capture: () =>
                    navigate(GuideDestination.capture, _capture),
              if ((_canReview || widget.canCreateCompany) &&
                  widget.attendance != null &&
                  company != null)
                GuideDestination.attendance: () =>
                    navigate(GuideDestination.attendance, _attendance),
              if (_canManage && _guideDestination != GuideDestination.team)
                GuideDestination.team: () => navigate(
                  GuideDestination.team,
                  () => setState(() => _tab = 2),
                ),
              if ((_canExport || widget.canCreateCompany) &&
                  company != null &&
                  widget.services != null &&
                  widget.host != null)
                GuideDestination.reports: () async {
                  await validate();
                  if (!_hasGuideDraft && !_busy) await _report();
                },
            }
          : const {},
    );
  }

  Widget _withCompanyGuide(Widget child) {
    final identity = _panelIdentity;
    if (_companyGuide == null || identity != _guideIdentity) {
      _guideIdentity = identity;
      _companyGuide = _makeCompanyGuide();
    }
    final body = Builder(
      builder: (context) {
        _sceneContext = context;
        return child;
      },
    );
    // Stateful workflow panels own their own changing selection scenes.
    return !_loading && (_capturing || _reviewing || _enrolling)
        ? GuideSceneBinding(
            guideContext: _companyGuide!,
            registry: GuideScope.registryOf(context),
            child: body,
          )
        : GuideScene(context: _companyGuide!, child: body);
  }

  List<Company> _companies = [];
  Company? _selected;
  Membership? _membership;
  List<StaffRecord> _staff = [];
  List<Membership> _members = [];
  bool _loading = true,
      _busy = false,
      _setup = false,
      _draft = false,
      _operator = false;
  StaffRecord? _editing;
  String? _error;
  bool _enrolling = false, _capturing = false, _reviewing = false;
  int _generation = 0;
  int _draftIdentity = 0;
  int _tab = 0;
  bool _manualEntry = false;
  bool get _canInvite =>
      _membership != null &&
      _managerMode &&
      AccessPolicy.eligible(_membership!, Capability.manageMemberships);
  bool _initialResolved = false, _initialRejected = false;
  Stream<StaffOverview>? _overview;
  Future<String>? _backup;
  bool get _managerMode => _owner || !widget.canCreateCompany;
  bool get _canReview =>
      _membership != null &&
      _managerMode &&
      AccessPolicy.eligible(_membership!, Capability.reviewAttendance);
  bool get _canExport =>
      _membership != null &&
      _managerMode &&
      AccessPolicy.eligible(_membership!, Capability.exportAttendance);
  late String _operation;
  @override
  void initState() {
    super.initState();
    _operation = widget.ids.next();
    _reload();
  }

  @override
  void didUpdateWidget(CompanyWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _generation++;
      _invalidateGuideAuthority();
      _enrolling = false;
      _capturing = false;
      _reviewing = false;
      _manualEntry = false;
      _tab = 0;
      _selected = null;
      _membership = null;
      _draft = false;
      _setup = false;
      _reload();
    }
  }

  /// Capture UI context before a host presents recovery. The returned callback
  /// ignores a later switch, replacement session, or disposed workspace.
  VoidCallback prepareRecoveryRefresh() {
    final generation = _generation,
        session = widget.session,
        company = _selected;
    return () {
      if (!mounted ||
          generation != _generation ||
          !identical(session, widget.session) ||
          company == null ||
          company.id != _selected?.id ||
          widget.services == null) {
        return;
      }
      setState(() {
        _backup = _backupText(widget.services!, company);
      });
    };
  }

  bool get _canManage =>
      _membership != null &&
      (_membership!.owner || !widget.canCreateCompany) &&
      AccessPolicy.eligible(_membership!, Capability.manageStaff);
  bool get _owner => _membership?.owner == true;
  void _failure(Object error) {
    if (!mounted) return;
    if (error is CheckException && error.code == CheckError.locked) {
      widget.onLocked();
      return;
    }
    setState(() {
      _loading = false;
      _busy = false;
      _error = profileError(
        error is CheckException ? error.code : CheckError.storageFailure,
      );
    });
  }

  Future<void> _reload() async {
    _invalidateGuideAuthority();
    if (mounted) setState(() => _loading = true);
    final generation = _generation;
    try {
      final companies = await widget.companies.listCompanies(widget.session);
      if (!mounted || generation != _generation) return;
      if (!_initialResolved && widget.initialCompanyId != null) {
        _initialResolved = true;
        final initial = companies
            .where((c) => c.id == widget.initialCompanyId)
            .firstOrNull;
        if (initial == null) {
          setState(() {
            _initialRejected = true;
            _loading = false;
            _selected = null;
            _companies = [];
          });
          return;
        }
        _selected = initial;
      }
      if (_initialRejected) return;
      setState(() {
        _companies = companies;
        _selected =
            companies.where((c) => c.id == _selected?.id).firstOrNull ??
            companies.firstOrNull;
      });
      if (_selected != null) {
        await _loadCompany(_selected!, generation);
      } else {
        setState(() {
          _loading = false;
          _membership = null;
        });
      }
      if (mounted && generation == _generation) widget.onAuthorizedActivity();
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> _loadCompany(Company company, int generation) async {
    try {
      final member = await widget.companies.membership(
        widget.session,
        company.id,
      );
      final canManage =
          member != null &&
          (member.owner || !widget.canCreateCompany) &&
          AccessPolicy.eligible(member, Capability.manageStaff);
      final staff = canManage
          ? await widget.companies.listStaff(widget.session, company.id)
          : <StaffRecord>[];
      final members = canManage
          ? await widget.companies.listMemberships(widget.session, company.id)
          : <Membership>[];
      if (!mounted || generation != _generation) return;
      setState(() {
        _invalidateGuideAuthority();
        _membership = member;
        final services = widget.services;
        if (services != null) {
          _overview = _canReview
              ? services.queries.forManager(_context())
              : widget.canCreateCompany
              ? services.queries.forStaff(widget.session, company.id)
              : null;
          _backup = _backupText(services, company);
        }
        _staff = staff;
        _members = members;
        _loading = false;
      });
      widget.onAuthorizedActivity();
    } catch (e) {
      if (generation == _generation) _failure(e);
    }
  }

  Future<void> _switch(Company company) async {
    if (company.id == _selected?.id) return;
    if (_draft || _setup || _operator) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this draft?'),
          content: const Text(
            'This draft belongs to the current company. Keep editing it or discard it before switching.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard draft'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _generation++;
      _invalidateGuideAuthority();
      _enrolling = false;
      _capturing = false;
      _reviewing = false;
      _manualEntry = false;
      _tab = 0;
      _selected = company;
      _draft = false;
      _setup = false;
      _operator = false;
      _editing = null;
      _error = null;
      _busy = false;
      _loading = true;
    });
    await _loadCompany(company, _generation);
  }

  void _newDraft({StaffRecord? staff, bool setup = false}) => setState(() {
    _operation = widget.ids.next();
    _capturing = false;
    _reviewing = false;
    _enrolling = false;
    _draftIdentity++;
    _busy = false;
    _setup = setup;
    _draft = !setup;
    _operator = false;
    _editing = staff;
    _error = null;
  });
  void _cancel() => setState(() {
    _draftIdentity++;
    _busy = false;
    _draft = false;
    _setup = false;
    _operator = false;
    _editing = null;
    _error = null;
  });
  CommandContext _context() => CommandContext(
    companyId: _selected!.id,
    session: widget.session,
    operationId: _operation,
    authorityGenerationId: _selected!.authorityGenerationId,
  );
  Future<void> _execute<T>(
    Future<CommandResult<T>> Function() action, {
    bool keepOperator = false,
  }) async {
    final generation = _generation;
    final draftIdentity = _draftIdentity;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      if (result is Rejected<T> && result.error == CheckError.locked) {
        widget.onLocked();
        return;
      }
      if (result is Committed<T>) widget.onAuthorizedActivity();
      if (generation != _generation || draftIdentity != _draftIdentity) return;
      switch (result) {
        case Committed<T>():
          setState(() {
            _busy = false;
            _operation = widget.ids.next();
            if (result.value is Company) _selected = result.value as Company;
            if (!keepOperator) {
              _draft = false;
              _setup = false;
              _operator = false;
              _editing = null;
            }
          });
          await _reload();
        case Rejected<T>():
          if (result.error == CheckError.locked) {
            widget.onLocked();
            return;
          }
          setState(() {
            _busy = false;
            _error = profileError(result.error);
          });
        case VersionConflict<T>():
          setState(() {
            _busy = false;
            _error = 'Records changed. Reopen the draft and try again.';
          });
      }
    } catch (e) {
      if (generation == _generation && draftIdentity == _draftIdentity) {
        _failure(e);
      }
    }
  }

  void _openEnrollment() => setState(() {
    _capturing = false;
    _reviewing = false;
    _enrolling = true;
  });
  @override
  Widget build(BuildContext context) => _withCompanyGuide(
    widget.services != null
        ? _feature(context)
        : Column(
            children: [
              if (widget.attendance != null && _selected != null)
                TextButton(
                  onPressed: () => setState(() {
                    _capturing = false;
                    _enrolling = false;
                    _reviewing = true;
                  }),
                  child: const Text('Review and attendance history'),
                ),
              if (widget.capture != null &&
                  _selected != null &&
                  widget.canCreateCompany)
                TextButton(
                  onPressed: () => setState(() {
                    _enrolling = false;
                    _capturing = true;
                    _reviewing = false;
                  }),
                  child: const Text('Attendance and receipts'),
                ),
              if (widget.enrollment != null && widget.messages != null)
                TextButton(
                  onPressed: _openEnrollment,
                  child: Text(
                    _canInvite
                        ? 'Invite or review join'
                        : 'Join or receive membership',
                  ),
                ),

              Row(
                children: [
                  Expanded(
                    child: CompanySwitcher(
                      companies: _companies,
                      selected: _selected,
                      onSelected: _switch,
                    ),
                  ),
                  if (widget.canCreateCompany)
                    GuideTarget(
                      id: 'companies-choose',
                      child: IconButton(
                        tooltip: 'Create company',
                        onPressed: () => _newDraft(setup: true),
                        icon: const Icon(Icons.add_business),
                      ),
                    ),
                ],
              ),
              if (_selected != null && !_setup)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '${_selected!.timeZoneId} · Root ${_selected!.rootFingerprint.substring(0, _selected!.rootFingerprint.length.clamp(0, 12))}',
                  ),
                ),
              Expanded(child: _body()),
            ],
          ),
  );
  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_reviewing && widget.attendance != null && _selected != null) {
      return Column(
        children: [
          TextButton(
            onPressed: () => setState(() {
              _reviewing = false;
              _manualEntry = false;
              _tab = 0;
            }),
            child: const Text('Back to company'),
          ),
          Expanded(
            child: ReviewWorkspace(
              key: ValueKey('review-${_selected!.id}'),
              service: widget.attendance!,
              initialManual: _manualEntry,
              queries: widget.services?.queries,
              session: widget.session,
              company: _selected!,
              ids: widget.ids,
              messages: widget.attendanceMessages,
              canManage:
                  _membership != null &&
                  (_owner || !widget.canCreateCompany) &&
                  AccessPolicy.eligible(
                    _membership!,
                    Capability.reviewAttendance,
                  ),
              staff: _staff,
              onChanged: widget.onAuthorizedActivity,
              onLocked: widget.onLocked,
            ),
          ),
        ],
      );
    }
    if (_capturing && widget.capture != null && _selected != null) {
      return Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _capturing = false),
            child: const Text('Back to company'),
          ),
          Expanded(
            child: CaptureWorkspace(
              key: ValueKey('capture-${_selected!.id}'),
              service: widget.capture!,
              session: widget.session,
              company: _selected!,
              ids: widget.ids,
              messages: widget.attendanceMessages,
              canCreateCode: _owner,
              onChanged: widget.onAuthorizedActivity,
              onLocked: widget.onLocked,
            ),
          ),
        ],
      );
    }
    if (_enrolling && widget.enrollment != null && widget.messages != null) {
      return Column(
        children: [
          TextButton(
            onPressed: () {
              setState(() => _enrolling = false);
              _reload();
            },
            child: const Text('Back to company'),
          ),
          Expanded(
            child: EnrollmentWorkspace(
              pickHistory: widget.pickHistory,
              key: ValueKey('enrollment-${_selected?.id}'),
              service: widget.enrollment!,
              companies: widget.companies,
              session: widget.session,
              ids: widget.ids,
              messages: widget.messages!,
              company: _selected,
              canManage: _canInvite,
              owner: _owner,
              manualStaff: _staff
                  .where(
                    (s) => _members.any(
                      (m) =>
                          m.id == s.membershipId &&
                          !m.owner &&
                          m.active &&
                          m.capabilities.isEmpty,
                    ),
                  )
                  .toList(),
              onChanged: widget.onAuthorizedActivity,
              onLocked: widget.onLocked,
            ),
          ),
        ],
      );
    }

    if (_setup) {
      return CompanySetupScreen(
        key: ValueKey('setup-$_operation'),
        busy: _busy,
        error: _error,
        onCancel: _cancel,
        onSave: (draft) {
          final operation = _operation;
          return _execute(
            () => widget.companies.createCompany(
              widget.session,
              draft,
              operation,
            ),
          );
        },
      );
    }
    if (_selected == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GuideInvitation(guideId: 'companies'),
            const Text(
              'Join your company with an invitation, or create a company to manage staff.',
            ),
            if (widget.enrollment != null && widget.messages != null)
              GuideTarget(
                id: 'membership-open',
                child: FilledButton(
                  onPressed: _openEnrollment,
                  child: const Text('Join company'),
                ),
              ),
            if (_error != null) Text(_error!),
            FilledButton(
              onPressed: () => _newDraft(setup: true),
              child: const Text('Create company'),
            ),
          ],
        ),
      );
    }
    final target = _editing == null
        ? null
        : _members.where((m) => m.id == _editing!.membershipId).firstOrNull;
    if (_operator && target != null) {
      return OperatorAccessScreen(
        key: ValueKey('operator-${target.id}'),
        membership: target,
        busy: _busy,
        error: _error,
        onCancel: () => setState(() => _operator = false),
        onGrant: (caps) {
          final original = _context();
          return _execute(
            () => widget.companies.grantCapabilities(original, target.id, caps),
            keepOperator: true,
          );
        },
        onActivate: (secret) {
          final original = _context();
          return _execute(
            () =>
                widget.companies.activateOperator(original, target.id, secret),
            keepOperator: true,
          );
        },
      );
    }
    if (_draft) {
      return StaffDetailScreen(
        key: ValueKey('staff-$_operation'),
        staff: _editing,
        busy: _busy,
        error: _error,
        onCancel: _cancel,
        onSave: (draft) {
          final original = _context();
          final staff = _editing;
          return _execute(
            () => staff == null
                ? widget.companies.createStaff(original, draft)
                : widget.companies.updateStaff(
                    original,
                    StaffUpdate(staff.employeeId, draft),
                  ),
          );
        },
        onOperatorAccess:
            _owner && target != null && !target.owner && target.active
            ? () => setState(() {
                _operator = true;
                _operation = widget.ids.next();
              })
            : null,
        onDeactivate: target != null && !target.owner && target.active
            ? (reason) {
                final original = _context();
                return _execute(
                  () => widget.companies.deactivateStaff(
                    original,
                    target.employeeId,
                    reason,
                  ),
                );
              }
            : null,
      );
    }
    if (!_canManage) {
      return const Center(
        child: Text('This membership has no staff management capability.'),
      );
    }
    return StaffListScreen(
      staff: _staff,
      memberships: _members,
      onSelect: (s) => _newDraft(staff: s),
      onAdd: () => _newDraft(),
    );
  }

  Future<String> _backupText(CheckServices services, Company company) async {
    try {
      final backup = await services.backups.last(widget.session);
      if (backup == null) return 'No backup recorded on this device.';
      final scope = backup.scope;
      if (scope is CompanyScope && scope.companyId != company.id) {
        return 'Latest backup is for another company. No backup age is available here.';
      }
      final days = DateTime.now()
          .toUtc()
          .difference(
            DateTime.fromMillisecondsSinceEpoch(
              backup.createdUtcMs,
              isUtc: true,
            ),
          )
          .inDays
          .clamp(0, 99999);
      return '${scope is PersonalScope ? "Personal" : "Company"} backup · $days day(s) old · created ${attendanceTime(backup.createdUtcMs, company.timeZoneId)}. ${backup.externalCopyConfirmed ? "External copy confirmed by you." : "Private copy only; external copy not confirmed."}';
    } on CheckException {
      return 'No accessible backup metadata for this session.';
    }
  }

  Future<void> _correctName() async {
    final company = _selected!, epoch = _generation, session = widget.session;
    final companies = widget.companies;
    final command = CommandContext(
      companyId: company.id,
      session: session,
      operationId: widget.ids.next(),
      authorityGenerationId: company.authorityGenerationId,
    );
    final corrected = await showDialog<Company>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CompanyNameRepairDialog(
        name: company.name,
        onSave: (name) => companies.correctName(command, name),
      ),
    );
    if (!mounted ||
        corrected == null ||
        _generation != epoch ||
        _selected?.id != company.id ||
        !identical(session, widget.session)) {
      return;
    }
    setState(() {
      _selected = corrected;
      _companies = [
        for (final c in _companies) c.id == company.id ? corrected : c,
      ];
    });
    widget.onAuthorizedActivity();
  }

  void _attendance() => setState(() {
    _tab = 1;
    _manualEntry = false;
    _capturing = false;
    _enrolling = false;
    _reviewing = true;
  });
  void _capture() => setState(() {
    _capturing = true;
    _reviewing = false;
    _enrolling = false;
  });
  Future<void> _report() async {
    final company = _selected!;
    await widget.host!.open(
      _sceneContext ?? context,
      GuideSceneBinding(
        guideContext: _companyGuide!,
        registry: GuideScope.registryOf(context),
        child: CompanyGuideScene(
          identity: Object(),
          destination: GuideDestination.reports,
          child: AttendanceReportScreen(
            services: widget.services!,
            session: widget.session,
            company: company,
            canExport: _canExport,
            personalAllowed: widget.canCreateCompany,
          ),
        ),
      ),
      'attendance-report',
    );
  }

  Widget _feature(BuildContext context) {
    if (_initialRejected) {
      return const Center(
        child: Text(
          'Requested company access was rejected. Exit and choose an authorized company.',
        ),
      );
    }
    final manager = _managerMode;
    final destinations = manager
        ? const [
            ('Overview', Icons.dashboard_outlined),
            ('Attendance', Icons.fact_check_outlined),
            ('Team', Icons.people_outline),
            ('More', Icons.more_horiz),
          ]
        : const [
            ('Home', Icons.home_outlined),
            ('Attendance', Icons.fact_check_outlined),
            ('Profile', Icons.person_outline),
          ];
    return Column(
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Icon(
                  Icons.business_outlined,
                  size: 22,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: CompanySwitcher(
                companies: _companies,
                selected: _selected,
                onSelected: _switch,
                subtitle: _selected == null
                    ? null
                    : '${manager ? "Management" : "Staff"} · ${_selected!.timeZoneId}',
              ),
            ),
            if (widget.canCreateCompany)
              GuideTarget(
                id: 'companies-choose',
                child: IconButton(
                  tooltip: 'Create company',
                  onPressed: () => _newDraft(setup: true),
                  icon: const Icon(Icons.add_business),
                ),
              ),
          ],
        ),
        Expanded(child: _featureBody()),
        if (_selected != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, box) {
                  final large = MediaQuery.textScalerOf(context).scale(14) > 21;
                  final columns = large && box.maxWidth < 600
                      ? 2
                      : destinations.length;
                  return Wrap(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        SizedBox(
                          width: box.maxWidth / columns,
                          child: Semantics(
                            selected: _tab == i,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: _tab == i
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: () => setState(() {
                                _tab = i;
                                _manualEntry = false;
                                _enrolling = false;
                                _capturing = false;
                                _reviewing = i == 1;
                                _draft = false;
                                _operator = false;
                                _setup = false;
                              }),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 20,
                                    height: 3,
                                    margin: const EdgeInsets.only(bottom: 6),
                                    decoration: BoxDecoration(
                                      color: _tab == i
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : null,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  Icon(destinations[i].$2),
                                  const SizedBox(height: 3),
                                  Text(
                                    destinations[i].$1,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: _tab == i
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _featureBody() {
    if (_loading ||
        _selected == null ||
        _setup ||
        _draft ||
        _operator ||
        _enrolling ||
        _capturing ||
        _reviewing) {
      return _body();
    }
    if (_tab == 0) {
      if (_overview == null) {
        return const Center(
          child: Text(
            'Your company tools are available in Team and More. Attendance overview requires review permission.',
          ),
        );
      }
      return StreamBuilder<StaffOverview>(
        key: ValueKey('overview-$_generation-${_selected!.id}'),
        stream: _overview,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                profileError(
                  snapshot.error is CheckException
                      ? (snapshot.error as CheckException).code
                      : CheckError.storageFailure,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<String>(
            future: _backup,
            builder: (context, backup) {
              final value = snapshot.data!;
              return _canReview
                  ? ManagerHomeScreen(
                      showContext: false,
                      overview: value as ManagerOverview,
                      onAttendance: _attendance,
                      onManual: () {
                        _attendance();
                        setState(() => _manualEntry = true);
                      },
                      onInvite: _canInvite ? _openEnrollment : null,
                      onWorkplace: _owner ? _capture : null,
                      backupLabel: backup.data,
                      onBackup: widget.onRecovery == null
                          ? null
                          : () => widget.onRecovery!(),
                    )
                  : StaffHomeScreen(
                      showContext: false,
                      overview: value,
                      onCapture: _capture,
                      onAttendance: _attendance,
                      backupLabel: backup.data,
                      onBackup: widget.onRecovery == null
                          ? null
                          : () => widget.onRecovery!(),
                    );
            },
          );
        },
      );
    }
    if (_tab == 2 && _managerMode) return _body();
    return DashboardLayout(
      children: [
        Text(
          _managerMode ? 'Company tools' : 'Your profile and company',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (_owner &&
            _selected!.name.runes.length > MessageLimits.nameCharacters)
          OutlinedButton(
            onPressed: _correctName,
            child: const Text('Correct company name'),
          ),
        if (_canExport || widget.canCreateCompany)
          GuideTarget(
            id: 'reports-scope',
            child: FilledButton.icon(
              onPressed: _report,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Attendance report'),
            ),
          ),
        if (widget.enrollment != null && widget.messages != null)
          GuideTarget(
            id: 'membership-open',
            child: OutlinedButton(
              onPressed: _openEnrollment,
              child: Text(
                _canInvite
                    ? 'Invite or review join'
                    : 'Join or receive membership',
              ),
            ),
          ),
        if (widget.onRecovery != null)
          OutlinedButton(
            onPressed: widget.onRecovery,
            child: const Text('Backup and device recovery'),
          ),
        if (widget.onSettings != null)
          OutlinedButton(
            onPressed: widget.onSettings,
            child: const Text('Settings'),
          ),
        Text('Company ID: ${_selected!.id}'),
        Text('Trusted root: ${_selected!.rootFingerprint}'),
        const Text(
          'Your company permissions determine which actions are available.',
        ),
      ],
    );
  }
}

/// Owns the editor until its route actually unmounts, including the exit animation.
class _CompanyNameRepairDialog extends StatefulWidget {
  const _CompanyNameRepairDialog({required this.name, required this.onSave});
  final String name;
  final Future<CommandResult<Company>> Function(String) onSave;
  @override
  State<_CompanyNameRepairDialog> createState() =>
      _CompanyNameRepairDialogState();
}

class _CompanyNameRepairDialogState extends State<_CompanyNameRepairDialog> {
  late final name = TextEditingController(text: widget.name);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.onSave(name.text);
      if (!mounted) return;
      if (result is Committed<Company>) {
        setState(() => busy = false);
        Navigator.pop(context, result.value);
      } else {
        setState(() {
          busy = false;
          error = profileError(
            result is Rejected<Company>
                ? result.error
                : CheckError.duplicateConflict,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = profileError(
          e is CheckException ? e.code : CheckError.storageFailure,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Correct company name'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Shorten this legacy name to 1–120 Unicode characters so new memberships can be issued. Existing signed messages keep their original names.',
        ),
        TextField(
          controller: name,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Company name'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy || !compatibleCompanyName(name.text) ? null : save,
        child: Text(busy ? 'Saving…' : 'Save corrected name'),
      ),
    ],
  );
}
