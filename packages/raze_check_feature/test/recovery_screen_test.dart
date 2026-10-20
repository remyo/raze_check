@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';
import 'support/settle_review.dart';
import 'package:raze_check_feature/src/guides/guide_catalog.dart';
import 'package:raze_check_feature/src/guides/guide_controller.dart';
import 'package:raze_check_feature/src/guides/guide_layer.dart';
import 'package:raze_check_feature/src/guides/guide_scope.dart';
import 'package:raze_check_feature/src/guides/guide_target.dart';

void main() {
  testWidgets(
    'handover source exposes original owner routing data and only implemented actions',
    (tester) async {
      late TwoDeviceFixture pair;
      await tester.runAsync(() async => pair = await TwoDeviceFixture.create());
      addTearDown(pair.dispose);
      final d = pair.manager;
      final archives = LocalArchiveService(
        paths: d.storage.paths,
        keys: d.storage.keys,
        repository: d.storage.repo,
        identity: d.identity,
        clock: d.clock,
        ids: SecureIds(),
      );
      final service = LocalHandoverService(
        repository: d.storage.repo,
        identity: d.identity,
        keys: d.storage.keys,
        clock: d.clock,
        ids: SecureIds(),
        archives: archives,
      );
      final files = RecoveryFiles(
        pickBytes: (_) async => null,
        pickArchive: (_) async => null,
        releaseArchive: (_) async {},
        share: (Uint8List _, String _, TransferGuard _) async =>
            ShareOutcome.opened,
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: HandoverScreen(
              identity: d.identity,
              session: d.session,
              company: pair.company,
              enrollment: d.enrollment,
              service: service,
              files: files,
            ),
          ),
        );
      });
      await settleReview(tester);
      expect(
        find.textContaining(d.identity.requireActor(d.session).personId),
        findsOneWidget,
      );
      expect(find.textContaining(pair.company.rootFingerprint), findsOneWidget);
      expect(find.text('Read target replacement request'), findsOneWidget);
      expect(find.textContaining('same person'), findsWidgets);
      d.identity.lock();
      await tester.runAsync(() async {
        await tester.tap(find.text('Read target replacement request'));
      });
      await tester.pumpAndSettle();
      expect(find.text('Protected recovery view'), findsOneWidget);
      expect(find.textContaining(pair.company.rootFingerprint), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    },
  );
  testWidgets(
    'staff recovery screen stages consent and accepts exact fresh grant without a setup pin',
    (tester) async {
      late TwoDeviceFixture pair;
      late EnrollmentDevice target;
      await tester.runAsync(() async {
        pair = await TwoDeviceFixture.create();
        await pair.enrollStaff();
        target = await EnrollmentDevice.create(pair.manager.clock, 'Setup');
      });
      addTearDown(() async {
        await target.storage.dispose();
        await pair.dispose();
      });
      LocalDeviceReplacementService replacement(EnrollmentDevice d) =>
          LocalDeviceReplacementService(
            repository: d.storage.repo,
            identity: d.identity,
            keys: d.storage.keys,
            clock: d.clock,
            ids: SecureIds(),
          );
      final incoming = Queue<Uint8List>(), sent = <Uint8List>[];
      final files = RecoveryFiles(
        pickBytes: (_) async =>
            incoming.isEmpty ? null : incoming.removeFirst(),
        pickArchive: (_) async => null,
        releaseArchive: (_) async {},
        share: (bytes, name, guard) async {
          await guard();
          sent.add(bytes);
          return ShareOutcome.opened;
        },
      );
      late String person, employee;
      await tester.runAsync(() async {
        person = pair.staff.identity.requireActor(pair.staff.session).personId;
        employee = (await pair.staff.companies.membership(
          pair.staff.session,
          pair.companyId,
        ))!.employeeId;
        incoming.add(
          MessageCodec().encode(
            await pair.manager.enrollment.createInvitation(
              pair.context('ui-invitation'),
            ),
          ),
        );
      });
      final archives = LocalArchiveService(
        paths: target.storage.paths,
        keys: target.storage.keys,
        repository: target.storage.repo,
        identity: target.identity,
        clock: target.clock,
        ids: SecureIds(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReplacementRequestScreen(
            identity: target.identity,
            recoveryIdentity: target.identity,
            session: target.session,
            enrollment: target.enrollment,
            service: replacement(target),
            restores: archives,
            files: files,
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(() async {
          await tester.pump();
          final end = DateTime.now().add(const Duration(seconds: 30));
          while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
              DateTime.now().isBefore(end)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }
        });
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('recovery-error')), findsNothing);
      }

      Future<void> press(String text) async {
        await tester.ensureVisible(find.text(text));
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(find.text(text));
        });
        await settle();
      }

      Future<void> fill(String label, String value) async {
        final f = find.widgetWithText(TextField, label);
        await tester.ensureVisible(f);
        await tester.enterText(f, value);
      }

      await press('Read company invitation');
      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          'I compared the full root fingerprint with management',
        ),
      );
      await tester.pump();
      await press('Confirm company trust');
      await fill('Original person ID', person);
      await fill('Employee ID', employee);
      await fill('Display name', 'Staff');
      await fill('New local passphrase', 'new local passphrase');
      await fill('Confirm local passphrase', 'new local passphrase');
      await press('Create fresh replacement request');
      await press('Share replacement request');
      await tester.runAsync(() async {
        expect(
          await target.storage.repo.read(
            pair.companyId,
            'enrollment-trust:${target.identity.requireActor(target.session).personId}',
          ),
          isNull,
        );
        final grant = await replacement(pair.manager).authorize(
          pair.context('ui-replace'),
          await pair.manager.enrollment.verifyIncoming(
            pair.manager.session,
            sent.single,
          ),
        );
        incoming.add(MessageCodec().encode(grant));
      });
      await press('Receive replacement grant');
      expect(
        find.textContaining('Original identity activated for this company'),
        findsOneWidget,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(() async {
        target.session = await target.identity.unlock(
          person,
          'new local passphrase',
        );
        expect(await target.canIssueAttendance(pair.companyId), isTrue);
      });
      final current = target.identity.requireActor(target.session);
      final guides = GuideController(catalog: GuideCatalog());
      await guides.initialize();
      addTearDown(() async {
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox());
        });
        guides.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: GuideScope(
            controller: guides,
            child: GuideLayer(
              child: RecoveryUnlockScreen(
                identity: target.identity,
                recoveryIdentity: target.identity,
                session: target.session,
                replacement: replacement(target),
                handover: LocalHandoverService(
                  repository: target.storage.repo,
                  identity: target.identity,
                  keys: target.storage.keys,
                  clock: target.clock,
                  ids: SecureIds(),
                  archives: archives,
                ),
                restores: archives,
                files: files,
              ),
            ),
          ),
        ),
      );
      await press('Recover another company for this already unlocked person');
      expect(
        find.widgetWithText(TextField, 'New local passphrase'),
        findsNothing,
      );
      expect(
        find.widgetWithText(TextField, 'Original owner person ID'),
        findsOneWidget,
      );
      await fill('Company ID', SecureIds().next());
      await fill('Full company root fingerprint', pair.company.rootFingerprint);
      final ownerConsent = find.descendant(
        of: find.widgetWithText(
          CheckboxListTile,
          'I confirmed this company root and my original identity',
        ),
        matching: find.byType(Checkbox),
      );
      await tester.ensureVisible(ownerConsent);
      await tester.pumpAndSettle();
      await tester.tap(ownerConsent);
      await settle();
      expect(tester.widget<Checkbox>(ownerConsent).value, isTrue);
      await press('Prepare company recovery with current identity');
      expect(
        find.text('Share target request with source device'),
        findsOneWidget,
      );
      final sentBeforeGuide = sent.length;
      await tester.ensureVisible(find.text('Source device lost'));
      await tester.tap(find.text('Source device lost'));
      await tester.pumpAndSettle();
      guides.start('new-device', restart: true);
      guides.next();
      guides.next();
      await tester.pumpAndSettle();
      expect(guides.active?.definition.variantId, 'owner-recovery');
      expect(guides.active!.definition.steps[2].targetId, isNull);
      expect(
        find.ancestor(
          of: find.widgetWithText(
            FilledButton,
            'Share target request with source device',
          ),
          matching: find.byWidgetPredicate(
            (w) => w is GuideTarget && w.id == 'new-device-request',
          ),
        ),
        findsNothing,
      );
      expect(
        find.text('Lost-source recovery requires a usable company backup.'),
        findsOneWidget,
      );
      guides.next();
      guides.next();
      guides.next();
      await tester.pumpAndSettle();
      expect(sent.length, sentBeforeGuide);
      await tester.runAsync(() async {
        // Disposing a live continuation starts real-I/O cancellation.
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        expect(await target.storage.keys.read(current.signingKeyId), isNotNull);
        expect(await target.canIssueAttendance(pair.companyId), isTrue);
      });
    },
  );
}
