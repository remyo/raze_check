import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

import '../company/company_models.dart';
import '../contracts/result.dart';
import 'message_limits.dart';

/// The complete v1 registry. Unknown kinds require a supported new version.
enum MessageKind {
  invitation,
  joinRequest,
  membershipGrant,
  workplace,
  attendance,
  receiptAck,
  attendanceDecision,
  correctionRequest,
  replacementRequest,
  authorityTransfer,
  transferAck,
}

/// A validated positional payload. Named access uses the same fixed registry as
/// decoding, so no unrecognized extension fields can reach dispatch.
final class MessagePayload {
  MessagePayload._(this.kind, this.values);

  factory MessagePayload(MessageKind kind, List<Object?> values) {
    final fields = _registry[kind]!;
    requireMessage(values.length == fields.length);
    for (var i = 0; i < fields.length; i++) {
      fields[i].validate(values[i]);
    }
    return MessagePayload._(
      kind,
      List<Object?>.unmodifiable(values.map(_freeze)),
    );
  }

  final MessageKind kind;
  final List<Object?> values;
  String get companyId => values[0] as String;
  String get messageId => values[1] as String;
  int get issuedAtUtcMs => values[2] as int;

  /// Names and their exact types are specified in receipt-v1.md.
  T field<T>(String name) {
    final index = _registry[kind]!.indexWhere((field) => field.name == name);
    if (index < 0) throw ArgumentError.value(name, 'name');
    return values[index] as T;
  }

  static List<String> fieldNames(MessageKind kind) =>
      List.unmodifiable(_registry[kind]!.map((field) => field.name));
}

Object? _freeze(Object? value) =>
    value is List ? List<Object?>.unmodifiable(value.map(_freeze)) : value;

/// Retains exact signed payload and, for decoded messages, original envelope.
/// Byte access always returns a copy; mutable caller buffers cannot alter it.
final class SignedMessage {
  SignedMessage({
    required this.kind,
    required this.keyId,
    required Uint8List payloadBytes,
    required Uint8List signature,
  }) : _payloadBytes = Uint8List.fromList(payloadBytes),
       _signature = Uint8List.fromList(signature) {
    validateKeyId(keyId);
    requireMessage(signature.length == 64);
    requireMessage(payloadBytes.length <= MessageLimits.fileBytes);
    payload = parsePayload(kind, _payloadBytes);
  }

  final MessageKind kind;
  final String keyId;
  final Uint8List _payloadBytes, _signature;
  late final MessagePayload payload;
  Uint8List get payloadBytes => Uint8List.fromList(_payloadBytes);
  Uint8List get signature => Uint8List.fromList(_signature);

  /// Ed25519 signs these exact bytes; no decode/re-encode of payload occurs.
  Uint8List get signingBytes => messageSigningBytes(kind, _payloadBytes);
}

/// Builders sign this with their local KeyService key ID, then place the
/// public fingerprint from messageKeyId in the envelope.
Uint8List messageSigningBytes(MessageKind kind, Uint8List payloadBytes) =>
    Uint8List.fromList([
      ...utf8.encode('RAZE_CHECK_V1\n${kind.name}\n'),
      ...payloadBytes,
    ]);

/// Root-signed authority v1, shared with Company.authority storage grammar.
final class AuthorityCertificate {
  AuthorityCertificate(List<Object?> values) {
    _authority(values);
    this.values = List<Object?>.unmodifiable(values);
  }
  late final List<Object?> values;
  String get generationId => values[0] as String;
  String? get parentGenerationId => values[1] as String?;
  int get sequence => values[2] as int;
  String get installationId => values[3] as String;
  Uint8List get publicKey => decodeMessageBase64(values[4], byteLength: 32);
  int get issuedAtUtcMs => values[5] as int;
  Uint8List get signature => decodeMessageBase64(values[6], byteLength: 64);
  Uint8List get signingBytes => Uint8List.fromList(
    utf8.encode(
      'RAZE_CHECK_AUTHORITY_V1\n${jsonEncode(values.take(6).toList())}',
    ),
  );
}

void requireMessage(bool condition) {
  if (!condition) throw const CheckException(CheckError.malformed);
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
void _id(Object? value) =>
    requireMessage(value is String && _uuid.hasMatch(value));
void validateKeyId(Object? value) {
  requireMessage(
    value is String && RegExp(r'^ed25519:[A-Za-z0-9_-]{43}$').hasMatch(value),
  );
  final encoded = (value as String).substring(8);
  requireMessage(
    base64UrlEncode(base64Url.decode('$encoded=')).replaceAll('=', '') ==
        encoded,
  );
}

/// Public wire ID; never a local secure-store signing-key reference.
Future<String> messageKeyId(Uint8List publicKey) async {
  requireMessage(publicKey.length == 32);
  final digest = await Sha256().hash(publicKey);
  return 'ed25519:${base64UrlEncode(digest.bytes).replaceAll('=', '')}';
}

/// Canonical padded RFC 4648 base64url, matching existing company certificates.
Uint8List decodeMessageBase64(Object? value, {int? byteLength}) {
  requireMessage(value is String);
  final text = value as String;
  requireMessage(RegExp(r'^[A-Za-z0-9_-]*={0,2}$').hasMatch(text));
  try {
    final bytes = base64Url.decode(text);
    requireMessage(base64UrlEncode(bytes) == text);
    requireMessage(byteLength == null || bytes.length == byteLength);
    return bytes;
  } on FormatException {
    throw const CheckException(CheckError.malformed);
  }
}

/// Bounded JSON decoding also rejects deeply nested input before jsonDecode.
Object? decodeMessageJson(Uint8List bytes) {
  requireMessage(bytes.length <= MessageLimits.fileBytes);
  try {
    final text = utf8.decode(bytes, allowMalformed: false);
    var depth = 0;
    var string = false;
    var escaped = false;
    for (final code in text.codeUnits) {
      if (string) {
        if (escaped) {
          escaped = false;
        } else if (code == 92) {
          escaped = true;
        } else if (code == 34) {
          string = false;
        }
      } else if (code == 34) {
        string = true;
      } else if (code == 91 || code == 123) {
        depth++;
        requireMessage(depth <= 4);
      } else if (code == 93 || code == 125) {
        depth--;
      }
    }
    return jsonDecode(text);
  } on FormatException {
    throw const CheckException(CheckError.malformed);
  }
}

MessagePayload parsePayload(MessageKind kind, Uint8List bytes) {
  final value = decodeMessageJson(bytes);
  requireMessage(value is List);
  return MessagePayload(kind, List<Object?>.from(value as List));
}

void _integer(Object? value, int min, int max) =>
    requireMessage(value is int && value >= min && value <= max);
void _utc(Object? v) =>
    _integer(v, -MessageLimits.maxUtcMs, MessageLimits.maxUtcMs);
void _positive(Object? v) => _integer(v, 1, MessageLimits.maxInteger);
void _offset(Object? v) => _integer(v, -840, 840);
void _text(Object? v, int max, {bool empty = false}) {
  requireMessage(v is String);
  final text = v as String;
  final scalars = text.runes.toList();
  requireMessage((empty || scalars.isNotEmpty) && scalars.length <= max);
  requireMessage(!scalars.any((r) => r >= 0xd800 && r <= 0xdfff));
}

void _name(Object? v) => _text(v, 120);
void _label(Object? v) => _text(v, 40);
void _reason(Object? v) => _text(v, 500, empty: true);
void _zone(Object? v) {
  _text(v, 120);
  requireMessage(CompanyTimeZones.all.contains(v));
}

void _key(Object? v) => decodeMessageBase64(v, byteLength: 32);
void _signature(Object? v) => decodeMessageBase64(v, byteLength: 64);
void _kind(Object? v) => requireMessage(v == 'checkIn' || v == 'checkOut');
void _outcome(Object? v) => requireMessage(v == 'approved' || v == 'rejected');
void _evidence(Object? v) => requireMessage(v == 'staticQr');
void _optionalId(Object? v) {
  if (v != null) _id(v);
}

void _authority(Object? value) {
  requireMessage(value is List && value.length == 7);
  final v = value as List;
  _id(v[0]);
  _optionalId(v[1]);
  _positive(v[2]);
  _id(v[3]);
  _key(v[4]);
  _utc(v[5]);
  _signature(v[6]);
  requireMessage(v[0] != v[1]);
  requireMessage((v[1] == null) == (v[2] == 1));
}

typedef _Validator = void Function(Object?);

final class _Field {
  const _Field(this.name, this.validate);
  final String name;
  final _Validator validate;
}

const _common = [
  _Field('companyId', _id),
  _Field('messageId', _id),
  _Field('issuedAtUtcMs', _utc),
];
const _registry = <MessageKind, List<_Field>>{
  MessageKind.invitation: [
    ..._common,
    _Field('companyLabel', _label),
    _Field('timeZoneId', _zone),
    _Field('workplaceId', _id),
    _Field('rootPublicKeyBase64Url', _key),
    _Field('authority', _authority),
  ],
  MessageKind.joinRequest: [
    ..._common,
    _Field('invitationId', _id),
    _Field('personId', _id),
    _Field('displayName', _name),
    _Field('installationId', _id),
    _Field('publicKeyBase64Url', _key),
  ],
  MessageKind.membershipGrant: [
    ..._common,
    _Field('joinOrReplacementRequestId', _id),
    _Field('membershipId', _id),
    _Field('membershipRevision', _positive),
    _Field('personId', _id),
    _Field('employeeId', _id),
    _Field('installationId', _id),
    _Field('publicKeyBase64Url', _key),
    _Field('companyLabel', _name),
    _Field('timeZoneId', _zone),
    _Field('workplaceId', _id),
    _Field('authority', _authority),
  ],
  MessageKind.workplace: [
    ..._common,
    _Field('workplaceId', _id),
    _Field('codeId', _id),
    _Field('authority', _authority),
  ],
  MessageKind.attendance: [
    ..._common,
    _Field('personId', _id),
    _Field('employeeId', _id),
    _Field('membershipId', _id),
    _Field('membershipRevision', _positive),
    _Field('installationId', _id),
    _Field('kind', _kind),
    _Field('claimedUtcMs', _utc),
    _Field('offsetMinutes', _offset),
    _Field('workplaceId', _id),
    _Field('codeId', _id),
    _Field('membershipAuthorityGenerationId', _id),
    _Field('evidence', _evidence),
  ],
  MessageKind.receiptAck: [
    ..._common,
    _Field('eventId', _id),
    _Field('eventPayloadSha256Base64Url', _key),
    _Field('receivedUtcMs', _utc),
    _Field('authority', _authority),
  ],
  MessageKind.attendanceDecision: [
    ..._common,
    _Field('eventId', _id),
    _Field('eventPayloadSha256Base64Url', _key),
    _Field('decisionId', _id),
    _Field('decisionRevision', _positive),
    _Field('outcome', _outcome),
    _Field('reason', _reason),
    _Field('correctionIdOrNull', _optionalId),
    _Field('effectiveKind', _kind),
    _Field('effectiveUtcMs', _utc),
    _Field('effectiveOffsetMinutes', _offset),
    _Field('actorPersonId', _id),
    _Field('authority', _authority),
  ],
  MessageKind.correctionRequest: [
    ..._common,
    _Field('employeeId', _id),
    _Field('eventId', _id),
    _Field('proposedKind', _kind),
    _Field('proposedUtcMs', _utc),
    _Field('proposedOffsetMinutes', _offset),
    _Field('reason', _reason),
  ],
  MessageKind.replacementRequest: [
    ..._common,
    _Field('personId', _id),
    _Field('employeeIdOrNull', _optionalId),
    _Field('newInstallationId', _id),
    _Field('newPublicKeyBase64Url', _key),
  ],
  MessageKind.authorityTransfer: [
    ..._common,
    _Field('targetReplacementRequestId', _id),
    _Field('snapshotManifestId', _id),
    _Field('snapshotSha256Base64Url', _key),
    _Field('nextAuthority', _authority),
    _Field('sourceAuthority', _authority),
  ],
  MessageKind.transferAck: [
    ..._common,
    _Field('transferMessageId', _id),
    _Field('snapshotManifestId', _id),
    _Field('snapshotSha256Base64Url', _key),
    _Field('authority', _authority),
  ],
};
