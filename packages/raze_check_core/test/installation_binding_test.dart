import 'dart:typed_data';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'adopted personal actor only exposes explicitly authorized companies',
    () {
      final actor = ActorIdentity(
        personId: 'same-person',
        installationId: 'fresh',
        signingKeyId: 'key',
        publicKey: Uint8List(32),
        authorizedCompanyIds: {'A'},
      );
      expect(() => actor.requireCompany('A'), returnsNormally);
      expect(
        () => actor.requireCompany('B'),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.unauthorized,
          ),
        ),
      );
    },
  );
}
