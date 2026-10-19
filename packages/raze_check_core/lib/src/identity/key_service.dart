import 'dart:typed_data';

abstract interface class KeyService {
  Future<Uint8List> sign(Uint8List bytes, String keyId);
  Future<bool> verify(
    Uint8List bytes,
    Uint8List signature,
    Uint8List publicKey,
  );
}
