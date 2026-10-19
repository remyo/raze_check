import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:raze_check_local/src/recovery/archive_records.dart';
import 'support/repository_fixture.dart';

void main() {
  test(
    'passive profile overlap disjoint union and replay retain names; conflicting key rolls back all additions',
    () async {
      final f = await RepositoryFixture.open();
      addTearDown(f.dispose);
      const person = 'person';
      await VaultKeys(f.keys).create(person);
      Map<String, dynamic> profile(String name, List<List<String>> keys) => {
        'version': 1,
        'personId': person,
        'displayName': name,
        'installations': keys,
      };
      final oldKey = base64UrlEncode(List.filled(32, 1)),
          newKey = base64UrlEncode(List.filled(32, 2));
      final bytes = ArchiveRecords().finish();
      await f.repo.importArchive(
        bytes,
        archiveId: 'first',
        beforeCommit: () {},
        profiles: [
          profile('Original', [
            ['old', oldKey],
          ]),
        ],
      );
      await f.repo.importArchive(
        bytes,
        archiveId: 'second',
        beforeCommit: () {},
        profiles: [
          profile('Different description', [
            ['old', oldKey],
            ['new', newKey],
          ]),
        ],
      );
      expect(
        (await f.repo.passiveProfiles()).single,
        profile('Original', [
          ['old', oldKey],
          ['new', newKey],
        ]),
      );
      expect(
        await f.repo.importArchive(
          bytes,
          archiveId: 'second',
          beforeCommit: () {},
          profiles: [
            profile('Different description', [
              ['old', oldKey],
              ['new', newKey],
            ]),
          ],
        ),
        isFalse,
      );
      final before = await f.repo.passiveProfiles();
      await expectLater(
        f.repo.importArchive(
          bytes,
          archiveId: 'conflict',
          beforeCommit: () {},
          profiles: [
            profile('Ignored', [
              ['another', newKey],
              ['old', newKey],
            ]),
          ],
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.duplicateConflict,
          ),
        ),
      );
      expect(await f.repo.passiveProfiles(), before);
      expect(await f.repo.hasRestoreCommit('conflict'), isFalse);
    },
  );
}
