import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:raze_check_core/raze_check_core.dart';

QrCode messageQr(Uint8List bytes) {
  if (bytes.length > MessageLimits.qrBytes) {
    throw const TransferException('Message needs a .razecheck-message file.');
  }
  final result = QrValidator.validate(
    data: utf8.decode(bytes),
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
  );
  if (result.qrCode == null) {
    throw const TransferException('Message needs file transfer.');
  }
  return result.qrCode!;
}

class ExactMessageQr extends StatelessWidget {
  const ExactMessageQr({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) {
    final qr = messageQr(bytes);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, 360.0)
            : 320.0;
        return SizedBox(
          width: size,
          height: size,
          child: QrImageView.withQr(
            qr: qr,
            backgroundColor: Colors.white,
            padding: EdgeInsets.all(size * 4 / (qr.moduleCount + 8)),
          ),
        );
      },
    );
  }
}

Future<Uint8List> renderMessageQrPng(Uint8List bytes) async {
  final qr = messageQr(bytes);
  final moduleScale = 1024 ~/ (qr.moduleCount + 8);
  final size = moduleScale * qr.moduleCount.toDouble();
  final offset = (1024 - size) / 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1024, 1024),
    Paint()..color = Colors.white,
  );
  canvas.translate(offset, offset);
  QrPainter.withQr(qr: qr, gapless: true).paint(canvas, Size.square(size));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1024, 1024);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const TransferException(
        'Could not render QR. Share the message file.',
      );
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
