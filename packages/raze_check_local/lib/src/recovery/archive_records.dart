import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'archive_codec.dart';

typedef ArchiveVisitor = Future<void> Function(String kind, Object value);

final class ArchiveRecord {
  const ArchiveRecord(this.category, this.record);
  final String category;
  final StoredRecord record;
}

final class ArchiveRevision {
  const ArchiveRevision(this.companyId, this.revision);
  final String companyId;
  final int revision;
}

/// Incrementally produces one strict JSON array. Definitions precede references;
/// byte-identical payloads and record descriptors alone are interned.
final class ArchiveRecords {
  final _out = BytesBuilder(copy: false);
  final _strings = <String, int>{};
  final _payloads = <String, ({int index, Uint8List bytes})>{};
  final _rows = <String, int>{};
  int _references = 0, _items = 0;
  ArchiveRecords() {
    _out.add(utf8.encode('[[1]\n'));
  }
  void _line(List<Object?> value) {
    final bytes = utf8.encode(',${jsonEncode(value)}\n');
    if (_out.length + bytes.length + 1 > ArchiveLimits.bytes) _limit();
    _out.add(bytes);
  }

  int _s(String value) {
    if (value.isEmpty || utf8.encode(value).length > 1024) _bad();
    return _strings.putIfAbsent(value, () {
      final i = _strings.length;
      _line(['s', value]);
      return i;
    });
  }

  Future<int> _p(Uint8List bytes) async {
    if (bytes.length > ArchiveLimits.otherEntry) _limit();
    final hash = base64UrlEncode((await Sha256().hash(bytes)).bytes);
    final old = _payloads[hash];
    if (old != null) {
      if (!_same(old.bytes, bytes)) _bad();
      return old.index;
    }
    final index = _payloads.length;
    _payloads[hash] = (index: index, bytes: bytes);
    _line(['p', hash, base64UrlEncode(bytes)]);
    return index;
  }

  Future<int> _r(StoredRecord row) async {
    final fields = <Object?>[
      _s(row.id),
      _s(row.companyId),
      _s(row.kind),
      row.revision,
      await _p(row.payload),
    ];
    final key = jsonEncode(fields);
    return _rows.putIfAbsent(key, () {
      final i = _rows.length;
      _line(['r', ...fields]);
      return i;
    });
  }

  void _charge(int bytes, [int items = 1]) {
    _references += bytes;
    _items += items;
    if (_references > ArchiveLimits.bytes || _items > ArchiveLimits.items) {
      _limit();
    }
  }

  static StoredRecord portableRecord(StoredRecord row) {
    if (row.kind != 'operatorCredential') return row;
    final j = jsonDecode(utf8.decode(row.payload)) as Map<String, dynamic>;
    return StoredRecord(
      row.id,
      row.companyId,
      'retiredLocalCredential',
      row.revision,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'reason': 'freshLocalSetupRequired',
            for (final key in [
              'id',
              'companyId',
              'membershipId',
              'personId',
              'installationId',
              'publicKey',
            ])
              key: j[key],
          }),
        ),
      ),
    );
  }

  Future<void> add(String kind, Object value) async {
    switch (kind) {
      case 'record':
        final original = value as ArchiveRecord;
        final r = ArchiveRecord(
          original.category,
          portableRecord(original.record),
        );
        _charge(r.record.payload.length);
        final index = await _r(r.record);
        _line(['e', _s(r.category), index]);
      case 'operation':
        final original = value as StoredOperation;
        final retired =
            original.retiredLocalCredential ||
            original.result?.kind == 'operatorCredential';
        final o = StoredOperation(
          companyId: original.companyId,
          operationId: original.operationId,
          authorityGenerationId: original.authorityGenerationId,
          requestDigest: retired ? Uint8List(32) : original.requestDigest,
          expectedRevision: original.expectedRevision,
          revision: original.revision,
          result: original.result == null
              ? null
              : portableRecord(original.result!),
          personalOwners: original.personalOwners,
          retiredLocalCredential: retired,
        );
        _charge(
          o.requestDigest.length + (o.result?.payload.length ?? 0),
          1 + o.personalOwners.length,
        );
        final result = o.result == null ? null : await _r(o.result!);
        _line([
          retired ? 't' : 'o',
          _s(o.companyId),
          _s(o.operationId),
          _s(o.authorityGenerationId),
          retired ? null : await _p(o.requestDigest),
          o.expectedRevision,
          o.revision,
          result,
          o.personalOwners.map(_s).toList(),
        ]);
      case 'journal':
        final j = value as RevisionEntry;
        _charge(0);
        _line(['j', _s(j.companyId), j.revision, _s(j.operationId)]);
      case 'association':
        final a = value as PersonalRecordAssociation;
        _charge(0);
        _line(['l', _s(a.companyId!), _s(a.recordId), _s(a.personId)]);
      case 'attachment':
        final a = value as AttachmentManifestEntry;
        _charge(0);
        _line([
          'a',
          _s(a.companyId),
          _s(a.recordId),
          _s(a.sha256),
          a.byteLength,
        ]);
      case 'revision':
        final r = value as ArchiveRevision;
        _charge(0);
        _line(['v', _s(r.companyId), r.revision]);
      default:
        _bad();
    }
  }

  Uint8List finish() {
    _out.addByte(93);
    return _out.takeBytes();
  }

  /// Parses one bounded line/item at a time, never jsonDecode of the full file.
  /// Tables have a hard byte/item bound inherited from the 64MiB encoded file.
  static Future<void> read(Uint8List bytes, ArchiveVisitor visit) async {
    final messages = ReceivePort();
    final worker = await Isolate.spawn(_readWorker, [messages.sendPort, bytes]);
    try {
      await for (final dynamic message in messages) {
        final event = message as List;
        if (event[0] == 'done') return;
        if (event[0] == 'error') {
          throw CheckException(CheckError.values.byName(event[1] as String));
        }
        await visit(event[0] as String, event[1] as Object);
        (event[2] as SendPort).send(null);
      }
    } finally {
      worker.kill(priority: Isolate.immediate);
      messages.close();
    }
  }

  static Future<void> readInline(Uint8List bytes, ArchiveVisitor visit) async {
    if (bytes.length > ArchiveLimits.bytes) _limit();
    final strings = <String>[],
        payloads = <Uint8List>[],
        rows = <List<dynamic>>[];
    final uniqueStrings = <String>{},
        uniquePayloads = <String>{},
        uniqueRows = <String>{},
        logical = <String>{};
    final usedPayloads = <int>{}, usedRows = <int>{}, usedStrings = <int>{};
    var pos = 0, lineNo = 0, references = 0, items = 0;
    String s(dynamic n) {
      if (n is! int || n < 0 || n >= strings.length) _bad();
      usedStrings.add(n);
      return strings[n];
    }

    Uint8List p(dynamic n) {
      if (n is! int || n < 0 || n >= payloads.length) _bad();
      return payloads[n];
    }

    int integer(dynamic n, {bool zero = false}) {
      if (n is! int || n < (zero ? 0 : 1)) _bad();
      return n;
    }

    StoredRecord r(dynamic n) {
      if (n is! int || n < 0 || n >= rows.length) _bad();
      usedRows.add(n);
      final v = rows[n];
      usedPayloads.add(v[5] as int);
      return StoredRecord(s(v[1]), s(v[2]), s(v[3]), integer(v[4]), p(v[5]));
    }

    void charge(int length, [int count = 1]) {
      references += length;
      items += count;
      if (references > ArchiveLimits.bytes || items > ArchiveLimits.items) {
        _limit();
      }
    }

    void unique(Object key) {
      if (!logical.add(jsonEncode(key))) _bad();
    }

    try {
      while (pos < bytes.length) {
        var end = pos;
        while (end < bytes.length && bytes[end] != 10) {
          end++;
        }
        if (end - pos > ArchiveLimits.otherEntry * 4 ~/ 3 + 256) _limit();
        final line = utf8.decode(Uint8List.sublistView(bytes, pos, end));
        pos = end + 1;
        if (lineNo++ == 0) {
          if (line != '[[1]') _bad();
          continue;
        }
        if (line == ']') {
          if (end != bytes.length ||
              usedRows.length != rows.length ||
              usedStrings.length != strings.length ||
              usedPayloads.length != payloads.length) {
            _bad();
          }
          return;
        }
        if (!line.startsWith(',')) _bad();
        final v = jsonDecode(line.substring(1));
        if (v is! List || v.isEmpty) _bad();
        final tag = v[0];
        final lengths = {
          's': 2,
          'p': 3,
          'r': 6,
          'e': 3,
          'o': 9,
          't': 9,
          'j': 4,
          'l': 4,
          'a': 5,
          'v': 3,
        };
        if (lengths[tag] != v.length) _bad();
        switch (tag) {
          case 's':
            final text = v[1];
            if (text is! String ||
                text.isEmpty ||
                utf8.encode(text).length > 1024 ||
                !uniqueStrings.add(text)) {
              _bad();
            }
            strings.add(text);
          case 'p':
            if (v[1] is! String || v[2] is! String) _bad();
            final raw = base64Url.decode(v[2] as String);
            if (raw.length > ArchiveLimits.otherEntry) _limit();
            if (base64UrlEncode(raw) != v[2] ||
                base64UrlEncode((await Sha256().hash(raw)).bytes) != v[1] ||
                !uniquePayloads.add(v[1] as String)) {
              _bad();
            }
            payloads.add(raw);
          case 'r':
            s(v[1]);
            s(v[2]);
            s(v[3]);
            integer(v[4]);
            p(v[5]);
            if (!uniqueRows.add(jsonEncode(v))) _bad();
            rows.add(v);
          case 'e':
            final category = s(v[1]), row = r(v[2]);
            if (!{
              'entity',
              'event',
              'outbox',
              'authority',
              'recovery',
            }.contains(category)) {
              _bad();
            }
            unique(['e', row.companyId, row.id]);
            charge(row.payload.length);
            await visit('record', ArchiveRecord(category, row));
          case 'o':
          case 't':
            final company = s(v[1]),
                op = s(v[2]),
                authority = s(v[3]),
                digest = tag == 't' ? Uint8List(32) : p(v[4]);
            if (tag == 't' && v[4] != null) _bad();
            if (tag == 'o') usedPayloads.add(v[4] as int);
            final expected = v[5] == null ? null : integer(v[5], zero: true),
                revision = v[6] == null ? null : integer(v[6]);
            final result = v[7] == null ? null : r(v[7]);
            if (digest.length != 32 ||
                (revision == null) != (result == null) ||
                result != null && result.companyId != company ||
                v[8] is! List) {
              _bad();
            }
            final owners = (v[8] as List).map(s).toSet();
            if (owners.length != (v[8] as List).length) _bad();
            unique(['o', company, op]);
            charge(
              digest.length + (result?.payload.length ?? 0),
              1 + owners.length,
            );
            await visit(
              'operation',
              StoredOperation(
                companyId: company,
                operationId: op,
                authorityGenerationId: authority,
                requestDigest: digest,
                expectedRevision: expected,
                revision: revision,
                result: result,
                personalOwners: owners,
                retiredLocalCredential: tag == 't',
              ),
            );
          case 'j':
            final c = s(v[1]), rev = integer(v[2]), op = s(v[3]);
            unique(['j', c, rev]);
            unique(['jo', c, op]);
            charge(0);
            await visit('journal', RevisionEntry(c, rev, op));
          case 'l':
            final c = s(v[1]), id = s(v[2]), person = s(v[3]);
            unique(['l', c, id, person]);
            charge(0);
            await visit(
              'association',
              PersonalRecordAssociation(person, id, companyId: c),
            );
          case 'a':
            final c = s(v[1]),
                id = s(v[2]),
                hash = s(v[3]),
                length = integer(v[4], zero: true);
            if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
                length > ArchiveLimits.otherEntry) {
              _bad();
            }
            unique(['a', c, id, hash]);
            charge(0);
            await visit(
              'attachment',
              AttachmentManifestEntry(
                companyId: c,
                recordId: id,
                sha256: hash,
                byteLength: length,
              ),
            );
          case 'v':
            final c = s(v[1]), rev = integer(v[2], zero: true);
            unique(['v', c]);
            charge(0);
            await visit('revision', ArchiveRevision(c, rev));
        }
        if (strings.length + payloads.length + rows.length >
            ArchiveLimits.items * 3) {
          _limit();
        }
      }
      _bad();
    } on CheckException {
      rethrow;
    } catch (_) {
      _bad();
    }
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Never _bad() => throw const CheckException(CheckError.malformed);
  static Never _limit() => throw const CheckException(CheckError.limitExceeded);
}

void _readWorker(List<dynamic> args) async {
  final output = args[0] as SendPort;
  try {
    await ArchiveRecords.readInline(args[1] as Uint8List, (kind, value) async {
      final ack = ReceivePort();
      try {
        output.send([kind, value, ack.sendPort]);
        await ack.first;
      } finally {
        ack.close();
      }
    });
    output.send(['done']);
  } catch (e) {
    output.send([
      'error',
      e is CheckException ? e.code.name : CheckError.malformed.name,
    ]);
  }
}

/// A persistent encoder isolate with one awaited input at a time.
final class ArchiveRecordWorker {
  ArchiveRecordWorker._(this.worker, this.input);
  final Isolate worker;
  final SendPort input;
  static Future<ArchiveRecordWorker> start() async {
    final ready = ReceivePort();
    final worker = await Isolate.spawn(_encodeWorker, ready.sendPort);
    final input = await ready.first as SendPort;
    ready.close();
    return ArchiveRecordWorker._(worker, input);
  }

  Future<dynamic> _call(List<Object?> args) async {
    final reply = ReceivePort();
    try {
      input.send([...args, reply.sendPort]);
      final result = await reply.first as List;
      if (result[0] == 'error') {
        throw CheckException(CheckError.values.byName(result[1] as String));
      }
      return result[1];
    } finally {
      reply.close();
    }
  }

  Future<void> add(String kind, Object value) async {
    await _call(['add', kind, value]);
  }

  Future<Uint8List> finish() async => await _call(['finish']) as Uint8List;
  void dispose() => worker.kill(priority: Isolate.immediate);
}

void _encodeWorker(SendPort ready) async {
  final messages = ReceivePort();
  ready.send(messages.sendPort);
  final encoder = ArchiveRecords();
  await for (final dynamic value in messages) {
    final request = value as List, reply = request.last as SendPort;
    try {
      if (request[0] == 'finish') {
        reply.send(['ok', encoder.finish()]);
        messages.close();
        break;
      }
      await encoder.add(request[1] as String, request[2] as Object);
      reply.send(['ok', null]);
    } catch (e) {
      reply.send([
        'error',
        e is CheckException ? e.code.name : CheckError.malformed.name,
      ]);
    }
  }
}
