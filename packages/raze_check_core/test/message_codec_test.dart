import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:test/test.dart';
import 'support/check_matchers.dart';

void main() {
  final codec = MessageCodec();
  Uint8List wire(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));
  final fixtures = Directory('test/fixtures/messages');

  test(
    'every reviewed v1 kind retains exact transport and signed payload bytes',
    () {
      final files = fixtures
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(files.length, greaterThanOrEqualTo(11));
      final kinds = <MessageKind>{};
      for (final file in files) {
        final bytes = file.readAsBytesSync();
        final message = codec.decode(bytes, maxBytes: MessageLimits.fileBytes);
        kinds.add(message.kind);
        expect(codec.encode(message), orderedEquals(bytes), reason: file.path);
        final reconstructed = SignedMessage(
          kind: message.kind,
          keyId: message.keyId,
          payloadBytes: message.payloadBytes,
          signature: message.signature,
        );
        expect(
          codec.encode(reconstructed),
          orderedEquals(bytes),
          reason: 'new encoder ${file.path}',
        );
        expect(
          message.payloadBytes,
          orderedEquals(
            base64Url.decode(
              (jsonDecode(utf8.decode(bytes)) as List)[3] as String,
            ),
          ),
        );
      }
      expect(kinds, containsAll(MessageKind.values));
    },
  );

  test('rejects unknown versions and kinds before payload dispatch', () {
    expect(
      () => codec.decode(wire([2, 'attendance', '', '', '']), maxBytes: 65536),
      throwsCheckError(CheckError.unsupportedVersion),
    );
    expect(
      () =>
          codec.decode(wire([1, 'locationProof', '', '', '']), maxBytes: 65536),
      throwsCheckError(CheckError.unsupportedVersion),
    );
  });

  test('rejects oversized input before attempting JSON work', () {
    expect(
      () => codec.decode(Uint8List(1501), maxBytes: 1500),
      throwsCheckError(CheckError.limitExceeded),
    );
    expect(
      () => codec.decode(Uint8List(65537), maxBytes: 999999),
      throwsCheckError(CheckError.limitExceeded),
    );
  });

  test('rejects truncated UTF8 JSON, extra fields and invalid base64', () {
    for (final bytes in [
      Uint8List.fromList([0xff]),
      wire({}),
      wire([1]),
      wire([1, 'attendance', 'x', '?', '?']),
      wire([1, 'attendance', 'x', '', '', null]),
      Uint8List.fromList(utf8.encode('[1,')),
    ]) {
      expect(
        () => codec.decode(bytes, maxBytes: 65536),
        throwsCheckError(CheckError.malformed),
      );
    }
  });

  test(
    'payload registry rejects every field with wrong type or extra field',
    () {
      for (final file in fixtures.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.json'),
      )) {
        final outer = jsonDecode(file.readAsStringSync()) as List;
        final payload =
            jsonDecode(utf8.decode(base64Url.decode(outer[3] as String)))
                as List;
        for (var i = 0; i < payload.length; i++) {
          final changed = List<Object?>.of(payload)..[i] = {'unexpected': true};
          final bad = List<Object?>.of(outer)
            ..[3] = base64UrlEncode(utf8.encode(jsonEncode(changed)));
          expect(
            () => codec.decode(wire(bad), maxBytes: 65536),
            throwsCheckError(CheckError.malformed),
            reason: '${file.path} field $i',
          );
        }
        final bad = List<Object?>.of(outer)
          ..[3] = base64UrlEncode(utf8.encode(jsonEncode([...payload, null])));
        expect(
          () => codec.decode(wire(bad), maxBytes: 65536),
          throwsCheckError(CheckError.malformed),
        );
      }
    },
  );
  test(
    'preserves noncanonical JSON whitespace across codec instances and buffer mutations',
    () {
      final original = File(
        'test/fixtures/messages/attendance.json',
      ).readAsBytesSync();
      final padded = Uint8List.fromList([
        ...utf8.encode(' \n'),
        ...original,
        32,
      ]);
      final expected = Uint8List.fromList(padded);
      final message = codec.decode(padded, maxBytes: 65536);
      padded[0] = 0;
      message.payloadBytes[0] = 0;
      message.signature[0] = 0;
      final output = MessageCodec().encode(message);
      expect(output, orderedEquals(expected));
      output[0] = 0;
      expect(MessageCodec().encode(message), orderedEquals(expected));
    },
  );

  test(
    'QR final UTF8 gate accepts 1500 and preserves file fallback at 1501',
    () {
      final fixture = File(
        'test/fixtures/messages/attendance.json',
      ).readAsBytesSync();
      for (final length in [1500, 1501, 65536]) {
        final bytes = Uint8List.fromList([
          ...fixture,
          ...List.filled(length - fixture.length, 32),
        ]);
        final message = codec.decode(bytes, maxBytes: 65536);
        expect(codec.fitsQr(message), length <= 1500);
        expect(codec.encode(message), orderedEquals(bytes));
      }
    },
  );

  test(
    'numeric and scalar bounds reject overflow, floats and malformed strings',
    () {
      final outer =
          jsonDecode(
                File(
                  'test/fixtures/messages/attendance.json',
                ).readAsStringSync(),
              )
              as List;
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(outer[3] as String))) as List;
      for (final entry in <(int, Object?)>[
        (0, 'not-a-uuid'),
        (2, 8640000000000001),
        (2, -8640000000000001),
        (2, 1.5),
        (6, 0),
        (6, 9007199254740992),
        (10, 841),
        (10, -841),
        (14, 'gps'),
      ]) {
        final changed = List<Object?>.of(payload)..[entry.$1] = entry.$2;
        final bad = List<Object?>.of(outer)
          ..[3] = base64UrlEncode(utf8.encode(jsonEncode(changed)));
        expect(
          () => codec.decode(wire(bad), maxBytes: 65536),
          throwsCheckError(CheckError.malformed),
        );
      }
    },
  );

  test(
    'requires canonical padded base64url, exact key/hash/signature lengths',
    () {
      final original =
          jsonDecode(
                File(
                  'test/fixtures/messages/invitation.json',
                ).readAsStringSync(),
              )
              as List;
      for (final index in [3, 4]) {
        for (final value in ['?', 'YQ', 'YR==', '+/8=', 'YQ==']) {
          final outer = List<Object?>.of(original)..[index] = value;
          expect(
            () => codec.decode(wire(outer), maxBytes: 65536),
            throwsCheckError(CheckError.malformed),
          );
        }
      }
      for (final key in [
        'signing:00000000-0000-4000-8000-000000000001',
        'ed25519:abc',
        '${original[2]}=',
      ]) {
        final bad = List<Object?>.of(original)..[2] = key;
        expect(
          () => codec.decode(wire(bad), maxBytes: 65536),
          throwsCheckError(CheckError.malformed),
        );
      }
    },
  );

  test(
    'certificate registry rejects unknown fields, types and invalid parent/sequence',
    () {
      final original =
          jsonDecode(
                File(
                  'test/fixtures/messages/invitation.json',
                ).readAsStringSync(),
              )
              as List;
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(original[3] as String)))
              as List;
      final certificate = payload[7] as List;
      final invalid = <List<Object?>>[
        [...certificate, null],
        for (var i = 0; i < 7; i++) List<Object?>.of(certificate)..[i] = {},
        List<Object?>.of(certificate)..[2] = 2,
        List<Object?>.of(certificate)..[1] = certificate[0],
      ];
      for (final cert in invalid) {
        final p = List<Object?>.of(payload)..[7] = cert;
        final bad = List<Object?>.of(original)
          ..[3] = base64UrlEncode(utf8.encode(jsonEncode(p)));
        expect(
          () => codec.decode(wire(bad), maxBytes: 65536),
          throwsCheckError(CheckError.malformed),
        );
      }
    },
  );
  test(
    'checked compact limits fit QR and long signed content requires intact file export',
    () {
      for (final kind in MessageKind.values) {
        final compact = File(
          'test/fixtures/messages/${kind.name}.compact.json',
        ).readAsBytesSync();
        expect(codec.fitsQr(codec.decode(compact, maxBytes: 1500)), isTrue);
        final maximum = File(
          'test/fixtures/messages/${kind.name}.max.json',
        ).readAsBytesSync();
        final message = codec.decode(maximum, maxBytes: 65536);
        expect(codec.encode(message), orderedEquals(maximum));
        if ([
          MessageKind.membershipGrant,
          MessageKind.attendanceDecision,
          MessageKind.correctionRequest,
        ].contains(kind)) {
          expect(codec.fitsQr(message), isFalse);
          expect(
            () => codec.decode(maximum, maxBytes: 1500),
            throwsCheckError(CheckError.limitExceeded),
          );
        }
      }
    },
  );

  test('Unicode limits count scalars and never silently shorten content', () {
    final original =
        jsonDecode(
              File(
                'test/fixtures/messages/joinRequest.json',
              ).readAsStringSync(),
            )
            as List;
    final payload =
        jsonDecode(utf8.decode(base64Url.decode(original[3] as String)))
            as List;
    for (final size in [120, 121]) {
      final p = List<Object?>.of(payload)..[5] = '😀' * size;
      final outer = List<Object?>.of(original)
        ..[3] = base64UrlEncode(utf8.encode(jsonEncode(p)));
      if (size == 120) {
        final message = codec.decode(wire(outer), maxBytes: 65536);
        expect(message.payload.field<String>('displayName').runes.length, 120);
      } else {
        expect(
          () => codec.decode(wire(outer), maxBytes: 65536),
          throwsCheckError(CheckError.malformed),
        );
      }
    }
    for (final text in ['', String.fromCharCode(0xd800)]) {
      final p = List<Object?>.of(payload)..[5] = text;
      final outer = List<Object?>.of(original)
        ..[3] = base64UrlEncode(utf8.encode(jsonEncode(p)));
      expect(
        () => codec.decode(wire(outer), maxBytes: 65536),
        throwsCheckError(CheckError.malformed),
      );
    }
  });

  test(
    'rejects deep nesting before decoder recursion and checks constructed file size',
    () {
      final nested = Uint8List.fromList(
        utf8.encode('${'[' * 1000}${']' * 1000}'),
      );
      expect(
        () => codec.decode(nested, maxBytes: 65536),
        throwsCheckError(CheckError.malformed),
      );
      final fixture = codec.decode(
        File('test/fixtures/messages/attendance.json').readAsBytesSync(),
        maxBytes: 65536,
      );
      final expandedPayload = Uint8List.fromList([
        ...fixture.payloadBytes,
        ...List.filled(50000, 32),
      ]);
      final message = SignedMessage(
        kind: fixture.kind,
        keyId: fixture.keyId,
        payloadBytes: expandedPayload,
        signature: fixture.signature,
      );
      expect(
        () => codec.encode(message),
        throwsCheckError(CheckError.limitExceeded),
      );
    },
  );

  test(
    'reason and compact invitation label bounds accept exact limit and reject excess',
    () {
      for (final entry in [
        (MessageKind.invitation, 3, 40),
        (MessageKind.attendanceDecision, 8, 500),
      ]) {
        final outer =
            jsonDecode(
                  File(
                    'test/fixtures/messages/${entry.$1.name}.json',
                  ).readAsStringSync(),
                )
                as List;
        final payload =
            jsonDecode(utf8.decode(base64Url.decode(outer[3] as String)))
                as List;
        for (final size in [entry.$3, entry.$3 + 1]) {
          final p = List<Object?>.of(payload)..[entry.$2] = '😀' * size;
          final changed = List<Object?>.of(outer)
            ..[3] = base64UrlEncode(utf8.encode(jsonEncode(p)));
          if (size == entry.$3) {
            expect(codec.decode(wire(changed), maxBytes: 65536).kind, entry.$1);
          } else {
            expect(
              () => codec.decode(wire(changed), maxBytes: 65536),
              throwsCheckError(CheckError.malformed),
            );
          }
        }
      }
    },
  );
}
