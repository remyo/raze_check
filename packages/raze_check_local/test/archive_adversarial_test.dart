import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/src/recovery/archive_codec.dart';
import 'package:raze_check_local/src/recovery/archive_records.dart';

void main() {
  Uint8List zip() {
    final a = Archive();
    for (final n in ['manifest.json', 'records.json', 'recovery.json']) {
      a.addFile(ArchiveFile(n, 2, [123, 125]));
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  int central(Uint8List bytes) =>
      ByteData.sublistView(bytes).getUint32(bytes.length - 6, Endian.little);
  test(
    'ZIP preflight rejects duplicate names, symlink, directory, expansion, inconsistent sizes, methods, offset and CRC',
    () {
      final original = zip();
      expect(ArchiveCodec.decodeZip(original).length, 3);
      final c = central(original);
      final cases = <void Function(Uint8List)>[
        (b) => ByteData.sublistView(
          b,
        ).setUint32(c + 38, 0xa1ff0000, Endian.little),
        (b) => ByteData.sublistView(b).setUint32(c + 38, 0x10, Endian.little),
        (b) => ByteData.sublistView(
          b,
        ).setUint32(c + 24, 9 * 1024 * 1024, Endian.little),
        (b) => ByteData.sublistView(b).setUint16(c + 10, 99, Endian.little),
        (b) => ByteData.sublistView(b).setUint32(c + 42, 5, Endian.little),
        (b) => ByteData.sublistView(b).setUint32(c + 16, 0, Endian.little),
        (b) => b[30] = 46,
        (b) => ByteData.sublistView(
          b,
        ).setUint16(b.length - 12, 10001, Endian.little),
      ];
      for (final mutate in cases) {
        final b = Uint8List.fromList(original);
        mutate(b);
        expect(() => ArchiveCodec.decodeZip(b), throwsA(isA<CheckException>()));
      }
      final d = zip(), first = central(original);
      final third =
          first + 46 + 'manifest.json'.length + 46 + 'records.json'.length;
      final local = ByteData.sublistView(
        d,
      ).getUint32(third + 42, Endian.little);
      d.setRange(third + 46, third + 46 + 13, 'manifest.json'.codeUnits);
      d.setRange(local + 30, local + 43, 'manifest.json'.codeUnits);
      expect(() => ArchiveCodec.decodeZip(d), throwsA(isA<CheckException>()));
    },
  );
  test(
    'references cannot expand a small payload table beyond 64 MiB',
    () async {
      final raw = Uint8List(1024 * 1024),
          hash = base64UrlEncode(
            (await Sha256().hash(Uint8List(1024 * 1024))).bytes,
          );
      final out = StringBuffer('[[1]\n');
      void line(Object v) => out.writeln(',${jsonEncode(v)}');
      line(['s', 'company']);
      line(['s', 'kind']);
      line(['s', 'entity']);
      line(['p', hash, base64UrlEncode(raw)]);
      for (var i = 0; i < 65; i++) {
        line(['s', 'row$i']);
        line(['r', i + 3, 0, 1, 1, 0]);
        line(['e', 2, i]);
      }
      out.write(']');
      await expectLater(
        ArchiveRecords.read(
          Uint8List.fromList(utf8.encode(out.toString())),
          (_, _) async {},
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'limit',
            CheckError.limitExceeded,
          ),
        ),
      );
    },
  );
  test(
    'unused table payloads and rows cannot smuggle out of scope recovery bytes',
    () async {
      final raw = Uint8List.fromList([1, 2, 3]),
          hash = base64UrlEncode((await Sha256().hash([1, 2, 3])).bytes);
      final bytes = utf8.encode(
        '[[1]\n,${jsonEncode(['p', hash, base64UrlEncode(raw)])}\n]',
      );
      await expectLater(
        ArchiveRecords.read(Uint8List.fromList(bytes), (_, _) async {}),
        throwsA(isA<CheckException>()),
      );
    },
  );
}
