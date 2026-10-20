import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart'
    show Variable, QueryInterceptor, ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:raze_check_local/src/database/check_database.dart';
import 'fake_clock.dart';

const acceptancePassword = 'Synthetic acceptance password 13';

/// Test-owned namespace over the actual supplied key adapter. No global cleanup.
final class NamespacedKeys implements SecureKeyStore {
  NamespacedKeys(this.delegate, this.prefix);
  final SecureKeyStore delegate;
  final String prefix;
  final owned = <String>{};
  @override
  Future<Uint8List?> read(String id) => delegate.read('$prefix:$id');
  @override
  Future<void> write(String id, Uint8List value) async {
    await delegate.write('$prefix:$id', value);
    owned.add(id);
  }

  @override
  Future<void> delete(String id) => delegate.delete('$prefix:$id');
  Future<void> cleanOwned() async {
    for (final id in owned) {
      await delete(id);
    }
  }
}

/// Real services and SQLite/AES. Caller explicitly chooses OS or host test keys.
final class AcceptanceDevice {
  AcceptanceDevice(
    this.paths,
    this.keys, {
    FakeClock? clock,
    this.interceptor,
    this.cipher,
  }) : clock = clock ?? FakeClock();
  final AppPaths paths;
  final SecureKeyStore keys;
  final FakeClock clock;
  final QueryInterceptor? interceptor;
  final PayloadCipher? cipher;
  late CheckDatabase database;
  late LocalCheckRepository repository;
  late LocalIdentityService identity;
  late LocalCompanyService companies;
  late LocalEnrollmentService enrollment;
  late LocalCaptureService capture;
  late LocalAttendanceService attendance;
  late LocalAttendanceQueries queries;
  late LocalArchiveService archives;
  late LocalHandoverService handover;
  late SessionHandle session;
  Future<void> open({
    String? unlockPerson,
    String name = 'Synthetic owner',
  }) async {
    await paths.root.create(recursive: true);
    database = interceptor == null
        ? CheckDatabase.open(paths)
        : CheckDatabase(
            NativeDatabase.createInBackground(
              paths.database,
            ).interceptWith(interceptor!),
          );
    repository = LocalCheckRepository(
      database: database,
      cipher: cipher ?? AesPayloadCipher(VaultKeys(keys)),
    );
    identity = LocalIdentityService(
      keys: keys,
      catalog: ProfileCatalog(paths: paths, keys: keys),
      clock: clock,
      ids: SecureIds(),
      repository: repository,
    );
    archives = LocalArchiveService(
      paths: paths,
      keys: keys,
      repository: repository,
      identity: identity,
      clock: clock,
      ids: SecureIds(),
    );
    await archives.resume();
    await identity.resumeRecoveryIdentities();
    companies = LocalCompanyService(
      repository: repository,
      identity: identity,
      keys: keys,
      clock: clock,
      ids: SecureIds(),
    );
    enrollment = LocalEnrollmentService(
      repository: repository,
      identity: identity,
      keys: keys,
      clock: clock,
      ids: SecureIds(),
    );
    capture = LocalCaptureService(
      repository: repository,
      identity: identity,
      keys: keys,
      clock: clock,
      ids: SecureIds(),
      offsetMinutes: () => 540,
    );
    attendance = LocalAttendanceService(
      repository: repository,
      identity: identity,
      keys: keys,
      clock: clock,
      ids: SecureIds(),
    );
    queries = LocalAttendanceQueries(
      repository: repository,
      identity: identity,
      clock: clock,
    );
    handover = LocalHandoverService(
      repository: repository,
      identity: identity,
      keys: keys,
      clock: clock,
      ids: SecureIds(),
      archives: archives,
    );
    session = unlockPerson == null
        ? await identity.createProfile(name, acceptancePassword)
        : await identity.unlock(unlockPerson, acceptancePassword);
  }

  Future<void> reopen() async {
    final person = identity.requireActor(session).personId;
    await close();
    await open(unlockPerson: person);
  }

  CommandContext context(Company company, [String? operation]) =>
      CommandContext(
        companyId: company.id,
        session: session,
        operationId: operation ?? SecureIds().next(),
        authorityGenerationId: company.authorityGenerationId,
      );
  Future<Company> createCompany() async =>
      (await companies.createCompany(
                session,
                const CompanyDraft(
                  'Synthetic acceptance company',
                  'Asia/Tokyo',
                ),
                SecureIds().next(),
              )
              as Committed<Company>)
          .value;
  Future<int> count(String kind) async =>
      (await database
              .customSelect(
                'SELECT COUNT(*) AS n FROM stored_rows WHERE kind = ?',
                variables: [Variable.withString(kind)],
              )
              .getSingle())
          .read<int>('n');
  Future<void> close() async {
    identity.lock();
    await repository.close();
  }
}

Future<void> enrollAcceptance(
  AcceptanceDevice manager,
  AcceptanceDevice staff,
  Company company,
) async {
  final invitation = await manager.enrollment.createInvitation(
    manager.context(company),
  );
  final accepted = await staff.enrollment.acceptInvitation(
    staff.session,
    MessageCodec().encode(invitation),
    acceptedRootFingerprint: company.rootFingerprint,
  );
  final request = await staff.enrollment.requestJoin(
    staff.session,
    accepted,
    SecureIds().next(),
  );
  final verified = await manager.enrollment.verifyIncoming(
    manager.session,
    MessageCodec().encode(request),
  );
  final grant =
      await manager.enrollment.approveJoin(manager.context(company), verified)
          as Committed<SignedMessage>;
  final received = await staff.enrollment.verifyIncoming(
    staff.session,
    MessageCodec().encode(grant.value),
  );
  final result = await staff.enrollment.acceptGrant(staff.session, received);
  if (result is! Committed<Membership>) {
    throw StateError('Enrollment rejected: $result');
  }
}

Future<AttendanceReceipt> captureAcceptance(
  AcceptanceDevice manager,
  AcceptanceDevice staff,
  Company company,
) async {
  final workplace = await manager.capture.createWorkplaceCode(
    manager.context(company),
  );
  final verified = await staff.capture.verifyWorkplace(
    staff.session,
    company.id,
    MessageCodec().encode(workplace),
  );
  final draft = await staff.capture.beginDraft(
    staff.session,
    company.id,
    verified,
    PunchKind.checkIn,
  );
  return (await staff.capture.recordPunch(
            draft.context(staff.session),
            verified,
            PunchKind.checkIn,
          )
          as Committed<AttendanceReceipt>)
      .value;
}

Future<Directory> acceptanceDirectory(String label) =>
    Directory.systemTemp.createTemp('raze-acceptance-$label-');
