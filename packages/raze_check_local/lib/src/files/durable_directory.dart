import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:raze_check_core/raze_check_core.dart';

/// Android/iOS/macOS POSIX directory sync closes the rename durability gap.
/// File contents must already have been flushed before calling this boundary.
abstract final class DurableDirectory {
  static final _lib = Platform.isAndroid
      ? DynamicLibrary.open('libc.so')
      : DynamicLibrary.process();
  static final _malloc = _lib
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');
  static final _free = _lib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  static final _open = _lib
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Int32),
        int Function(Pointer<Uint8>, int)
      >('open');
  static final _sync = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');
  static final _close = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static void sync(Directory directory) {
    if (!(Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux)) {
      throw const CheckException(CheckError.storageFailure);
    }
    final encoded = utf8.encode(directory.absolute.path);
    final memory = _malloc(encoded.length + 1);
    if (memory == nullptr) {
      throw const CheckException(CheckError.storageFailure);
    }
    try {
      final chars = memory.cast<Uint8>();
      chars.asTypedList(encoded.length + 1)
        ..setRange(0, encoded.length, encoded)
        ..[encoded.length] = 0;
      final fd = _open(chars, 0);
      if (fd < 0) throw const CheckException(CheckError.storageFailure);
      try {
        if (_sync(fd) != 0) {
          throw const CheckException(CheckError.storageFailure);
        }
      } finally {
        _close(fd);
      }
    } finally {
      _free(memory);
    }
  }

  static void through(Directory leaf, Directory root) {
    var current = leaf.absolute;
    final stop = root.absolute.path;
    if (current.path != stop && !current.path.startsWith('$stop/')) {
      throw const CheckException(CheckError.malformed);
    }
    while (true) {
      sync(current);
      if (current.path == stop) break;
      current = current.parent;
    }
  }
}
