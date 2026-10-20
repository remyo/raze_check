import '../messaging/message_limits.dart';
import '../contracts/capability.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// New names must fit the unchanged v1 membership-grant scalar limit.
/// Stored historical names remain readable without normalization.
bool compatibleCompanyName(String name) {
  final scalars = name.runes.toList();
  return name.trim().isNotEmpty &&
      scalars.length <= MessageLimits.nameCharacters &&
      !scalars.any((r) => r >= 0xd800 && r <= 0xdfff);
}

final class CompanyDraft {
  const CompanyDraft(this.name, this.timeZoneId);
  final String name;
  final String timeZoneId;
}

final class Company {
  Company({
    required this.id,
    required this.name,
    required this.timeZoneId,
    required this.workplaceId,
    required this.authorityGenerationId,
    required this.authoritySigningKeyId,
    required this.rootPublicKey,
    required this.rootFingerprint,
    required List<Object?> authority,
    required this.creationPersonId,
    required this.creationOperationId,
    required this.creationDigest,
  }) : authority = List.unmodifiable(authority);
  final String id, name, timeZoneId, workplaceId, authorityGenerationId;
  final String authoritySigningKeyId;
  final String rootPublicKey, rootFingerprint;

  /// The exact v1 certificate array, including the root signature.
  final List<Object?> authority;
  final String creationPersonId, creationOperationId, creationDigest;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'timeZoneId': timeZoneId,
    'workplaceId': workplaceId,
    'authorityGenerationId': authorityGenerationId,
    'authoritySigningKeyId': authoritySigningKeyId,
    'rootPublicKey': rootPublicKey,
    'rootFingerprint': rootFingerprint,
    'authority': authority,
    'creationPersonId': creationPersonId,
    'creationOperationId': creationOperationId,
    'creationDigest': creationDigest,
  };
  factory Company.fromJson(Map<String, dynamic> j) => Company(
    id: j['id'] as String,
    name: j['name'] as String,
    timeZoneId: j['timeZoneId'] as String,
    workplaceId: j['workplaceId'] as String,
    authorityGenerationId: j['authorityGenerationId'] as String,
    authoritySigningKeyId: j['authoritySigningKeyId'] as String,
    rootPublicKey: j['rootPublicKey'] as String,
    rootFingerprint: j['rootFingerprint'] as String,
    authority: List<Object?>.unmodifiable(j['authority'] as List),
    creationPersonId: j['creationPersonId'] as String,
    creationOperationId: j['creationOperationId'] as String,
    creationDigest: j['creationDigest'] as String,
  );
}

final class Membership {
  Membership({
    required this.id,
    required this.companyId,
    required this.personId,
    required this.employeeId,
    required this.owner,
    required this.active,
    required Set<Capability> capabilities,
    required this.revision,
  }) : capabilities = Set.unmodifiable(capabilities);
  final String id, companyId, personId, employeeId;
  final bool owner, active;
  final Set<Capability> capabilities;
  final int revision;
  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'personId': personId,
    'employeeId': employeeId,
    'owner': owner,
    'active': active,
    'capabilities': (capabilities.map((c) => c.name).toList()..sort()),
    'revision': revision,
  };
  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
    id: j['id'] as String,
    companyId: j['companyId'] as String,
    personId: j['personId'] as String,
    employeeId: j['employeeId'] as String,
    owner: j['owner'] as bool,
    active: j['active'] as bool,
    capabilities: (j['capabilities'] as List)
        .map((c) => Capability.values.byName(c as String))
        .toSet(),
    revision: j['revision'] as int,
  );
}

final class StaffDraft {
  const StaffDraft({
    required this.name,
    this.employeeNumber,
    this.contact,
    this.birthday,
    this.department,
    this.position,
    this.joiningDate,
  });
  final String name;
  final String? employeeNumber,
      contact,
      birthday,
      department,
      position,
      joiningDate;
  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'employeeNumber': employeeNumber,
    'contact': contact,
    'birthday': birthday,
    'department': department,
    'position': position,
    'joiningDate': joiningDate,
  };
  factory StaffDraft.fromJson(Map<String, dynamic> j) => StaffDraft(
    name: j['name'] as String,
    employeeNumber: j['employeeNumber'] as String?,
    contact: j['contact'] as String?,
    birthday: j['birthday'] as String?,
    department: j['department'] as String?,
    position: j['position'] as String?,
    joiningDate: j['joiningDate'] as String?,
  );
}

final class StaffUpdate {
  const StaffUpdate(this.employeeId, this.draft);
  final String employeeId;
  final StaffDraft draft;
}

final class StaffRecord {
  const StaffRecord({
    required this.employeeId,
    required this.companyId,
    required this.personId,
    required this.membershipId,
    required this.details,
    required this.revision,
  });
  final String employeeId, companyId, personId, membershipId;
  final StaffDraft details;
  final int revision;

  /// Derived for display only; never persisted as a field.
  int? ageOn(DateTime date) {
    final birth = DateTime.tryParse(details.birthday ?? '');
    if (birth == null || birth.isAfter(date)) return null;
    var age = date.year - birth.year;
    if (date.month < birth.month ||
        (date.month == birth.month && date.day < birth.day)) {
      age--;
    }
    return age;
  }

  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'companyId': companyId,
    'personId': personId,
    'membershipId': membershipId,
    'details': details.toJson(),
    'revision': revision,
  };
  factory StaffRecord.fromJson(Map<String, dynamic> j) => StaffRecord(
    employeeId: j['employeeId'] as String,
    companyId: j['companyId'] as String,
    personId: j['personId'] as String,
    membershipId: j['membershipId'] as String,
    details: StaffDraft.fromJson(j['details'] as Map<String, dynamic>),
    revision: j['revision'] as int,
  );
}

final class OperatorCredential {
  const OperatorCredential({
    required this.id,
    required this.companyId,
    required this.membershipId,
    required this.personId,
  });
  final String id, companyId, membershipId, personId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'membershipId': membershipId,
    'personId': personId,
  };
  factory OperatorCredential.fromJson(Map<String, dynamic> j) =>
      OperatorCredential(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        membershipId: j['membershipId'] as String,
        personId: j['personId'] as String,
      );
}

/// Only the labels needed to choose a local company credential at unlock.
/// Like local profile labels, these are available while the session is locked.
final class OperatorChoice {
  const OperatorChoice({
    required this.companyId,
    required this.companyName,
    required this.membershipId,
    required this.displayName,
  });
  final String companyId, companyName, membershipId, displayName;
}

abstract final class CompanyTimeZones {
  static final List<String> all = _load();
  static List<String> _load() {
    tzdata.initializeTimeZones();
    return List.unmodifiable(
      tz.timeZoneDatabase.locations.keys.toList()..sort(),
    );
  }
}
