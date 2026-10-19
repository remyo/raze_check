import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';

class CorrectionRequestScreen extends StatefulWidget {
  const CorrectionRequestScreen({
    super.key,
    required this.record,
    required this.manager,
    required this.busy,
    required this.onSubmit,
    required this.onCancel,
  });
  final AttendanceRecord record;
  final bool manager, busy;
  final Future<void> Function(ProposedCorrection) onSubmit;
  final VoidCallback onCancel;
  @override
  State<CorrectionRequestScreen> createState() =>
      _CorrectionRequestScreenState();
}

class _CorrectionRequestScreenState extends State<CorrectionRequestScreen> {
  late PunchKind kind = widget.record.effectiveKind;
  late final time = TextEditingController(
    text: DateTime.fromMillisecondsSinceEpoch(
      widget.record.effectiveUtcMs,
      isUtc: true,
    ).toIso8601String(),
  );
  late final offset = TextEditingController(
    text: widget.record.effectiveOffsetMinutes.toString(),
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
      Text(widget.manager ? 'Manager correction' : 'Request a correction'),
      const Text('Original receipt and review status are preserved.'),
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
          labelText: 'Correct time (ISO date/time with Z or offset)',
        ),
      ),
      TextField(
        controller: offset,
        decoration: const InputDecoration(
          labelText: 'Claimed UTC offset in minutes',
        ),
      ),
      TextField(
        controller: reason,
        decoration: const InputDecoration(labelText: 'Correction reason'),
      ),
      if (error != null) Text(error!),
      FilledButton(
        onPressed: widget.busy
            ? null
            : () async {
                try {
                  if (!RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(time.text) ||
                      reason.text.trim().isEmpty) {
                    throw const FormatException();
                  }
                  final date = DateTime.parse(time.text),
                      minutes = int.parse(offset.text);
                  if (minutes.abs() > 840) throw const FormatException();
                  await widget.onSubmit(
                    ProposedCorrection(
                      kind: kind,
                      utcMs: date.millisecondsSinceEpoch,
                      offsetMinutes: minutes,
                      reason: reason.text,
                    ),
                  );
                } on FormatException {
                  setState(
                    () => error = 'Enter a valid time, offset and reason.',
                  );
                }
              },
        child: Text(
          widget.manager ? 'Save manager correction' : 'Save signed request',
        ),
      ),
      TextButton(
        onPressed: widget.busy ? null : widget.onCancel,
        child: const Text('Cancel'),
      ),
    ],
  );
}
