// Run from packages/raze_check_core. Deterministic public test seeds only.
import 'message_vectors.dart';

Future<void> main() async => (await MessageVectors.create()).writeFixtures();
