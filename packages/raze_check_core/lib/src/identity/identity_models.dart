import 'dart:typed_data';
import '../contracts/result.dart';

final class LocalProfile {
  const LocalProfile({
    required this.personId,
    required this.displayName,
    required this.installationId,
    required this.signingKeyId,
    required this.publicKey,
    this.authorizedCompanyIds,
  });
  final String personId;
  final String displayName;
  final String installationId;
  final String signingKeyId;
  final Uint8List publicKey;
  final Set<String>? authorizedCompanyIds;
}

/// Identity only: company membership and permissions are resolved separately.
final class ActorIdentity {
  ActorIdentity({
    required this.personId,
    required this.installationId,
    required this.signingKeyId,
    required Uint8List publicKey,
    this.restrictedCompanyId,
    this.restrictedMembershipId,
    Set<String>? authorizedCompanyIds,
  }) : authorizedCompanyIds = authorizedCompanyIds == null
           ? null
           : Set.unmodifiable(authorizedCompanyIds),
       publicKey = publicKey.asUnmodifiableView();
  final String personId;
  final String installationId;
  final String signingKeyId;
  final Uint8List publicKey;
  final String? restrictedCompanyId, restrictedMembershipId;
  final Set<String>? authorizedCompanyIds;
  void requireCompany(String companyId) {
    if (restrictedCompanyId != null && restrictedCompanyId != companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    if (authorizedCompanyIds != null &&
        !authorizedCompanyIds!.contains(companyId)) {
      throw const CheckException(CheckError.unauthorized);
    }
  }
}
