import 'dart:convert';
import 'dart:typed_data';
import '../contracts/result.dart';
import 'message_limits.dart';
import 'message_types.dart';

/// Strict bounded transport parsing. Decoding is not trust verification.
final class MessageCodec {
  static final Expando<Uint8List> _original = Expando<Uint8List>();

  Uint8List encode(SignedMessage message) {
    final bytes =
        _original[message] ??
        Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              1,
              message.kind.name,
              message.keyId,
              base64UrlEncode(message.payloadBytes),
              base64UrlEncode(message.signature),
            ]),
          ),
        );
    if (bytes.length > MessageLimits.fileBytes) {
      throw const CheckException(CheckError.limitExceeded);
    }
    return Uint8List.fromList(bytes);
  }

  SignedMessage decode(Uint8List bytes, {required int maxBytes}) {
    if (bytes.length > maxBytes || bytes.length > MessageLimits.fileBytes) {
      throw const CheckException(CheckError.limitExceeded);
    }
    final value = decodeMessageJson(bytes);
    requireMessage(value is List && value.length == 5);
    final fields = value as List;
    requireMessage(fields[0] is int && fields[1] is String);
    if (fields[0] != 1) {
      throw const CheckException(CheckError.unsupportedVersion);
    }
    final kinds = MessageKind.values.where((k) => k.name == fields[1]);
    if (kinds.isEmpty) {
      throw const CheckException(CheckError.unsupportedVersion);
    }
    validateKeyId(fields[2]);
    final message = SignedMessage(
      kind: kinds.single,
      keyId: fields[2] as String,
      payloadBytes: decodeMessageBase64(fields[3]),
      signature: decodeMessageBase64(fields[4], byteLength: 64),
    );
    _original[message] = Uint8List.fromList(bytes);
    return message;
  }

  /// False means offer untruncated file export.
  bool fitsQr(SignedMessage message) =>
      encode(message).length <= MessageLimits.qrBytes;
}
