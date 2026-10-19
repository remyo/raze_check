import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';

Future<IdentityService> createLocalIdentity() async {
  final paths = await AppPaths.persistent();
  final keys = OsSecureKeyStore();
  return LocalIdentityService(
    keys: keys,
    catalog: ProfileCatalog(paths: paths, keys: keys),
    clock: SystemCheckClock(),
    ids: SecureIds(),
  );
}
