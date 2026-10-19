import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../security/secure_key_store.dart';

abstract final class ArchiveLimits {
  static const bytes = 64 * 1024 * 1024;
  static const otherEntry = 8 * 1024 * 1024;
  static const entries = 10000;
  static const items = 524288;
}

/// Whole-body AES-GCM is deliberately bounded, and executed off the UI isolate.
/// Authentication completes BEFORE any ZIP metadata or content is inspected.
abstract final class ArchiveCodec {
  static Future<Uint8List> seal(
    Map<String, Uint8List> files,
    String passphrase,
  ) => Isolate.run(() async {
    if (passphrase.runes.length < 12) {
      throw const CheckException(CheckError.wrongSecret);
    }
    var total = 0;
    if (files.length > ArchiveLimits.entries) _limit();
    for (final e in files.entries) {
      _name(e.key);
      total += e.value.length;
      if (e.value.length > _entryLimit(e.key) || total > ArchiveLimits.bytes) {
        _limit();
      }
    }
    _required(files.keys.toSet());
    final archive = Archive();
    for (final e in files.entries) {
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    if (zip.length + 68 > ArchiveLimits.bytes) _limit();
    final header = Uint8List(52)..setRange(0, 8, 'RZCKBK01'.codeUnits);
    final h = ByteData.sublistView(header);
    h.setUint16(8, 1, Endian.little);
    header[10] = 1;
    header[11] = 1;
    header.setRange(12, 28, secureRandomBytes(16));
    header.setRange(28, 40, secureRandomBytes(12));
    h.setUint32(40, 600000, Endian.little);
    h.setUint64(44, zip.length, Endian.little);
    final key = await _key(passphrase, header.sublist(12, 28));
    final box = await AesGcm.with256bits().encrypt(
      zip,
      secretKey: key,
      nonce: header.sublist(28, 40),
      aad: header,
    );
    return Uint8List.fromList([...header, ...box.cipherText, ...box.mac.bytes]);
  });

  static Future<Map<String, Uint8List>> open(
    Uint8List bytes,
    String passphrase,
  ) => Isolate.run(() async {
    if (bytes.length > ArchiveLimits.bytes) _limit();
    if (bytes.length < 68) _bad();
    final h = ByteData.sublistView(bytes);
    if (ascii.decode(bytes.sublist(0, 8), allowInvalid: true) != 'RZCKBK01') {
      _bad();
    }
    if (h.getUint16(8, Endian.little) != 1 ||
        bytes[10] != 1 ||
        bytes[11] != 1 ||
        h.getUint32(40, Endian.little) != 600000) {
      throw const CheckException(CheckError.unsupportedVersion);
    }
    if (h.getUint64(44, Endian.little) != bytes.length - 68) _bad();
    final key = await _key(passphrase, bytes.sublist(12, 28));
    late List<int> plain;
    try {
      plain = await AesGcm.with256bits().decrypt(
        SecretBox(
          bytes.sublist(52, bytes.length - 16),
          nonce: bytes.sublist(28, 40),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: key,
        aad: bytes.sublist(0, 52),
      );
    } on SecretBoxAuthenticationError {
      throw const CheckException(CheckError.invalidSignature);
    }
    return decodeZip(Uint8List.fromList(plain));
  });
  static Future<SecretKey> _key(String pass, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(pass)), nonce: salt);

  /// Strict non-ZIP64, single-disk ZIP profile. Validate all structure before
  /// invoking deflate. No package decoder can coalesce duplicates or symlinks.
  static Map<String, Uint8List> decodeZip(Uint8List zip) {
    if (zip.length > ArchiveLimits.bytes) _limit();
    if (zip.length < 22) _bad();
    final d = ByteData.sublistView(zip);
    int u16(int p) {
      if (p < 0 || p + 2 > zip.length) _bad();
      return d.getUint16(p, Endian.little);
    }

    int u32(int p) {
      if (p < 0 || p + 4 > zip.length) _bad();
      return d.getUint32(p, Endian.little);
    }

    // V1 deliberately disallows comments, extra fields, ZIP64 and multidisk.
    final end = zip.length - 22;
    if (u32(end) != 0x06054b50 ||
        u16(end + 4) != 0 ||
        u16(end + 6) != 0 ||
        u16(end + 20) != 0) {
      _bad();
    }
    final count = u16(end + 10),
        central = u32(end + 16),
        centralSize = u32(end + 12);
    if (count > ArchiveLimits.entries) _limit();
    if (count != u16(end + 8) || central + centralSize != end) _bad();
    final entries = <(String, int, int, int, int, int)>[];
    final names = <String>{};
    var p = central, localEnd = 0, expanded = 0;
    for (var i = 0; i < count; i++) {
      if (p + 46 > end || u32(p) != 0x02014b50) _bad();
      final flags = u16(p + 8),
          method = u16(p + 10),
          crc = u32(p + 16),
          compressed = u32(p + 20),
          size = u32(p + 24);
      final n = u16(p + 28),
          extra = u16(p + 30),
          comment = u16(p + 32),
          offset = u32(p + 42),
          mode = u32(p + 38) >> 16;
      if (n == 0 ||
          n > 100 ||
          extra != 0 ||
          comment != 0 ||
          u16(p + 34) != 0 ||
          u32(p + 38) & 0x10 != 0 ||
          p + 46 + n > end ||
          flags & ~0x808 != 0 ||
          !(method == 0 || method == 8) ||
          (mode & 0xf000 != 0 && mode & 0xf000 != 0x8000)) {
        _bad();
      }
      final name = utf8.decode(zip.sublist(p + 46, p + 46 + n));
      _name(name);
      if (!names.add(name)) _bad();
      expanded += size;
      if (size > _entryLimit(name) || expanded > ArchiveLimits.bytes) _limit();
      if (offset != localEnd ||
          offset + 30 > central ||
          u32(offset) != 0x04034b50 ||
          u16(offset + 6) != flags ||
          u16(offset + 8) != method ||
          u16(offset + 26) != n ||
          u16(offset + 28) != 0) {
        _bad();
      }
      final start = offset + 30 + n;
      if (start + compressed > central ||
          utf8.decode(zip.sublist(offset + 30, start)) != name) {
        _bad();
      }
      var finish = start + compressed;
      if (flags & 8 == 0) {
        if (u32(offset + 14) != crc ||
            u32(offset + 18) != compressed ||
            u32(offset + 22) != size) {
          _bad();
        }
      } else {
        if (u32(offset + 14) != 0 ||
            u32(offset + 18) != 0 ||
            u32(offset + 22) != 0 ||
            finish + 16 > central ||
            u32(finish) != 0x08074b50 ||
            u32(finish + 4) != crc ||
            u32(finish + 8) != compressed ||
            u32(finish + 12) != size) {
          _bad();
        }
        finish += 16;
      }
      if (method == 0 && compressed != size) _bad();
      entries.add((name, start, compressed, size, method, crc));
      localEnd = finish;
      p += 46 + n;
    }
    if (p != end || localEnd != central) _bad();
    _required(names);
    final result = <String, Uint8List>{};
    try {
      for (final (name, start, length, size, method, crc) in entries) {
        final sink = _BoundedSink(size);
        final compressed = Uint8List.sublistView(zip, start, start + length);
        if (method == 0) {
          sink.add(compressed);
          sink.close();
        } else {
          final decoder = io.ZLibDecoder(
            raw: true,
          ).startChunkedConversion(sink);
          for (var at = 0; at < compressed.length; at += 32768) {
            decoder.add(
              Uint8List.sublistView(
                compressed,
                at,
                (at + 32768).clamp(0, compressed.length),
              ),
            );
          }
          decoder.close();
        }
        final value = sink.bytes.takeBytes();
        if (value.length != size || getCrc32(value) != crc) _bad();
        result[name] = value;
      }
    } on CheckException {
      rethrow;
    } catch (_) {
      _bad();
    }
    return result;
  }

  static int _entryLimit(String name) =>
      name == 'records.json' ? ArchiveLimits.bytes : ArchiveLimits.otherEntry;
  static void _required(Set<String> names) {
    if (!names.containsAll({
      'manifest.json',
      'records.json',
      'recovery.json',
    })) {
      _bad();
    }
  }

  static void _name(String name) {
    if (!{'manifest.json', 'records.json', 'recovery.json'}.contains(name) &&
        !RegExp(r'^attachments/[a-f0-9]{64}$').hasMatch(name)) {
      _bad();
    }
  }

  static Never _bad() => throw const CheckException(CheckError.malformed);
  static Never _limit() => throw const CheckException(CheckError.limitExceeded);
}

final class _BoundedSink extends ByteConversionSinkBase {
  _BoundedSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  int count = 0;
  @override
  void add(List<int> chunk) {
    count += chunk.length;
    if (count > limit) throw const CheckException(CheckError.limitExceeded);
    bytes.add(chunk);
  }

  @override
  void close() {}
}
