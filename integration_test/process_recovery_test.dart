// A two-launch harness. The first launch intentionally waits for host SIGKILL.
// Never report its interrupted driver as a pass; compare pre/post host artifacts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../packages/raze_check_local/test/support/acceptance_device.dart';

const runId = String.fromEnvironment('RAZE_PROCESS_RUN');
const killCase = String.fromEnvironment(
  'RAZE_PROCESS_CASE',
  defaultValue: 'visible',
);
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'owned resumable OS process-death receipt case',
    (tester) async {
      if (!RegExp(r'^[a-zA-Z0-9-]{8,80}$').hasMatch(runId) ||
          !['before', 'committed', 'visible'].contains(killCase)) {
        throw StateError(
          'Supply unique RAZE_PROCESS_RUN and before/committed/visible CASE.',
        );
      }
      final base = await AppPaths.persistent();
      final root = Directory('${base.root.path}/acceptance/process-$runId');
      await root.create(recursive: true);
      final manifest = File('${root.path}/run.json');
      Future<void> write(String name, Map<String, Object?> value) async {
        final temporary = File('${root.path}/$name.tmp');
        await temporary.writeAsString(jsonEncode(value), flush: true);
        await temporary.rename('${root.path}/$name');
      }

      final prior = await manifest.exists()
          ? jsonDecode(await manifest.readAsString()) as Map<String, dynamic>
          : null;
      if (prior != null &&
          (prior['run'] != runId ||
              prior['case'] != killCase ||
              prior['phase'] != 'armed')) {
        throw StateError(
          'Run exists but is not an armed resumable case; do not overwrite evidence.',
        );
      }
      AcceptanceDevice device(String role) => AcceptanceDevice(
        AppPaths(Directory('${root.path}/$role')),
        NamespacedKeys(OsSecureKeyStore(), 'acceptance:process-$runId:$role'),
      );
      final staff = device('staff');
      late Company company;
      late String operation;
      final boundary = GlobalKey();
      Future<void> mount(CaptureService service) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              home: Scaffold(
                body: CaptureWorkspace(
                  service: service,
                  session: staff.session,
                  company: company,
                  ids: SecureIds(),
                  onChanged: () {},
                  onLocked: () {},
                ),
              ),
            ),
          ),
        );
      }

      Future<void> until(bool Function() predicate) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!predicate() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          predicate(),
          isTrue,
          reason: 'Timed out waiting for real capture UI',
        );
      }

      Future<Map<String, Object?>> evidence(AttendanceReceipt receipt) async =>
          {
            'run': runId,
            'case': killCase,
            'operationId': operation,
            'eventId': receipt.eventId,
            'transportBase64': base64Encode(receipt.bytes),
            'payloadBase64': base64Encode(receipt.message.payloadBytes),
            'eventCount': await staff.count('attendance'),
            'outboxCount': await staff.count('attendanceOutbox'),
          };
      if (prior != null) {
        await staff.open(unlockPerson: prior['staffPerson'] as String);
        company = (await staff.companies.readCompany(
          staff.session,
          prior['company'] as String,
        ))!;
        operation = prior['operationId'] as String;
        final draft = await staff.capture.currentDraft(
          staff.session,
          company.id,
        );
        expect(draft!.operationId, operation);
        if (killCase == 'before') {
          expect(draft.eventId, isNull);
          expect(await staff.count('attendance'), 0);
          expect(await staff.count('attendanceOutbox'), 0);
          await mount(staff.capture);
          await until(
            () => find.text('Retry saved punch').evaluate().isNotEmpty,
          );
          await tester.tap(find.text('Retry saved punch'));
        } else {
          final pre =
              jsonDecode(await File('${root.path}/pre.json').readAsString())
                  as Map<String, dynamic>;
          expect(draft.eventId, pre['eventId']);
          final receipt = await staff.capture.getReceipt(
            staff.session,
            company.id,
            draft.eventId!,
          );
          expect(
            receipt.bytes,
            orderedEquals(base64Decode(pre['transportBase64'] as String)),
          );
          expect(
            receipt.message.payloadBytes,
            orderedEquals(base64Decode(pre['payloadBase64'] as String)),
          );
          await mount(staff.capture);
        }
        await until(
          () => find.text('Saved on this device').evaluate().isNotEmpty,
        );
        final saved = await staff.capture.currentDraft(
          staff.session,
          company.id,
        );
        final receipt = await staff.capture.getReceipt(
          staff.session,
          company.id,
          saved!.eventId!,
        );
        final code = await staff.capture.verifyWorkplace(
          staff.session,
          company.id,
          saved.workplaceBytes,
        );
        final replay =
            await staff.capture.recordPunch(
                  saved.context(staff.session),
                  code,
                  saved.kind,
                )
                as Committed<AttendanceReceipt>;
        expect(replay.value.bytes, orderedEquals(receipt.bytes));
        expect(replay.duplicate, isTrue);
        expect(await staff.count('attendance'), 1);
        expect(await staff.count('attendanceOutbox'), 1);
        final post = await evidence(receipt);
        post['result'] = 'verified-after-relaunch';
        await write('post.json', post);
        await write('run.json', {...prior, 'phase': 'complete'});
        await tester.pumpWidget(const SizedBox.shrink());
        await staff.close();
        return;
      }
      final manager = device('manager');
      await manager.open();
      await staff.open(name: 'Synthetic staff');
      company = await manager.createCompany();
      await enrollAcceptance(manager, staff, company);
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
      operation = draft.operationId;
      final state = <String, Object?>{
        'run': runId,
        'case': killCase,
        'phase': 'setup',
        'company': company.id,
        'staffPerson': staff.identity.requireActor(staff.session).personId,
        'operationId': operation,
        'mode':
            'independent logical stores on one phone; not two-phone printed-camera proof',
      };
      await write('run.json', state);
      await manager.close();
      Future<void> armed(Map<String, Object?> pre) async {
        await write('pre.json', pre);
        await write('run.json', {...state, 'phase': 'armed'});
      }

      Future<void> hold() => Completer<void>().future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException(
          'Host did not kill armed disposable app within five minutes',
        ),
      );
      CaptureService capture = staff.capture;
      if (killCase == 'before') {
        capture = LocalCaptureService(
          repository: BeforeMutation(staff.repository, operation, () async {
            await armed({
              'run': runId,
              'case': killCase,
              'operationId': operation,
              'barrier':
                  'real builder completed; mutation not returned for writes',
              'savedVisible': false,
            });
            await hold();
          }),
          identity: staff.identity,
          keys: staff.keys,
          clock: staff.clock,
          ids: SecureIds(),
          offsetMinutes: () => 540,
        );
      } else if (killCase == 'committed') {
        capture = AfterCapture(staff.capture, (receipt) async {
          await armed({
            ...await evidence(receipt),
            'barrier': 'real Committed result; receipt not exposed',
            'savedVisible': false,
          });
          await hold();
        });
      }
      await mount(capture);
      await until(() => find.text('Retry saved punch').evaluate().isNotEmpty);
      await tester.tap(find.text('Retry saved punch'));
      if (killCase == 'visible') {
        await until(
          () => find.text('Saved on this device').evaluate().isNotEmpty,
        );
        await tester.pump();
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File(
          '${root.path}/visible.png',
        ).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        final saved = await staff.capture.currentDraft(
          staff.session,
          company.id,
        );
        await armed({
          ...await evidence(
            await staff.capture.getReceipt(
              staff.session,
              company.id,
              saved!.eventId!,
            ),
          ),
          'barrier': 'actual saved receipt rendered',
          'savedVisible': true,
        });
      }
      // Keep real event loop active. Host retrieves armed artifacts, kills and relaunches.
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      throw TimeoutException(
        'No host process termination; this case did not pass',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

final class BeforeMutation implements CheckRepository {
  BeforeMutation(this.delegate, this.operation, this.barrier);
  final CheckRepository delegate;
  final String operation;
  final Future<void> Function() barrier;
  @override
  Future<CommandResult<StoredRecord>> commit(
    CommandContext context, {
    required Uint8List requestDigest,
    required Future<Mutation> Function(ReadView) build,
    Future<void> Function(ReadView)? authorize,
    void Function()? beforeCommit,
  }) => delegate.commit(
    context,
    requestDigest: requestDigest,
    authorize: authorize,
    beforeCommit: beforeCommit,
    build: (view) async {
      final mutation = await build(view);
      if (context.operationId == operation) {
        await barrier();
      }
      return mutation;
    },
  );
  @override
  Future<void> prepare(
    CommandContext c, {
    required Uint8List requestDigest,
    Set<String> personalOwners = const {},
  }) => delegate.prepare(
    c,
    requestDigest: requestDigest,
    personalOwners: personalOwners,
  );
  @override
  Future<List<StoredOperation>> pendingOperations(
    String c, {
    String? personId,
  }) => delegate.pendingOperations(c, personId: personId);
  @override
  Future<StoredRecord?> read(String c, String r) => delegate.read(c, r);
  @override
  Stream<int> watchRevision(String c) => delegate.watchRevision(c);
  @override
  Future<LogicalSnapshot> snapshot(
    ExportScope scope, {
    int maxBytes = 64 * 1024 * 1024,
    int maxEntries = 524288,
  }) => delegate.snapshot(scope, maxBytes: maxBytes, maxEntries: maxEntries);
}

final class AfterCapture implements CaptureService {
  AfterCapture(this.delegate, this.barrier);
  final CaptureService delegate;
  final Future<void> Function(AttendanceReceipt) barrier;
  @override
  Future<CommandResult<AttendanceReceipt>> recordPunch(
    CommandContext c,
    VerifiedMessage w,
    PunchKind k,
  ) async {
    final result = await delegate.recordPunch(c, w, k);
    if (result is Committed<AttendanceReceipt>) {
      await barrier(result.value);
    }
    return result;
  }

  @override
  Future<SignedMessage> createWorkplaceCode(CommandContext c) =>
      delegate.createWorkplaceCode(c);
  @override
  Future<VerifiedMessage> verifyWorkplace(
    SessionHandle s,
    String c,
    Uint8List b,
  ) => delegate.verifyWorkplace(s, c, b);
  @override
  Future<CaptureDraft> beginDraft(
    SessionHandle s,
    String c,
    VerifiedMessage w,
    PunchKind k,
  ) => delegate.beginDraft(s, c, w, k);
  @override
  Future<CaptureDraft?> currentDraft(SessionHandle s, String c) =>
      delegate.currentDraft(s, c);
  @override
  Future<void> finishDraft(SessionHandle s, String c, String e) =>
      delegate.finishDraft(s, c, e);
  @override
  Future<AttendanceReceipt> getReceipt(SessionHandle s, String c, String e) =>
      delegate.getReceipt(s, c, e);
  @override
  Future<List<AttendanceReceipt>> listOutbox(SessionHandle s, String c) =>
      delegate.listOutbox(s, c);
}
