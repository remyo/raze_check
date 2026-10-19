import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:raze_check_local/src/recovery/archive_codec.dart';
import 'package:raze_check_local/src/recovery/archive_validation.dart';
import 'dart:convert';
import 'support/repository_fixture.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'real company archive attachment, passive restore and rollback at every boundary',
    () async {
      final source = await RepositoryFixture.open();
      addTearDown(source.dispose);
      final identity = LocalIdentityService(
        keys: source.keys,
        catalog: ProfileCatalog(paths: source.paths, keys: source.keys),
        clock: SystemCheckClock(),
        ids: SecureIds(),
        repository: source.repo,
      );
      final session = await identity.createProfile(
        'Owner',
        'a secure local password',
      );
      final companies = LocalCompanyService(
        repository: source.repo,
        identity: identity,
        keys: source.keys,
        clock: SystemCheckClock(),
        ids: SecureIds(),
      );
      final company =
          (await companies.createCompany(
                    session,
                    const CompanyDraft('Company', 'Asia/Tokyo'),
                    'create',
                  )
                  as Committed<Company>)
              .value;
      final attachments = ImmutableAttachmentStore(
        paths: source.paths,
        cipher: AesPayloadCipher(VaultKeys(source.keys)),
      );
      final file = await attachments.put(
        companyId: company.id,
        recordId: 'attachment',
        plain: Uint8List.fromList([0, 255, 1, 13, 10]),
      );
      final record = StoredRecord(
        'attachment',
        company.id,
        'attachmentExample',
        1,
        Uint8List.fromList([10, 20]),
      );
      await source.repo.commit(
        CommandContext(
          companyId: company.id,
          session: session,
          operationId: 'attachment',
          authorityGenerationId: company.authorityGenerationId,
        ),
        requestDigest: Uint8List(32),
        build: (_) async =>
            Mutation([record], [], [], record, attachments: [file]),
      );
      final service = LocalArchiveService(
        paths: source.paths,
        keys: source.keys,
        repository: source.repo,
        identity: identity,
        clock: SystemCheckClock(),
        ids: SecureIds(),
      );
      final descriptor = await service.create(
        session,
        CompanyScope(company.id),
        'a secure archive password',
      );
      final saved = await service.shareBytes(session, descriptor.artifactId);
      final contents = await ArchiveCodec.open(
        saved,
        'a secure archive password',
      );
      final attachmentName = 'attachments/${file.sha256}';
      await expectLater(
        ArchiveValidation().read({...contents}..remove(attachmentName)),
        throwsA(isA<CheckException>()),
      );
      await expectLater(
        ArchiveValidation().read({
          ...contents,
          attachmentName: Uint8List.fromList([1, 2, 3]),
        }),
        throwsA(isA<CheckException>()),
      );
      final missingRecovery = {
        ...contents,
        'recovery.json': archiveJson({'version': 1, 'profiles': []}),
      };
      final manifest =
          jsonDecode(utf8.decode(contents['manifest.json']!))
              as Map<String, dynamic>;
      for (final entry in manifest['files'] as List) {
        if (entry['path'] == 'recovery.json') {
          entry['byteLength'] = missingRecovery['recovery.json']!.length;
          entry['sha256'] = await archiveHash(
            missingRecovery['recovery.json']!,
          );
        }
      }
      missingRecovery['manifest.json'] = archiveJson(manifest);
      await expectLater(
        ArchiveValidation().read(missingRecovery),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'missing recovery',
            CheckError.recoveryRequired,
          ),
        ),
      );
      await expectLater(
        service.create(session, CompanyScope(company.id), 'short'),
        throwsA(isA<CheckException>()),
      );
      expect(await service.shareBytes(session, descriptor.artifactId), saved);
      final selected = File('${source.paths.root.path}/selected.archive');
      await selected.writeAsBytes(
        await service.shareBytes(session, descriptor.artifactId),
      );
      for (final fault in [
        'journal',
        'keyWritten',
        'keys',
        'attachmentMoved',
        'concurrentAttachmentWriter',
        'attachments',
        'beforeDatabase',
        'afterDatabase',
        null,
      ]) {
        final target = await RepositoryFixture.open();
        final targetIdentity = LocalIdentityService(
          keys: target.keys,
          catalog: ProfileCatalog(paths: target.paths, keys: target.keys),
          clock: SystemCheckClock(),
          ids: SecureIds(),
          repository: target.repo,
        );
        final targetSession = await targetIdentity.createProfile(
          'Target',
          'another secure password',
        );
        final restore = LocalArchiveService(
          paths: target.paths,
          keys: target.keys,
          repository: target.repo,
          identity: targetIdentity,
          clock: SystemCheckClock(),
          ids: SecureIds(),
          fault: (phase) async {
            if (fault == 'concurrentAttachmentWriter' &&
                phase == 'attachmentMoved') {
              final writer = await LocalCheckRepository.open(
                paths: target.paths,
                cipher: AesPayloadCipher(VaultKeys(target.keys)),
              );
              try {
                final linked =
                    await ImmutableAttachmentStore(
                      paths: target.paths,
                      cipher: AesPayloadCipher(VaultKeys(target.keys)),
                    ).put(
                      companyId: company.id,
                      recordId: 'other-writer',
                      plain: Uint8List.fromList([0, 255, 1, 13, 10]),
                    );
                final row = StoredRecord(
                  'other-writer',
                  company.id,
                  'attachmentExample',
                  1,
                  Uint8List.fromList([1]),
                );
                expect(
                  await writer.commit(
                    CommandContext(
                      companyId: company.id,
                      session: targetSession,
                      operationId: 'other-writer',
                      authorityGenerationId: company.authorityGenerationId,
                    ),
                    requestDigest: Uint8List(32),
                    build: (_) async =>
                        Mutation([row], [], [], row, attachments: [linked]),
                  ),
                  isA<Committed>(),
                );
              } finally {
                await writer.close();
              }
              throw StateError(
                'concurrent attachment writer then restore interruption',
              );
            }

            if (phase == fault) throw StateError('fault');
          },
        );
        final preview = await restore.inspect(
          targetSession,
          selected.path,
          'a secure archive password',
        );
        expect(preview.filesComplete, true);
        if (fault == null) {
          final result = await restore.apply(
            preview,
            RestoreChoice.newInstallation,
          );
          expect(result.requiresActivation, true);
          expect(
            (await target.repo.read(company.id, 'attachment'))!.payload,
            record.payload,
          );
          expect(
            await ImmutableAttachmentStore(
              paths: target.paths,
              cipher: AesPayloadCipher(VaultKeys(target.keys)),
            ).read(file),
            [0, 255, 1, 13, 10],
          );
        } else {
          await expectLater(
            restore.apply(preview, RestoreChoice.newInstallation),
            throwsA(anything),
          );
          await LocalArchiveService(
            paths: target.paths,
            keys: target.keys,
            repository: target.repo,
            identity: targetIdentity,
            clock: SystemCheckClock(),
            ids: SecureIds(),
          ).resume();
          if (fault == 'concurrentAttachmentWriter') {
            expect(
              await target.repo.read(company.id, 'other-writer'),
              isNotNull,
            );
            final linked = AttachmentManifestEntry(
              companyId: company.id,
              recordId: 'other-writer',
              sha256: file.sha256,
              byteLength: file.byteLength,
            );
            expect(
              await ImmutableAttachmentStore(
                paths: target.paths,
                cipher: AesPayloadCipher(VaultKeys(target.keys)),
              ).read(linked),
              [0, 255, 1, 13, 10],
            );
          }
          expect(
            await target.repo.read(company.id, 'attachment'),
            fault == 'afterDatabase' ? isNotNull : null,
          );
        }
        expect(await selected.exists(), true);
        await target.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  for (final crash in [true, false]) {
    test(
      'discard waits for applying restore ${crash ? "interruption" : "commit"} and preserves durable intent',
      () async {
        final source = await RepositoryFixture.open(),
            target = await RepositoryFixture.open();
        addTearDown(source.dispose);
        addTearDown(target.dispose);
        LocalIdentityService identity(RepositoryFixture f) =>
            LocalIdentityService(
              keys: f.keys,
              catalog: ProfileCatalog(paths: f.paths, keys: f.keys),
              clock: SystemCheckClock(),
              ids: SecureIds(),
              repository: f.repo,
            );
        final sourceIdentity = identity(source),
            targetIdentity = identity(target);
        final sourceSession = await sourceIdentity.createProfile(
          'Source',
          'source secure password',
        );
        final targetSession = await targetIdentity.createProfile(
          'Target',
          'target secure password',
        );
        final company =
            (await LocalCompanyService(
                      repository: source.repo,
                      identity: sourceIdentity,
                      keys: source.keys,
                      clock: SystemCheckClock(),
                      ids: SecureIds(),
                    ).createCompany(
                      sourceSession,
                      const CompanyDraft('Source', 'Asia/Tokyo'),
                      'create',
                    )
                    as Committed<Company>)
                .value;
        final backup = LocalArchiveService(
          paths: source.paths,
          keys: source.keys,
          repository: source.repo,
          identity: sourceIdentity,
          clock: SystemCheckClock(),
          ids: SecureIds(),
        );
        final archive = await backup.create(
          sourceSession,
          CompanyScope(company.id),
          'archive secure password',
        );
        final selected = File('${source.paths.root.path}/selected.archive');
        await selected.writeAsBytes(
          await backup.shareBytes(sourceSession, archive.artifactId),
        );
        final entered = Completer<void>(), release = Completer<void>();
        final restore = LocalArchiveService(
          paths: target.paths,
          keys: target.keys,
          repository: target.repo,
          identity: targetIdentity,
          clock: SystemCheckClock(),
          ids: SecureIds(),
          fault: (phase) async {
            if (phase == 'keys') {
              entered.complete();
              await release.future;
              if (crash) throw StateError('simulated process exit');
            }
          },
        );
        final preview = await restore.inspect(
          targetSession,
          selected.path,
          'archive secure password',
        );
        final applying = restore
            .apply(preview, RestoreChoice.newInstallation)
            .then<Object>((r) => r, onError: (Object e, StackTrace s) => e);
        await entered.future.timeout(const Duration(seconds: 10));
        var discardFinished = false;
        final discarding = restore.discard(preview).then<Object?>((_) {
          discardFinished = true;
          return null;
        }, onError: (Object e, StackTrace s) => e);
        try {
          // This read queues after discard's first repository call. Before the
          // fix that call replaced the applying journal with an empty marker.
          final jobs = await target.repo.restoreJournals();
          expect(jobs[preview.stagingToken], isNotEmpty);
          expect(discardFinished, false);
          expect(
            await target.keys.read('vault:restore-${preview.stagingToken}'),
            isNotNull,
          );
          final observer = await LocalCheckRepository.open(
            paths: target.paths,
            cipher: AesPayloadCipher(VaultKeys(target.keys)),
          );
          try {
            expect(
              (await observer.restoreJournals())[preview.stagingToken],
              isNotEmpty,
            );
          } finally {
            await observer.close();
          }
        } finally {
          release.complete();
          await applying;
          await discarding;
        }
        expect(
          await applying,
          crash ? isA<CheckException>() : isA<RestoreResult>(),
        );
        expect(await discarding, isNull);
        await target.reopen();
        await LocalArchiveService(
          paths: target.paths,
          keys: target.keys,
          repository: target.repo,
          identity: targetIdentity,
          clock: SystemCheckClock(),
          ids: SecureIds(),
        ).resume();
        expect(await target.repo.restoreJournals(), isEmpty);
        expect(
          await target.keys.read('vault:restore-${preview.stagingToken}'),
          isNull,
        );
        expect(await target.keys.read('vault:${company.id}'), isNotNull);
        expect(
          await target.keys.read('company-root:${company.id}'),
          crash ? isNull : isNotNull,
        );
        expect(
          await target.repo.read(company.id, company.id),
          crash ? isNull : isNotNull,
        );
        expect(await selected.exists(), true);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
