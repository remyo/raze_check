import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';

Uint8List png(int w, int h) {
  final b = Uint8List(33);
  b.setAll(0, [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82]);
  final d = ByteData.sublistView(b);
  d.setUint32(16, w);
  d.setUint32(20, h);
  b[24] = 8;
  b[25] = 2;
  d.setUint32(29, imageHeaderCrc(b.sublist(12, 29)));
  return b;
}

void main() {
  test(
    'decoded Apple bytes exclude Vision headers and retain exact wire bytes',
    () {
      final payload = Uint8List.fromList([32, 91, 93, 32]);
      expect(
        qrBytes(
          BarcodeCapture(
            barcodes: [
              Barcode(
                format: BarcodeFormat.qrCode,
                rawDecodedBytes: DecodedVisionBarcodeBytes(
                  rawBytes: Uint8List.fromList([99, ...payload]),
                  bytes: payload,
                ),
              ),
            ],
          ),
        ).single,
        orderedEquals(payload),
      );
      expect(
        qrBytes(
          BarcodeCapture(
            barcodes: [Barcode(format: BarcodeFormat.qrCode, rawValue: ' [] ')],
          ),
        ).single,
        orderedEquals(payload),
      );
    },
  );
  test(
    'share staging revalidates before opening and cleans rejected staging',
    () async {
      final dir = await Directory.systemTemp.createTemp('raze-share-test-');
      addTearDown(() => dir.delete(recursive: true));
      var opened = 0;
      final ready = Completer<void>();
      final release = Completer<void>();
      final sharing = SharePort(
        directory: () async {
          ready.complete();
          await release.future;
          return dir;
        },
        share: (params) async {
          opened++;
          return const ShareResult('', ShareResultStatus.success);
        },
      );
      var current = true;
      final pending = sharing.share(
        Uint8List(10),
        'message.razecheck-message',
        'application/octet-stream',
        guard: () async {
          if (!current) {
            throw const TransferException(
              'Return to the original company to continue',
            );
          }
        },
        anchor: () => const Rect.fromLTWH(10, 20, 100, 50),
      );
      await ready.future;
      current = false;
      final expectation = expectLater(
        pending,
        throwsA(isA<TransferException>()),
      );
      release.complete();
      await expectation;
      expect(opened, 0);
      expect(
        await Directory('${dir.path}/raze-share-staging').list().length,
        0,
      );
    },
  );
  test(
    'share keeps exact bytes with iPad anchor, serializes, expires only owned files',
    () async {
      final dir = await Directory.systemTemp.createTemp('raze-share-test-');
      addTearDown(() => dir.delete(recursive: true));
      final persistent = File('${dir.path}/event')
        ..writeAsStringSync('persistent');
      final done = Completer<ShareResult>();
      final shown = Completer<ShareParams>();
      final sharing = SharePort(
        directory: () async => dir,
        share: (params) {
          shown.complete(params);
          return done.future;
        },
      );
      final payload = Uint8List.fromList([32, 91, 93, 32]);
      final pending = sharing.share(
        payload,
        'message.razecheck-message',
        'application/octet-stream',
        guard: () async {},
        anchor: () => const Rect.fromLTWH(10, 20, 100, 50),
      );
      final params = await shown.future;
      expect(params.sharePositionOrigin, const Rect.fromLTWH(10, 20, 100, 50));
      expect(await params.files!.single.readAsBytes(), orderedEquals(payload));
      expect(
        await sharing.share(
          payload,
          'x',
          'x',
          guard: () async {},
          anchor: () => Rect.zero,
        ),
        ShareOutcome.unavailable,
      );
      done.complete(const ShareResult('', ShareResultStatus.success));
      expect(await pending, ShareOutcome.opened);
      expect(await File(params.files!.single.path).exists(), true);
      final later = SharePort(
        now: () => DateTime.now().add(const Duration(days: 2)),
      );
      await later.expire(Directory('${dir.path}/raze-share-staging'));
      expect(await File(params.files!.single.path).exists(), false);
      expect(await persistent.readAsString(), 'persistent');
    },
  );

  test('header guard rejects malformed and pixel bombs before decode', () {
    final corrupt = png(100, 100)..[29] = 0;
    expect(() => validateQrImage(corrupt), throwsA(isA<TransferException>()));
    final jpeg = Uint8List.fromList([
      255,
      216,
      255,
      192,
      0,
      11,
      8,
      0,
      100,
      0,
      100,
      1,
      1,
      17,
      0,
    ]);
    expect(validateQrImage(jpeg), (width: 100, height: 100));
    expect(
      () => validateQrImage(jpeg.sublist(0, 12)),
      throwsA(isA<TransferException>()),
    );
    expect(
      () => validateQrImage(png(8193, 1)),
      throwsA(isA<TransferException>()),
    );
    expect(
      () => validateQrImage(png(8192, 8192)),
      throwsA(isA<TransferException>()),
    );
    expect(
      () => validateQrImage(png(0xffffffff, 0xffffffff)),
      throwsA(isA<TransferException>()),
    );
    expect(
      () => validateQrImage(Uint8List(20)),
      throwsA(isA<TransferException>()),
    );
    expect(() => validateQrImage(png(0, 1)), throwsA(isA<TransferException>()));
    expect(validateQrImage(png(4096, 4096)), (width: 4096, height: 4096));
  });
  test(
    'bounded staging ignores unknown or lying sizes and removes partial',
    () async {
      final dir = await Directory.systemTemp.createTemp('raze-transfer-test-');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/owned');
      await expectLater(
        copyBounded(
          Stream.fromIterable([Uint8List(8), Uint8List(9)]),
          target,
          16,
        ),
        throwsA(isA<TransferException>()),
      );
      expect(await target.exists(), false);
      await copyBounded(
        Stream.fromIterable([Uint8List(8), Uint8List(8)]),
        target,
        16,
      );
      expect(await target.length(), 16);
    },
  );
  test('document cancellation differs from unavailable offline file', () async {
    final cancel = DocumentPort(pick: (_) async => null);
    expect(await cancel.pickMessage(), isNull);
    final offline = DocumentPort(
      pick: (_) async =>
          throw const TransferException('Save the file locally and retry.'),
    );
    await expectLater(offline.pickMessage(), throwsA(isA<TransferException>()));
  });
}
