@Timeout(Duration(minutes: 2))
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/src/profile/profile_gate.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../../raze_check_local/test/support/acceptance_device.dart';
import '../../raze_check_local/test/support/memory_key_store.dart';

final class UnavailableKeys extends MemoryKeyStore {
  bool unavailable = false;
  @override
  Future<Uint8List?> read(String id) {
    if (unavailable) throw const CheckException(CheckError.storageFailure);
    return super.read(id);
  }
}

Future<void> settle(WidgetTester tester, {String? untilText}) async {
  await tester.runAsync(() async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    for (var i = 0; DateTime.now().isBefore(end); i++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (untilText != null
          ? find.text(untilText).evaluate().isNotEmpty
          : i > 2 &&
                find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
    throw StateError('Profile read did not settle');
  });
}

void main() {
  testWidgets(
    'lost catalog key explains fresh external recovery without clearing data',
    (tester) async {
      final keys = MemoryKeyStore();
      final device = (await tester.runAsync(() async {
        final d = AcceptanceDevice(
          AppPaths(await acceptanceDirectory('guidance')),
          keys,
        );
        await d.open();
        return d;
      }))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await device.close();
          await device.paths.root.delete(recursive: true);
        });
      });
      final before = (await tester.runAsync(device.paths.catalog.readAsBytes))!;
      await keys.delete('vault:installation-catalog');
      await tester.pumpWidget(
        MaterialApp(home: CheckProfileGate(identity: device.identity)),
      );
      await settle(tester);
      expect(
        find.textContaining('another device or a fresh installation'),
        findsOneWidget,
      );
      expect(find.textContaining('Keep the existing data'), findsOneWidget);
      expect(find.text('Create local profile'), findsNothing);
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(
        await tester.runAsync(device.paths.catalog.readAsBytes),
        orderedEquals(before),
      );
      expect(await keys.read('vault:installation-catalog'), isNull);
    },
  );
  testWidgets(
    'temporary secure-store failure offers retry and recovers existing profile',
    (tester) async {
      final keys = UnavailableKeys();
      final device = (await tester.runAsync(() async {
        final d = AcceptanceDevice(
          AppPaths(await acceptanceDirectory('temporary-keys')),
          keys,
        );
        await d.open();
        return d;
      }))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await device.close();
          await device.paths.root.delete(recursive: true);
        });
      });
      keys.unavailable = true;
      await tester.pumpWidget(
        MaterialApp(home: CheckProfileGate(identity: device.identity)),
      );
      await settle(tester);
      expect(find.textContaining('Try again'), findsOneWidget);
      expect(
        find.textContaining('another device or a fresh installation'),
        findsNothing,
      );
      keys.unavailable = false;
      expect(await tester.runAsync(device.identity.profiles), hasLength(1));
      await tester.runAsync(() => tester.tap(find.text('Retry')));
      await settle(tester, untilText: 'Unlock Synthetic owner');
      expect(find.text('Unlock Synthetic owner'), findsOneWidget);
    },
  );
}
