@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';
import '../../raze_check_local/test/receipt_import_test.dart' show service;
import 'capture_flow_test.dart' show CapturePort;
import 'support/settle_review.dart';

Uint8List wire(String id) => Uint8List.fromList(
  utf8.encode(
    jsonEncode([
      1,
      'replacementRequest',
      'ed25519:${'A' * 43}',
      base64UrlEncode(
        utf8.encode(
          jsonEncode([
            '00000000-0000-4000-8000-000000000001',
            id,
            0,
            '00000000-0000-4000-8000-000000000003',
            null,
            '00000000-0000-4000-8000-000000000004',
            base64UrlEncode(Uint8List(32)),
          ]),
        ),
      ),
      base64UrlEncode(Uint8List(64)),
    ]),
  ),
);
void main() {
  testWidgets(
    'repeated scanner callbacks persist one real signed attendance import',
    (tester) async {
      final pair = (await tester.runAsync(TwoDeviceFixture.create))!;
      addTearDown(() => tester.runAsync(pair.dispose));
      final receipt = (await tester.runAsync(() async {
        await pair.enrollStaff();
        return pair.captureCheckIn();
      }))!;
      final attendance = service(pair.manager);
      late ValueChanged<List<Uint8List>> callbacks;
      Future<void>? imported;
      final before = (await tester.runAsync(
        () => pair.manager.storage.repo.snapshot(CompanyScope(pair.companyId)),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final bytes = await Navigator.push<Uint8List>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScanScreen(
                      camera: (cb) {
                        callbacks = cb;
                        return const Text('controlled camera delivery');
                      },
                      allowed: {MessageKind.attendance},
                      guard: () async {},
                      pickFile: () async => null,
                      pickImage: () async => null,
                    ),
                  ),
                );
                if (bytes != null) {
                  imported = () async {
                    final verified = await attendance.verifyIncoming(
                      pair.manager.session,
                      pair.companyId,
                      bytes,
                    );
                    final result = await attendance.importReceipt(
                      pair.context(SecureIds().next()),
                      verified,
                    );
                    expect(result.status, ImportStatus.received);
                  }();
                }
              },
              child: const Text('Scan real receipt'),
            ),
          ),
        ),
      );
      // Start the route and its continuation in the real-I/O zone as well as
      // awaiting it there; an already-started fake-zone future can starve I/O.
      await tester.runAsync(() async {
        await tester.tap(find.text('Scan real receipt'));
        await tester.pumpAndSettle();
        callbacks([receipt.bytes]);
        callbacks([receipt.bytes]);
        await tester.pumpAndSettle();
        expect(imported, isNotNull);
        await imported!.timeout(const Duration(seconds: 20));
      });
      final after = (await tester.runAsync(
        () => pair.manager.storage.repo.snapshot(CompanyScope(pair.companyId)),
      ))!;
      expect(after.events.where((r) => r.kind == 'attendance'), hasLength(1));
      expect(
        after.records.where((r) => r.kind == 'receiptImport'),
        hasLength(1),
      );
      expect(after.operations.length, before.operations.length + 1);
      expect(after.journal.length, before.journal.length + 1);
      expect(
        after.events.singleWhere((r) => r.kind == 'attendance').payload,
        orderedEquals(receipt.bytes),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'restricted management operator can start authorized enrollment transfer',
    (tester) async {
      final pair = (await tester.runAsync(TwoDeviceFixture.create))!;
      addTearDown(pair.dispose);
      final session = (await tester.runAsync(() async {
        final staff =
            (await pair.manager.companies.createStaff(
                      pair.context('transfer-operator'),
                      const StaffDraft(name: 'Transfer operator'),
                    )
                    as Committed<StaffRecord>)
                .value;
        await pair.manager.companies.grantCapabilities(
          pair.context('transfer-grant'),
          staff.membershipId,
          {Capability.manageStaff},
        );
        await pair.manager.companies.activateOperator(
          pair.context('transfer-activate'),
          staff.membershipId,
          'transfer operator passphrase',
        );
        return pair.manager.companies.unlockOperator(
          pair.companyId,
          staff.membershipId,
          'transfer operator passphrase',
        );
      }))!;
      final port = CountedEnrollmentPort();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentWorkspace(
              service: pair.manager.enrollment,
              session: session,
              ids: SecureIds(),
              messages: port,
              company: pair.company,
              canManage: true,
              onChanged: () {},
              onLocked: () {},
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Read join request'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(port.reads, 1);
      expect(
        () => pair.manager.enrollment.requireTransferSession(
          session,
          companyId: SecureIds().next(),
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.wrongCompany,
          ),
        ),
      );
      pair.manager.identity.lock();
      expect(
        () => pair.manager.enrollment.requireTransferSession(
          session,
          companyId: pair.companyId,
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.locked,
          ),
        ),
      );
    },
  );

  testWidgets(
    'camera denial offers Files and manager assistance; cancel leaves no completion',
    (tester) async {
      var completed = false, reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final value = await Navigator.push<Uint8List>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScanScreen(
                      camera: (_) => const Text('Camera permission denied'),
                      allowed: {MessageKind.attendance},
                      guard: () async {},
                      pickFile: () async {
                        reads++;
                        return null;
                      },
                      pickImage: () async => null,
                    ),
                  ),
                );
                completed = value != null;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('manager for assisted entry'), findsOneWidget);
      await tester.tap(find.text('Message from Files'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(completed, false);
      expect(find.text('Camera permission denied'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(completed, false);
    },
  );

  testWidgets(
    'original company picker completion never imports into newly visible company',
    (tester) async {
      final pair = (await tester.runAsync(TwoDeviceFixture.create))!;
      addTearDown(pair.dispose);
      await tester.runAsync(pair.enrollStaff);
      final receiptForA = (await tester.runAsync(pair.captureCheckIn))!;
      final companyB = (await tester.runAsync(
        () async =>
            (await pair.manager.companies.createCompany(
                      pair.manager.session,
                      const CompanyDraft('B', 'Asia/Tokyo'),
                      'transfer-company-b',
                    )
                    as Committed<Company>)
                .value,
      ))!;
      final flow = TransferTestFlow(
        tester,
        pair,
        CapturePort()..delayed = Completer<Uint8List?>(),
      );
      await flow.startImportFor(pair.company);
      await flow.switchCompany(companyB);
      await flow.completePickerWith(receiptForA.bytes);
      expect(await flow.eventCount(companyB), 0);
      expect(await flow.eventCount(pair.company), 0);
      expect(
        find.text('Return to the original company to continue'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'session expiry during picker and cancellation create no import',
    (tester) async {
      final pair = (await tester.runAsync(TwoDeviceFixture.create))!;
      addTearDown(pair.dispose);
      await tester.runAsync(pair.enrollStaff);
      final receipt = (await tester.runAsync(pair.captureCheckIn))!;
      final port = CapturePort()..delayed = Completer<Uint8List?>();
      final flow = TransferTestFlow(tester, pair, port);
      await flow.startImportFor(pair.company);
      await flow.completePickerWith(null);
      expect(await flow.eventCount(pair.company), 0);
      port.delayed = Completer<Uint8List?>();
      await flow.startImportFor(pair.company);
      pair.manager.identity.lock();
      await flow.completePickerWith(receipt.bytes);
      expect(flow.locked, true);
      expect(
        await tester.runAsync(
          () => pair.manager.storage.repo.read(pair.companyId, receipt.eventId),
        ),
        isNull,
      );
    },
  );

  testWidgets(
    'multiple decoded messages require selection and callback repeats finish once',
    (tester) async {
      late ValueChanged<List<Uint8List>> codes;
      var completions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await Navigator.push<Uint8List>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScanScreen(
                      camera: (callback) {
                        codes = callback;
                        return const Text('camera');
                      },
                      allowed: {MessageKind.replacementRequest},
                      guard: () async {},
                      pickFile: () async => null,
                      pickImage: () async => null,
                    ),
                  ),
                );
                if (result != null) completions++;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final a = wire('00000000-0000-4000-8000-000000000011'),
          b = wire('00000000-0000-4000-8000-000000000012');
      codes([a, b]);
      codes([a, b]);
      await tester.pumpAndSettle();
      expect(find.text('Choose a QR message'), findsOneWidget);
      expect(completions, 0);
      await tester.tap(find.text('QR 2 · replacementRequest'));
      await tester.pumpAndSettle();
      expect(completions, 1);
    },
  );
  test('wrong purpose explains actual message kind', () {
    expect(
      () => validateTransferMessage(
        wire('00000000-0000-4000-8000-000000000011'),
        {MessageKind.attendance},
      ),
      throwsA(
        isA<TransferException>().having(
          (e) => e.message,
          'message',
          contains('replacementRequest'),
        ),
      ),
    );
  });
  testWidgets(
    'QR export has 1024 pixel white quiet zone and screen uses ECC M',
    (tester) async {
      final bytes = wire('00000000-0000-4000-8000-000000000011');
      final png = (await tester.runAsync(() => renderMessageQrPng(bytes)))!;
      expect(ByteData.sublistView(png).getUint32(16), 1024);
      expect(ByteData.sublistView(png).getUint32(20), 1024);
      final qr = messageQr(bytes);
      expect(qr.errorCorrectLevel, QrErrorCorrectLevel.M);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        final pixels = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final border = 4 * (1024 ~/ (qr.moduleCount + 8));
        for (var y = 0; y < 1024; y++) {
          for (var x = 0; x < 1024; x++) {
            if (x < border ||
                y < border ||
                x >= 1024 - border ||
                y >= 1024 - border) {
              final offset = 4 * (y * 1024 + x);
              if (pixels.getUint32(offset) != 0xffffffff) {
                fail('Quiet zone is not white');
              }
            }
          }
        }
        frame.image.dispose();
        codec.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: EnrollmentMessageView(
            message: MessageCodec().decode(bytes, maxBytes: 65536),
          ),
        ),
      );
      expect(find.byType(ExactMessageQr), findsOneWidget);
    },
  );
}

// Native picker is the only fake; real signatures, services and encrypted DBs.
class TransferTestFlow {
  TransferTestFlow(this.tester, this.pair, this.port);
  final WidgetTester tester;
  final TwoDeviceFixture pair;
  final CapturePort port;
  bool locked = false;
  Future<void> switchCompany(Company company) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewWorkspace(
              key: const Key('transfer-review'),
              service: service(pair.manager),
              session: pair.manager.session,
              company: company,
              ids: SecureIds(),
              canManage: true,
              staff: const [],
              messages: port,
              onChanged: () {},
              onLocked: () {
                locked = true;
              },
            ),
          ),
        ),
      );
    });
    await settleReview(tester);
  }

  Future<void> startImportFor(Company company) async {
    await switchCompany(company);
    await tester.runAsync(() async {
      await tester.tap(find.text('Import receipt or correction'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  }

  Future<void> completePickerWith(Uint8List? bytes) async {
    await tester.runAsync(() async {
      port.delayed!.complete(bytes);
    });
    await settleReview(tester);
  }

  Future<int?> eventCount(Company company) => tester.runAsync(
    () async => (await service(
      pair.manager,
    ).list(pair.manager.session, company.id)).length,
  );
}

class CountedEnrollmentPort implements EnrollmentMessagePort {
  int reads = 0;
  @override
  Future<Uint8List?> receive() async {
    reads++;
    return null;
  }

  @override
  Future<void> send(Uint8List bytes) async {}
}
