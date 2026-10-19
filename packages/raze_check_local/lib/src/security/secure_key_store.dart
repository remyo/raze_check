import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:raze_check_core/raze_check_core.dart';

abstract interface class SecureKeyStore {
  Future<Uint8List?> read(String id);
  Future<void> write(String id, Uint8List value);
  Future<void> delete(String id);
}

/// Only keys and credential material belong here; never domain record bodies.
final class OsSecureKeyStore implements SecureKeyStore {
  OsSecureKeyStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
          synchronizable: false,
        ),
        aOptions: AndroidOptions(resetOnError: false),
      );
  final FlutterSecureStorage _storage;
  @override
  Future<Uint8List?> read(String id) async {
    try {
      final encoded = await _storage.read(key: 'raze-check:$id');
      return encoded == null ? null : base64Decode(encoded);
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }

  @override
  Future<void> write(String id, Uint8List value) async {
    try {
      await _storage.write(key: 'raze-check:$id', value: base64Encode(value));
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _storage.delete(key: 'raze-check:$id');
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }
}

Uint8List secureRandomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

/// Provisioning is explicit. Reads never manufacture replacement keys.
final class VaultKeys {
  VaultKeys(this.store);
  final SecureKeyStore store;
  Future<void> create(String scopeId) async {
    try {
      if (await store.read('vault:$scopeId') != null) {
        throw const CheckException(CheckError.invalidTransition);
      }
      await store.write('vault:$scopeId', secureRandomBytes(32));
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }

  Future<Uint8List> require(String scopeId) async {
    try {
      final key = await store.read('vault:$scopeId');
      if (key == null || key.length != 32) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      return key;
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }
}
