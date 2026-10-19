import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'fake_clock.dart';
import 'repository_fixture.dart';

final class EnrollmentDevice {
  EnrollmentDevice._(this.storage, this.clock);
  final RepositoryFixture storage;
  final FakeClock clock;
  late LocalIdentityService identity;
  late CompanyService companies;
  late EnrollmentService enrollment;
  late CaptureService capture;
  late SessionHandle session;
  static Future<EnrollmentDevice> create(FakeClock clock, String name) async {
    final d = EnrollmentDevice._(await RepositoryFixture.open(), clock);
    d.identity = LocalIdentityService(
      keys: d.storage.keys,
      catalog: ProfileCatalog(paths: d.storage.paths, keys: d.storage.keys),
      clock: clock,
      ids: SecureIds(),
      repository: d.storage.repo,
    );
    d.companies = LocalCompanyService(
      repository: d.storage.repo,
      identity: d.identity,
      keys: d.storage.keys,
      clock: clock,
      ids: SecureIds(),
    );
    d.enrollment = LocalEnrollmentService(
      repository: d.storage.repo,
      identity: d.identity,
      keys: d.storage.keys,
      clock: clock,
      ids: SecureIds(),
    );
    d.capture = LocalCaptureService(
      repository: d.storage.repo,
      identity: d.identity,
      keys: d.storage.keys,
      clock: clock,
      ids: SecureIds(),
      offsetMinutes: () => 540,
    );
    d.session = await d.identity.createProfile(
      name,
      'a strong local passphrase',
    );
    return d;
  }

  Future<int> eventCount() => storage.count('attendance');
  void rebuildServices() {
    capture = LocalCaptureService(
      repository: storage.repo,
      identity: identity,
      keys: storage.keys,
      clock: clock,
      ids: SecureIds(),
      offsetMinutes: () => 540,
    );
    companies = LocalCompanyService(
      repository: storage.repo,
      identity: identity,
      keys: storage.keys,
      clock: clock,
      ids: SecureIds(),
    );
    enrollment = LocalEnrollmentService(
      repository: storage.repo,
      identity: identity,
      keys: storage.keys,
      clock: clock,
      ids: SecureIds(),
    );
  }

  Future<bool> canIssueAttendance(String companyId) =>
      enrollment.canIssueAttendance(session, companyId);
  Future<int> employeeCount(String companyId) async =>
      (await companies.listStaff(session, companyId))
          .where((s) => s.personId != identity.requireActor(session).personId)
          .length;
  Future<int> membershipCount(String companyId) async =>
      (await storage.repo.snapshot(
        CompanyScope(companyId),
      )).records.where((r) => r.kind == 'membership').length;
  Future<void> acceptGrantTwice(SignedMessage grant) async {
    final verified = await enrollment.verifyIncoming(
      session,
      MessageCodec().encode(grant),
    );
    for (var i = 0; i < 2; i++) {
      final result = await enrollment.acceptGrant(session, verified);
      if (result is! Committed<Membership>) {
        throw StateError('Grant failed: $result');
      }
    }
  }
}

/// Independent file-backed repositories, vaults, installation keys and sessions.
final class TwoDeviceFixture {
  TwoDeviceFixture._(this.manager, this.staff, this.company);
  final EnrollmentDevice manager, staff;
  final Company company;
  String get companyId => company.id;
  static Future<TwoDeviceFixture> create() async {
    // These databases intentionally have separate files and key stores.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final clock = FakeClock();
    final manager = await EnrollmentDevice.create(clock, 'Owner');
    final staff = await EnrollmentDevice.create(clock, 'Staff');
    final company =
        (await manager.companies.createCompany(
                  manager.session,
                  const CompanyDraft('Offline company', 'Asia/Tokyo'),
                  'create-company',
                )
                as Committed<Company>)
            .value;
    return TwoDeviceFixture._(manager, staff, company);
  }

  CommandContext context(String operationId) => CommandContext(
    companyId: companyId,
    session: manager.session,
    operationId: operationId,
    authorityGenerationId: company.authorityGenerationId,
  );
  Future<VerifiedMessage> invitation() async {
    final signed = await manager.enrollment.createInvitation(
      context('invitation'),
    );
    return staff.enrollment.acceptInvitation(
      staff.session,
      MessageCodec().encode(signed),
      acceptedRootFingerprint: company.rootFingerprint,
    );
  }

  Future<VerifiedMessage> join({String? operationId}) async {
    final signed = await staff.enrollment.requestJoin(
      staff.session,
      await invitation(),
      operationId ?? SecureIds().next(),
    );
    return manager.enrollment.verifyIncoming(
      manager.session,
      MessageCodec().encode(signed),
    );
  }

  Future<SignedMessage> approveSameJoinTwice() async {
    final request = await join();
    final first =
        await manager.enrollment.approveJoin(context('approve'), request)
            as Committed<SignedMessage>;
    final second =
        await manager.enrollment.approveJoin(context('approve-again'), request)
            as Committed<SignedMessage>;
    if (first.value.payload.messageId != second.value.payload.messageId) {
      throw StateError('Duplicate grant');
    }
    return first.value;
  }

  Future<({Company company, Membership membership})> enrollStaff() async {
    await staff.acceptGrantTwice(await approveSameJoinTwice());
    return (
      company: (await staff.companies.readCompany(staff.session, companyId))!,
      membership: (await staff.companies.membership(staff.session, companyId))!,
    );
  }

  Future<VerifiedMessage> workplace() async {
    final signed = await manager.capture.createWorkplaceCode(
      context('workplace'),
    );
    return staff.capture.verifyWorkplace(
      staff.session,
      companyId,
      MessageCodec().encode(signed),
    );
  }

  Future<AttendanceReceipt> captureCheckIn() => capture(PunchKind.checkIn);
  Future<AttendanceReceipt> capture(
    PunchKind kind, {
    bool newPunch = false,
  }) async {
    if (newPunch) {
      final old = await staff.capture.currentDraft(staff.session, companyId);
      await staff.capture.finishDraft(staff.session, companyId, old!.eventId!);
    }
    final code = await workplace();
    final draft = await staff.capture.beginDraft(
      staff.session,
      companyId,
      code,
      kind,
    );
    return (await staff.capture.recordPunch(
              draft.context(staff.session),
              code,
              kind,
            )
            as Committed<AttendanceReceipt>)
        .value;
  }

  Future<void> restartStaff() async {
    staff.identity.lock();
    await staff.storage.reopen();
    staff.identity = LocalIdentityService(
      keys: staff.storage.keys,
      catalog: ProfileCatalog(
        paths: staff.storage.paths,
        keys: staff.storage.keys,
      ),
      clock: staff.clock,
      ids: SecureIds(),
      repository: staff.storage.repo,
    );
    final profile = (await staff.identity.profiles()).first;
    staff.session = await staff.identity.unlock(
      profile.personId,
      'a strong local passphrase',
    );
    staff.rebuildServices();
  }

  Future<AttendanceReceipt> exportReceipt(String eventId) =>
      staff.capture.getReceipt(staff.session, companyId, eventId);
  Future<void> dispose() async {
    manager.identity.lock();
    staff.identity.lock();
    await manager.storage.dispose();
    await staff.storage.dispose();
  }
}
