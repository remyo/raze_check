import 'dart:convert';
import 'package:raze_check_core/raze_check_core.dart';

/// Stored in encrypted company rows/operation journal, with authority gates in
/// the same SQLite transaction. No archive passphrase or signing seed belongs here.
final class HandoverJournal {
  const HandoverJournal(this.data);
  factory HandoverJournal.read(StoredRecord row) => HandoverJournal(
    jsonDecode(utf8.decode(row.payload)) as Map<String, dynamic>,
  );
  final Map<String, dynamic> data;
  String get state => data['state'] as String;
  bool get mayCancel => state == 'preparing';
}
