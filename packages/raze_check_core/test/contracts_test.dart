import 'package:raze_check_core/raze_check_core.dart';
import 'package:test/test.dart';

final uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  test('IDs are distinct UUIDv4 strings', () {
    final ids = SecureIds();
    expect(ids.next(), matches(uuidV4Pattern));
    expect(ids.next(), isNot(ids.next()));
  });

  test(
    'result variants preserve committed duplicate and conflict distinctions',
    () {
      final CommandResult<String> saved = Committed('event', 7, false);
      final CommandResult<String> retry = Committed('event', 7, true);
      final CommandResult<String> stale = VersionConflict(9);
      final CommandResult<String> rejected = Rejected(
        CheckError.duplicateConflict,
      );

      String outcome(CommandResult<String> result) => switch (result) {
        Committed(:final value, :final revision, :final duplicate) =>
          '$value:$revision:$duplicate',
        VersionConflict(:final currentRevision) => 'conflict:$currentRevision',
        Rejected(:final error) => 'rejected:${error.name}',
      };

      expect(outcome(saved), 'event:7:false');
      expect(outcome(retry), 'event:7:true');
      expect(outcome(stale), 'conflict:9');
      expect(outcome(rejected), 'rejected:duplicateConflict');
    },
  );

  test('system clock supplies UTC instants', () {
    final before = DateTime.now().toUtc();
    final instant = SystemCheckClock().nowUtc();
    final after = DateTime.now().toUtc();
    expect(instant.isUtc, isTrue);
    expect(instant.isBefore(before), isFalse);
    expect(instant.isAfter(after), isFalse);
  });

  test('check exceptions retain the domain error code', () {
    expect(
      () => throw CheckException(CheckError.locked),
      throwsA(
        isA<CheckException>().having((e) => e.code, 'code', CheckError.locked),
      ),
    );
  });
}
