import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_local/raze_check_local.dart';

/// Host composition owns navigation, native adapters, and share serialization.
final class NativeTransfer implements TransferPort {
  NativeTransfer({
    required this.context,
    required this.guard,
    required this.documents,
    required this.qr,
    required this.sharing,
  });
  final BuildContext Function() context;
  final TransferGuard guard;
  final DocumentPort documents;
  final MobileQrPort qr;
  final SharePort sharing;
  @override
  Future<Uint8List?> scan({required Set<MessageKind> allowed}) async {
    await guard();
    final ctx = context();
    if (!ctx.mounted) return null;
    return Navigator.push<Uint8List>(
      ctx,
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          camera: qr.camera,
          allowed: allowed,
          guard: guard,
          pickFile: pickMessage,
          pickImage: decodePickedImage,
        ),
      ),
    );
  }

  @override
  Future<Uint8List?> pickMessage() => documents.pickMessage();
  @override
  Future<Uint8List?> decodePickedImage() async {
    final candidates = await qr.decodePickedImage();
    if (candidates == null) return null;
    await guard();
    final ctx = context();
    if (!ctx.mounted) return null;
    return selectTransferMessage(ctx, candidates, MessageKind.values.toSet());
  }

  Future<void> _visibleGuard() async {
    await guard();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      throw const TransferException('Return to the original screen to share.');
    }
  }

  Rect _anchor() {
    final ctx = context();
    if (!ctx.mounted) {
      throw const TransferException('Return to the original screen to share.');
    }
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      throw const TransferException('Share position unavailable. Retry.');
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Future<ShareOutcome> shareMessage(Uint8List bytes, String suggestedName) {
    MessageCodec().decode(bytes, maxBytes: MessageLimits.fileBytes);
    return sharing.share(
      bytes,
      'message.razecheck-message',
      'application/octet-stream',
      guard: _visibleGuard,
      anchor: _anchor,
    );
  }

  @override
  Future<ShareOutcome> shareQrPng(Uint8List messageBytes) async {
    if (messageBytes.length > MessageLimits.qrBytes) {
      return shareMessage(messageBytes, 'message.razecheck-message');
    }
    final png = await renderMessageQrPng(messageBytes);
    return sharing.share(
      png,
      'message.png',
      'image/png',
      guard: _visibleGuard,
      anchor: _anchor,
    );
  }
}
