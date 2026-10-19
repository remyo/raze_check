import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'secure_key_store.dart';

abstract interface class PayloadCipher {
  Future<Uint8List> seal({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List plain,
  });
  Future<Uint8List> open({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List sealed,
  });
}

/// v1 bytes: version(1), random nonce(12), ciphertext, authentication tag(16).
final class AesPayloadCipher implements PayloadCipher {
  AesPayloadCipher(this.keys);
  final VaultKeys keys;
  final _aes = AesGcm.with256bits();
  List<int> _context(String scope, String record, int revision) => utf8.encode(
    jsonEncode(['RAZE_CHECK_PAYLOAD_V1', scope, record, revision]),
  );
  @override
  Future<Uint8List> seal({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List plain,
  }) async {
    final key = await keys.require(scopeId);
    try {
      final box = await _aes.encrypt(
        plain,
        secretKey: SecretKey(key),
        nonce: secureRandomBytes(12),
        aad: _context(scopeId, recordId, revision),
      );
      return Uint8List.fromList([
        1,
        ...box.nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }

  @override
  Future<Uint8List> open({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List sealed,
  }) async {
    final key = await keys.require(scopeId);
    if (sealed.length < 29) throw const CheckException(CheckError.malformed);
    if (sealed[0] != 1) {
      throw const CheckException(CheckError.unsupportedVersion);
    }
    try {
      return Uint8List.fromList(
        await _aes.decrypt(
          SecretBox(
            sealed.sublist(13, sealed.length - 16),
            nonce: sealed.sublist(1, 13),
            mac: Mac(sealed.sublist(sealed.length - 16)),
          ),
          secretKey: SecretKey(key),
          aad: _context(scopeId, recordId, revision),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const CheckException(CheckError.invalidSignature);
    } catch (_) {
      throw const CheckException(CheckError.malformed);
    }
  }
}
