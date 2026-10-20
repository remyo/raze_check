import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/temp_paths.dart';

GuideProgressSnapshot progress({bool dismissed = true}) =>
    GuideProgressSnapshot(
      welcomeDismissed: dismissed,
      entries: [
        GuideProgress(
          guideId: 'attendance',
          variantId: 'worker',
          contentRevision: 1,
          stepId: 'choose-punch',
          viewed: true,
          invitationDismissed: true,
        ),
      ],
    );
void main() {
  late AppPaths paths;
  late File file;
  setUp(() async {
    paths = await tempPaths();
    file = File('${paths.root.path}/guide-progress.v1.json');
  });
  tearDown(() async {
    await paths.root.delete(recursive: true);
  });
  test(
    'fresh, ordered concurrent writes, flush and reopen preserve business files',
    () async {
      final databaseBytes = [1, 2, 3];
      final originalBytes = [4, 5, 6];
      await paths.database.writeAsBytes(databaseBytes);
      await paths.catalog.writeAsBytes(originalBytes);
      final store = LocalGuideProgressStore(paths: paths);
      expect((await store.read()).entries, isEmpty);
      final writes = [
        store.write(progress(dismissed: false)),
        store.write(progress()),
      ];
      await store.flush();
      await Future.wait(writes);
      final snapshot = await LocalGuideProgressStore(paths: paths).read();
      expect(snapshot.welcomeDismissed, isTrue);
      expect(snapshot.entries.single.stepId, 'choose-punch');
      expect(snapshot.entries.single.viewed, isTrue);
      expect(snapshot.entries.single.invitationDismissed, isTrue);
      expect(await paths.catalog.readAsBytes(), originalBytes);
      expect(await paths.database.readAsBytes(), databaseBytes);
      expect((await file.readAsBytes()).length, lessThanOrEqualTo(65536));
    },
  );
  test(
    'interrupted temporary file never replaces main or fresh state',
    () async {
      final store = LocalGuideProgressStore(paths: paths);
      await store.write(progress());
      await File('${file.path}.tmp').writeAsString('interrupted');
      expect(
        (await LocalGuideProgressStore(paths: paths).read()).welcomeDismissed,
        isTrue,
      );
      await file.delete();
      expect(
        (await LocalGuideProgressStore(paths: paths).read()).entries,
        isEmpty,
      );
    },
  );
  for (final source in [
    '{',
    '{"version":2}',
    'x' * 65537,
    '{"version":1,"welcomeDismissed":1,"entries":[]}',
    '{"version":1,"entries":[{"guideId":"BAD","variantId":"worker","contentRevision":1}]}',
  ]) {
    test(
      'invalid input remains untouched and disables writes (${source.length})',
      () async {
        await file.writeAsString(source);
        final bytes = await file.readAsBytes();
        final store = LocalGuideProgressStore(paths: paths);
        await expectLater(store.read(), throwsA(anything));
        await expectLater(store.write(progress()), throwsA(anything));
        expect(await file.readAsBytes(), bytes);
      },
    );
  }
  test('write before read protects unsupported source', () async {
    await file.writeAsString('{"version":2}');
    await expectLater(
      LocalGuideProgressStore(paths: paths).write(progress()),
      throwsA(anything),
    );
    expect(await file.readAsString(), '{"version":2}');
  });
  test(
    'rejects oversized output and entry count without replacing main',
    () async {
      final store = LocalGuideProgressStore(paths: paths);
      await store.write(progress());
      final bytes = await file.readAsBytes();
      for (final snapshot in [
        GuideProgressSnapshot(
          entries: [
            GuideProgress(
              guideId: 'x' * 65536,
              variantId: 'worker',
              contentRevision: 1,
            ),
          ],
        ),
        GuideProgressSnapshot(
          entries: List.generate(
            65,
            (i) => GuideProgress(
              guideId: 'guide-$i',
              variantId: 'worker',
              contentRevision: 1,
            ),
          ),
        ),
      ]) {
        await expectLater(store.write(snapshot), throwsA(anything));
        expect(await file.readAsBytes(), bytes);
      }
    },
  );
  test('ignores unknown fields and does not retain them', () async {
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'welcomeDismissed': false,
        'entries': [],
        'unknown': 'discard',
      }),
    );
    final store = LocalGuideProgressStore(paths: paths);
    await store.write(await store.read());
    expect(jsonDecode(await file.readAsString()), isNot(contains('unknown')));
  });
  test('unavailable storage surfaces errors', () async {
    final blocker = File('${paths.root.path}/blocker');
    await blocker.writeAsString('x');
    final store = LocalGuideProgressStore(
      paths: AppPaths(Directory('${blocker.path}/child')),
    );
    await expectLater(store.read(), throwsA(anything));
    await expectLater(store.write(progress()), throwsA(anything));
  });
}
