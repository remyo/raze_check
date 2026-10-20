@Timeout(Duration(hours: 1))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'package:raze_check_local/src/recovery/archive_codec.dart';
import 'package:raze_check_local/src/recovery/archive_records.dart';
import 'support/acceptance_device.dart';
import 'support/capacity_cost_probe.dart';
import 'support/memory_key_store.dart';

void main() {
  test(
    'current services retain the complete historical 100 staff 10000 event fixture',
    () async {
      final path = Platform.environment['RAZE_CAPACITY_RECONCILIATION']!;
      final provenance =
          jsonDecode(await File('$path/provenance.json').readAsString())
              as Map<String, dynamic>;
      expect(provenance['baselineEvents'], 10000);
      final keys = MemoryKeyStore();
      final encoded =
          jsonDecode(
                await File(
                  '$path/synthetic-manager-keys.private.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      for (final entry in encoded.entries) {
        keys.values[entry.key] = base64Decode(entry.value as String);
      }
      final cost = CostProbe(AesPayloadCipher(VaultKeys(keys)));
      final manager = AcceptanceDevice(
        AppPaths(Directory('$path/manager')),
        keys,
        interceptor: cost,
        cipher: cost,
      );
      await manager.open(unlockPerson: provenance['personId'] as String);
      addTearDown(manager.close);
      final company = (await manager.companies.readCompany(
        manager.session,
        provenance['companyId'] as String,
      ))!;
      final results = <String, Object?>{
        'provenance': provenance,
        'claim':
            'current-source compatibility and retention; initial imports used original source',
        'cipherMetricsScope':
            'repository PayloadCipher; archive password encryption is timed separately',
        'phases': <String, Object?>{},
      };
      Future<void> save() async {
        results['maxRssBytes'] = ProcessInfo.maxRss;
        await File('$path/reconciliation-results.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(results),
          flush: true,
        );
      }

      Future<T> measure<T>(
        String label,
        Future<T> Function() action, {
        CostProbe? measuredCost,
      }) async {
        final probe = measuredCost ?? cost;
        probe.metrics.clear();
        final watch = Stopwatch()..start();
        try {
          return await action();
        } finally {
          (results['phases'] as Map)[label] = {
            'elapsedUs': watch.elapsedMicroseconds,
            ...probe.metrics,
            'rssBytes': ProcessInfo.currentRss,
          };
          await save();
          // ignore: avoid_print
          print('RECONCILIATION $label');
        }
      }

      try {
        expect(await manager.count('attendance'), 10000);
        expect(
          await manager.companies.listStaff(manager.session, company.id),
          hasLength(101),
        );
        await measure('reopen', manager.reopen);
        final expected = <String, Map<String, Object?>>{};
        final perPerson = <String, int>{};
        final codec = MessageCodec();
        Uint8List? firstWire;
        String? firstOperation;
        var wireBytes = 0, largestWire = 0;
        // This is explicitly a privileged storage oracle, not an owner call to
        // the personal CaptureService.getReceipt API or an impersonated session.
        await measure('completeImmutableStorageOracle', () async {
          await for (final line
              in File('$path/synthetic-receipts.ndjson')
                  .openRead()
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())) {
            final entry = jsonDecode(line) as List<dynamic>;
            final wire = base64Decode(entry[2] as String);
            final message = codec.decode(
              wire,
              maxBytes: MessageLimits.fileBytes,
            );
            final payload = message.payload;
            expect(message.kind, MessageKind.attendance);
            expect(payload.messageId, entry[0]);
            expect(payload.companyId, company.id);
            final person = payload.field<String>('personId');
            expect(person, isNot(provenance['personId']));
            final index = perPerson[person] ?? 0;
            perPerson[person] = index + 1;
            final time = DateTime.utc(2026, 8, 1)
                .add(Duration(days: index ~/ 2, hours: index.isEven ? 0 : 8))
                .millisecondsSinceEpoch;
            expect(payload.field<int>('claimedUtcMs'), time);
            expect(
              payload.field<String>('kind'),
              index.isEven ? 'checkIn' : 'checkOut',
            );
            expect(payload.field<int>('offsetMinutes'), 540);
            expect(expected.containsKey(payload.messageId), isFalse);
            expected[payload.messageId] = {
              'person': person,
              'employee': payload.field<String>('employeeId'),
              'time': time,
              'kind': payload.field<String>('kind'),
            };
            final stored = await manager.repository.read(
              company.id,
              payload.messageId,
            );
            expect(stored!.payload, orderedEquals(wire));
            firstWire ??= wire;
            firstOperation ??= entry[1] as String;
            wireBytes += wire.length;
            if (wire.length > largestWire) largestWire = wire.length;
          }
        });
        expect(expected, hasLength(10000));
        expect(perPerson, hasLength(100));
        expect(perPerson.values, everyElement(100));
        results.addAll({
          'oracleEventsMaterialized': expected.length,
          'externalStaff': perPerson.length,
          'originalWireBytes': wireBytes,
          'maximumSingleWireBytes': largestWire,
        });

        void checkItem(AttendanceItem item) {
          final r = item.record, e = expected[item.record.eventId]!;
          expect(r.personId, e['person']);
          expect(r.employeeId, e['employee']);
          expect(r.claimedUtcMs, e['time']);
          expect(r.effectiveUtcMs, e['time']);
          expect(r.effectiveKind.name, e['kind']);
          expect(r.data['originalKind'], e['kind']);
          expect(r.effectiveOffsetMinutes, 540);
          expect(r.data['originalOffsetMinutes'], 540);
          expect(r.review, ReviewStatus.pending);
          expect(r.delivery, DeliveryStatus.received);
          expect(r.flags, isEmpty);
          expect(r.decisionRevision, 0);
        }

        await measure('allHistoryPages', () async {
          AttendanceCursor? cursor;
          final seen = <String>{};
          var pages = 0, maximumPage = 0;
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
              checkItem(item);
            }
            if (page.items.length > maximumPage) {
              maximumPage = page.items.length;
            }
            cursor = page.next;
            pages++;
          } while (cursor != null);
          expect(seen, expected.keys.toSet());
          results['historyPages'] = pages;
          results['maximumHistoryOutputRows'] = maximumPage;
        });
        await measure('fullReport', () async {
          final report = await manager.queries.report(
            manager.context(company),
            DateRange(DateTime.utc(2026, 8, 1), DateTime.utc(2026, 10, 1)),
            scope: AttendanceScope.management,
          );
          expect(
            report.rows.map((i) => i.record.eventId).toSet(),
            expected.keys.toSet(),
          );
          expect(report.rows, hasLength(10000));
          for (final item in report.rows) {
            checkItem(item);
            expect(item.decisions, isEmpty);
          }
          results['fullReportOutputRows'] = report.rows.length;
        });
        await measure('outOfRangeReport', () async {
          final report = await manager.queries.report(
            manager.context(company),
            DateRange(DateTime.utc(2026, 7, 1), DateTime.utc(2026, 7, 1)),
            scope: AttendanceScope.management,
          );
          expect(report.rows, isEmpty);
        });

        final first = codec.decode(
          firstWire!,
          maxBytes: MessageLimits.fileBytes,
        );
        final originalImport = await manager.repository.read(
          company.id,
          'import:${first.payload.messageId}',
        );
        final originalAck = base64Url.decode(
          (jsonDecode(utf8.decode(originalImport!.payload))
                  as Map<String, dynamic>)['wire']
              as String,
        );
        final verified = await measure(
          'verifyOriginalReceipt',
          () => manager.attendance.verifyIncoming(
            manager.session,
            company.id,
            firstWire!,
          ),
        );
        for (final sameOperation in [true, false]) {
          final outcome = await measure(
            sameOperation ? 'sameOperationReplay' : 'newOperationDuplicate',
            () => manager.attendance.importReceipt(
              manager.context(company, sameOperation ? firstOperation : null),
              verified,
            ),
          );
          expect(outcome.status, ImportStatus.alreadyReceived);
          expect(
            codec.encode(outcome.returnMessage!),
            orderedEquals(originalAck),
          );
          expect(await manager.count('attendance'), 10000);
        }

        // Actual row counts before full export, including all setup/history and
        // the legitimate new duplicate-operation journal entry.
        final tableCounts = <String, int>{};
        for (final table in [
          'stored_rows',
          'operation_rows',
          'revision_journal',
          'personal_operations',
          'company_scopes',
          'personal_records',
          'attachment_rows',
          'company_creation_reservations',
          'restore_jobs',
          'passive_scopes',
          'restore_commits',
          'restored_profiles',
        ]) {
          tableCounts[table] =
              (await manager.database
                      .customSelect('SELECT COUNT(*) AS n FROM $table')
                      .getSingle())
                  .read<int>('n');
        }
        results['preArchiveTableCounts'] = tableCounts;
        results['preArchiveKinds'] =
            (await manager.database
                    .customSelect(
                      'SELECT category, kind, COUNT(*) AS n FROM stored_rows GROUP BY category, kind ORDER BY category, kind',
                    )
                    .get())
                .map((r) => r.data)
                .toList();
        final bytes = await measure('wholeArchiveCreate', () async {
          final descriptor = await manager.archives.create(
            manager.session,
            CompanyScope(company.id),
            acceptancePassword,
          );
          results['archiveCounts'] = descriptor.counts;
          return manager.archives.shareBytes(
            manager.session,
            descriptor.artifactId,
          );
        });
        final file = File('$path/current-whole-manager.razecheck-backup');
        await file.writeAsBytes(bytes, flush: true);
        results['encryptedBytes'] = bytes.length;
        results['compressedBytes'] = bytes.length - 68;
        results['archiveSha256Base64'] = base64Encode(
          (await Sha256().hash(bytes)).bytes,
        );
        final contents = await measure(
          'authenticateWholeArchive',
          () => ArchiveCodec.open(bytes, acceptancePassword),
        );
        results['entryBytes'] = contents.map((k, v) => MapEntry(k, v.length));
        results['expandedBytes'] = contents.values.fold<int>(
          0,
          (n, b) => n + b.length,
        );
        final recordHash = base64Encode(
          (await Sha256().hash(contents['records.json']!)).bytes,
        );
        results['recordsSha256Base64'] = recordHash;
        Future<String> logicalHash(AcceptanceDevice device) async {
          final encoder = await ArchiveRecordWorker.start();
          var count = 0;
          await device.repository.visitArchive(CompanyScope(company.id), (
            kind,
            value,
          ) async {
            count++;
            await encoder.add(kind, value);
          });
          final records = await encoder.finish();
          results['lastLogicalItems'] = count;
          results['lastEncodedRecordsBytes'] = records.length;
          return base64Encode((await Sha256().hash(records)).bytes);
        }

        expect(
          await measure(
            'completeSourceLogicalTraversal',
            () => logicalHash(manager),
          ),
          recordHash,
        );

        final targetKeys = MemoryKeyStore();
        final targetCost = CostProbe(AesPayloadCipher(VaultKeys(targetKeys)));
        final target = AcceptanceDevice(
          AppPaths(Directory('$path/restored')),
          targetKeys,
          interceptor: targetCost,
          cipher: targetCost,
        );
        await target.open(name: 'Synthetic current-source recovery setup');
        addTearDown(target.close);
        final preview = await measure(
          'wholeArchiveInspect',
          () => target.archives.inspect(
            target.session,
            file.path,
            acceptancePassword,
          ),
          measuredCost: targetCost,
        );
        expect(preview.conflicts, isEmpty);
        expect(preview.filesComplete, isTrue);
        await measure(
          'wholeArchiveApply',
          () => target.archives.apply(preview, RestoreChoice.newInstallation),
          measuredCost: targetCost,
        );
        expect(
          await measure(
            'completeRestoredLogicalTraversal',
            () => logicalHash(target),
            measuredCost: targetCost,
          ),
          recordHash,
        );
        expect(await target.count('attendance'), 10000);
        await expectLater(
          target.queries.historyPage(
            target.session,
            company.id,
            scope: AttendanceScope.management,
          ),
          throwsA(
            isA<CheckException>().having(
              (e) => e.code,
              'code',
              CheckError.unauthorized,
            ),
          ),
        );
        await expectLater(
          target.capture.getReceipt(
            target.session,
            company.id,
            first.payload.messageId,
          ),
          throwsA(
            isA<CheckException>().having(
              (e) => e.code,
              'code',
              CheckError.unauthorized,
            ),
          ),
        );
        results['exactLogicalArchiveRestored'] = true;
        results['finalEvents'] = await manager.count('attendance');
        results['result'] = 'passed-current-source-historical-fixture';
        await save();
      } catch (error) {
        results['result'] = 'failed';
        results['failure'] = error.toString();
        results['actualPersistedEventsAtFailure'] = await manager.count(
          'attendance',
        );
        await save();
        rethrow;
      }
    },
    skip: Platform.environment['RAZE_CAPACITY_RECONCILIATION'] == null
        ? 'Requires complete, owned 10000-event historical copy; never mutates original'
        : false,
  );
}
