@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/acceptance_device.dart';
import 'support/memory_key_store.dart';

final class CostProbe extends QueryInterceptor implements PayloadCipher {
  CostProbe(this.real);
  final PayloadCipher real;
  final metrics = <String, int>{};
  var active = 0;
  var activeSealedBytes = 0;
  void add(String key, int value) =>
      metrics.update(key, (v) => v + value, ifAbsent: () => value);
  void maximum(String key, int value) {
    if (value > (metrics[key] ?? 0)) {
      metrics[key] = value;
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    final family = statement.contains('SELECT r.* FROM stored_rows r')
        ? 'history'
        : statement.contains('stored_rows')
        ? 'stored'
        : statement.contains('personal_operations')
        ? 'owners'
        : statement.contains('revision_journal')
        ? 'journal'
        : statement.contains('operation_rows')
        ? 'operations'
        : 'other';
    add('sql.$family.calls', 1);
    add('sql.$family.rows', rows.length);
    maximum('sql.$family.maxRows', rows.length);
    var bodyBytes = 0;
    for (final row in rows) {
      for (final value in row.values) {
        if (value is Uint8List) {
          bodyBytes += value.length;
        }
      }
    }
    add('sql.$family.bodyBytes', bodyBytes);
    maximum('sql.$family.maxBodyBytes', bodyBytes);
    return rows;
  }

  @override
  Future<Uint8List> open({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List sealed,
  }) async {
    active++;
    activeSealedBytes += sealed.length;
    maximum('aes.maxConcurrentOpens', active);
    maximum('aes.maxConcurrentSealedBytes', activeSealedBytes);
    add('aes.opens', 1);
    add('aes.sealedBytes', sealed.length);
    if (recordId.startsWith('record:attendance-state:')) {
      add('aes.attendanceStateOpens', 1);
    }
    if (recordId.startsWith('operation:')) {
      add('aes.operationOpens', 1);
    }
    try {
      final value = await real.open(
        scopeId: scopeId,
        recordId: recordId,
        revision: revision,
        sealed: sealed,
      );
      add('aes.plainBytes', value.length);
      maximum('aes.maxSinglePlainBytes', value.length);
      return value;
    } finally {
      active--;
      activeSealedBytes -= sealed.length;
    }
  }

  @override
  Future<Uint8List> seal({
    required String scopeId,
    required String recordId,
    required int revision,
    required Uint8List plain,
  }) async {
    add('aes.seals', 1);
    add('aes.sealPlainBytes', plain.length);
    return real.seal(
      scopeId: scopeId,
      recordId: recordId,
      revision: revision,
      plain: plain,
    );
  }
}

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
        'phases': <String, Object?>{},
      };
      Future<T> measure<T>(String label, Future<T> Function() action) async {
        probe.metrics.clear();
        final watch = Stopwatch()..start();
        final result = await action();
        (results['phases'] as Map)[label] = {
          'elapsedUs': watch.elapsedMicroseconds,
          ...probe.metrics,
          'rssBytes': ProcessInfo.currentRss,
        };
        await File('$path/probe-results.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(results),
          flush: true,
        );
        return result;
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
      final receipt = codec.encode(
        await sign(MessageKind.attendance, [
          company.id,
          event,
          time,
          person,
          grant.field<String>('employeeId'),
          grant.field<String>('membershipId'),
          grant.field<int>('membershipRevision'),
          installation,
          'checkIn',
          time,
          540,
          workplace.payload.field<String>('workplaceId'),
          workplace.payload.field<String>('codeId'),
          AuthorityCertificate(
            grant.field<List<Object?>>('authority'),
          ).generationId,
          'staticQr',
        ]),
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
      expect(imported.status, ImportStatus.received);
      expect(
        (results['phases'] as Map)['freshImport']['aes.attendanceStateOpens'],
        provenance['baselineEvents'],
      );
      await measure(
        'sameOperationReplay',
        () => manager.attendance.importReceipt(context, verified),
      );
      final duplicate = await measure(
        'newOperationDuplicate',
        () => manager.attendance.importReceipt(
          manager.context(company),
          verified,
        ),
      );
      expect(duplicate.status, ImportStatus.alreadyReceived);
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
        (provenance['baselineEvents'] as int) + 1,
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
