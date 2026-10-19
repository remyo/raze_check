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
