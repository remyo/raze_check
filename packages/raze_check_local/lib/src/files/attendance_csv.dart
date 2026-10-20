import 'dart:convert';
import 'dart:typed_data';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:timezone/timezone.dart' as tz;

abstract final class AttendanceCsv {
  /// CSV quoting alone does not prevent spreadsheet formula execution.
  static String cell(String value, {bool userText = true}) {
    if (userText && value.isNotEmpty && '=+-@\t\r'.contains(value[0])) {
      value = "'$value";
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  static Uint8List encode(AttendanceReport report) {
    CompanyTimeZones.all;
    final zone = tz.getLocation(report.company.timeZoneId);
    String time(int? ms) => ms == null
        ? ''
        : tz.TZDateTime.fromMillisecondsSinceEpoch(zone, ms).toIso8601String();
    final lines = <List<String>>[
      ['Company', report.company.name, 'Time zone', report.company.timeZoneId],
      [
        'Date axis',
        'Current effective punch time',
        'Start date',
        report.range.start.toIso8601String().substring(0, 10),
        'End date (inclusive)',
        report.range.end.toIso8601String().substring(0, 10),
      ],
      ['Generated at', time(report.generatedUtcMs), 'Scope', report.scope.name],
      [
        'Event ID',
        'Employee ID',
        'Name',
        'Original time',
        'Received time',
        'Effective time',
        'Original kind',
        'Effective kind',
        'Source',
        'Delivery',
        'Review',
        'Review hints (known receipts; offline delivery may be incomplete)',
        'Manual reason',
        'Correction history',
        'Correction requests',
        'Decision history',
      ],
      for (final item in report.rows)
        [
          item.record.eventId,
          item.record.employeeId,
          item.employeeName,
          time(item.record.claimedUtcMs),
          time(item.record.receivedUtcMs),
          time(item.record.effectiveUtcMs),
          item.record.data['originalKind'] as String,
          item.record.effectiveKind.name,
          item.record.source.name,
          item.record.delivery.name,
          item.record.review.name,
          item.record.flags.map(attendanceHintLabel).join('; '),
          item.record.data['reason'] as String? ?? '',
          item.decisions
              .where((d) => d.correctionId != null)
              .map(
                (d) =>
                    '${d.correctionId}: ${d.correctionOutcome?.name}; request ${d.requestId ?? "manager"}; ${d.reason}',
              )
              .join('\n'),
          item.requests
              .map(
                (r) =>
                    '${r.requestId}: ${r.outcome?.name ?? "pending"}; ${r.proposedKind}; ${time(r.proposedUtcMs)}; ${r.reason}',
              )
              .join('\n'),
          item.decisions
              .map((d) => '${d.revision}: ${d.data['outcome']}; ${d.reason}')
              .join('\n'),
        ],
    ];
    return Uint8List.fromList(
      utf8.encode(
        '${lines.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n',
      ),
    );
  }
}
