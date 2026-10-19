import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';

/// The standalone host owns adapter lifetime; features receive contracts only.
final class LocalComposition {
  LocalComposition._({
    required this.identity,
    required this.repository,
    required this.vaultKeys,
    required this.attachments,
    required this.signingKeys,
    required this.companies,
    required this.enrollment,
  });
  final IdentityService identity;
  final LocalCheckRepository repository;
  final VaultKeys vaultKeys;
  final ImmutableAttachmentStore attachments;
  final KeyService signingKeys;
  final CompanyService companies;
  final EnrollmentService enrollment;

  static Future<LocalComposition> open({
    AppPaths? paths,
    SecureKeyStore? secureKeys,
    CheckClock? clock,
  }) async {
    final localClock = clock ?? SystemCheckClock();
    final localPaths = paths ?? await AppPaths.persistent();
    final keys = secureKeys ?? OsSecureKeyStore();
    final vault = VaultKeys(keys);
    final cipher = AesPayloadCipher(vault);
    final repository = await LocalCheckRepository.open(
      paths: localPaths,
      cipher: cipher,
    );
    try {
      final identity = LocalIdentityService(
        keys: keys,
        catalog: ProfileCatalog(paths: localPaths, keys: keys),
        clock: localClock,
        ids: SecureIds(),
        repository: repository,
      );
      return LocalComposition._(
        identity: identity,
        companies: LocalCompanyService(
          repository: repository,
          identity: identity,
          keys: keys,
          clock: localClock,
          ids: SecureIds(),
        ),
        enrollment: LocalEnrollmentService(
          repository: repository,
          identity: identity,
          keys: keys,
          clock: localClock,
          ids: SecureIds(),
        ),
        repository: repository,
        vaultKeys: vault,
        signingKeys: LocalKeyService(keys),
        attachments: ImmutableAttachmentStore(
          paths: localPaths,
          cipher: cipher,
        ),
      );
    } catch (_) {
      await repository.close();
      rethrow;
    }
  }

  Future<void> close() async {
    identity.lock();
    await repository.close();
  }
}
