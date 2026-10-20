@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/acceptance_device.dart';
import 'support/capacity_cost_probe.dart';
import 'support/memory_key_store.dart';

void main() {
  test(
    'diagnostic copied checkpoint measures real SQL and AES work without changing baseline',
    () async {
      final path = Platform.environment['RAZE_CAPACITY_PROBE']!,
          root = Directory(path);
      final provenance =
          jsonDecode(await File('$path/provenance.json').readAsString())
              as Map<String, dynamic>;
      final encoded =
          jsonDecode(
                await File(
                  '$path/synthetic-manager-keys.private.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final keys = MemoryKeyStore();
      for (final e in encoded.entries) {
        keys.values[e.key] = base64Decode(e.value as String);
      }
      final probe = CostProbe(AesPayloadCipher(VaultKeys(keys)));
      final manager = AcceptanceDevice(
        AppPaths(Directory('$path/manager')),
        keys,
        interceptor: probe,
        cipher: probe,
      );
      await manager.open(unlockPerson: provenance['personId'] as String);
      addTearDown(manager.close);
      final company = (await manager.companies.readCompany(
        manager.session,
        provenance['companyId'] as String,
      ))!;
      expect(await manager.count('attendance'), provenance['baselineEvents']);
      final results = <String, Object?>{
        'provenance': provenance,
        'extraDiagnosticStaff': 1,
        'extraDiagnosticEvents': 3,
        'claim':
            'current-source fresh imports on a historical snapshot; not repeated initial imports',
        'phases': <String, Object?>{},
      };
      Future<T> measure<T>(String label, Future<T> Function() action) async {
        probe.metrics.clear();
        final watch = Stopwatch()..start();
        try {
          return await action();
        } catch (error) {
          results['failedPhase'] = label;
          results['failure'] = error.toString();
          rethrow;
        } finally {
          (results['phases'] as Map)[label] = {
            'elapsedUs': watch.elapsedMicroseconds,
            ...probe.metrics,
            'rssBytes': ProcessInfo.currentRss,
          };
          await File('$path/probe-results.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert(results),
            flush: true,
          );
        }
      }

      final codec = MessageCodec(),
          signer = LocalKeyService(MemoryKeyStore()),
          key = SecureIds().next(),
          person = SecureIds().next(),
          installation = SecureIds().next();
      final public = await signer.create(key);
      Future<SignedMessage> sign(MessageKind kind, List<Object?> values) async {
        final payload = Uint8List.fromList(
          utf8.encode(jsonEncode(MessagePayload(kind, values).values)),
        );
        return SignedMessage(
          kind: kind,
          keyId: await messageKeyId(public),
          payloadBytes: payload,
          signature: await signer.sign(messageSigningBytes(kind, payload), key),
        );
      }

      final invitation = await manager.enrollment.createInvitation(
        manager.context(company),
      );
      final join = await sign(MessageKind.joinRequest, [
        company.id,
        SecureIds().next(),
        manager.clock.now.millisecondsSinceEpoch,
        invitation.payload.messageId,
        person,
        'Synthetic diagnostic signer',
        installation,
        base64UrlEncode(public),
      ]);
      final grant =
          (await manager.enrollment.approveJoin(
                    manager.context(company),
                    await manager.enrollment.verifyIncoming(
                      manager.session,
                      codec.encode(join),
                    ),
                  )
                  as Committed<SignedMessage>)
              .value
              .payload;
      final workplace = await manager.capture.createWorkplaceCode(
        manager.context(company),
      );
      final event = SecureIds().next(),
          time = DateTime.utc(2026, 8, 1).millisecondsSinceEpoch;
      Future<Uint8List> attendanceWire(
        String eventId,
        String kind,
        int at,
      ) async => codec.encode(
        await sign(MessageKind.attendance, [
          company.id,
          eventId,
          at,
          person,
          grant.field<String>('employeeId'),
          grant.field<String>('membershipId'),
          grant.field<int>('membershipRevision'),
          installation,
          kind,
          at,
          540,
          workplace.payload.field<String>('workplaceId'),
          workplace.payload.field<String>('codeId'),
          AuthorityCertificate(
            grant.field<List<Object?>>('authority'),
          ).generationId,
          'staticQr',
        ]),
      );
      final receipt = await attendanceWire(
        event,
        'checkOut',
        time + 8 * 3600000,
      );
      final verified = await measure(
        'verify',
        () => manager.attendance.verifyIncoming(
          manager.session,
          company.id,
          receipt,
        ),
      );
      final context = manager.context(company);
      final imported = await measure(
        'freshImport',
        () => manager.attendance.importReceipt(context, verified),
      );
      expect(imported.status, ImportStatus.needsReview);
      expect(
        (await manager.attendance.get(
          manager.session,
          company.id,
          event,
        )).flags,
        contains('missingCheckIn'),
      );
      final originalAck = codec.encode(imported.returnMessage!);
      final replay = await measure(
        'sameOperationReplay',
        () => manager.attendance.importReceipt(context, verified),
      );
      expect(replay.status, ImportStatus.alreadyReceived);
      expect(codec.encode(replay.returnMessage!), orderedEquals(originalAck));
      final duplicate = await measure(
        'newOperationDuplicate',
        () => manager.attendance.importReceipt(
          manager.context(company),
          verified,
        ),
      );
      expect(duplicate.status, ImportStatus.alreadyReceived);
      expect(
        codec.encode(duplicate.returnMessage!),
        orderedEquals(originalAck),
      );
      final lateId = SecureIds().next();
      final lateWire = await attendanceWire(lateId, 'checkIn', time);
      final lateVerified = await measure(
        'verifyLateEndpoint',
        () => manager.attendance.verifyIncoming(
          manager.session,
          company.id,
          lateWire,
        ),
      );
      final late = await measure(
        'lateEndpointImport',
        () => manager.attendance.importReceipt(
          manager.context(company),
          lateVerified,
        ),
      );
      expect(late.status, ImportStatus.received);
      expect(
        (await manager.attendance.get(
          manager.session,
          company.id,
          event,
        )).flags,
        isEmpty,
      );
      final repeatedId = SecureIds().next();
      final repeatedWire = await attendanceWire(
        repeatedId,
        'checkIn',
        time + 3600000,
      );
      final repeatedVerified = await measure(
        'verifyRepeatedCheckIn',
        () => manager.attendance.verifyIncoming(
          manager.session,
          company.id,
          repeatedWire,
        ),
      );
      final repeated = await measure(
        'repeatedCheckInImport',
        () => manager.attendance.importReceipt(
          manager.context(company),
          repeatedVerified,
        ),
      );
      expect(repeated.status, ImportStatus.needsReview);
      expect(
        (await manager.attendance.get(
          manager.session,
          company.id,
          repeatedId,
        )).flags,
        containsAll(['missingCheckOut', 'unexpectedOrder']),
      );
      // Privileged test storage oracle; not a manager call to personal getReceipt.
      for (final entry in {
        event: receipt,
        lateId: lateWire,
        repeatedId: repeatedWire,
      }.entries) {
        expect(
          (await manager.repository.read(company.id, entry.key))!.payload,
          orderedEquals(entry.value),
        );
      }
      final page = await measure(
        'firstHistory100',
        () => manager.queries.historyPage(
          manager.session,
          company.id,
          scope: AttendanceScope.management,
          pageSize: 100,
        ),
      );
      expect(page.items, hasLength(100));
      expect(probe.metrics['sql.history.maxRows'], 100);
      await measure(
        'secondHistory100',
        () => manager.queries.historyPage(
          manager.session,
          company.id,
          scope: AttendanceScope.management,
          pageSize: 100,
          cursor: page.next,
        ),
      );
      var logical = 0;
      await measure(
        'wholeArchiveTraversal',
        () => manager.repository.visitArchive(CompanyScope(company.id), (
          kind,
          value,
        ) async {
          logical++;
        }),
      );
      results['visitedLogicalItems'] = logical;
      final plans = <String, Object?>{};
      for (final e in {
        'journalOperation':
            'SELECT * FROM revision_journal WHERE company_id=? AND operation_id=?',
        'journalRevision':
            'SELECT * FROM revision_journal WHERE company_id=? AND revision=?',
        'owners':
            'SELECT * FROM personal_operations WHERE company_id=? AND operation_id=?',
        'history':
            "SELECT r.* FROM stored_rows r WHERE company_id=? AND category='event' AND kind IN ('attendance','manualAttendance') AND id>? ORDER BY id LIMIT 100",
      }.entries) {
        plans[e.key] =
            (await manager.database
                    .customSelect(
                      'EXPLAIN QUERY PLAN ${e.value}',
                      variables: [
                        Variable.withString(company.id),
                        Variable.withString(
                          e.key == 'journalRevision'
                              ? '1'
                              : context.operationId,
                        ),
                      ],
                    )
                    .get())
                .map((r) => r.data)
                .toList();
      }
      results['queryPlans'] = plans;
      results['finalDiagnosticEvents'] = await manager.count('attendance');
      results['maxRssBytes'] = ProcessInfo.maxRss;
      expect(
        results['finalDiagnosticEvents'],
        (provenance['baselineEvents'] as int) + 3,
      );
      await File('${root.path}/probe-results.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(results),
        flush: true,
      );
      // ignore: avoid_print
      print('PROBE ${root.path}/probe-results.json');
    },
    skip: Platform.environment['RAZE_CAPACITY_PROBE'] == null
        ? 'Requires explicitly owned online-backup diagnostic copy'
        : false,
  );
}
