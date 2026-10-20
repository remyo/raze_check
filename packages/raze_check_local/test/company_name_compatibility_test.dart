@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';
import 'package:raze_check_local/src/recovery/archive_codec.dart';
import 'package:raze_check_local/src/recovery/archive_records.dart';
import 'package:raze_check_local/src/recovery/archive_validation.dart';

void main() {
  test(
    'legacy name blocks a new replacement grant until authorized owner repair',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final enrolled = await p.enrollStaff();
      final target = await EnrollmentDevice.create(p.manager.clock, 'Setup');
      addTearDown(target.storage.dispose);
      final d = p.manager;
      final invitation = await d.enrollment.createInvitation(
        p.context('replacement-invite'),
      );
      await target.enrollment.acceptInvitation(
        target.session,
        MessageCodec().encode(invitation),
        acceptedRootFingerprint: p.company.rootFingerprint,
      );
      final candidate = await target.identity.stageRecoveryIdentity(
        target.session,
        companyId: p.companyId,
        personId: p.staff.identity.requireActor(p.staff.session).personId,
        displayName: 'Recovered',
        rootFingerprint: p.company.rootFingerprint,
        passphrase: 'replacement passphrase',
      );
      LocalDeviceReplacementService replacement(EnrollmentDevice d) =>
          LocalDeviceReplacementService(
            repository: d.storage.repo,
            identity: d.identity,
            keys: d.storage.keys,
            clock: d.clock,
            ids: SecureIds(),
          );
      final request = await replacement(target).createRequest(
        target.session,
        p.companyId,
        enrolled.membership.employeeId,
        candidate: candidate,
      );
      final verified = await d.enrollment.verifyIncoming(
        d.session,
        MessageCodec().encode(request),
      );
      final old = (await d.storage.repo.read(p.companyId, p.companyId))!;
      final legacy = StoredRecord(
        old.id,
        old.companyId,
        old.kind,
        old.revision + 1,
        Uint8List.fromList(
          utf8.encode(jsonEncode({...p.company.toJson(), 'name': 'X' * 121})),
        ),
      );
      await d.storage.repo.commit(
        p.context('legacy-fixture'),
        requestDigest: Uint8List(32),
        build: (_) async => Mutation([legacy], [], [], legacy),
      );
      await expectLater(
        replacement(d).authorize(p.context('replace'), verified),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.incompatibleCompanyName,
          ),
        ),
      );
      expect(
        await d.companies.correctName(p.context('repair'), 'Compatible name'),
        isA<Committed<Company>>(),
      );
      expect(
        (await replacement(d).authorize(
          p.context('replace'),
          verified,
        )).payload.field<String>('companyLabel'),
        'Compatible name',
      );
    },
  );

  test(
    'company setup rejects 121 scalars and 120 scalars produces a full membership grant',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final d = p.manager;
      expect(
        await d.companies.createCompany(
          d.session,
          CompanyDraft('😀' * 121, 'Asia/Tokyo'),
          'too-long',
        ),
        isA<Rejected<Company>>(),
      );
      final c =
          (await d.companies.createCompany(
                    d.session,
                    CompanyDraft('😀' * 120, 'Asia/Tokyo'),
                    'boundary',
                  )
                  as Committed<Company>)
              .value;
      CommandContext ctx(String op) => CommandContext(
        companyId: c.id,
        session: d.session,
        operationId: op,
        authorityGenerationId: c.authorityGenerationId,
      );
      final invitation = await d.enrollment.createInvitation(ctx('invite'));
      final accepted = await p.staff.enrollment.acceptInvitation(
        p.staff.session,
        MessageCodec().encode(invitation),
        acceptedRootFingerprint: c.rootFingerprint,
      );
      final request = await p.staff.enrollment.requestJoin(
        p.staff.session,
        accepted,
        SecureIds().next(),
      );
      final grant =
          (await d.enrollment.approveJoin(
                    ctx('approve'),
                    await d.enrollment.verifyIncoming(
                      d.session,
                      MessageCodec().encode(request),
                    ),
                  )
                  as Committed<SignedMessage>)
              .value;
      expect(grant.payload.field<String>('companyLabel'), '😀' * 120);
      expect(
        MessageCodec()
            .decode(
              MessageCodec().encode(grant),
              maxBytes: MessageLimits.fileBytes,
            )
            .payload
            .values,
        grant.payload.values,
      );
    },
  );
  test(
    'legacy overlong name remains readable and owner correction enables grants without rewriting evidence',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      final d = p.manager;
      final request = await p.join();
      final originalInvitation = await d.enrollment.createInvitation(
        p.context('saved-invite'),
      );
      final old = (await d.storage.repo.read(p.companyId, p.companyId))!;
      final legacy = StoredRecord(
        old.id,
        old.companyId,
        old.kind,
        old.revision + 1,
        Uint8List.fromList(
          utf8.encode(jsonEncode({...p.company.toJson(), 'name': 'X' * 121})),
        ),
      );
      await d.storage.repo.commit(
        p.context('legacy-fixture'),
        requestDigest: Uint8List(32),
        build: (_) async => Mutation([legacy], [], [], legacy),
      );
      expect(
        (await d.companies.readCompany(d.session, p.companyId))!.name,
        'X' * 121,
      );
      final rejected = await d.enrollment.approveJoin(
        p.context('overlong-grant'),
        request,
      );
      expect(
        (rejected as Rejected<SignedMessage>).error.name,
        'incompatibleCompanyName',
      );
      final snapshot = await d.storage.repo.snapshot(CompanyScope(p.companyId));
      expect(
        snapshot.records.singleWhere((r) => r.id == p.companyId).payload,
        legacy.payload,
      );
      final archive = LocalArchiveService(
        paths: d.storage.paths,
        keys: d.storage.keys,
        repository: d.storage.repo,
        identity: d.identity,
        clock: d.clock,
        ids: SecureIds(),
      );
      final exported = await archive.create(
        d.session,
        CompanyScope(p.companyId),
        'legacy archive passphrase',
      );
      final entries = await ArchiveCodec.open(
        await archive.shareBytes(d.session, exported.artifactId),
        'legacy archive passphrase',
      );
      await ArchiveValidation().read(entries);
      var preserved = false;
      await ArchiveRecords.read(entries['records.json']!, (kind, value) async {
        if (kind == 'record' &&
            (value as ArchiveRecord).record.id == p.companyId) {
          expect(value.record.payload, legacy.payload);
          preserved = true;
        }
      });
      expect(preserved, isTrue);
      final service = d.companies;
      final correction = await service.correctName(
        p.context('correct-name'),
        'Compatible name',
      );
      expect(correction, isA<Committed<Company>>());
      expect(
        (await service.correctName(p.context('correct-name'), 'Compatible name')
                as Committed<Company>)
            .duplicate,
        isTrue,
      );
      expect(
        (correction as Committed<Company>).value.rootPublicKey,
        p.company.rootPublicKey,
      );
      expect(
        await d.enrollment.approveJoin(p.context('after-correction'), request),
        isA<Committed<SignedMessage>>(),
      );
      expect(
        MessageCodec().encode(
          await d.enrollment.createInvitation(p.context('saved-invite')),
        ),
        MessageCodec().encode(originalInvitation),
      );
      await p.staff.acceptGrantTwice(
        (await d.enrollment.approveJoin(p.context('after-correction'), request)
                as Committed<SignedMessage>)
            .value,
      );
      final staffService = p.staff.companies;
      final staffContext = CommandContext(
        companyId: p.companyId,
        session: p.staff.session,
        operationId: 'unauthorized',
        authorityGenerationId: p.company.authorityGenerationId,
      );
      expect(
        await staffService.correctName(staffContext, 'No'),
        isA<Rejected<Company>>(),
      );
      expect(
        await service.correctName(
          CommandContext(
            companyId: SecureIds().next(),
            session: d.session,
            operationId: 'wrong-company',
            authorityGenerationId: p.company.authorityGenerationId,
          ),
          'No',
        ),
        isA<Rejected<Company>>(),
      );
      expect(
        await service.correctName(p.context('empty-name'), ''),
        isA<Rejected<Company>>(),
      );
      expect(
        await service.correctName(p.context('long-name'), 'X' * 121),
        isA<Rejected<Company>>(),
      );
    },
  );
}
