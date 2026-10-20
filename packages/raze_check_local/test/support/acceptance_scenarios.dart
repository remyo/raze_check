import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'acceptance_device.dart';

Future<({Company company, AttendanceReceipt receipt})> offlineAcceptance(
  AcceptanceDevice manager,
  AcceptanceDevice staff,
) async {
  final company = await manager.createCompany();
  await enrollAcceptance(manager, staff, company);
  final receipt = await captureAcceptance(manager, staff, company);
  final draft = await staff.capture.currentDraft(staff.session, company.id);
  final operation = draft!.operationId;
  expect(await staff.count('attendance'), 1);
  expect(await staff.count('attendanceOutbox'), 1);
  await staff.reopen();
  final reopened = await staff.capture.currentDraft(staff.session, company.id);
  expect(reopened!.operationId, operation);
  expect(reopened.eventId, receipt.eventId);
  expect(
    (await staff.capture.getReceipt(
      staff.session,
      company.id,
      receipt.eventId,
    )).bytes,
    orderedEquals(receipt.bytes),
  );
  final verified = await manager.attendance.verifyIncoming(
    manager.session,
    company.id,
    receipt.bytes,
  );
  final imported = await manager.attendance.importReceipt(
    manager.context(company, 'acceptance-import'),
    verified,
  );
  expect(imported.status, ImportStatus.received);
  final duplicate = await manager.attendance.importReceipt(
    manager.context(company, 'acceptance-import-again'),
    verified,
  );
  expect(duplicate.status, ImportStatus.alreadyReceived);
  expect(
    MessageCodec().encode(duplicate.returnMessage!),
    orderedEquals(MessageCodec().encode(imported.returnMessage!)),
  );
  expect(await manager.count('attendance'), 1);
  expect(await manager.count('receiptImport'), 1);
  Future<void> accept(SignedMessage message) async {
    expect(
      await staff.attendance.accept(
        staff.session,
        await staff.attendance.verifyIncoming(
          staff.session,
          company.id,
          MessageCodec().encode(message),
        ),
      ),
      isA<Committed<AttendanceRecord>>(),
    );
  }

  await accept(imported.returnMessage!);
  final decision =
      await manager.attendance.decide(
            manager.context(company),
            receipt.eventId,
            ReviewDecision.approve,
            'Synthetic acceptance review',
          )
          as Committed<DecisionRecord>;
  await accept(decision.value.returnMessage!);
  final request = await staff.attendance.request(
    staff.session,
    company.id,
    receipt.eventId,
    ProposedCorrection(
      kind: PunchKind.checkOut,
      utcMs: receipt.claimedUtcMs + 60000,
      offsetMinutes: 540,
      reason: 'Synthetic correction',
    ),
    SecureIds().next(),
  );
  final correction =
      await manager.attendance.resolve(
            manager.context(company),
            await manager.attendance.verifyIncoming(
              manager.session,
              company.id,
              MessageCodec().encode(request),
            ),
            true,
            'Synthetic accepted correction',
          )
          as Committed<CorrectionRecord>;
  await accept(correction.value.decision.returnMessage!);
  for (final device in [manager, staff]) {
    await device.reopen();
    final page = await device.queries.historyPage(
      device.session,
      company.id,
      scope: device == manager
          ? AttendanceScope.management
          : AttendanceScope.personal,
      pageSize: 1,
    );
    expect(page.items.single.record.eventId, receipt.eventId);
    expect(page.items.single.record.review, ReviewStatus.approved);
    expect(page.items.single.record.effectiveKind, PunchKind.checkOut);
    expect(
      page.items.single.record.effectiveUtcMs,
      receipt.claimedUtcMs + 60000,
    );
    expect(
      (await device.repository.read(company.id, receipt.eventId))!.payload,
      orderedEquals(receipt.bytes),
    );
  }
  final evidence = {
    'companyId': company.id,
    'eventId': receipt.eventId,
    'operationId': operation,
    'transportSha256': base64Encode((await Sha256().hash(receipt.bytes)).bytes),
    'payloadSha256': base64Encode(
      (await Sha256().hash(
        MessageCodec()
            .decode(receipt.bytes, maxBytes: MessageLimits.fileBytes)
            .payloadBytes,
      )).bytes,
    ),
    'transportBytes': receipt.bytes.length,
    'events': 1,
    'outbox': 1,
    'mode': 'logical stores; graceful reopen; not OS process-death evidence',
  };
  await File(
    '${staff.paths.root.path}/receipt.razecheck-message',
  ).writeAsBytes(receipt.bytes, flush: true);
  await File(
    '${staff.paths.root.path}/evidence.json',
  ).writeAsString(jsonEncode(evidence), flush: true);
  return (company: company, receipt: receipt);
}

Future<void> recoveryAcceptance(
  AcceptanceDevice manager,
  AcceptanceDevice staff,
  AcceptanceDevice target,
) async {
  final flow = await offlineAcceptance(manager, staff), company = flow.company;
  final owner = manager.identity.requireActor(manager.session);
  final archive = await manager.archives.create(
    manager.session,
    CompanyScope(company.id),
    acceptancePassword,
  );
  final file = File('${target.paths.root.path}/external-copy.razecheck-backup');
  await file.writeAsBytes(
    await manager.archives.shareBytes(manager.session, archive.artifactId),
    flush: true,
  );
  await expectLater(
    target.archives.inspect(
      target.session,
      file.path,
      'a wrong archive password',
    ),
    throwsA(isA<CheckException>()),
  );
  expect(await target.count('attendance'), 0);
  final preview = await target.archives.inspect(
    target.session,
    file.path,
    acceptancePassword,
  );
  expect(preview.conflicts, isEmpty);
  expect(preview.filesComplete, isTrue);
  await expectLater(
    target.queries.historyPage(
      target.session,
      company.id,
      scope: AttendanceScope.management,
    ),
    throwsA(isA<CheckException>()),
  );
  final candidate = await target.identity.stageRecoveryIdentity(
    target.session,
    companyId: company.id,
    personId: owner.personId,
    displayName: 'Synthetic recovered owner',
    rootFingerprint: company.rootFingerprint,
    passphrase: acceptancePassword,
  );
  await target.handover.recover(
    target.session,
    preview,
    RecoveryAcknowledgment(
      manifestId: preview.manifestId,
      manifestSha256Base64Url: preview.manifestSha256Base64Url,
      acceptsMissingData: true,
    ),
    candidate: candidate,
  );
  target.session = await target.identity.unlock(
    owner.personId,
    acceptancePassword,
  );
  final restored = await target.companies.readCompany(
    target.session,
    company.id,
  );
  expect(restored!.authorityGenerationId, isNot(company.authorityGenerationId));
  expect(
    target.identity.requireActor(target.session).installationId,
    isNot(owner.installationId),
  );
  await target.reopen();
  final page = await target.queries.historyPage(
    target.session,
    company.id,
    scope: AttendanceScope.management,
    pageSize: 1,
  );
  expect(page.items.single.record.eventId, flow.receipt.eventId);
  expect(page.items.single.record.review, ReviewStatus.approved);
  expect(page.items.single.record.effectiveKind, PunchKind.checkOut);
  expect(
    (await target.repository.read(company.id, flow.receipt.eventId))!.payload,
    orderedEquals(flow.receipt.bytes),
  );
  expect(
    (await target.attendance.history(
      target.session,
      company.id,
      flow.receipt.eventId,
    )).length,
    2,
  );
  // Smoke: a personal descriptor produces encrypted bytes. Authenticated content
  // scope/root exclusion is checked by archive_scope_test.dart (personal scope),
  // and actual passive restoration/activation by device_replacement_test.dart.
  // This smoke tail alone does not inspect the encrypted contents.
  final personal = await staff.archives.create(
    staff.session,
    PersonalScope(staff.identity.requireActor(staff.session).personId),
    acceptancePassword,
  );
  expect(personal.scope, isA<PersonalScope>());
  expect(
    await staff.archives.shareBytes(staff.session, personal.artifactId),
    isNotEmpty,
  );
}
