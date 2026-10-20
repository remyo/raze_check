@Timeout(Duration(hours: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:raze_check_local/src/recovery/archive_codec.dart';
import 'package:raze_check_local/src/recovery/archive_records.dart';
import 'support/acceptance_device.dart';
import 'support/memory_key_store.dart';

void main() {
  test(
    '100 external staff and 10000 real imports retain whole manager archive',
    () async {
      final root = await acceptanceDirectory('capacity');
      final metrics = <String, Object?>{
        'base': '186ab549e3d6a469a61eebf548bbe6f010755b83',
        'runtime': Platform.version,
        'platform': Platform.operatingSystem,
        'externalStaff': 100,
        'targetEvents': 10000,
        'committedEvents': 0,
        'keyAdapter': 'host memory keys, real AES and Ed25519',
        'checkpoints': <Object?>[],
      };
      final output = File('${root.path}/metrics.json');
      final watch = Stopwatch()..start();
      Future<void> save(String phase) async {
        metrics['phase'] = phase;
        metrics['elapsedMs'] = watch.elapsedMilliseconds;
        metrics['maxRssBytes'] = ProcessInfo.maxRss;
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(metrics),
          flush: true,
        );
        // Only aggregate synthetic metrics and the owned output path are logged.
        // ignore: avoid_print
        print('CAPACITY $phase ${watch.elapsedMilliseconds}ms ${output.path}');
      }

      final managerKeys = MemoryKeyStore();
      final manager = AcceptanceDevice(
        AppPaths(Directory('${root.path}/manager')),
        managerKeys,
      );
      AcceptanceDevice? target;
      await manager.open();
      // Private synthetic keys support post-run diagnostic reopening; never commit.
      Future<void> retainKeys() async {
        final file = File('${root.path}/synthetic-manager-keys.private.json');
        await file.writeAsString(
          jsonEncode(
            managerKeys.values.map((k, v) => MapEntry(k, base64Encode(v))),
          ),
          flush: true,
        );
        await Process.run('chmod', ['600', file.path]);
      }

      try {
        final company = await manager.createCompany();
        metrics['companyId'] = company.id;
        metrics['personId'] = manager.identity
            .requireActor(manager.session)
            .personId;
        final invitation = await manager.enrollment.createInvitation(
          manager.context(company),
        );
        final workplace = await manager.capture.createWorkplaceCode(
          manager.context(company),
        );
        final senders =
            <
              ({
                LocalKeyService signing,
                String key,
                Uint8List public,
                String person,
                String installation,
                SignedMessage grant,
              })
            >[];
        final codec = MessageCodec();
        Future<SignedMessage> sign(
          LocalKeyService keys,
          String key,
          Uint8List public,
          MessageKind kind,
          List<Object?> values,
        ) async {
          final payload = Uint8List.fromList(
            utf8.encode(jsonEncode(MessagePayload(kind, values).values)),
          );
          return SignedMessage(
            kind: kind,
            keyId: await messageKeyId(public),
            payloadBytes: payload,
            signature: await keys.sign(messageSigningBytes(kind, payload), key),
          );
        }

        for (var i = 0; i < 100; i++) {
          final keys = LocalKeyService(MemoryKeyStore()),
              key = SecureIds().next(),
              person = SecureIds().next(),
              installation = SecureIds().next();
          final public = await keys.create(key);
          final join = await sign(keys, key, public, MessageKind.joinRequest, [
            company.id,
            SecureIds().next(),
            manager.clock.now.millisecondsSinceEpoch,
            invitation.payload.messageId,
            person,
            'Synthetic staff ${i + 1}',
            installation,
            base64UrlEncode(public),
          ]);
          final grant =
              await manager.enrollment.approveJoin(
                    manager.context(company),
                    await manager.enrollment.verifyIncoming(
                      manager.session,
                      codec.encode(join),
                    ),
                  )
                  as Committed<SignedMessage>;
          senders.add((
            signing: keys,
            key: key,
            public: public,
            person: person,
            installation: installation,
            grant: grant.value,
          ));
        }
        expect(
          (await manager.companies.listStaff(
            manager.session,
            company.id,
          )).length,
          101,
        );
        await retainKeys();
        await save('enrolled-100-non-owner-staff');
        final eventIds = <String>{};
        Uint8List? firstBytes;
        String? firstOperation;
        var verifyUs = 0, importUs = 0;
        final receipts = File(
          '${root.path}/synthetic-receipts.ndjson',
        ).openWrite();
        try {
          for (var n = 0; n < 10000; n++) {
            final sender = senders[n % 100], index = n ~/ 100;
            final grant = sender.grant.payload;
            final claimed = DateTime.utc(2026, 8, 1)
                .add(Duration(days: index ~/ 2, hours: index.isEven ? 0 : 8))
                .millisecondsSinceEpoch;
            final event = SecureIds().next();
            final wire = codec.encode(
              await sign(
                sender.signing,
                sender.key,
                sender.public,
                MessageKind.attendance,
                [
                  company.id,
                  event,
                  claimed,
                  sender.person,
                  grant.field<String>('employeeId'),
                  grant.field<String>('membershipId'),
                  grant.field<int>('membershipRevision'),
                  sender.installation,
                  index.isEven ? 'checkIn' : 'checkOut',
                  claimed,
                  540,
                  workplace.payload.field<String>('workplaceId'),
                  workplace.payload.field<String>('codeId'),
                  AuthorityCertificate(
                    grant.field<List<Object?>>('authority'),
                  ).generationId,
                  'staticQr',
                ],
              ),
            );
            final operation = SecureIds().next();
            final timer = Stopwatch()..start();
            final verified = await manager.attendance.verifyIncoming(
              manager.session,
              company.id,
              wire,
            );
            verifyUs += timer.elapsedMicroseconds;
            timer.reset();
            final imported = await manager.attendance.importReceipt(
              manager.context(company, operation),
              verified,
            );
            importUs += timer.elapsedMicroseconds;
            if (imported.status == ImportStatus.received ||
                imported.status == ImportStatus.needsReview) {
              metrics['committedEvents'] =
                  (metrics['committedEvents'] as int? ?? 0) + 1;
            }
            expect(
              imported.status,
              ImportStatus.received,
              reason: 'event ${n + 1}: ${imported.error}',
            );
            expect(eventIds.add(event), isTrue);
            receipts.writeln(
              jsonEncode([event, operation, base64Encode(wire)]),
            );
            firstBytes ??= wire;
            firstOperation ??= operation;
            if ([1, 10, 100, 1000, 5000, 10000].contains(n + 1)) {
              metrics['verifyUs'] = verifyUs;
              metrics['importUs'] = importUs;
              (metrics['checkpoints'] as List).add({
                'events': n + 1,
                'elapsedMs': watch.elapsedMilliseconds,
                'verifyUs': verifyUs,
                'importUs': importUs,
                'rss': ProcessInfo.currentRss,
              });
              await receipts.flush();
              await save('imports-${n + 1}');
            }
          }
        } finally {
          await receipts.flush();
          await receipts.close();
        }
        expect(await manager.count('attendance'), 10000);
        final reopen = Stopwatch()..start();
        await manager.reopen();
        metrics['reopenMs'] = reopen.elapsedMilliseconds;
        final pageWatch = Stopwatch()..start();
        AttendanceCursor? cursor;
        final seen = <String>{};
        var pages = 0;
        do {
          final page = await manager.queries.historyPage(
            manager.session,
            company.id,
            scope: AttendanceScope.management,
            pageSize: 100,
            cursor: cursor,
          );
          expect(page.refreshRequired, isFalse);
          expect(page.items.length, lessThanOrEqualTo(100));
          for (final item in page.items) {
            expect(seen.add(item.record.eventId), isTrue);
          }
          cursor = page.next;
          pages++;
        } while (cursor != null);
        expect(seen, eventIds);
        metrics['historyPages'] = pages;
        metrics['historyMs'] = pageWatch.elapsedMilliseconds;
        final verified = await manager.attendance.verifyIncoming(
          manager.session,
          company.id,
          firstBytes!,
        );
        final duplicate = Stopwatch()..start();
        final same = await manager.attendance.importReceipt(
          manager.context(company, firstOperation),
          verified,
        );
        expect(same.status, ImportStatus.received);
        metrics['sameOperationReplayMs'] = duplicate.elapsedMilliseconds;
        duplicate.reset();
        final fresh = await manager.attendance.importReceipt(
          manager.context(company),
          verified,
        );
        expect(fresh.status, ImportStatus.alreadyReceived);
        metrics['newOperationDuplicateMs'] = duplicate.elapsedMilliseconds;
        expect(
          codec.encode(fresh.returnMessage!),
          orderedEquals(codec.encode(same.returnMessage!)),
        );
        expect(await manager.count('attendance'), 10000);
        final counts = <String, Object?>{};
        for (final table in [
          'stored_rows',
          'operation_rows',
          'revision_journal',
          'personal_records',
          'personal_operations',
          'attachment_rows',
        ]) {
          counts[table] =
              (await manager.database
                      .customSelect('SELECT COUNT(*) AS n FROM $table')
                      .getSingle())
                  .read<int>('n');
        }
        counts['kinds'] =
            (await manager.database
                    .customSelect(
                      'SELECT kind,COUNT(*) AS n FROM stored_rows GROUP BY kind ORDER BY kind',
                    )
                    .get())
                .map((r) => r.data)
                .toList();
        metrics['counts'] = counts;
        final plans = <String, Object?>{};
        for (final entry in {
          'journalOperation':
              'SELECT * FROM revision_journal WHERE company_id=? AND operation_id=?',
          'journalRevision':
              'SELECT * FROM revision_journal WHERE company_id=? AND revision=?',
          'owners':
              'SELECT * FROM personal_operations WHERE company_id=? AND operation_id=?',
          'history':
              "SELECT r.* FROM stored_rows r WHERE company_id=? AND category='event' AND kind IN ('attendance','manualAttendance') AND id>? ORDER BY id LIMIT 100",
          'projections':
              "SELECT * FROM stored_rows WHERE company_id=? AND kind='attendanceState' AND id>? ORDER BY id LIMIT 100",
        }.entries) {
          plans[entry.key] =
              (await manager.database
                      .customSelect(
                        'EXPLAIN QUERY PLAN ${entry.value}',
                        variables: [
                          Variable.withString(company.id),
                          Variable.withString(
                            entry.key == 'journalRevision'
                                ? '1'
                                : firstOperation!,
                          ),
                        ],
                      )
                      .get())
                  .map((r) => r.data)
                  .toList();
        }
        metrics['queryPlans'] = plans;
        await save('reopen-pages-duplicates-complete');
        final exportWatch = Stopwatch()..start();
        final descriptor = await manager.archives.create(
          manager.session,
          CompanyScope(company.id),
          acceptancePassword,
        );
        final bytes = await manager.archives.shareBytes(
          manager.session,
          descriptor.artifactId,
        );
        metrics['exportMs'] = exportWatch.elapsedMilliseconds;
        metrics['encryptedBytes'] = bytes.length;
        metrics['compressedBytes'] = bytes.length - 68;
        metrics['archiveCounts'] = descriptor.counts;
        final file = File('${root.path}/whole-manager.razecheck-backup');
        await file.writeAsBytes(bytes, flush: true);
        final contents = await ArchiveCodec.open(bytes, acceptancePassword);
        metrics['entryBytes'] = contents.map((k, v) => MapEntry(k, v.length));
        metrics['expandedBytes'] = contents.values.fold<int>(
          0,
          (n, b) => n + b.length,
        );
        final originalRecordsHash = base64Encode(
          (await Sha256().hash(contents['records.json']!)).bytes,
        );
        await save('whole-manager-exported');
        target = AcceptanceDevice(
          AppPaths(Directory('${root.path}/restored')),
          MemoryKeyStore(),
        );
        await target.open(name: 'Synthetic recovery setup');
        final restoreWatch = Stopwatch()..start();
        final preview = await target.archives.inspect(
          target.session,
          file.path,
          acceptancePassword,
        );
        expect(preview.conflicts, isEmpty);
        await target.archives.apply(preview, RestoreChoice.newInstallation);
        metrics['restoreMs'] = restoreWatch.elapsedMilliseconds;
        final encoder = await ArchiveRecordWorker.start();
        await target.repository.visitArchive(
          CompanyScope(company.id),
          encoder.add,
        );
        final restored = await encoder.finish();
        expect(
          base64Encode((await Sha256().hash(restored)).bytes),
          originalRecordsHash,
          reason: 'ALL exact manager logical content, not a subset',
        );
        expect(await target.count('attendance'), 10000);
        await expectLater(
          target.queries.historyPage(
            target.session,
            company.id,
            scope: AttendanceScope.management,
          ),
          throwsA(isA<CheckException>()),
        );
        metrics['exactLogicalArchiveRestored'] = true;
        metrics['result'] = 'passed-host-engineering';
        await retainKeys();
        await save('complete');
      } catch (error) {
        metrics['result'] = 'failed';
        metrics['failure'] = error.toString();
        await save('failed');
        rethrow;
      } finally {
        await target?.close();
        await manager.close();
      }
    },
    skip: Platform.environment['RAZE_CAPACITY'] != '1'
        ? 'Opt in with RAZE_CAPACITY=1; full 100/10000 real-service engineering run'
        : false,
  );
}
