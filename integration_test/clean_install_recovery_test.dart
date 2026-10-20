// The host retains an actual prior exported archive outside the phone, verifies
// disposable install ownership, uninstalls, then supplies these exact bytes to
// a fresh installation. This transport does not exercise the native Files UI.
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../packages/raze_check_local/test/support/acceptance_device.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'external archive recovers after owned uninstall and reinstall',
    (tester) async {
      const run = String.fromEnvironment('RAZE_LIFECYCLE_RUN');
      expect(RegExp(r'^[a-zA-Z0-9-]{8,80}$').hasMatch(run), isTrue);
      final archiveBytes = base64Decode(
        const String.fromEnvironment('RAZE_LIFECYCLE_ARCHIVE'),
      );
      final receiptBytes = base64Decode(
        const String.fromEnvironment('RAZE_LIFECYCLE_RECEIPT'),
      );
      final receipt = MessageCodec().decode(
        receiptBytes,
        maxBytes: MessageLimits.fileBytes,
      );
      final base = await AppPaths.persistent();
      final root = Directory('${base.root.path}/acceptance/lifecycle-$run');
      expect(
        await root.exists(),
        isFalse,
        reason: 'Never overwrite a prior run',
      );
      final target = AcceptanceDevice(
        AppPaths(root),
        NamespacedKeys(OsSecureKeyStore(), 'acceptance:lifecycle-$run'),
      );
      await target.open(name: 'Synthetic clean installation');
      try {
        expect(await target.count('attendance'), 0);
        final file = File('${root.path}/retained-external.razecheck-backup');
        await file.writeAsBytes(archiveBytes, flush: true);
        final preview = await target.archives.inspect(
          target.session,
          file.path,
          acceptancePassword,
        );
        expect(preview.conflicts, isEmpty);
        expect(preview.filesComplete, isTrue);
        final company = preview.companyIds.single;
        final candidate = await target.identity.stageRecoveryIdentity(
          target.session,
          companyId: company,
          personId: preview.personId,
          displayName: 'Synthetic restored owner',
          rootFingerprint: preview.companyRootFingerprints[company]!,
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
          preview.personId,
          acceptancePassword,
        );
        await target.reopen();
        final page = await target.queries.historyPage(
          target.session,
          company,
          scope: AttendanceScope.management,
        );
        final event = page.items.single.record;
        expect(event.review, ReviewStatus.approved);
        expect(event.effectiveKind, PunchKind.checkOut);
        expect(
          (await target.repository.read(company, event.eventId))!.payload,
          orderedEquals(receiptBytes),
        );
        expect(
          (await target.attendance.history(
            target.session,
            company,
            event.eventId,
          )).length,
          2,
        );
        expect(await target.count('attendance'), 1);
        final result = {
          'run': run,
          'companyId': company,
          'personId': preview.personId,
          'eventId': event.eventId,
          'archiveSha256': base64Encode(
            (await Sha256().hash(archiveBytes)).bytes,
          ),
          'transportSha256': base64Encode(
            (await Sha256().hash(receiptBytes)).bytes,
          ),
          'payloadSha256': base64Encode(
            (await Sha256().hash(receipt.payloadBytes)).bytes,
          ),
          'eventCount': 1,
          'historyCount': 2,
          'result': 'verified-after-clean-install',
          'scope':
              'host-supplied external bytes; native Files UI not exercised',
        };
        await File(
          '${root.path}/result.json',
        ).writeAsString(jsonEncode(result), flush: true);
      } finally {
        await target.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
