import 'dart:io';
import 'dart:convert';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:test/test.dart';
import 'support/message_vectors.dart';
import 'support/check_matchers.dart';

void main() {
  final codec = MessageCodec();
  late MessageVectors vectors;
  setUp(() async {
    vectors = await MessageVectors.create();
  });

  test(
    'verifies all registry fixtures using pinned root and signer history',
    () async {
      final verifier = MessageVerifier(vectors.keys);
      for (final kind in MessageKind.values) {
        final message = codec.decode(
          File('test/fixtures/messages/${kind.name}.json').readAsBytesSync(),
          maxBytes: 65536,
        );
        final verified = await verifier.verify(message, vectors.trust);
        expect(verified.message.kind, kind);
        expect(
          verified.proofOfPossessionOnly,
          kind == MessageKind.joinRequest ||
              kind == MessageKind.replacementRequest,
        );
      }
    },
  );

  test('tampered signed fields are rejected field by field', () async {
    final verifier = MessageVerifier(vectors.keys);
    for (final message in await vectors.messages()) {
      for (final tampered in vectors.mutations(message)) {
        await expectLater(
          verifier.verify(tampered, vectors.trust),
          throwsCheckError(CheckError.invalidSignature),
        );
      }
    }
  });

  test(
    'rejects wrong company, unknown issuer, root and signature domain',
    () async {
      final verifier = MessageVerifier(vectors.keys);
      final message = (await vectors.messages()).first;
      await expectLater(
        verifier.verify(message, vectors.wrongCompany),
        throwsCheckError(CheckError.wrongCompany),
      );
      await expectLater(
        verifier.verify(message, vectors.unknownIssuer),
        throwsCheckError(CheckError.unknownIssuer),
      );
      await expectLater(
        verifier.verify(message, vectors.wrongRoot),
        throwsCheckError(CheckError.invalidSignature),
      );
      await expectLater(
        verifier.verify(await vectors.wrongDomain(), vectors.trust),
        throwsCheckError(CheckError.invalidSignature),
      );
      await expectLater(
        verifier.verify(await vectors.wrongType(), vectors.trust),
        throwsCheckError(CheckError.invalidSignature),
      );
    },
  );
  test(
    'wire key IDs are derived from actual public keys for every message kind',
    () async {
      final verifier = MessageVerifier(vectors.keys);
      for (final message in await vectors.messages()) {
        final changed = SignedMessage(
          kind: message.kind,
          keyId: await messageKeyId(vectors.root),
          payloadBytes: message.payloadBytes,
          signature: message.signature,
        );
        await expectLater(
          verifier.verify(changed, vectors.trust),
          throwsCheckError(
            message.kind == MessageKind.attendance ||
                    message.kind == MessageKind.correctionRequest
                ? CheckError.unknownIssuer
                : CheckError.invalidSignature,
          ),
        );
      }
    },
  );

  test(
    'retired keys still verify authentic historical receipts without authorizing activity',
    () async {
      final trust = vectors.withHistory(
        [vectors.authority],
        credentials: [
          vectors.credential(retired: true),
          vectors.credential(revision: 2),
        ],
      );
      final message = await vectors.signed(
        MessageKind.attendance,
        vectors.payload(MessageKind.attendance),
      );
      final result = await MessageVerifier(vectors.keys).verify(message, trust);
      expect(result.historicalCredential, isTrue);
      expect(result.proofOfPossessionOnly, isFalse);
    },
  );

  test(
    'valid signatures cannot borrow another staff enrollment identity',
    () async {
      final p = vectors.payload(MessageKind.attendance)..[3] = id(77);
      await expectLater(
        MessageVerifier(vectors.keys).verify(
          await vectors.signed(MessageKind.attendance, p),
          vectors.trust,
        ),
        throwsCheckError(CheckError.unauthorized),
      );
      final correction = vectors.payload(MessageKind.correctionRequest)
        ..[3] = id(77);
      await expectLater(
        MessageVerifier(vectors.keys).verify(
          await vectors.signed(MessageKind.correctionRequest, correction),
          vectors.trust,
        ),
        throwsCheckError(CheckError.unauthorized),
      );
    },
  );

  test(
    'detects signed authority forks, missing ancestors and sequence gaps',
    () async {
      final verifier = MessageVerifier(vectors.keys);
      final message = await vectors.signed(
        MessageKind.invitation,
        vectors.payload(MessageKind.invitation),
      );
      final sibling = await vectors.certificate(
        id(66),
        id(2),
        2,
        id(67),
        vectors.staff,
        MessageVectors.timestamp,
      );
      await expectLater(
        verifier.verify(
          message,
          vectors.withHistory([
            vectors.authority,
            vectors.nextAuthority,
            sibling,
          ]),
        ),
        throwsCheckError(CheckError.recoveryRequired),
      );
      final gap = await vectors.certificate(
        id(66),
        id(2),
        3,
        id(67),
        vectors.staff,
        MessageVectors.timestamp,
      );
      await expectLater(
        verifier.verify(message, vectors.withHistory([vectors.authority, gap])),
        throwsCheckError(CheckError.invalidTransition),
      );
      await expectLater(
        verifier.verify(message, vectors.withHistory([vectors.nextAuthority])),
        throwsCheckError(CheckError.unknownIssuer),
      );
    },
  );

  test(
    'unknown embedded self-signed issuer cannot become company authority',
    () async {
      final counterfeit = List<Object?>.of(vectors.authority)
        ..[4] = base64UrlEncode(vectors.staff);
      final p = vectors.payload(MessageKind.invitation)..[7] = counterfeit;
      final message = await vectors.signed(
        MessageKind.invitation,
        p,
        signerOverride: 'staff',
      );
      await expectLater(
        MessageVerifier(vectors.keys).verify(message, vectors.trust),
        throwsCheckError(CheckError.invalidSignature),
      );
    },
  );
  test('every outer signature byte is authenticated', () async {
    final verifier = MessageVerifier(vectors.keys);
    final original = await vectors.signed(
      MessageKind.invitation,
      vectors.payload(MessageKind.invitation),
    );
    for (var i = 0; i < 64; i++) {
      final signature = original.signature..[i] ^= 1;
      final message = SignedMessage(
        kind: original.kind,
        keyId: original.keyId,
        payloadBytes: original.payloadBytes,
        signature: signature,
      );
      await expectLater(
        verifier.verify(message, vectors.trust),
        throwsCheckError(CheckError.invalidSignature),
      );
    }
  });

  test(
    'first-use invitation uses explicitly pinned root and requests grant no authority',
    () async {
      final message = await vectors.signed(
        MessageKind.invitation,
        vectors.payload(MessageKind.invitation),
      );
      final trust = TrustContext(
        companyId: id(1),
        rootPublicKey: vectors.root,
        authorities: [],
      );
      expect(
        (await MessageVerifier(
          vectors.keys,
        ).verify(message, trust)).proofOfPossessionOnly,
        isFalse,
      );
      final request = await vectors.signed(
        MessageKind.joinRequest,
        vectors.payload(MessageKind.joinRequest),
      );
      expect(
        (await MessageVerifier(
          vectors.keys,
        ).verify(request, vectors.wrongRoot)).proofOfPossessionOnly,
        isTrue,
      );
    },
  );

  test(
    'transfer target must extend source generation and use a fresh installation',
    () async {
      final sameInstallation = await vectors.certificate(
        id(4),
        id(2),
        2,
        id(3),
        vectors.next,
        MessageVectors.timestamp,
      );
      final p = vectors.payload(MessageKind.authorityTransfer)
        ..[6] = sameInstallation;
      await expectLater(
        MessageVerifier(vectors.keys).verify(
          await vectors.signed(MessageKind.authorityTransfer, p),
          vectors.trust,
        ),
        throwsCheckError(CheckError.invalidTransition),
      );
    },
  );
  test(
    'wire fingerprint matches independently computed SHA256 test vector',
    () async {
      expect(
        await messageKeyId(vectors.issuer),
        'ed25519:ajgD1fBZkCocba-8m6RykhL3yqwIY0zDrnaydSnwOCc',
      );
      expect(
        await messageKeyId(vectors.staff),
        'ed25519:ti6Gf6LzOv5i1daxZC4WIdVDMHhGsqV7iX5xCRm3Zwk',
      );
    },
  );
}
