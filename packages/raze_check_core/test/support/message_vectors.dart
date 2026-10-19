import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
Uint8List jsonBytes(Object? v) =>
    Uint8List.fromList(utf8.encode(jsonEncode(v)));

/// Real Ed25519 with public deterministic TEST ONLY seeds. No production keys.
final class VectorKeys implements KeyService {
  final algorithm = Ed25519();
  final pairs = <String, SimpleKeyPair>{};
  Future<Uint8List> add(String label, int seedByte) async {
    final pair = await algorithm.newKeyPairFromSeed(List.filled(32, seedByte));
    pairs[label] = pair;
    return Uint8List.fromList((await pair.extractPublicKey()).bytes);
  }

  @override
  Future<Uint8List> sign(Uint8List bytes, String keyId) async =>
      Uint8List.fromList(
        (await algorithm.sign(bytes, keyPair: pairs[keyId]!)).bytes,
      );
  @override
  Future<bool> verify(
    Uint8List bytes,
    Uint8List signature,
    Uint8List publicKey,
  ) async => algorithm.verify(
    bytes,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
}

final class MessageVectors {
  final keys = VectorKeys();
  late Uint8List root, issuer, staff, next;
  late List<Object?> authority, nextAuthority;
  late TrustContext trust;
  static const timestamp = 1792368000000;
  static Future<MessageVectors> create() async {
    final v = MessageVectors();
    v.root = await v.keys.add('root', 1);
    v.issuer = await v.keys.add('issuer', 2);
    v.staff = await v.keys.add('staff', 3);
    v.next = await v.keys.add('next', 4);
    v.authority = await v.certificate(
      id(2),
      null,
      1,
      id(3),
      v.issuer,
      timestamp - 1000,
    );
    v.nextAuthority = await v.certificate(
      id(4),
      id(2),
      2,
      id(5),
      v.next,
      timestamp,
    );
    v.trust = TrustContext(
      companyId: id(1),
      rootPublicKey: v.root,
      authorities: [AuthorityCertificate(v.authority)],
      credentials: [v.credential()],
    );
    return v;
  }

  TrustedCredential credential({
    bool retired = false,
    int revision = 1,
    Uint8List? publicKey,
  }) => TrustedCredential(
    companyId: id(1),
    personId: id(6),
    employeeId: id(7),
    installationId: id(8),
    membershipId: id(9),
    membershipRevision: revision,
    authorityGenerationId: id(2),
    publicKey: publicKey ?? staff,
    retired: retired,
  );
  Future<List<Object?>> certificate(
    String generation,
    String? parent,
    int sequence,
    String installation,
    Uint8List public,
    int issued,
  ) async {
    final fields = <Object?>[
      generation,
      parent,
      sequence,
      installation,
      base64UrlEncode(public),
      issued,
    ];
    final signature = await keys.sign(
      Uint8List.fromList([
        ...utf8.encode('RAZE_CHECK_AUTHORITY_V1\n'),
        ...jsonBytes(fields),
      ]),
      'root',
    );
    return [...fields, base64UrlEncode(signature)];
  }

  TrustContext get wrongCompany => TrustContext(
    companyId: id(99),
    rootPublicKey: root,
    authorities: trust.authorities,
  );
  TrustContext get unknownIssuer => TrustContext(
    companyId: id(1),
    rootPublicKey: root,
    authorities: [AuthorityCertificate(nextAuthority)],
  );
  TrustContext get wrongRoot => TrustContext(
    companyId: id(1),
    rootPublicKey: staff,
    authorities: trust.authorities,
  );
  TrustContext withHistory(
    List<List<Object?>> authorities, {
    List<TrustedCredential>? credentials,
  }) => TrustContext(
    companyId: id(1),
    rootPublicKey: root,
    authorities: authorities.map(AuthorityCertificate.new).toList(),
    credentials: credentials ?? trust.credentials,
  );

  // Explicit registry vectors, independent of production payload serialization.
  List<Object?> payload(MessageKind kind) {
    final common = <Object?>[id(1), id(10 + kind.index), timestamp];
    final hash = base64UrlEncode(List.filled(32, 5));
    return [
      ...common,
      ...switch (kind) {
        MessageKind.invitation => [
          'Raze Check',
          'Asia/Tokyo',
          id(20),
          base64UrlEncode(root),
          authority,
        ],
        MessageKind.joinRequest => [
          id(10),
          id(6),
          'Alex Tanaka',
          id(8),
          base64UrlEncode(staff),
        ],
        MessageKind.membershipGrant => [
          id(11),
          id(9),
          1,
          id(6),
          id(7),
          id(8),
          base64UrlEncode(staff),
          'Raze Check',
          'Asia/Tokyo',
          id(20),
          authority,
        ],
        MessageKind.workplace => [id(20), id(21), authority],
        MessageKind.attendance => [
          id(6),
          id(7),
          id(9),
          1,
          id(8),
          'checkIn',
          timestamp,
          540,
          id(20),
          id(21),
          id(2),
          'staticQr',
        ],
        MessageKind.receiptAck => [id(14), hash, timestamp, authority],
        MessageKind.attendanceDecision => [
          id(14),
          hash,
          id(22),
          1,
          'approved',
          'Correct missed check-in',
          null,
          null,
          null,
          'checkIn',
          timestamp,
          540,
          id(6),
          authority,
        ],
        MessageKind.correctionRequest => [
          id(7),
          id(14),
          'checkIn',
          timestamp,
          540,
          'Correct missed check-in',
        ],
        MessageKind.replacementRequest => [
          id(6),
          null,
          id(8),
          base64UrlEncode(staff),
        ],
        MessageKind.authorityTransfer => [
          id(18),
          id(23),
          hash,
          nextAuthority,
          authority,
        ],
        MessageKind.transferAck => [id(19), id(23), hash, nextAuthority],
      },
    ];
  }

  String signer(MessageKind kind) => switch (kind) {
    MessageKind.joinRequest ||
    MessageKind.attendance ||
    MessageKind.correctionRequest ||
    MessageKind.replacementRequest => 'staff',
    MessageKind.transferAck => 'next',
    _ => 'issuer',
  };
  Future<SignedMessage> signed(
    MessageKind kind,
    List<Object?> payload, {
    String? domain,
    String? signerOverride,
  }) async {
    final label = signerOverride ?? signer(kind);
    final public = Uint8List.fromList(
      (await keys.pairs[label]!.extractPublicKey()).bytes,
    );
    final bytes = jsonBytes(payload);
    final signature = await keys.sign(
      Uint8List.fromList([
        ...utf8.encode(domain ?? 'RAZE_CHECK_V1\n${kind.name}\n'),
        ...bytes,
      ]),
      label,
    );
    return SignedMessage(
      kind: kind,
      keyId: await messageKeyId(public),
      payloadBytes: bytes,
      signature: signature,
    );
  }

  Future<List<SignedMessage>> messages() async => [
    for (final kind in MessageKind.values) await signed(kind, payload(kind)),
  ];
  Future<SignedMessage> wrongDomain() => signed(
    MessageKind.invitation,
    payload(MessageKind.invitation),
    domain: 'WRONG_DOMAIN\n',
  );
  Future<SignedMessage> wrongType() => signed(
    MessageKind.invitation,
    payload(MessageKind.invitation),
    domain: 'RAZE_CHECK_V1\nworkplace\n',
  );

  Iterable<SignedMessage> mutations(SignedMessage message) sync* {
    final values = message.payload.values;
    for (var i = 1; i < values.length; i++) {
      final changed = List<Object?>.of(values);
      final value = values[i];
      final name = MessagePayload.fieldNames(message.kind)[i];
      if (name == 'evidence') continue; // Only one valid enum value.
      if (value is List) {
        // Mutate each certificate's signed field and its root signature.
        for (var j = 0; j < value.length; j++) {
          final cert = List<Object?>.of(value);
          if (j == 1 || j == 2) {
            continue; // Linked parent/sequence tested separately.
          }
          cert[j] = j == 4 || j == 6
              ? base64UrlEncode(List.filled(j == 4 ? 32 : 64, 9))
              : j == 5
              ? (cert[j] as int) - 1
              : id(80 + j);
          final p = List<Object?>.of(values)..[i] = cert;
          yield SignedMessage(
            kind: message.kind,
            keyId: message.keyId,
            payloadBytes: jsonBytes(p),
            signature: message.signature,
          );
        }
        continue;
      }
      changed[i] = value == null
          ? id(90)
          : value is int
          ? value + (value == 540 ? 1 : -1)
          : name == 'kind' || name == 'effectiveKind' || name == 'proposedKind'
          ? 'checkOut'
          : name == 'outcome'
          ? 'rejected'
          : name == 'timeZoneId'
          ? 'Asia/Seoul'
          : value is String && value.startsWith('00000000-')
          ? id(91)
          : name.contains('Base64Url')
          ? base64UrlEncode(List.filled(32, 9))
          : '${value}x';
      if (name == 'membershipRevision' || name == 'decisionRevision') {
        changed[i] = 2;
      }
      if (message.kind == MessageKind.attendanceDecision && i >= 9 && i <= 11) {
        changed[9] = id(90);
        changed[10] = i == 10 ? id(91) : null;
        changed[11] = 'approved';
      }
      yield SignedMessage(
        kind: message.kind,
        keyId: message.keyId,
        payloadBytes: jsonBytes(changed),
        signature: message.signature,
      );
    }
    final signature = message.signature..[0] ^= 1;
    yield SignedMessage(
      kind: message.kind,
      keyId: message.keyId,
      payloadBytes: message.payloadBytes,
      signature: signature,
    );
  }

  // Explicit limit vectors. Controls deliberately exercise worst JSON escaping.
  List<Object?> limitPayload(MessageKind kind) {
    final p = payload(kind)..[2] = 8640000000000000;
    switch (kind) {
      case MessageKind.invitation:
        p[3] = '\u0000' * 40;
        p[4] = 'America/Argentina/Buenos_Aires';
      case MessageKind.joinRequest:
        p[5] = '\u0000' * 120;
      case MessageKind.membershipGrant:
        p[5] = 9007199254740991;
        p[10] = '\u0000' * 120;
        p[11] = 'America/Argentina/Buenos_Aires';
      case MessageKind.attendance:
        p[6] = 9007199254740991;
        p[8] = 'checkOut';
        p[9] = -8640000000000000;
        p[10] = -840;
      case MessageKind.receiptAck:
        p[5] = -8640000000000000;
      case MessageKind.attendanceDecision:
        p[6] = 9007199254740991;
        p[7] = 'rejected';
        p[8] = '\u0000' * 500;
        p[9] = id(90);
        p[10] = id(91);
        p[11] = 'rejected';
        p[12] = 'checkOut';
        p[13] = -8640000000000000;
        p[14] = -840;
      case MessageKind.correctionRequest:
        p[5] = 'checkOut';
        p[6] = -8640000000000000;
        p[7] = -840;
        p[8] = '\u0000' * 500;
      case MessageKind.replacementRequest:
        p[4] = id(7);
      case MessageKind.workplace ||
          MessageKind.authorityTransfer ||
          MessageKind.transferAck:
        break;
    }
    return p;
  }

  /// Independent outer construction, deliberately not MessageCodec.encode.
  Uint8List envelope(SignedMessage message) => jsonBytes([
    1,
    message.kind.name,
    message.keyId,
    base64UrlEncode(message.payloadBytes),
    base64UrlEncode(message.signature),
  ]);

  Future<void> writeFixtures() async {
    final directory = Directory('test/fixtures/messages')
      ..createSync(recursive: true);
    for (final kind in MessageKind.values) {
      final normal = await signed(kind, payload(kind));
      File(
        '${directory.path}/${kind.name}.json',
      ).writeAsBytesSync(envelope(normal));
      final p = limitPayload(kind);
      File(
        '${directory.path}/${kind.name}.max.json',
      ).writeAsBytesSync(envelope(await signed(kind, p)));
      // Choose valid compact content before signing. Runtime export never edits
      // an existing payload or signature to fit QR.
      final textIndex = switch (kind) {
        MessageKind.invitation => 3,
        MessageKind.joinRequest => 5,
        MessageKind.membershipGrant => 10,
        MessageKind.attendanceDecision || MessageKind.correctionRequest => 8,
        _ => null,
      };
      var compact = await signed(kind, p);
      while (envelope(compact).length > 1500 && textIndex != null) {
        p[textIndex] = (p[textIndex] as String).substring(1);
        compact = await signed(kind, p);
      }
      final maxText = switch (kind) {
        MessageKind.invitation => 40,
        MessageKind.joinRequest || MessageKind.membershipGrant => 120,
        _ => 500,
      };
      while (textIndex != null &&
          (p[textIndex] as String).runes.length < maxText) {
        final candidate = List<Object?>.of(p)..[textIndex] = '${p[textIndex]}a';
        final signedCandidate = await signed(kind, candidate);
        if (envelope(signedCandidate).length > 1500) {
          break;
        }
        p[textIndex] = candidate[textIndex];
        compact = signedCandidate;
      }
      File(
        '${directory.path}/${kind.name}.compact.json',
      ).writeAsBytesSync(envelope(compact));
    }
  }
}
