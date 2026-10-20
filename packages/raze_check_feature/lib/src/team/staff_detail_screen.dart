import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../guides/guide_target.dart';

class StaffDetailScreen extends StatefulWidget {
  const StaffDetailScreen({
    super.key,
    this.staff,
    required this.onSave,
    required this.onCancel,
    this.onOperatorAccess,
    this.onDeactivate,
    this.busy = false,
    this.error,
  });
  final StaffRecord? staff;
  final Future<void> Function(StaffDraft) onSave;
  final VoidCallback onCancel;
  final VoidCallback? onOperatorAccess;
  final Future<void> Function(String)? onDeactivate;
  final bool busy;
  final String? error;
  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  late final _fields = <String, TextEditingController>{
    for (final entry
        in (widget.staff?.details.toJson() ??
                const StaffDraft(name: '').toJson())
            .entries)
      entry.key: TextEditingController(text: entry.value as String? ?? ''),
  };
  final _reason = TextEditingController();
  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  String? _optional(String key) =>
      _fields[key]!.text.trim().isEmpty ? null : _fields[key]!.text.trim();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        widget.staff == null ? 'Add staff' : 'Staff details',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      for (final entry in _fields.entries)
        TextField(
          key: Key('staff-${entry.key}'),
          controller: entry.value,
          enabled: !widget.busy,
          decoration: InputDecoration(
            labelText: switch (entry.key) {
              'name' => 'Name',
              'employeeNumber' => 'Employee number (optional)',
              'contact' => 'Contact (optional)',
              'birthday' => 'Birthday YYYY-MM-DD (optional)',
              'department' => 'Department (optional)',
              'position' => 'Position (optional)',
              _ => 'Joining date YYYY-MM-DD (optional)',
            },
          ),
        ),
      if (widget.staff?.ageOn(DateTime.now()) case final int age)
        Text('Age: $age (calculated for display)'),
      const SizedBox(height: 12),
      const Text('A manual staff record does not require an enrolled phone.'),
      if (widget.error != null) Text(widget.error!),
      GuideTarget(
        id: 'team-details',
        child: FilledButton(
          onPressed: widget.busy
              ? null
              : () => widget.onSave(
                  StaffDraft(
                    name: _fields['name']!.text,
                    employeeNumber: _optional('employeeNumber'),
                    contact: _optional('contact'),
                    birthday: _optional('birthday'),
                    department: _optional('department'),
                    position: _optional('position'),
                    joiningDate: _optional('joiningDate'),
                  ),
                ),
          child: const Text('Save staff'),
        ),
      ),
      if (widget.onOperatorAccess != null)
        GuideTarget(
          id: 'team-capabilities',
          child: OutlinedButton(
            onPressed: widget.busy ? null : widget.onOperatorAccess,
            child: const Text('Manage operator access'),
          ),
        ),
      if (widget.onDeactivate != null) ...[
        TextField(
          controller: _reason,
          decoration: const InputDecoration(
            labelText: 'Reason for deactivation',
          ),
        ),
        TextButton(
          onPressed: widget.busy
              ? null
              : () => widget.onDeactivate!(_reason.text),
          child: const Text('Deactivate staff'),
        ),
      ],
      TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
    ],
  );
}
