import 'dart:typed_data';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:test/test.dart';

class Handle implements SessionHandle {}

class Identity implements IdentityService {
  ActorIdentity actor = ActorIdentity(
    personId: 'p',
    installationId: 'i',
    signingKeyId: 'k',
    publicKey: Uint8List(32),
  );
  final session = Handle();
  @override
  ActorIdentity requireActor(SessionHandle s) {
    if (!identical(s, session)) throw const CheckException(CheckError.locked);
    return actor;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final identity = Identity();
  final policy = AccessPolicy(identity);
  Membership member(
    String company, {
    bool owner = false,
    bool active = true,
    Set<Capability> caps = const {},
  }) => Membership(
    id: 'm',
    companyId: company,
    personId: 'p',
    employeeId: 'e',
    owner: owner,
    active: active,
    capabilities: caps,
    revision: 1,
  );
  test(
    'pure core eligibility rejects inactive owners and owner-only staff grants',
    () {
      expect(
        AccessPolicy.eligible(
          member('a', owner: true, active: false),
          Capability.manageStaff,
        ),
        isFalse,
      );
      expect(
        AccessPolicy.eligible(
          member('a', caps: {Capability.manageCompany}),
          Capability.manageCompany,
        ),
        isFalse,
      );
      expect(
        AccessPolicy.eligible(
          member('a', caps: {Capability.manageStaff}),
          Capability.manageStaff,
        ),
        isTrue,
      );
      expect(
        AccessPolicy.eligible(
          member('a', owner: true),
          Capability.recoverCompany,
        ),
        isTrue,
      );
    },
  );
  test('staff and owner permissions belong to each company membership', () {
    expect(policy.can(member('a'), Capability.manageStaff), isFalse);
    expect(
      policy.can(member('b', owner: true), Capability.manageStaff),
      isTrue,
    );
    expect(
      policy.can(
        member('a', caps: {Capability.manageCompany}),
        Capability.manageCompany,
      ),
      isFalse,
    );
    expect(
      policy.can(
        member('a', caps: {Capability.backupCompany}),
        Capability.backupCompany,
      ),
      isFalse,
    );
    expect(
      policy.can(
        member('a', caps: {Capability.recoverCompany}),
        Capability.recoverCompany,
      ),
      isFalse,
    );
  });
  test('stored grant alone cannot authorize personal staff management', () {
    identity.actor = ActorIdentity(
      personId: 'p',
      installationId: 'i',
      signingKeyId: 'k',
      publicKey: Uint8List(32),
    );
    final granted = member('a', caps: {Capability.manageStaff});
    expect(policy.can(granted, Capability.manageStaff), isTrue);
    expect(
      () => policy.require(identity.session, granted, Capability.manageStaff),
      throwsA(
        isA<CheckException>().having(
          (e) => e.code,
          'code',
          CheckError.unauthorized,
        ),
      ),
    );
    identity.actor = ActorIdentity(
      personId: 'p',
      installationId: 'i',
      signingKeyId: 'op',
      publicKey: Uint8List(32),
      restrictedCompanyId: 'a',
      restrictedMembershipId: 'm',
    );
    expect(
      policy
          .require(identity.session, granted, Capability.manageStaff)
          .personId,
      'p',
    );
  });
  test(
    'operator actor cannot impersonate its personal membership elsewhere',
    () {
      identity.actor = ActorIdentity(
        personId: 'p',
        installationId: 'i',
        signingKeyId: 'op',
        publicKey: Uint8List(32),
        restrictedCompanyId: 'a',
        restrictedMembershipId: 'm',
      );
      expect(
        () => policy.require(
          identity.session,
          member('b', owner: true),
          Capability.manageStaff,
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.wrongCompany,
          ),
        ),
      );
      expect(
        () => policy.require(Handle(), member('a'), Capability.manageStaff),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.locked,
          ),
        ),
      );
    },
  );
}
