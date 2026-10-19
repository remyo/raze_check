import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:raze_check_local/src/recovery/archive_codec.dart';
import 'package:raze_check_local/src/recovery/archive_records.dart';
import 'package:raze_check_local/src/recovery/archive_validation.dart';
import 'support/two_device_fixture.dart';
import 'support/repository_fixture.dart';

void main() {
  test(
    'operator tombstones preserve provenance but export no reusable credential or password digest; personal scope stays own',
    () async {
      final f = await TwoDeviceFixture.create();
      addTearDown(f.dispose);
      final manager = f.manager, staff = f.staff;
      final invitation = await f.invitation();
      final join = await staff.enrollment.requestJoin(
        staff.session,
        invitation,
        SecureIds().next(),
      );
      final verified = await manager.enrollment.verifyIncoming(
        manager.session,
        MessageCodec().encode(join),
      );
      final grant =
          (await manager.enrollment.approveJoin(f.context('approve'), verified)
                  as Committed<SignedMessage>)
              .value;
      await staff.acceptGrantTwice(grant);
      await f.captureCheckIn();
      final operator =
          (await manager.companies.createStaff(
                    f.context('operator-staff'),
                    const StaffDraft(name: 'Operator'),
                  )
                  as Committed<StaffRecord>)
              .value;
      await manager.companies.activateOperator(
        f.context('activate-secret'),
        operator.membershipId,
        'operator secret passphrase',
      );
      final old = (await manager.storage.repo.read(
        f.companyId,
        'operator:${operator.membershipId}',
      ))!;
      final oldJson =
          jsonDecode(utf8.decode(old.payload)) as Map<String, dynamic>;
      final snapshot = await manager.storage.repo.snapshot(
        CompanyScope(f.companyId),
      );
      final secretDigest = snapshot.operations
          .firstWhere((o) => o.operationId == 'activate-secret')
          .requestDigest;
      LocalArchiveService archives(EnrollmentDevice d) => LocalArchiveService(
        paths: d.storage.paths,
        keys: d.storage.keys,
        repository: d.storage.repo,
        identity: d.identity,
        clock: d.clock,
        ids: SecureIds(),
      );
      final service = archives(manager), personalService = archives(staff);
      await expectLater(
        personalService.create(
          staff.session,
          CompanyScope(f.companyId),
          'archive strong passphrase',
        ),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'owner only',
            CheckError.unauthorized,
          ),
        ),
      );
      final personal = await personalService.create(
        staff.session,
        PersonalScope(staff.identity.requireActor(staff.session).personId),
        'archive strong passphrase',
      );
      final personalFiles = await ArchiveCodec.open(
        await personalService.shareBytes(staff.session, personal.artifactId),
        'archive strong passphrase',
      );
      await ArchiveValidation().read(personalFiles);
      await ArchiveRecords.read(personalFiles['records.json']!, (
        kind,
        value,
      ) async {
        if (kind == 'record') {
          final row = (value as ArchiveRecord).record;
          expect(
            row.kind,
            isNot(
              anyOf(
                'companyRootRecovery',
                'operatorCredential',
                'retiredLocalCredential',
              ),
            ),
          );
          if (row.kind == 'membership') {
            expect(
              Membership.fromJson(
                jsonDecode(utf8.decode(row.payload)) as Map<String, dynamic>,
              ).personId,
              staff.identity.requireActor(staff.session).personId,
            );
          }
        }
      });
      final backup = await service.create(
        manager.session,
        CompanyScope(f.companyId),
        'archive strong passphrase',
      );
      final original = await service.shareBytes(
            manager.session,
            backup.artifactId,
          ),
          files = await ArchiveCodec.open(
            original,
            'archive strong passphrase',
          );
      StoredOperation? tombstone;
      var retainedJournal = false;
      await ArchiveRecords.read(files['records.json']!, (kind, value) async {
        if (kind == 'operation' &&
            (value as StoredOperation).operationId == 'activate-secret') {
          tombstone = value;
          expect(value.retiredLocalCredential, true);
          expect(value.requestDigest, isNot(secretDigest));
        }
        if (kind == 'journal' &&
            (value as RevisionEntry).operationId == 'activate-secret') {
          retainedJournal = true;
        }
        if (kind == 'record') {
          final row = (value as ArchiveRecord).record;
          expect(row.kind, isNot('operatorCredential'));
          if (row.kind == 'retiredLocalCredential') {
            final text = utf8.decode(row.payload);
            for (final field in ['salt', 'verifier', 'signingKeyId']) {
              expect(text, isNot(contains(oldJson[field] as String)));
            }
          }
        }
      });
      expect(tombstone, isNotNull);
      expect(retainedJournal, true);
      final sourceReview = File(
        '${manager.storage.paths.root.path}/review.backup',
      );
      await sourceReview.writeAsBytes(original);
      final conflicting = await service.inspect(
        manager.session,
        sourceReview.path,
        'archive strong passphrase',
      );
      expect(conflicting.conflicts, isNotEmpty);
      await expectLater(
        service.apply(conflicting, RestoreChoice.mergeNonConflicting),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'live credential conflict',
            CheckError.duplicateConflict,
          ),
        ),
      );
      await service.discard(conflicting);
      final target = await RepositoryFixture.open();
      addTearDown(target.dispose);
      final identity = LocalIdentityService(
        keys: target.keys,
        catalog: ProfileCatalog(paths: target.paths, keys: target.keys),
        clock: manager.clock,
        ids: SecureIds(),
        repository: target.repo,
      );
      final session = await identity.createProfile(
        'Target',
        'target local passphrase',
      );
      final restore = LocalArchiveService(
        paths: target.paths,
        keys: target.keys,
        repository: target.repo,
        identity: identity,
        clock: manager.clock,
        ids: SecureIds(),
      );
      final source = File('${target.paths.root.path}/source.backup');
      await source.writeAsBytes(original);
      final preview = await restore.inspect(
        session,
        source.path,
        'archive strong passphrase',
      );
      await restore.apply(preview, RestoreChoice.newInstallation);
      // Simulate only removal of Task11's gate to prove tombstone replay itself
      // fails closed; this is not a device activation implementation.
      await target.database.customStatement('DELETE FROM passive_scopes');
      expect(
        (await target.repo.commit(
              CommandContext(
                companyId: f.companyId,
                session: session,
                operationId: 'activate-secret',
                authorityGenerationId: f.company.authorityGenerationId,
              ),
              requestDigest: secretDigest,
              build: (_) async => throw StateError('must not build'),
            ))
            as Rejected,
        isA<Rejected>().having(
          (r) => r.error,
          'retired replay',
          CheckError.recoveryRequired,
        ),
      );
      await expectLater(
        identity.unlockOperator(
          f.companyId,
          operator.membershipId,
          'operator secret passphrase',
        ),
        throwsA(isA<CheckException>()),
      );
      expect(
        (await manager.storage.repo.read(f.companyId, old.id))!.payload,
        old.payload,
      );
      final again = await restore.inspect(
        session,
        source.path,
        'archive strong passphrase',
      );
      expect(
        (await restore.apply(
          again,
          RestoreChoice.mergeNonConflicting,
        )).duplicate,
        true,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
