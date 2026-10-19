import 'dart:typed_data';
import 'package:raze_check_local/raze_check_local.dart';

class MemoryKeyStore implements SecureKeyStore {
  final values = <String, Uint8List>{};
  bool failWrites = false;
  @override
  Future<Uint8List?> read(String id) async =>
      values[id] == null ? null : Uint8List.fromList(values[id]!);
  @override
  Future<void> write(String id, Uint8List value) async {
    if (failWrites) throw StateError('storage unavailable');
    values[id] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String id) async {
    values.remove(id);
  }
}
