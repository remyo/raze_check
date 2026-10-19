import 'dart:typed_data';

final class LocalProfile {
  const LocalProfile({
    required this.personId,
    required this.displayName,
    required this.installationId,
    required this.signingKeyId,
    required this.publicKey,
  });
  final String personId;
  final String displayName;
  final String installationId;
  final String signingKeyId;
  final Uint8List publicKey;
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
  }) : publicKey = publicKey.asUnmodifiableView();
  final String personId;
  final String installationId;
  final String signingKeyId;
  final Uint8List publicKey;
  final String? restrictedCompanyId, restrictedMembershipId;
}
