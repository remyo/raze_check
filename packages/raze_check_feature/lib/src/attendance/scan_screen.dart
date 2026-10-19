import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';

/// Camera implementation belongs to the host/local adapter; feature receives
/// only exact candidates. A single route completion gates repeated callbacks.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.camera,
    required this.allowed,
    required this.guard,
    required this.pickFile,
    required this.pickImage,
  });
  final Widget Function(ValueChanged<List<Uint8List>>) camera;
  final Set<MessageKind> allowed;
  final TransferGuard guard;
  final Future<Uint8List?> Function() pickFile, pickImage;
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool busy = false, finished = false;
  String? error;
  Future<void> accept(List<Uint8List> codes) async {
    if (busy || finished || codes.isEmpty) return;
    setState(() => busy = true);
    try {
      final bytes = await selectTransferMessage(context, codes, widget.allowed);
      if (bytes == null) return;
      await widget.guard();
      if (!mounted) return;
      finished = true;
      Navigator.pop(context, bytes);
    } catch (e) {
      if (mounted) setState(() => error = transferError(e));
    } finally {
      if (mounted && !finished) setState(() => busy = false);
    }
  }

  Future<void> pick(Future<Uint8List?> Function() action) async {
    if (busy || finished) return;
    setState(() => busy = true);
    try {
      await widget.guard();
      final bytes = await action();
      if (bytes == null) return;
      await widget.guard();
      if (!mounted) return;
      final validated = validateTransferMessage(bytes, widget.allowed);
      finished = true;
      Navigator.pop(context, validated);
    } catch (e) {
      if (mounted) setState(() => error = transferError(e));
    } finally {
      if (mounted && !finished) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan QR message')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: busy
                ? const Center(child: Text('Reading QR message…'))
                : widget.camera(accept),
          ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
          const Text(
            'You can also use Files, or ask a manager for assisted entry.',
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: busy ? null : () => pick(widget.pickFile),
                child: const Text('Message from Files'),
              ),
              TextButton(
                onPressed: busy ? null : () => pick(widget.pickImage),
                child: const Text('QR image from Files'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Uint8List validateTransferMessage(
  Uint8List bytes,
  Set<MessageKind> allowed, {
  int limit = MessageLimits.fileBytes,
}) {
  SignedMessage message;
  try {
    message = MessageCodec().decode(bytes, maxBytes: limit);
  } on CheckException catch (e) {
    if (e.code == CheckError.unsupportedVersion) {
      throw const TransferException(
        'Unsupported message type or version. Update Raze Check to read it.',
      );
    }
    throw const TransferException(
      'This is not a supported Raze Check message.',
    );
  }
  if (!allowed.contains(message.kind)) {
    throw TransferException(
      'This is a ${message.kind.name} message. This action accepts ${allowed.map((k) => k.name).join(', ')}.',
    );
  }
  return Uint8List.fromList(bytes);
}

Future<Uint8List?> selectTransferMessage(
  BuildContext context,
  List<Uint8List> candidates,
  Set<MessageKind> allowed,
) async {
  final unique = <String, Uint8List>{};
  for (final bytes in candidates) {
    unique[base64Encode(bytes)] = bytes;
  }
  if (unique.isEmpty) {
    throw const TransferException(
      'No QR message found. Save a clearer image and retry.',
    );
  }
  Uint8List? chosen;
  if (unique.length == 1) {
    chosen = unique.values.single;
  } else {
    chosen = await showDialog<Uint8List>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a QR message'),
        children: [
          for (final item in unique.values.indexed)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item.$2),
              child: Text('QR ${item.$1 + 1} · ${candidateLabel(item.$2)}'),
            ),
        ],
      ),
    );
  }
  return chosen == null
      ? null
      : validateTransferMessage(chosen, allowed, limit: MessageLimits.qrBytes);
}

String candidateLabel(Uint8List bytes) {
  try {
    return MessageCodec()
        .decode(bytes, maxBytes: MessageLimits.qrBytes)
        .kind
        .name;
  } catch (_) {
    return 'Unsupported message';
  }
}

String transferError(Object e) => e is TransferException
    ? e.message
    : e is CheckException && e.code == CheckError.locked
    ? 'Session expired. Unlock again to continue.'
    : 'Could not transfer this message. Please retry.';
