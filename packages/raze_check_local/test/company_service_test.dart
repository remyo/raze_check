@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/repository_fixture.dart';
import 'support/fake_clock.dart';

void main() {
  late RepositoryFixture fixture;
  late LocalIdentityService identity;
  late LocalCompanyService companies;
  late SessionHandle owner;
  late FakeClock clock;
  setUp(() async {
    clock = FakeClock();
    fixture = await RepositoryFixture.open();
    identity = LocalIdentityService(
      keys: fixture.keys,
      catalog: ProfileCatalog(paths: fixture.paths, keys: fixture.keys),
      clock: clock,
      ids: SecureIds(),
      repository: fixture.repo,
    );
    companies = LocalCompanyService(
      repository: fixture.repo,
      identity: identity,
      keys: fixture.keys,
      clock: clock,
      ids: SecureIds(),
    );
    owner = await identity.createProfile('Owner', 'owner passphrase 123');
  });
  tearDown(() => fixture.dispose());
  Future<Company> create(String op, [String name = 'Company A']) async =>
      (await companies.createCompany(
                owner,
                CompanyDraft(name, 'Asia/Tokyo'),
                op,
              )
              as Committed<Company>)
          .value;
  CommandContext context(
    Company company,
    String op, {
    SessionHandle? session,
  }) => CommandContext(
    companyId: company.id,
    session: session ?? owner,
    operationId: op,
    authorityGenerationId: company.authorityGenerationId,
  );
  test(
    'rejected operator activation deletes its owned uncommitted signing key',
    () async {
      final a = await create('cleanup-company');
      final staff =
          (await companies.createStaff(
                    context(a, 'staff'),
                    const StaffDraft(name: 'Operator'),
                  )
                  as Committed<StaffRecord>)
              .value;
      final cipher = GatedCipher(AesPayloadCipher(VaultKeys(fixture.keys)));
      final slowRepository = LocalCheckRepository(
        database: fixture.database,
        cipher: cipher,
      );
      final slowCompanies = LocalCompanyService(
        repository: slowRepository,
        identity: identity,
        keys: fixture.keys,
        clock: clock,
        ids: SecureIds(),
      );
      final beforeKeys = fixture.keys.values.keys
          .where((key) => key.startsWith('operator-signing:'))
          .toSet();
      final activation = slowCompanies.activateOperator(
        context(a, 'expired-activation'),
        staff.membershipId,
        'operator own passphrase',
      );
      await cipher.entered.future;
      clock.advance(const Duration(minutes: 5));
      cipher.release.complete();
      expect(
        (await activation as Rejected<OperatorCredential>).error,
        CheckError.locked,
      );
      expect(
        fixture.keys.values.keys
            .where((key) => key.startsWith('operator-signing:'))
            .toSet(),
        beforeKeys,
      );
      expect(
        await fixture.repo.read(a.id, 'operator:${staff.membershipId}'),
        isNull,
      );
    },
  );
  test(
    'creation reservation authenticates allocated company and authority routing ids',
    () async {
      await create('reserved-create');
      await fixture.database.customStatement(
        "UPDATE company_creation_reservations SET authority_generation_id = 'tampered'",
      );
      final retry = await companies.createCompany(
        owner,
        const CompanyDraft('Company A', 'Asia/Tokyo'),
        'reserved-create',
      );
      expect((retry as Rejected<Company>).error, CheckError.invalidSignature);
    },
  );
  test(
    'granted personal staff session reads company but management needs activated operator',
    () async {
      final ownerId = identity.requireActor(owner).personId;
      final a = await create('personal-staff-company');
      final personal = await identity.createProfile(
        'Enrolled staff',
        'personal staff passphrase',
      );
      final personId = identity.requireActor(personal).personId;
      owner = await identity.unlock(ownerId, 'owner passphrase 123');
      final idGenerator = SecureIds();
      final memberId = idGenerator.next();
      final employeeId = idGenerator.next();
      final member = Membership(
        id: memberId,
        companyId: a.id,
        personId: personId,
        employeeId: employeeId,
        owner: false,
        active: true,
        capabilities: {},
        revision: 1,
      );
      final staff = StaffRecord(
        employeeId: employeeId,
        companyId: a.id,
        personId: personId,
        membershipId: memberId,
        details: const StaffDraft(name: 'Enrolled staff'),
        revision: 1,
      );
      StoredRecord row(String id, String kind, Object payload) => StoredRecord(
        id,
        a.id,
        kind,
        1,
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      );
      final memberRow = row(memberId, 'membership', member.toJson());
      await fixture.repo.commit(
        context(a, 'approved-enrollment-fixture'),
        requestDigest: Uint8List(32),
        build: (_) async => Mutation(
          [
            memberRow,
            row(employeeId, 'staff', staff.toJson()),
            row('member-index:$personId', 'membershipIndex', {
              'membershipId': memberId,
            }),
          ],
          [],
          [],
          memberRow,
        ),
      );
      await companies.grantCapabilities(context(a, 'grant'), memberId, {
        Capability.manageStaff,
      });
      final staffSession = await identity.unlock(
        personId,
        'personal staff passphrase',
      );
      expect((await companies.readCompany(staffSession, a.id))!.id, a.id);
      final before = await fixture.repo.watchRevision(a.id).first;
      expect(
        (await companies.createStaff(
                  context(a, 'personal-management', session: staffSession),
                  const StaffDraft(name: 'Denied'),
                )
                as Rejected<StaffRecord>)
            .error,
        CheckError.unauthorized,
      );
      expect(await fixture.repo.watchRevision(a.id).first, before);
      owner = await identity.unlock(ownerId, 'owner passphrase 123');
      await companies.activateOperator(
        context(a, 'activate'),
        memberId,
        'company operator passphrase',
      );
      final operator = await companies.unlockOperator(
        a.id,
        memberId,
        'company operator passphrase',
      );
      expect(
        await companies.createStaff(
          context(a, 'operator-management', session: operator),
          const StaffDraft(name: 'Allowed'),
        ),
        isA<Committed<StaffRecord>>(),
      );
    },
  );
  test(
    'expiry during replay decryption rejects disclosure without another revision',
    () async {
      final a = await create('replay-company');
      await companies.createStaff(
        context(a, 'replayed-staff'),
        const StaffDraft(name: 'Already saved'),
      );
      final before = await fixture.repo.watchRevision(a.id).first;
      final cipher = GatedCipher(
        AesPayloadCipher(VaultKeys(fixture.keys)),
        openRecordId: 'operation:replayed-staff',
      );
      final slowRepository = LocalCheckRepository(
        database: fixture.database,
        cipher: cipher,
      );
      final slowCompanies = LocalCompanyService(
        repository: slowRepository,
        identity: identity,
        keys: fixture.keys,
        clock: clock,
        ids: SecureIds(),
      );
      final replay = slowCompanies.createStaff(
        context(a, 'replayed-staff'),
        const StaffDraft(name: 'Already saved'),
      );
      await cipher.entered.future;
      clock.advance(const Duration(minutes: 5));
      cipher.release.complete();
      expect((await replay as Rejected<StaffRecord>).error, CheckError.locked);
      expect(await fixture.repo.watchRevision(a.id).first, before);
      expect(await fixture.count('staff'), 2);
    },
  );
  test(
    'expiry during slow encryption rolls back before transaction acceptance',
    () async {
      final a = await create('slow-company');
      final before = await fixture.repo.watchRevision(a.id).first;
      final cipher = GatedCipher(AesPayloadCipher(VaultKeys(fixture.keys)));
      final slowRepository = LocalCheckRepository(
        database: fixture.database,
        cipher: cipher,
      );
      final slowCompanies = LocalCompanyService(
        repository: slowRepository,
        identity: identity,
        keys: fixture.keys,
        clock: clock,
        ids: SecureIds(),
      );
      final save = slowCompanies.createStaff(
        context(a, 'slow-staff'),
        const StaffDraft(name: 'Never committed'),
      );
      await cipher.entered.future;
      clock.advance(const Duration(minutes: 5));
      cipher.release.complete();
      expect((await save as Rejected<StaffRecord>).error, CheckError.locked);
      expect(await fixture.repo.watchRevision(a.id).first, before);
      expect(await fixture.count('staff'), 1);
    },
  );
  test(
    'lock after acceptance preserves durable committed result and retry reconciliation',
    () async {
      final a = await create('accepted-company');
      final personId = identity.requireActor(owner).personId;
      final row = StoredRecord(
        'accepted-row',
        a.id,
        'accepted-test',
        1,
        Uint8List.fromList(utf8.encode('{}')),
      );
      final original = context(a, 'accepted-save');
      final result = await fixture.repo.commit(
        original,
        requestDigest: Uint8List(32),
        build: (_) async => Mutation([row], [], [], row),
        beforeCommit: () {
          identity.recordActivity(owner);
          scheduleMicrotask(identity.lock);
        },
      );
      expect(result, isA<Committed<StoredRecord>>());
      expect(
        () => identity.requireActor(owner),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.locked,
          ),
        ),
      );
      expect((await fixture.repo.read(a.id, row.id))!.id, row.id);
      owner = await identity.unlock(personId, 'owner passphrase 123');
      final retry = await fixture.repo.commit(
        context(a, 'accepted-save'),
        requestDigest: Uint8List(32),
        build: (_) async => throw StateError('replay must not rebuild'),
        beforeCommit: () => identity.requireActor(owner),
      );
      expect((retry as Committed<StoredRecord>).duplicate, isTrue);
    },
  );
  test(
    'operator cannot impersonate the same person with owner membership in another company',
    () async {
      final a = await create('a');
      final b = await create('b', 'Company B');
      final staff =
          (await companies.createStaff(
                    context(a, 'staff'),
                    const StaffDraft(name: 'Operator'),
                  )
                  as Committed<StaffRecord>)
              .value;
      await companies.grantCapabilities(
        context(a, 'caps'),
        staff.membershipId,
        {Capability.manageStaff},
      );
      await companies.activateOperator(
        context(a, 'activate'),
        staff.membershipId,
        'operator own secret',
      );
      final foreign = Membership(
        id: 'foreign-owner',
        companyId: b.id,
        personId: staff.personId,
        employeeId: 'foreign-employee',
        owner: true,
        active: true,
        capabilities: Capability.values.toSet(),
        revision: 1,
      );
      final foreignRow = StoredRecord(
        foreign.id,
        b.id,
        'membership',
        1,
        Uint8List.fromList(utf8.encode(jsonEncode(foreign.toJson()))),
      );
      final index = StoredRecord(
        'member-index:${staff.personId}',
        b.id,
        'membershipIndex',
        1,
        Uint8List.fromList(
          utf8.encode(jsonEncode({'membershipId': foreign.id})),
        ),
      );
      await fixture.repo.commit(
        context(b, 'enrollment-fixture'),
        requestDigest: Uint8List(32),
        build: (_) async => Mutation([foreignRow, index], [], [], foreignRow),
      );
      final operator = await companies.unlockOperator(
        a.id,
        staff.membershipId,
        'operator own secret',
      );
      final before = await fixture.repo.watchRevision(b.id).first;
      expect(await companies.readCompany(operator, b.id), isNull);
      expect(
        (await companies.createStaff(
                  context(b, 'impersonate', session: operator),
                  const StaffDraft(name: 'No'),
                )
                as Rejected<StaffRecord>)
            .error,
        CheckError.wrongCompany,
      );
      expect(
        (await companies.grantCapabilities(
                  context(b, 'foreign-grant', session: operator),
                  foreign.id,
                  {Capability.manageStaff},
                )
                as Rejected<Membership>)
            .error,
        CheckError.wrongCompany,
      );
      expect(await fixture.repo.watchRevision(b.id).first, before);
      expect(
        (await companies.createStaff(
          context(a, 'authorized', session: operator),
          const StaffDraft(name: 'Allowed in A'),
        )),
        isA<Committed<StaffRecord>>(),
      );
    },
  );
  test(
    'operator selection survives lock and leaves personal unlock credential intact',
    () async {
      final personId = identity.requireActor(owner).personId;
      final a = await create('operator-company');
      final staff =
          (await companies.createStaff(
                    context(a, 'operator-staff'),
                    const StaffDraft(name: 'Operator'),
                  )
                  as Committed<StaffRecord>)
              .value;
      await companies.activateOperator(
        context(a, 'operator-activate'),
        staff.membershipId,
        'operator own secret',
      );
      identity.lock();
      final choices = await companies.operatorChoices();
      expect(choices.single.membershipId, staff.membershipId);
      expect(choices.single.companyName, a.name);
      await expectLater(
        companies.unlockOperator(
          a.id,
          staff.membershipId,
          'owner passphrase 123',
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.wrongSecret,
          ),
        ),
      );
      final operator = await companies.unlockOperator(
        a.id,
        staff.membershipId,
        'operator own secret',
      );
      expect(identity.requireActor(operator).restrictedCompanyId, a.id);
      identity.lock();
      final personal = await identity.unlock(personId, 'owner passphrase 123');
      expect(identity.requireActor(personal).restrictedCompanyId, isNull);
    },
  );
  test(
    'create replay survives new service and returns the same persisted company',
    () async {
      final a = await create('create');
      expect(a.authorityGenerationId, a.authority.first);
      final certificateBytes = Uint8List.fromList(
        utf8.encode(
          'RAZE_CHECK_AUTHORITY_V1\n${jsonEncode(a.authority.take(6).toList())}',
        ),
      );
      expect(
        await LocalKeyService(fixture.keys).verify(
          certificateBytes,
          base64Url.decode(a.authority.last as String),
          base64Url.decode(a.rootPublicKey),
        ),
        isTrue,
      );

      final replay =
          await companies.createCompany(
                owner,
                CompanyDraft('Company A', 'Asia/Tokyo'),
                'create',
              )
              as Committed<Company>;
      expect(replay.value.id, a.id);
      expect(replay.duplicate, isTrue);
      expect((await companies.listCompanies(owner)).length, 1);
      expect(
        (await fixture.repo.snapshot(CompanyScope(a.id))).authorityHistory,
        hasLength(1),
      );
      expect(
        (await fixture.repo.snapshot(CompanyScope(a.id))).recovery,
        hasLength(1),
      );
      await fixture.reopen();
      companies = LocalCompanyService(
        repository: fixture.repo,
        identity: identity,
        keys: fixture.keys,
        clock: clock,
        ids: SecureIds(),
      );
      expect(
        (await companies.createCompany(
                  owner,
                  CompanyDraft('Company A', 'Asia/Tokyo'),
                  'create',
                )
                as Committed<Company>)
            .value
            .id,
        a.id,
      );
      expect(
        (await companies.createCompany(
                  owner,
                  CompanyDraft('Changed', 'Asia/Tokyo'),
                  'create',
                )
                as Rejected<Company>)
            .error,
        CheckError.duplicateConflict,
      );
    },
  );
  test(
    'staff edits preserve identities; unauthorized commands leave revision unchanged',
    () async {
      final a = await create('a');
      final b = await create('b', 'Company B');
      final staff =
          (await companies.createStaff(
                    context(a, 'staff'),
                    const StaffDraft(name: 'Staff', department: 'Ops'),
                  )
                  as Committed<StaffRecord>)
              .value;
      final edited =
          (await companies.updateStaff(
                    context(a, 'edit'),
                    StaffUpdate(
                      staff.employeeId,
                      const StaffDraft(name: 'Edited'),
                    ),
                  )
                  as Committed<StaffRecord>)
              .value;
      expect(edited.personId, staff.personId);
      expect(edited.membershipId, staff.membershipId);
      await companies.grantCapabilities(
        context(a, 'grant'),
        staff.membershipId,
        {Capability.manageStaff},
      );
      await companies.activateOperator(
        context(a, 'activate'),
        staff.membershipId,
        'staff passphrase 123',
      );
      final operator = await companies.unlockOperator(
        a.id,
        staff.membershipId,
        'staff passphrase 123',
      );
      final before = await fixture.repo.watchRevision(a.id).first;
      expect(
        (await companies.grantCapabilities(
                  context(a, 'selfgrant', session: operator),
                  staff.membershipId,
                  {Capability.manageCompany},
                )
                as Rejected<Membership>)
            .error,
        CheckError.unauthorized,
      );
      expect(await fixture.repo.watchRevision(a.id).first, before);
      expect(await companies.readCompany(operator, b.id), isNull);
      expect(
        (await companies.createStaff(
                  context(b, 'cross', session: operator),
                  const StaffDraft(name: 'Intruder'),
                )
                as Rejected<StaffRecord>)
            .error,
        CheckError.wrongCompany,
      );
      expect(
        (await companies.createCompany(
                  operator,
                  const CompanyDraft('No', 'Asia/Tokyo'),
                  'operator-create',
                )
                as Rejected<Company>)
            .error,
        CheckError.unauthorized,
      );
    },
  );
  test(
    'deactivation preserves membership and person ids and revokes operator',
    () async {
      final a = await create('a');
      final staff =
          (await companies.createStaff(
                    context(a, 'staff'),
                    const StaffDraft(name: 'Manual'),
                  )
                  as Committed<StaffRecord>)
              .value;
      await companies.activateOperator(
        context(a, 'activate'),
        staff.membershipId,
        'staff passphrase 123',
      );
      final deactivated =
          await companies.deactivateStaff(
                context(a, 'deactivate'),
                staff.employeeId,
                'Left company',
              )
              as Committed<Membership>;
      expect(deactivated.value.personId, staff.personId);
      expect(deactivated.value.id, staff.membershipId);
      expect(deactivated.value.active, isFalse);
      expect(
        () => companies.unlockOperator(
          a.id,
          staff.membershipId,
          'staff passphrase 123',
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.revokedCredential,
          ),
        ),
      );
    },
  );
  test('invalid time zones and expired contexts never write', () async {
    expect(
      (await companies.createCompany(
                owner,
                CompanyDraft('Bad', 'JST'),
                'invalid',
              )
              as Rejected<Company>)
          .error,
      CheckError.malformed,
    );
    final a = await create('a');
    final before = await fixture.repo.watchRevision(a.id).first;
    clock.advance(const Duration(minutes: 5));
    expect(
      (await companies.createStaff(
                context(a, 'expired'),
                const StaffDraft(name: 'No'),
              )
              as Rejected<StaffRecord>)
          .error,
      CheckError.locked,
    );
    expect(await fixture.repo.watchRevision(a.id).first, before);
  });
}

class GatedCipher implements PayloadCipher {
  GatedCipher(this.delegate, {this.openRecordId});
  final String? openRecordId;
  final PayloadCipher delegate;
  final entered = Completer<void>(), release = Completer<void>();
  bool gated = false;
  @override
  Future<Uint8List> seal({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List plain,
  }) async {
    if (!gated && openRecordId == null) {
      gated = true;
      entered.complete();
      await release.future;
    }
    return delegate.seal(
      scopeId: scopeId,
      recordId: recordId,
      revision: revision,
      plain: plain,
    );
  }

  @override
  Future<Uint8List> open({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List sealed,
  }) async {
    final plain = await delegate.open(
      scopeId: scopeId,
      recordId: recordId,
      revision: revision,
      sealed: sealed,
    );
    if (!gated && recordId == openRecordId) {
      gated = true;
      entered.complete();
      await release.future;
    }
    return plain;
  }
}
