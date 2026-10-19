import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'secure_key_store.dart';

final class LocalKeyService implements KeyService {
  LocalKeyService(this.keys);
  final SecureKeyStore keys;
  final _algorithm = Ed25519();
  Future<Uint8List> create(String keyId) async {
    try {
      if (await keys.read(keyId) != null) {
        throw const CheckException(CheckError.invalidTransition);
      }
      final seed = secureRandomBytes(32);
      final pair = await _algorithm.newKeyPairFromSeed(seed);
      await keys.write(keyId, seed);
      return Uint8List.fromList((await pair.extractPublicKey()).bytes);
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }

  @override
  Future<Uint8List> sign(Uint8List bytes, String keyId) async {
    try {
      final seed = await keys.read(keyId);
      if (seed == null || seed.length != 32) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      final pair = await _algorithm.newKeyPairFromSeed(seed);
      return Uint8List.fromList(
        (await _algorithm.sign(bytes, keyPair: pair)).bytes,
      );
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }

  @override
  Future<bool> verify(
    Uint8List bytes,
    Uint8List signature,
    Uint8List publicKey,
  ) async {
    if (signature.length != 64 || publicKey.length != 32) return false;
    try {
      return await _algorithm.verify(
        bytes,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
