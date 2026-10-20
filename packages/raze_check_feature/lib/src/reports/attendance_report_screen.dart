import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../host/check_services.dart';
import '../dashboard/staff_home_screen.dart';
import '../recovery/recovery_shared.dart';
import '../guides/guide_target.dart';
import '../guides/guide_invitation.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({
    super.key,
    required this.services,
    required this.session,
    required this.company,
    required this.canExport,
    required this.personalAllowed,
  });
  final CheckServices services;
  final SessionHandle session;
  final Company company;
  final bool canExport, personalAllowed;
  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState
    extends RecoveryState<AttendanceReportScreen> {
  @override
  IdentityService get identity => widget.services.identity;
  @override
  SessionHandle get session => widget.session;
  final start = TextEditingController(), end = TextEditingController();
  AttendanceScope scope = AttendanceScope.personal;
  AttendanceReport? report;
  @override
  void initState() {
    super.initState();
    scope = widget.personalAllowed
        ? AttendanceScope.personal
        : AttendanceScope.management;
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    super.dispose();
  }

  CommandContext get command => CommandContext(
    companyId: widget.company.id,
    session: session,
    operationId: 'report-read',
    authorityGenerationId: widget.company.authorityGenerationId,
  );
  @override
  Future<void> guard() async {
    await super.guard();
    await widget.services.queries.authorizeReport(command, scope);
    await super.guard();
  }

  DateTime parse(String text) {
    final parts = text.split('-');
    if (parts.length != 3) throw const CheckException(CheckError.malformed);
    final values = parts.map(int.tryParse).toList();
    if (values.any((v) => v == null)) {
      throw const CheckException(CheckError.malformed);
    }
    final d = DateTime.utc(values[0]!, values[1]!, values[2]!);
    if (d.year != values[0] || d.month != values[1] || d.day != values[2]) {
      throw const CheckException(CheckError.malformed);
    }
    return d;
  }

  @override
  Widget build(BuildContext context) => frame('Attendance report', [
    const GuideInvitation(guideId: 'reports'),
    if (widget.canExport && widget.personalAllowed)
      Text(
        '${widget.company.name} · ${scope == AttendanceScope.personal ? "My records" : "Management"}',
      )
    else
      GuideTarget(
        id: 'reports-scope',
        child: Text(
          '${widget.company.name} · ${scope == AttendanceScope.personal ? "My records" : "Management"}',
        ),
      ),
    Text(
      'Filter by current effective punch date · ${widget.company.timeZoneId}',
    ),
    const Text(
      'Start and end are inclusive calendar dates. Original and received times remain in the export.',
    ),
    if (widget.canExport && widget.personalAllowed)
      GuideTarget(
        id: 'reports-scope',
        child: DropdownButtonFormField<AttendanceScope>(
          initialValue: scope,
          decoration: const InputDecoration(labelText: 'Report scope'),
          items: const [
            DropdownMenuItem(
              value: AttendanceScope.personal,
              child: Text('My attendance'),
            ),
            DropdownMenuItem(
              value: AttendanceScope.management,
              child: Text('Company attendance'),
            ),
          ],
          onChanged: busy
              ? null
              : (value) => setState(() {
                  scope = value!;
                  report = null;
                }),
        ),
      ),
    const SizedBox(height: 16),
    GuideTarget(
      id: 'reports-dates',
      child: TextField(
        controller: start,
        onChanged: (_) => setState(() => report = null),
        keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(labelText: 'Start date (YYYY-MM-DD)'),
        enabled: !busy,
      ),
    ),
    const SizedBox(height: 16),
    TextField(
      controller: end,
      onChanged: (_) => setState(() => report = null),
      keyboardType: TextInputType.datetime,
      decoration: const InputDecoration(labelText: 'End date (YYYY-MM-DD)'),
      enabled: !busy,
    ),
    button('Generate report', () async {
      final value = await widget.services.queries.report(
        command,
        DateRange(parse(start.text), parse(end.text)),
        scope: scope,
        cancelled: () => !mounted || hidden,
      );
      await guard();
      if (mounted) setState(() => report = value);
    }),
    if (report != null) ...[
      Text(
        '${report!.rows.length} ${report!.rows.length == 1 ? "record" : "records"} · generated ${attendanceTime(report!.generatedUtcMs, widget.company.timeZoneId)}',
      ),
      const Text(
        'The export is a consistent snapshot. Regenerate to include later changes.',
      ),
      GuideTarget(
        id: 'reports-csv',
        child: button('Share CSV', () async {
          final outcome = await widget.services.shareReport(report!, guard);
          if (mounted) {
            setState(
              () => message = outcome == ShareOutcome.opened
                  ? 'Share sheet opened. External delivery is not confirmed.'
                  : 'Sharing did not confirm an external copy. Retry when available.',
            );
          }
        }),
      ),
      for (final item in report!.rows.take(25))
        ListTile(
          title: Text(
            '${item.employeeName} · ${item.record.effectiveKind.name}',
          ),
          subtitle: Text(
            '${attendanceTime(item.record.effectiveUtcMs, widget.company.timeZoneId)}\n${item.record.delivery.name} · ${item.record.review.name}',
          ),
        ),
      if (report!.rows.length > 25)
        const Text(
          'Preview shows the first 25 rows; CSV includes every selected row.',
        ),
    ],
  ]);
}
