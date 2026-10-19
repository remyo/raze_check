// Regenerate with flutter test docs/testing/generate_transfer_fixture.dart.
// Writes only /tmp; sips converts the PNG for the checked-in JPEG test fixture.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import '../../packages/raze_check_core/test/support/message_vectors.dart';

void main() {
  testWidgets('generate signed transfer fixture', (tester) async {
    await tester.runAsync(() async {
      final vectors = await MessageVectors.create();
      final message = await vectors.signed(
        MessageKind.attendance,
        vectors.payload(MessageKind.attendance),
      );
      final original = MessageCodec().encode(message);
      final bytes = Uint8List.fromList([
        ...original,
        ...List.filled(1500 - original.length, 32),
      ]);
      await File(
        '/tmp/raze-task9-fixture.png',
      ).writeAsBytes(await renderMessageQrPng(bytes));
      await File(
        '/tmp/raze-task9-fixture.razecheck-message',
      ).writeAsBytes(bytes);
    });
  });
}
