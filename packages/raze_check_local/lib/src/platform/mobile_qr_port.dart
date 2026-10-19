import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'document_port.dart';

/// Uses decoded bytes, never Apple's Vision QR headers/padding.
List<Uint8List> qrBytes(BarcodeCapture capture) {
  final unique = <String, Uint8List>{};
  for (final code in capture.barcodes) {
    if (code.format != BarcodeFormat.qrCode) continue;
    final decoded = switch (code.rawDecodedBytes) {
      DecodedBarcodeBytes(:final bytes) => bytes,
      DecodedVisionBarcodeBytes(:final bytes) => bytes,
      null => null,
    };
    final bytes =
        decoded ??
        (code.rawValue == null
            ? null
            : Uint8List.fromList(utf8.encode(code.rawValue!)));
    if (bytes != null) unique[base64Encode(bytes)] = bytes;
  }
  return unique.values.toList();
}

final class MobileQrPort {
  MobileQrPort(this.documents);
  final DocumentPort documents;
  Future<List<Uint8List>?> decodePickedImage() async {
    final file = await documents.pick(DocumentPurpose.image);
    if (file == null) return null;
    final controller = MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
    );
    try {
      // Native stream bound has already run. This is bounded compressed data,
      // inspected structurally before the native decoder allocates a raster.
      validateQrImage(await file.readAsBytes());
      final capture = await controller.analyzeImage(
        file.path,
        formats: const [BarcodeFormat.qrCode],
      );
      return capture == null ? [] : qrBytes(capture);
    } on TransferException {
      rethrow;
    } catch (_) {
      throw const TransferException(
        'Could not decode this PNG/JPEG. Save a clear QR image and retry.',
      );
    } finally {
      await controller.dispose();
      await file.delete();
    }
  }

  Widget camera(ValueChanged<List<Uint8List>> onCodes) =>
      _Camera(onCodes: onCodes);
}

class _Camera extends StatefulWidget {
  const _Camera({required this.onCodes});
  final ValueChanged<List<Uint8List>> onCodes;
  @override
  State<_Camera> createState() => _CameraState();
}

class _CameraState extends State<_Camera> with WidgetsBindingObserver {
  final controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    returnImage: false,
  );
  bool active = true;
  Future<void> operations = Future.value();
  void change(bool start) {
    active = start;
    operations = operations.then((_) async {
      if (!mounted) return;
      try {
        if (active) {
          await controller.start();
        } else {
          await controller.stop();
        }
      } catch (_) {
        /* errorBuilder explains camera failures */
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => change(true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      change(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    active = false;
    unawaited(operations.then((_) => controller.dispose()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
    controller: controller,
    onDetect: (capture) {
      if (active) widget.onCodes(qrBytes(capture));
    },
    errorBuilder: (_, _) => const Center(
      child: Text(
        'Camera unavailable or permission denied. Use Files below, or ask a manager for assisted entry.',
      ),
    ),
  );
}
