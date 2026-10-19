import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:test/test.dart';
import 'support/message_vectors.dart';
import 'support/check_matchers.dart';

void main() {
  late MessageVectors v;
  late String fingerprint;
  setUp(() async {
    v = await MessageVectors.create();
    fingerprint = (await Sha256().hash(
      v.root,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  });
  Uint8List file(List<List<Object?>> certs, {String? company, String? root}) =>
      jsonBytes([
        'RAZE_CHECK_AUTHORITY_HISTORY',
        1,
        company ?? id(1),
        root ?? fingerprint,
        certs,
      ]);
  test(
    'three missing generations verify without intermediate envelopes; historical receipt survives',
    () async {
      final third = await v.certificate(
        id(40),
        id(4),
        3,
        id(41),
        v.next,
        MessageVectors.timestamp,
      );
      final fourth = await v.certificate(
        id(42),
        id(40),
        4,
        id(43),
        v.next,
        MessageVectors.timestamp,
      );
      final chain = await AuthorityHistoryFile.decode(
        file([v.nextAuthority, third, fourth]),
      ).verify(v.keys, v.trust);
      expect(chain.map((a) => a.sequence), [1, 2, 3, 4]);
      final receipt = await v.signed(
        MessageKind.attendance,
        v.payload(MessageKind.attendance),
      );
      expect(
        (await MessageVerifier(v.keys).verify(
          receipt,
          TrustContext(
            companyId: id(1),
            rootPublicKey: v.root,
            authorities: chain,
            credentials: v.trust.credentials,
          ),
        )).message.payload.messageId,
        id(14),
      );
      expect(v.trust.authorities, hasLength(1));
    },
  );
  test('exact duplicate certificates are idempotent', () async {
    final chain = await AuthorityHistoryFile.decode(
      file([v.authority, v.nextAuthority, v.nextAuthority]),
    ).verify(v.keys, v.trust);
    expect(chain, hasLength(2));
  });
  test(
    'wrong company, wrong root, invalid signature and missing parent reject',
    () async {
      await expectLater(
        AuthorityHistoryFile.decode(
          file([v.authority], company: id(99)),
        ).verify(v.keys, v.trust),
        throwsCheckError(CheckError.wrongCompany),
      );
      await expectLater(
        AuthorityHistoryFile.decode(
          file([v.authority], root: '0' * 64),
        ).verify(v.keys, v.trust),
        throwsCheckError(CheckError.invalidSignature),
      );
      final bad = [...v.nextAuthority]..[6] = base64UrlEncode(Uint8List(64));
      await expectLater(
        AuthorityHistoryFile.decode(file([bad])).verify(v.keys, v.trust),
        throwsCheckError(CheckError.invalidSignature),
      );
      final third = await v.certificate(
        id(40),
        id(4),
        3,
        id(41),
        v.next,
        MessageVectors.timestamp,
      );
      await expectLater(
        AuthorityHistoryFile.decode(
          file([third, v.nextAuthority]),
        ).verify(v.keys, v.trust),
        throwsCheckError(CheckError.unknownIssuer),
      );
    },
  );
  test('signed sequence gap and time rollback reject', () async {
    for (final cert in [
      await v.certificate(
        id(40),
        id(2),
        3,
        id(41),
        v.next,
        MessageVectors.timestamp,
      ),
      await v.certificate(
        id(40),
        id(2),
        2,
        id(41),
        v.next,
        MessageVectors.timestamp - 2000,
      ),
    ]) {
      await expectLater(
        AuthorityHistoryFile.decode(file([cert])).verify(v.keys, v.trust),
        throwsCheckError(CheckError.invalidTransition),
      );
    }
  });
  test(
    'siblings and same-ID conflicting definitions reject without choosing a head',
    () async {
      final sibling = await v.certificate(
        id(40),
        id(2),
        2,
        id(41),
        v.next,
        MessageVectors.timestamp,
      );
      await expectLater(
        AuthorityHistoryFile.decode(
          file([v.nextAuthority, sibling]),
        ).verify(v.keys, v.trust),
        throwsCheckError(CheckError.recoveryRequired),
      );
      final conflict = await v.certificate(
        id(2),
        null,
        1,
        id(41),
        v.next,
        MessageVectors.timestamp,
      );
      await expectLater(
        AuthorityHistoryFile.decode(file([conflict])).verify(v.keys, v.trust),
        throwsCheckError(CheckError.recoveryRequired),
      );
    },
  );
  test(
    'bounds and exact shape reject before decoding nested or oversized input',
    () {
      for (final input in [
        Uint8List(65537),
        Uint8List.fromList([255]),
        jsonBytes(['RAZE_CHECK_AUTHORITY_HISTORY', 1, id(1), fingerprint, []]),
        file(List.filled(129, v.authority)),
        jsonBytes([
          'RAZE_CHECK_AUTHORITY_HISTORY',
          1,
          id(1),
          fingerprint,
          [v.authority],
          null,
        ]),
        Uint8List.fromList(utf8.encode('[' * 20000)),
      ]) {
        expect(
          () => AuthorityHistoryFile.decode(input),
          throwsA(isA<CheckException>()),
        );
      }
    },
  );
  test(
    'export batches 130 ancestors with independently checked predecessor continuity',
    () async {
      final chain = [AuthorityCertificate(v.authority)];
      for (var i = 2; i <= 130; i++) {
        chain.add(
          AuthorityCertificate(
            await v.certificate(
              id(100 + i),
              chain.last.generationId,
              i,
              id(1000 + i),
              v.next,
              MessageVectors.timestamp,
            ),
          ),
        );
      }
      final files = AuthorityHistoryFile.batches(id(1), fingerprint, chain);
      expect(files, hasLength(2));
      var accepted = <AuthorityCertificate>[];
      for (final bytes in files) {
        expect(bytes.length, lessThanOrEqualTo(65536));
        accepted = await AuthorityHistoryFile.decode(bytes).verify(
          v.keys,
          TrustContext(
            companyId: id(1),
            rootPublicKey: v.root,
            authorities: accepted,
          ),
        );
      }
      expect(accepted, hasLength(130));
    },
  );
}
