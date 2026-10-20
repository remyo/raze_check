import '../guides/guide_scope.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'scan_screen.dart';

/// Each operation captures a fresh port bound to its ORIGINAL guard and anchor.
final class FeatureMessagePort
    implements
        EnrollmentMessagePort,
        AttendanceMessagePort,
        ContextualMessagePort {
  FeatureMessagePort({required this.context, required this.create});
  final BuildContext Function() context;
  final TransferPort Function(TransferGuard) create;
  Future<T> _withGuidePaused<T>(Future<T> Function() action) async {
    final source = context();
    final guides = source.mounted ? GuideScope.maybeOf(source) : null;
    final original = guides?.currentContext;
    final wasPaused = guides?.paused ?? false;
    guides?.setPaused(true);
    try {
      return await action();
    } finally {
      // Native outcomes retain their existing business guard. Guide resumption
      // is independently limited to the original live domain context.
      try {
        await original?.validateCurrent();
        if (source.mounted && !wasPaused) guides?.setPaused(false);
      } catch (_) {
        if (original != null) {
          guides?.invalidateAuthority(original.authorityToken);
        }
        if (!wasPaused) guides?.setPaused(false);
      }
    }
  }

  @override
  Future<Uint8List?> receive() =>
      throw StateError('Native transfer requires original context');
  @override
  Future<void> send(Uint8List bytes) =>
      throw StateError('Native transfer requires original context');
  @override
  Future<Uint8List?> receiveFor(
    Set<MessageKind> allowed,
    TransferGuard guard,
  ) => _withGuidePaused(() => _receiveFor(allowed, guard));
  Future<Uint8List?> _receiveFor(
    Set<MessageKind> allowed,
    TransferGuard guard,
  ) async {
    await guard();
    final ctx = context();
    if (!ctx.mounted) return null;
    final method = await showModalBottomSheet<int>(
      context: ctx,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Scan QR'),
              onTap: () => Navigator.pop(context, 0),
            ),
            ListTile(
              title: const Text('QR image from Files'),
              onTap: () => Navigator.pop(context, 1),
            ),
            ListTile(
              title: const Text('Message from Files'),
              onTap: () => Navigator.pop(context, 2),
            ),
          ],
        ),
      ),
    );
    if (method == null) return null;
    await guard();
    final port = create(guard);
    final bytes = await switch (method) {
      0 => port.scan(allowed: allowed),
      1 => port.decodePickedImage(),
      _ => port.pickMessage(),
    };
    if (bytes == null) return null;
    await guard();
    return validateTransferMessage(bytes, allowed);
  }

  @override
  Future<void> sendFor(Uint8List bytes, TransferGuard guard) =>
      _withGuidePaused(() => _sendFor(bytes, guard));
  Future<void> _sendFor(Uint8List bytes, TransferGuard guard) async {
    await guard();
    final ctx = context();
    if (!ctx.mounted) return;
    final method = await showModalBottomSheet<int>(
      context: ctx,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bytes.length <= MessageLimits.qrBytes)
              ListTile(
                title: const Text('Share QR image'),
                onTap: () => Navigator.pop(context, 0),
              ),
            ListTile(
              title: const Text('Share message file'),
              onTap: () => Navigator.pop(context, 1),
            ),
          ],
        ),
      ),
    );
    if (method == null) return;
    await guard();
    final port = create(guard);
    final outcome = method == 0
        ? await port.shareQrPng(bytes)
        : await port.shareMessage(bytes, 'message.razecheck-message');
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          ShareOutcome.opened => 'Share opened. Delivery is not confirmed.',
          ShareOutcome.dismissed => 'Share dismissed.',
          ShareOutcome.unavailable =>
            'Share result unavailable. Delivery is not confirmed.',
          ShareOutcome.failed =>
            'Could not open sharing. Retry from the saved message.',
        }),
      ),
    );
  }
}

Future<Uint8List?> receiveTransfer(
  Object port,
  Set<MessageKind> allowed,
  TransferGuard guard,
) async {
  await guard();
  final bytes = port is ContextualMessagePort
      ? await port.receiveFor(allowed, guard)
      : port is EnrollmentMessagePort
      ? await port.receive()
      : await (port as AttendanceMessagePort).receive();
  if (bytes == null) return null;
  await guard();
  return validateTransferMessage(bytes, allowed);
}

Future<void> sendTransfer(
  Object port,
  Uint8List bytes,
  TransferGuard guard,
) async {
  await guard();
  if (port is ContextualMessagePort) {
    await port.sendFor(bytes, guard);
  } else if (port is EnrollmentMessagePort) {
    await port.send(bytes);
  } else {
    await (port as AttendanceMessagePort).send(bytes);
  }
}
