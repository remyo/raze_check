import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:raze_check/app/local_composition.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../packages/raze_check_local/test/support/memory_key_store.dart';
import '../packages/raze_check_local/test/support/temp_paths.dart';
import '../packages/raze_check_local/test/support/repository_fixture.dart'
    show RepositorySession;

void main() {
  test(
    'real composition persists companies and independent operator unlock across reopen',
    () async {
      final paths = await tempPaths();
      addTearDown(() => paths.root.delete(recursive: true));
      final keys = MemoryKeyStore();
      var services = await LocalComposition.open(
        paths: paths,
        secureKeys: keys,
      );
      final session = await services.identity.createProfile(
        'Owner',
        'owner passphrase 123',
      );
      final company =
          (await services.companies.createCompany(
                    session,
                    const CompanyDraft('Composed company', 'Asia/Tokyo'),
                    'create-company',
                  )
                  as Committed<Company>)
              .value;
      CommandContext context(String op) => CommandContext(
        companyId: company.id,
        session: session,
        operationId: op,
        authorityGenerationId: company.authorityGenerationId,
      );
      final staff =
          (await services.companies.createStaff(
                    context('staff'),
                    const StaffDraft(name: 'Local operator'),
                  )
                  as Committed<StaffRecord>)
              .value;
      await services.companies.grantCapabilities(
        context('grant'),
        staff.membershipId,
        {Capability.manageStaff},
      );
      await services.companies.activateOperator(
        context('activate'),
        staff.membershipId,
        'operator passphrase 123',
      );
      await services.close();
      services = await LocalComposition.open(paths: paths, secureKeys: keys);
      addTearDown(services.close);
      expect(
        (await services.companies.operatorChoices()).single.displayName,
        'Local operator',
      );
      final operator = await services.companies.unlockOperator(
        company.id,
        staff.membershipId,
        'operator passphrase 123',
      );
      expect(
        services.identity.requireActor(operator).restrictedCompanyId,
        company.id,
      );
      expect(
        (await services.companies.listCompanies(operator)).single.id,
        company.id,
      );
      expect(
        (await services.companies.listStaff(operator, company.id)).length,
        2,
      );
    },
  );
  test(
    'standalone composition opens the real persistent repository with shared vault keys',
    () async {
      final paths = await tempPaths();
      addTearDown(() => paths.root.delete(recursive: true));
      final store = MemoryKeyStore();
      var services = await LocalComposition.open(
        paths: paths,
        secureKeys: store,
      );
      await services.vaultKeys.create('company-a');
      final context = CommandContext(
        companyId: 'company-a',
        session: RepositorySession(),
        operationId: 'op',
        authorityGenerationId: 'authority',
      );
      final row = StoredRecord(
        'row',
        'company-a',
        'example',
        1,
        Uint8List.fromList([1, 2, 3]),
      );
      expect(
        await services.repository.commit(
          context,
          requestDigest: Uint8List(32),
          build: (_) async => Mutation([row], [], [], row),
        ),
        isA<Committed<StoredRecord>>(),
      );
      await services.close();
      services = await LocalComposition.open(paths: paths, secureKeys: store);
      addTearDown(services.close);
      expect((await services.repository.read('company-a', 'row'))!.payload, [
        1,
        2,
        3,
      ]);
    },
  );
}
