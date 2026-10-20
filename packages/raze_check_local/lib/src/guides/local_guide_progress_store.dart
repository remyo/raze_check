import 'dart:convert';
import 'dart:io';
import 'package:raze_check_core/raze_check_core.dart';
import '../files/app_paths.dart';

/// Bounded, atomic tutorial preferences. Errors are handled by the guide caller.
final class LocalGuideProgressStore implements GuideProgressStore {
  LocalGuideProgressStore({required AppPaths paths})
    : _file = File('${paths.root.path}/guide-progress.v1.json');

  static const _maxBytes = 65536;
  static final _id = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');
  final File _file;
  Future<void> _pending = Future.value();
  bool _disabled = false;

  Future<T> _ordered<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    // Keep the queue usable after a caller observes an operation failure.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _checkEnabled() {
    if (_disabled) throw StateError('Guide persistence disabled');
  }

  @override
  Future<GuideProgressSnapshot> read() => _ordered(_read);

  Future<GuideProgressSnapshot> _read() async {
    _checkEnabled();
    final bytes = <int>[];
    try {
      final input = await _file.open();
      try {
        while (bytes.length <= _maxBytes) {
          final chunk = await input.read(_maxBytes + 1 - bytes.length);
          if (chunk.isEmpty) break;
          bytes.addAll(chunk);
        }
      } finally {
        await input.close();
      }
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2 &&
          await _file.parent.exists() &&
          await FileSystemEntity.type(_file.path, followLinks: false) ==
              FileSystemEntityType.notFound) {
        return GuideProgressSnapshot();
      }
      rethrow;
    }
    try {
      if (bytes.length > _maxBytes) {
        throw const FormatException('Guide file too large');
      }
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map ||
          value['version'] != 1 ||
          value['version'] is! int ||
          value['entries'] is! List ||
          (value.containsKey('welcomeDismissed') &&
              value['welcomeDismissed'] is! bool)) {
        throw const FormatException('Invalid guide file');
      }
      final entries = value['entries'] as List;
      if (entries.length > 64) throw const FormatException('Too many guides');
      final snapshot = GuideProgressSnapshot(
        welcomeDismissed: value['welcomeDismissed'] as bool? ?? false,
        entries: entries.map((entry) {
          if (entry is! Map ||
              entry['guideId'] is! String ||
              entry['variantId'] is! String ||
              entry['contentRevision'] is! int ||
              (entry['stepId'] != null && entry['stepId'] is! String) ||
              (entry.containsKey('viewed') && entry['viewed'] is! bool) ||
              (entry.containsKey('invitationDismissed') &&
                  entry['invitationDismissed'] is! bool)) {
            throw const FormatException('Invalid guide entry');
          }
          return GuideProgress(
            guideId: entry['guideId'] as String,
            variantId: entry['variantId'] as String,
            contentRevision: entry['contentRevision'] as int,
            stepId: entry['stepId'] as String?,
            viewed: entry['viewed'] as bool? ?? false,
            invitationDismissed: entry['invitationDismissed'] as bool? ?? false,
          );
        }).toList(),
      );
      _validate(snapshot);
      return snapshot;
    } catch (_) {
      _disabled = true;
      rethrow;
    }
  }

  void _validate(GuideProgressSnapshot snapshot) {
    if (snapshot.entries.length > 64) {
      throw const FormatException('Too many guides');
    }
    for (final entry in snapshot.entries) {
      if (!_id.hasMatch(entry.guideId) ||
          !_id.hasMatch(entry.variantId) ||
          (entry.stepId != null && !_id.hasMatch(entry.stepId!)) ||
          entry.contentRevision <= 0) {
        throw const FormatException('Invalid guide values');
      }
    }
  }

  @override
  Future<void> write(GuideProgressSnapshot snapshot) => _ordered(() async {
    _checkEnabled();
    // Validate existing source even when the caller has never read it.
    await _read();
    _validate(snapshot);
    final bytes = utf8.encode(
      jsonEncode({
        'version': 1,
        'welcomeDismissed': snapshot.welcomeDismissed,
        'entries': snapshot.entries
            .map(
              (entry) => {
                'guideId': entry.guideId,
                'variantId': entry.variantId,
                'contentRevision': entry.contentRevision,
                'stepId': entry.stepId,
                'viewed': entry.viewed,
                'invitationDismissed': entry.invitationDismissed,
              },
            )
            .toList(),
      }),
    );
    if (bytes.length > _maxBytes) {
      throw const FormatException('Guide output too large');
    }
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(_file.path);
  });

  @override
  Future<void> flush() => _pending;
}
