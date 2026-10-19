import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';

/// Input uses explicit ISO date/time and offset so claimed civil time is visible.
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({
    super.key,
    required this.staff,
    required this.busy,
    required this.onSave,
    required this.onCancel,
  });
  final List<AttendanceSubject> staff;
  final bool busy;
  final Future<void> Function(ManualPunch) onSave;
  final VoidCallback onCancel;
  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  String? employee;
  PunchKind kind = PunchKind.checkIn;
  final time = TextEditingController(
    text: DateTime.now().toIso8601String().split('.').first,
  );
  final offset = TextEditingController(
    text: DateTime.now().timeZoneOffset.inMinutes.toString(),
  );
  final reason = TextEditingController();
  String? error;
  @override
  void dispose() {
    time.dispose();
    offset.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text('Manual attendance · local record'),
      const Text(
        'Requires a reason and separate approval. This record has no staff-phone return exchange.',
      ),
      DropdownButtonFormField<String>(
        initialValue: employee,
        decoration: const InputDecoration(labelText: 'Employee'),
        items: [
          for (final s in widget.staff)
            DropdownMenuItem(value: s.employeeId, child: Text(s.name)),
        ],
        onChanged: widget.busy ? null : (v) => setState(() => employee = v),
      ),
      DropdownButtonFormField<PunchKind>(
        initialValue: kind,
        items: [
          for (final k in PunchKind.values)
            DropdownMenuItem(value: k, child: Text(k.name)),
        ],
        onChanged: widget.busy ? null : (v) => setState(() => kind = v!),
      ),
      TextField(
        controller: time,
        decoration: const InputDecoration(
          labelText: 'Local date/time (YYYY-MM-DDTHH:MM:SS)',
        ),
      ),
      TextField(
        controller: offset,
        decoration: const InputDecoration(labelText: 'UTC offset in minutes'),
      ),
      TextField(
        controller: reason,
        decoration: const InputDecoration(labelText: 'Reason'),
      ),
      if (error != null) Text(error!),
      FilledButton(
        onPressed: widget.busy
            ? null
            : () async {
                try {
                  final parsed = DateTime.parse('${time.text}Z'),
                      minutes = int.parse(offset.text);
                  if (employee == null ||
                      reason.text.trim().isEmpty ||
                      minutes.abs() > 840) {
                    throw const FormatException();
                  }
                  await widget.onSave(
                    ManualPunch(
                      employeeId: employee!,
                      kind: kind,
                      utcMs: parsed.millisecondsSinceEpoch - minutes * 60000,
                      offsetMinutes: minutes,
                      reason: reason.text,
                    ),
                  );
                } on FormatException {
                  setState(
                    () => error =
                        'Enter an employee, date/time, offset and reason.',
                  );
                }
              },
        child: const Text('Save pending manual entry'),
      ),
      TextButton(
        onPressed: widget.busy ? null : widget.onCancel,
        child: const Text('Cancel'),
      ),
    ],
  );
}
