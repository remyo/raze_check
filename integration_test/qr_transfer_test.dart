// Physical devices only. iOS Simulator analyzeImage is explicitly unsupported.
// Run automatic image tests first; opt into interactive camera/Files/share only
// with a free device, airplane mode set by its operator, and fixture prepared.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../packages/raze_check_core/test/support/message_vectors.dart';
import 'transfer_image_fixture.dart';

const interactive = bool.fromEnvironment('RAZE_TRANSFER_INTERACTIVE');
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final expected = base64Decode(transferWireBase64);
  Future<void> verify(Uint8List bytes) async {
    expect(bytes, orderedEquals(expected));
    final vectors = await MessageVectors.create();
    final decoded = MessageCodec().decode(bytes, maxBytes: 1500);
    final verified = await MessageVerifier(
      vectors.keys,
    ).verify(decoded, vectors.trust);
    expect(verified.message.kind, MessageKind.attendance);
  }

  for (final format in ['png', 'jpeg']) {
    testWidgets(
      'physical native $format decode preserves 1500 original bytes and signature',
      (tester) async {
        final dir = await Directory.systemTemp.createTemp('raze-task9-image-');
        addTearDown(() => dir.delete(recursive: true));
        final image = File('${dir.path}/fixture.$format');
        await image.writeAsBytes(
          format == 'png'
              ? await renderMessageQrPng(expected)
              : base64Decode(transferJpegBase64),
        );
        // Injects only the controlled path to isolate native ML Kit/Vision from
        // interactive Files. It is NOT evidence of document-provider execution.
        final qr = MobileQrPort(DocumentPort(pick: (_) async => image.path));
        final candidates = await qr.decodePickedImage();
        expect(candidates, hasLength(1));
        await verify(candidates!.single);
      },
    );
  }
  testWidgets('physical offline live camera exact bytes and signature', (
    tester,
  ) async {
    final qr = MobileQrPort(DocumentPort());
    Uint8List? scanned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              scanned = await Navigator.push<Uint8List>(
                context,
                MaterialPageRoute(
                  builder: (_) => ScanScreen(
                    camera: qr.camera,
                    allowed: {MessageKind.attendance},
                    guard: () async {},
                    pickFile: () async => null,
                    pickImage: () async => null,
                  ),
                ),
              );
            },
            child: const Text('Start physical scan'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start physical scan'));
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (scanned == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(
      scanned,
      isNotNull,
      reason:
          'Operator must show exact generated fixture on another screen/print.',
    );
    await verify(scanned!);
  }, skip: !interactive);
  testWidgets('physical Files bridge message and image imports', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text(
            'Select the task9 message, then the task9 QR image from Files.',
          ),
        ),
      ),
    );
    final documents = DocumentPort();
    final bytes = await documents.pickMessage();
    expect(bytes, isNotNull);
    await verify(bytes!);
    final images = await MobileQrPort(documents).decodePickedImage();
    expect(images, hasLength(1));
    await verify(images!.single);
  }, skip: !interactive);
  testWidgets('physical native share opens with readable staged source', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('Use the share sheet to save the task9 message to Files.'),
        ),
      ),
    );
    final result = await SharePort().share(
      expected,
      'task9-fixture.razecheck-message',
      'application/octet-stream',
      guard: () async {},
      anchor: () => const Rect.fromLTWH(10, 10, 200, 100),
    );
    expect(result, isNot(ShareOutcome.failed));
    // External recipient readability/delivery must be inspected separately;
    // ShareOutcome.opened never establishes it.
  }, skip: !interactive);
}
