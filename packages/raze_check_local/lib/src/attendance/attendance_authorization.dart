import 'dart:convert';
import 'package:raze_check_core/raze_check_core.dart';

/// Internal shared boundary for personal capture. Pass ReadView.read for every
/// mutation/replay; repository reads are only suitable for bounded queries.
/// Task 11 extends this boundary with persisted activation/retirement gates.
final class AttendanceAuthorization {
  AttendanceAuthorization(this.identity);
  final IdentityService identity;
  static Map<String, dynamic> _json(StoredRecord r) =>
      jsonDecode(utf8.decode(r.payload)) as Map<String, dynamic>;
  ActorIdentity requirePersonal(SessionHandle session) {
    final actor = identity.requireActor(session);
    if (actor.restrictedCompanyId != null) {
      throw const CheckException(CheckError.unauthorized);
    }
    return actor;
  }

  Future<({ActorIdentity actor, Membership member, Company company})> require(
    SessionHandle session,
    String companyId,
    Future<StoredRecord?> Function(String) read, {
    String? generation,
    bool issue = true,
  }) async {
    final actor = requirePersonal(session);
    actor.requireCompany(companyId);
    final index = await read('member-index:${actor.personId}');
    final memberRow = index == null
        ? null
        : await read(_json(index)['membershipId'] as String);
    if (memberRow == null) throw const CheckException(CheckError.unauthorized);
    final member = Membership.fromJson(_json(memberRow));
    if (member.companyId != companyId || member.personId != actor.personId) {
      throw const CheckException(CheckError.unauthorized);
    }
    if (issue) AccessPolicy(identity).requireMembership(actor, member);
    final companyRow = await read(companyId);
    if (companyRow == null) throw const CheckException(CheckError.wrongCompany);
    var company = Company.fromJson(_json(companyRow));
    final localAuthority = AuthorityCertificate(company.authority);
    if (localAuthority.generationId != company.authorityGenerationId) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    final remote = await read('remote-authority:${actor.personId}');
    if (remote != null && !member.owner) {
      final a = AuthorityCertificate(
        List<Object?>.from(_json(remote)['authority'] as List),
      );
      final known = await read(a.generationId);
      if (known == null ||
          known.kind != 'authority' ||
          utf8.decode(known.payload) != jsonEncode(a.values)) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      if (a.sequence == localAuthority.sequence &&
          a.generationId != localAuthority.generationId) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      if (a.sequence >= localAuthority.sequence) {
        company = Company.fromJson({
          ...company.toJson(),
          'authorityGenerationId': a.generationId,
          'authority': a.values,
          'authoritySigningKeyId': '',
        });
      }
    }
    if (generation != null && company.authorityGenerationId != generation) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    if (issue) {
      final certificate = AuthorityCertificate(company.authority);
      if (certificate.generationId != company.authorityGenerationId) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      final credential = await read(
        'credential:${member.id}:${member.revision}',
      );
      if (credential == null) {
        if (!member.owner ||
            certificate.installationId != actor.installationId ||
            company.authoritySigningKeyId != actor.signingKeyId ||
            base64UrlEncode(certificate.publicKey) !=
                base64UrlEncode(actor.publicKey)) {
          throw const CheckException(CheckError.revokedCredential);
        }
      } else {
        final c = _json(credential);
        if (c['retired'] != false ||
            c['companyId'] != companyId ||
            c['personId'] != actor.personId ||
            c['employeeId'] != member.employeeId ||
            c['membershipId'] != member.id ||
            c['membershipRevision'] != member.revision ||
            c['installationId'] != actor.installationId ||
            c['publicKey'] != base64UrlEncode(actor.publicKey)) {
          throw const CheckException(CheckError.revokedCredential);
        }
        final issuing = await read(c['authorityGenerationId'] as String);
        if (issuing == null || issuing.kind != 'authority') {
          throw const CheckException(CheckError.unknownIssuer);
        }
      }
    }
    identity.requireActor(session);
    return (actor: actor, member: member, company: company);
  }
}
