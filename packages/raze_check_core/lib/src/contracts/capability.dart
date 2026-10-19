/// Company-scoped management permissions, checked against the active session.
enum Capability {
  manageCompany,
  manageStaff,
  manageMemberships,
  reviewAttendance,
  exportAttendance,
  backupCompany,
  recoverCompany,
}
