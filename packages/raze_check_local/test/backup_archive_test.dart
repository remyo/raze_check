import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/src/recovery/archive_codec.dart';

void main() {
  const pass = 'correct archive passphrase';
  final files = <String, Uint8List>{
    'manifest.json': Uint8List.fromList([123, 125]),
    'records.json': Uint8List.fromList([91, 93]),
    'recovery.json': Uint8List.fromList([123, 125]),
    'attachments/${'a' * 64}': Uint8List.fromList([0, 255, 13, 10, 80, 78, 71]),
  };
  late Uint8List sealed;
  setUpAll(() async {
    sealed = await ArchiveCodec.seal(files, pass);
  });
  test('header and actual binary attachment roundtrip', () async {
    expect(sealed.take(8), 'RZCKBK01'.codeUnits);
    final result = await ArchiveCodec.open(sealed, pass);
    expect(result.keys.toSet(), files.keys.toSet());
    for (final key in files.keys) {
      expect(result[key], files[key]);
    }
  });
  test('wrong password and tampering fail authentication', () async {
    for (final bytes in [sealed, Uint8List.fromList(sealed)..[55] ^= 1]) {
      await expectLater(
        ArchiveCodec.open(bytes, 'wrong archive passphrase'),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.invalidSignature,
          ),
        ),
      );
    }
  });
  test(
    'rejects truncated header, ciphertext, version and attacker KDF before derivation',
    () async {
      for (final bytes in [
        Uint8List(12),
        Uint8List.fromList(sealed.sublist(0, sealed.length - 1)),
        Uint8List.fromList(sealed)..[8] = 2,
        Uint8List.fromList(sealed)..[40] = 1,
      ]) {
        await expectLater(
          ArchiveCodec.open(bytes, pass),
          throwsA(isA<CheckException>()),
        );
      }
    },
  );
  test(
    'unsafe and unexpected zip names rejected by writer and preflight',
    () async {
      for (final name in [
        '../records.json',
        '/records.json',
        'attachments/link',
        'extra.json',
      ]) {
        await expectLater(
          ArchiveCodec.seal({...files, name: Uint8List(0)}, pass),
          throwsA(isA<CheckException>()),
        );
      }
    },
  );
}
