import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:share_plus/share_plus.dart';

/// Owns temporary exports only. Persistent event/archive sources are untouched.
final class SharePort {
  SharePort({
    Future<Directory> Function()? directory,
    Future<ShareResult> Function(ShareParams)? share,
    DateTime Function()? now,
  }) : _directory = directory ?? getTemporaryDirectory,
       _share = share ?? SharePlus.instance.share,
       _now = now ?? DateTime.now;
  final Future<Directory> Function() _directory;
  final Future<ShareResult> Function(ShareParams) _share;
  final DateTime Function() _now;
  bool _busy = false;
  Future<ShareOutcome> share(
    Uint8List bytes,
    String name,
    String mime, {
    required TransferGuard guard,
    required Rect Function() anchor,
  }) async {
    if (_busy) return ShareOutcome.unavailable;
    _busy = true;
    File? staged;
    var opened = false;
    try {
      if (bytes.length > 64 * 1024 * 1024) {
        throw const TransferException('Export exceeds 64 MiB.');
      }
      final dir = await Directory(
        '${(await _directory()).path}/raze-share-staging',
      ).create(recursive: true);
      await expire(dir);
      final safeName = RegExp(r'^[a-zA-Z0-9._-]{1,80}$').hasMatch(name)
          ? name
          : 'message.razecheck-message';
      final owned = await Directory(
        '${dir.path}/${SecureIds().next()}',
      ).create();
      staged = File('${owned.path}/$safeName');
      await staged.writeAsBytes(bytes, flush: true);
      // This MUST run after all awaits in staging and directly before opening.
      await guard();
      final origin = anchor();
      if (!origin.isFinite || origin.width <= 0 || origin.height <= 0) {
        throw const TransferException(
          'Return to the original screen to share.',
        );
      }
      opened = true;
      final result = await _share(
        ShareParams(
          files: [XFile(staged.path, mimeType: mime)],
          fileNameOverrides: [safeName],
          sharePositionOrigin: origin,
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => ShareOutcome.opened,
        ShareResultStatus.dismissed => ShareOutcome.dismissed,
        ShareResultStatus.unavailable => ShareOutcome.unavailable,
      };
    } on TransferException {
      rethrow;
    } on CheckException {
      rethrow;
    } catch (_) {
      return ShareOutcome.failed;
    } finally {
      _busy = false;
      if (!opened && staged != null && await staged.parent.exists()) {
        await staged.parent.delete(recursive: true);
      }
    }
  }

  Future<void> expire(Directory dir) async {
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is Directory &&
          _now().difference((await entry.stat()).modified) >
              const Duration(hours: 24)) {
        await entry.delete(recursive: true);
      }
    }
  }
}
