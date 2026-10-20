/// Review hints only; never evidence of fraud or payable working time.
enum AttendanceFlag {
  possibleDuplicate,
  unexpectedOrder,
  missingCheckIn,
  missingCheckOut,
}

String attendanceHintLabel(String flag) => switch (flag) {
  'missingCheckIn' => 'No known preceding check-in receipt',
  'missingCheckOut' => 'No known check-out receipt between check-in receipts',
  'unexpectedOrder' => 'Unexpected order among known receipts',
  'possibleDuplicate' => 'Possible duplicate within two minutes',
  'historicalCredential' => 'Historical credential',
  'clockAnomaly' => 'Clock difference needs review',
  _ => flag,
};
