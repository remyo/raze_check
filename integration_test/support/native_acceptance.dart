import 'dart:io';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../../packages/raze_check_local/test/support/acceptance_device.dart';

/// Never opens the ordinary app profile catalog or deletes preexisting keys.
Future<List<AcceptanceDevice>> nativeAcceptanceDevices(
  List<String> roles,
) async {
  final base = await AppPaths.persistent(), run = SecureIds().next();
  final result = <AcceptanceDevice>[];
  for (final role in roles) {
    final device = AcceptanceDevice(
      AppPaths(Directory('${base.root.path}/acceptance/$run/$role')),
      NamespacedKeys(OsSecureKeyStore(), 'acceptance:$run:$role'),
    );
    await device.open(name: 'Synthetic $role');
    result.add(device);
  }
  return result;
}

Future<void> closeNativeAcceptance(List<AcceptanceDevice> devices) async {
  for (final device in devices) {
    await device.close();
  }
  // Retain owned synthetic files/OS keys for inspection; no global cleanup.
}
