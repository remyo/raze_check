import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:raze_check_core/raze_check_core.dart';

enum DocumentPurpose { message, image, archive }

int documentLimit(DocumentPurpose p) => switch (p) {
  DocumentPurpose.message => 65536,
  DocumentPurpose.image => 20 * 1024 * 1024,
  DocumentPurpose.archive => 64 * 1024 * 1024,
};

/// Native hosts MUST implement the bounded open-in-place bridge. Do not replace
/// this with file_selector: its mobile materialization precedes Dart's limits.
final class DocumentPort {
  DocumentPort({Future<String?> Function(DocumentPurpose)? pick})
    : _pick = pick ?? _nativePick;
  final Future<String?> Function(DocumentPurpose) _pick;
  static Future<String?> _nativePick(DocumentPurpose purpose) async {
    try {
      return await const MethodChannel(
        'com.remyo.razecheck/documents',
      ).invokeMethod<String>('pick', {'purpose': purpose.name});
    } on PlatformException catch (e) {
      throw TransferException(
        e.code == 'limitExceeded'
            ? 'File is too large. Save a smaller file and retry.'
            : 'File unavailable offline. Save it locally in Files and retry.',
      );
    }
  }

  Future<File?> pick(DocumentPurpose purpose) async {
    final path = await _pick(purpose);
    if (path == null) return null;
    final file = File(path);
    try {
      if (await file.length() > documentLimit(purpose)) {
        throw const TransferException(
          'File is too large. Save a smaller file and retry.',
        );
      }
      return file;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<Uint8List?> pickMessage() async {
    final file = await pick(DocumentPurpose.message);
    if (file == null) return null;
    try {
      final data = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        if (data.length + chunk.length > 65536) {
          throw const TransferException('Message exceeds 64 KiB.');
        }
        data.add(chunk);
      }
      return data.takeBytes();
    } finally {
      await file.delete();
    }
  }
}

/// Defense in depth and reusable streaming primitive; provider length is never
/// used for allocation. Native code applies the same bound BEFORE Dart sees it.
Future<void> copyBounded(
  Stream<List<int>> input,
  File target,
  int limit,
) async {
  final sink = target.openWrite();
  var count = 0;
  try {
    await for (final chunk in input) {
      count += chunk.length;
      if (count > limit) throw const TransferException('File is too large.');
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();
  } catch (_) {
    await sink.close();
    if (await target.exists()) await target.delete();
    rethrow;
  }
}

/// Reads only structural headers, never a full raster. Bound applies before
/// mobile_scanner/ML Kit/Vision is allowed to allocate the decoded image.
({int width, int height}) validateQrImage(Uint8List bytes) {
  Never bad() => throw const TransferException(
    'Unsupported or malformed PNG/JPEG. Save a valid image and retry.',
  );
  int? width, height;
  if (bytes.length > 20 * 1024 * 1024) {
    throw const TransferException(
      'Image exceeds 20 MiB. Crop or save smaller.',
    );
  }
  if (bytes.length >= 33 &&
      _same(bytes, 0, [137, 80, 78, 71, 13, 10, 26, 10])) {
    if (!_same(bytes, 8, [0, 0, 0, 13, 73, 72, 68, 82])) bad();
    final d = ByteData.sublistView(bytes);
    if (imageHeaderCrc(bytes.sublist(12, 29)) != d.getUint32(29)) bad();
    width = d.getUint32(16);
    height = d.getUint32(20);
    final depth = bytes[24], color = bytes[25];
    final validDepths = <int, List<int>>{
      0: [1, 2, 4, 8, 16],
      2: [8, 16],
      3: [1, 2, 4, 8],
      4: [8, 16],
      6: [8, 16],
    };
    if (!(validDepths[color]?.contains(depth) ?? false) ||
        bytes[26] != 0 ||
        bytes[27] != 0 ||
        bytes[28] > 1) {
      bad();
    }
  } else if (bytes.length >= 4 && _same(bytes, 0, [255, 216])) {
    var i = 2;
    while (i < bytes.length) {
      if (bytes[i++] != 255) bad();
      while (i < bytes.length && bytes[i] == 255) {
        i++;
      }
      if (i >= bytes.length) bad();
      final marker = bytes[i++];
      if (marker == 0xda || marker == 0xd9 || marker == 0 || marker == 0xd8) {
        bad();
      }
      if (marker == 1 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (i + 2 > bytes.length) bad();
      final length = (bytes[i] << 8) | bytes[i + 1];
      if (length < 2 || i + length > bytes.length) bad();
      if ([0xc0, 0xc1, 0xc2].contains(marker)) {
        if (length < 8 || bytes[i + 2] != 8) bad();
        height = (bytes[i + 3] << 8) | bytes[i + 4];
        width = (bytes[i + 5] << 8) | bytes[i + 6];
        final components = bytes[i + 7];
        if (components < 1 || components > 4 || length != 8 + 3 * components) {
          bad();
        }
        break;
      }
      i += length;
    }
  } else {
    bad();
  }
  if (width == null || height == null || width == 0 || height == 0) bad();
  // Bound each edge before multiplying; native overflow cannot be triggered.
  if (width > 8192 || height > 8192 || width * height > 16777216) {
    throw const TransferException(
      'Image dimensions are too large. Crop or save smaller (8192 per edge, 16 megapixels).',
    );
  }
  return (width: width, height: height);
}

bool _same(Uint8List b, int offset, List<int> expected) {
  for (var i = 0; i < expected.length; i++) {
    if (b[offset + i] != expected[i]) return false;
  }
  return true;
}

/// PNG CRC is checked only for IHDR (no raster inflation/allocation).
int imageHeaderCrc(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
