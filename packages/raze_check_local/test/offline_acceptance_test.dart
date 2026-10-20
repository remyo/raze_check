@Timeout(Duration(minutes: 4))
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/acceptance_device.dart';
import 'support/acceptance_scenarios.dart';
import 'support/memory_key_store.dart';

void main() {
  test(
    'real offline flow and owner recovery retain history through authorized queries',
    () async {
      final root = await acceptanceDirectory('host');
      final devices = <AcceptanceDevice>[];
      for (final role in ['manager', 'staff', 'target']) {
        final d = AcceptanceDevice(
          AppPaths(Directory('${root.path}/$role')),
          MemoryKeyStore(),
        );
        await d.open(name: 'Synthetic $role');
        devices.add(d);
      }
      addTearDown(() async {
        for (final d in devices) {
          await d.close();
        }
        await root.delete(recursive: true);
      });
      await recoveryAcceptance(devices[0], devices[1], devices[2]);
    },
  );
}
