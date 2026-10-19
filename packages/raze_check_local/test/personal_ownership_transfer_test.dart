import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'support/repository_fixture.dart';

void main() {
  late RepositoryFixture f;
  setUp(() async {
    f = await RepositoryFixture.open();
    final row = f.record('staff');
    await f.repo.commit(
      f.context('create'),
      requestDigest: f.digest(),
      build: (_) async => Mutation(
        [row],
        [],
        [],
        row,
        personalRecords: [
          const PersonalRecordAssociation('placeholder', 'staff'),
        ],
      ),
    );
  });
  tearDown(() => f.dispose());
  test(
    'ownership transfer and its replay preserve only the chosen personal owner',
    () async {
      var builds = 0;
      Future<CommandResult<StoredRecord>> transfer() => f.repo.commit(
        f.context('link'),
        requestDigest: f.digest(2),
        build: (_) async {
          builds++;
          final row = f.record('staff', revision: 2, body: 'linked person');
          return Mutation(
            [row],
            [],
            [],
            row,
            removePersonalRecords: [
              const PersonalRecordAssociation('placeholder', 'staff'),
            ],
            personalRecords: [
              const PersonalRecordAssociation('real-person', 'staff'),
            ],
          );
        },
      );
      expect(await transfer(), isA<Committed<StoredRecord>>());
      expect((await transfer() as Committed<StoredRecord>).duplicate, isTrue);
      expect(builds, 1);
      expect(
        (await f.repo.snapshot(const PersonalScope('placeholder'))).records,
        isEmpty,
      );
      expect(
        (await f.repo.snapshot(
          const PersonalScope('real-person'),
        )).records.single.id,
        'staff',
      );
    },
  );
  test(
    'failed acceptance rolls back record update and personal ownership together',
    () async {
      final result = await f.repo.commit(
        f.context('link'),
        requestDigest: f.digest(2),
        build: (_) async => Mutation(
          [f.record('staff', revision: 2)],
          [],
          [],
          f.record('staff'),
          removePersonalRecords: [
            const PersonalRecordAssociation('placeholder', 'staff'),
          ],
          personalRecords: [
            const PersonalRecordAssociation('real-person', 'staff'),
          ],
        ),
        beforeCommit: () => throw const CheckException(CheckError.locked),
      );
      expect((result as Rejected<StoredRecord>).error, CheckError.locked);
      expect(
        (await f.repo.snapshot(
          const PersonalScope('placeholder'),
        )).records.single.revision,
        1,
      );
      expect(
        (await f.repo.snapshot(const PersonalScope('real-person'))).records,
        isEmpty,
      );
    },
  );
  test(
    'cross-company ownership removals reject and leave prior owner intact',
    () async {
      final result = await f.repo.commit(
        f.context('link'),
        requestDigest: f.digest(2),
        build: (_) async => Mutation(
          [],
          [],
          [],
          f.record('staff'),
          removePersonalRecords: [
            const PersonalRecordAssociation(
              'placeholder',
              'staff',
              companyId: 'company-b',
            ),
          ],
        ),
      );
      expect((result as Rejected<StoredRecord>).error, CheckError.wrongCompany);
      expect(
        (await f.repo.snapshot(const PersonalScope('placeholder'))).records,
        hasLength(1),
      );
    },
  );
}
