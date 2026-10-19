import '../contracts/capability.dart';
import '../contracts/context.dart';
import '../contracts/result.dart';
import '../identity/identity_models.dart';
import '../identity/identity_service.dart';
import 'company_models.dart';

final class AccessPolicy {
  AccessPolicy(this.identity);
  final IdentityService identity;
  static const ownerOnly = {
    Capability.manageCompany,
    Capability.backupCompany,
    Capability.recoverCompany,
  };

  /// Stored eligibility only; session-mode and actor checks belong in require.
  static bool eligible(Membership membership, Capability capability) =>
      membership.active &&
      (membership.owner ||
          (!ownerOnly.contains(capability) &&
              membership.capabilities.contains(capability)));
  bool can(Membership membership, Capability capability) =>
      eligible(membership, capability);
  ActorIdentity require(
    SessionHandle session,
    Membership membership,
    Capability capability,
  ) {
    final actor = identity.requireActor(session);
    requireMembership(actor, membership);
    if ((!membership.owner && actor.restrictedCompanyId == null) ||
        !can(membership, capability)) {
      throw const CheckException(CheckError.unauthorized);
    }
    return actor;
  }

  void requireMembership(ActorIdentity actor, Membership membership) {
    if (actor.restrictedCompanyId != null &&
        actor.restrictedCompanyId != membership.companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    if (actor.personId != membership.personId ||
        (actor.restrictedMembershipId != null &&
            actor.restrictedMembershipId != membership.id) ||
        !membership.active) {
      throw const CheckException(CheckError.unauthorized);
    }
  }
}
