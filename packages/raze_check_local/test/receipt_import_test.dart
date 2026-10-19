import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'support/two_device_fixture.dart';

LocalAttendanceService service(EnrollmentDevice d) => LocalAttendanceService(
  repository: d.storage.repo,
  identity: d.identity,
  keys: d.storage.keys,
  clock: d.clock,
  ids: SecureIds(),
);
void main() {
  test(
    'receipt import deduplicates without approving and preserves exact original',
    () async {
      final p = await TwoDeviceFixture.create();
      addTearDown(p.dispose);
      await p.enrollStaff();
      final receipt = await p.captureCheckIn();
      final manager = service(p.manager);
      final verified = await manager.verifyIncoming(
        p.manager.session,
        p.companyId,
        receipt.bytes,
      );
      final first = await manager.importReceipt(p.context('receive'), verified);
      expect(first.status, ImportStatus.received);
      expect(
        (await manager.importReceipt(p.context('receive2'), verified)).status,
        ImportStatus.alreadyReceived,
      );
      expect(
        (await manager.get(
          p.manager.session,
          p.companyId,
          receipt.eventId,
        )).review,
        ReviewStatus.pending,
      );
      final approved = await manager.decide(
        p.context('review-approve'),
        receipt.eventId,
        ReviewDecision.approve,
        'Checked',
      );
      expect(approved, isA<Committed<DecisionRecord>>());
      await manager.decide(
        p.context('review-approve'),
        receipt.eventId,
        ReviewDecision.approve,
        'Checked',
      );
      await manager.importReceipt(p.context('receive3'), verified);
      expect(
        (await manager.get(
          p.manager.session,
          p.companyId,
          receipt.eventId,
        )).review,
        ReviewStatus.approved,
      );
      expect(
        (await p.manager.storage.repo.read(
          p.companyId,
          receipt.eventId,
        ))!.payload,
        orderedEquals(receipt.bytes),
      );
      expect(
        (await manager.history(
          p.manager.session,
          p.companyId,
          receipt.eventId,
        )).length,
        1,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
