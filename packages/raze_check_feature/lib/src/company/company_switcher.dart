import 'package:flutter/material.dart';
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

class CompanySwitcher extends StatelessWidget {
  const CompanySwitcher({
    super.key,
    required this.companies,
    required this.selected,
    required this.onSelected,
  });
  final List<Company> companies;
  final Company? selected;
  final ValueChanged<Company> onSelected;
  @override
  Widget build(BuildContext context) => PopupMenuButton<Company>(
    key: const Key('company-switcher'),
    tooltip: 'Switch company',
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final company in companies)
        PopupMenuItem(value: company, child: Text(company.name)),
    ],
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              selected?.name ?? 'Select company',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
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
    this.enrollment,
    this.messages,
    this.pickHistory,
    this.capture,
    this.attendance,
    this.attendanceMessages,
  });
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
  State<CompanyWorkspace> createState() => _CompanyWorkspaceState();
}

class _CompanyWorkspaceState extends State<CompanyWorkspace> {
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
  late String _operation;
  @override
  void initState() {
    super.initState();
    _operation = widget.ids.next();
    _reload();
  }

  @override
  void didUpdateWidget(CompanyWorkspace old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      _generation++;
      _enrolling = false;
      _capturing = false;
      _reviewing = false;
      _selected = null;
      _draft = false;
      _setup = false;
      _reload();
    }
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
    if (mounted) setState(() => _loading = true);
    final generation = _generation;
    try {
      final companies = await widget.companies.listCompanies(widget.session);
      if (!mounted || generation != _generation) return;
      setState(() {
        _companies = companies;
        _selected =
            companies.where((c) => c.id == _selected?.id).firstOrNull ??
            companies.firstOrNull;
      });
      if (_selected != null) {
        await _loadCompany(_selected!, generation);
      } else {
        setState(() => _loading = false);
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
        _membership = member;
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
      _enrolling = false;
      _capturing = false;
      _reviewing = false;
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
    _setup = setup;
    _draft = !setup;
    _operator = false;
    _editing = staff;
    _error = null;
  });
  void _cancel() => setState(() {
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
      if (generation != _generation) return;
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
      if (generation == _generation) _failure(e);
    }
  }

  void _openEnrollment() => setState(() {
    _capturing = false;
    _reviewing = false;
    _enrolling = true;
  });
  @override
  Widget build(BuildContext context) => Column(
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
            _canManage ? 'Invite or review join' : 'Join or receive membership',
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
            IconButton(
              tooltip: 'Create company',
              onPressed: () => _newDraft(setup: true),
              icon: const Icon(Icons.add_business),
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
  );
  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_reviewing && widget.attendance != null && _selected != null) {
      return Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _reviewing = false),
            child: const Text('Back to company'),
          ),
          Expanded(
            child: ReviewWorkspace(
              key: ValueKey('review-${_selected!.id}'),
              service: widget.attendance!,
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
              session: widget.session,
              ids: widget.ids,
              messages: widget.messages!,
              company: _selected,
              canManage: _canManage,
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
            const Text('Create your first company to manage staff offline.'),
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
}
