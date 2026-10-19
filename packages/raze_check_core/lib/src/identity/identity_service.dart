import '../contracts/context.dart';
import 'identity_models.dart';

abstract interface class IdentityService {
  Future<List<LocalProfile>> profiles();
  Future<SessionHandle> createProfile(String name, String passphrase);
  Future<SessionHandle> unlock(String personId, String passphrase);
  void lock();
  ActorIdentity requireActor(SessionHandle session);
}
