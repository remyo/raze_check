import 'dart:typed_data';
import 'dart:async';
import 'guide_entry_test.dart' show mountGuides, drainGuideFuture;
import 'support/dashboard_fixture.dart' show unlockFeature, settleFeature;
import 'company_context_test.dart' show Companies;
import 'package:raze_check_feature/src/guides/guide_models.dart';
import 'package:raze_check_feature/src/guides/guide_scene.dart';
import 'package:raze_check_feature/src/host/check_feature_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_feature/src/guides/recovery_guide_bindings.dart';
import 'package:raze_check_feature/src/guides/guide_catalog.dart';
import 'package:raze_check_feature/src/guides/guide_controller.dart';
import 'package:raze_check_feature/src/guides/guide_layer.dart';
import 'package:raze_check_feature/src/guides/guide_scope.dart';

class Session implements SessionHandle {}

class Identity implements IdentityService {
  bool restricted = false;
  @override
  ActorIdentity requireActor(SessionHandle session) => ActorIdentity(
    personId: 'person',
    installationId: 'device',
    signingKeyId: 'key',
    publicKey: Uint8List(32),
    restrictedCompanyId: restricted ? 'company' : null,
  );
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Services
    implements
        BackupService,
        RestoreService,
        DeviceReplacementService,
        RecoveryIdentityService,
        EnrollmentService,
        HandoverService,
        StaffRecoveryBackupService,
        AuthorityHistoryService {
  final calls = <String>[];
  ArchiveDescriptor? existing;
  @override
  Future<HandoverOffer?> pendingOffer(
    SessionHandle session,
    String companyId,
  ) async => null;
  @override
  Future<Uint8List> shareBytes(
    SessionHandle session,
    String artifactId,
  ) async => Uint8List(1);
  @override
  String get storageDescription => 'Private storage';
  @override
  Future<ArchiveDescriptor?> last(SessionHandle session) async => existing;
  @override
  dynamic noSuchMethod(Invocation i) {
    calls.add(i.memberName.toString());
    throw StateError('Unexpected business operation');
  }
}

class DelayedCompanies extends Companies {
  Completer<Membership?>? nextRead;
  @override
  Future<Membership?> membership(SessionHandle session, String company) {
    final pending = nextRead;
    nextRead = null;
    return pending?.future ?? super.membership(session, company);
  }
}

// Exercises the shared production send/guard path without constructing a signed
// offer: the native boundary receives opaque bytes and does not verify them.
class RecoverySendHarness extends StatefulWidget {
  const RecoverySendHarness({
    super.key,
    required this.identity,
    required this.session,
    required this.files,
  });
  final IdentityService identity;
  final SessionHandle session;
  final RecoveryFiles files;
  @override
  State<RecoverySendHarness> createState() => _RecoverySendHarnessState();
}

class _RecoverySendHarnessState extends RecoveryState<RecoverySendHarness> {
  @override
  IdentityService get identity => widget.identity;
  @override
  SessionHandle get session => widget.session;
  @override
  String get recoveryVariant => 'staff-replacement';
  @override
  Widget build(BuildContext context) => frame('Recovery send', [
    button(
      'Send recovery file',
      () => send(widget.files, Uint8List(1), 'recovery.razecheck-message'),
    ),
  ]);
}

void main() {
  test(
    'recovery eligibility denies operator backup and requires both export checks',
    () {
      for (final allowed in [false, true]) {
        final audience = recoveryGuideAudience(
          restrictedOperator: true,
          owner: true,
          canExportStaffRecovery: allowed,
          recoveryVariant: 'staff-replacement',
        );
        expect(audience.variants['backup'], isNull);
        expect(
          audience.variants['new-device'],
          allowed ? 'staff-replacement' : null,
        );
        expect(
          recoveryGuideAudience(
            restrictedOperator: true,
            owner: true,
            canExportStaffRecovery: allowed,
            recoveryVariant: 'owner-source',
          ).variants['new-device'],
          isNull,
        );
      }
      expect(
        recoveryGuideAudience(
          restrictedOperator: false,
          owner: false,
          canExportStaffRecovery: false,
          recoveryVariant: 'owner-source',
        ).variants['new-device'],
        isNull,
      );
      for (final variant in [
        'staff-replacement',
        'owner-target',
        'owner-recovery',
      ]) {
        expect(
          recoveryGuideAudience(
            restrictedOperator: false,
            owner: false,
            canExportStaffRecovery: false,
            recoveryVariant: variant,
          ).variants['new-device'],
          variant,
        );
      }
      expect(
        recoveryGuideAudience(
          restrictedOperator: false,
          owner: true,
          canExportStaffRecovery: true,
          recoveryVariant: 'owner-source',
        ).variants['backup'],
        'owner',
      );
    },
  );

  test(
    'staff recovery export needs membership management and attendance export together',
    () {
      for (final management in [false, true]) {
        for (final export in [false, true]) {
          final member = Membership(
            id: 'm',
            companyId: 'a',
            personId: 'p',
            employeeId: 'e',
            owner: false,
            active: true,
            capabilities: {
              if (management) Capability.manageMemberships,
              if (export) Capability.exportAttendance,
            },
            revision: 1,
          );
          expect(recoveryExportAllowed(member), management && export);
        }
      }
    },
  );

  for (final kind in [
    'backup picker',
    'backup share',
    'recovery picker',
    'recovery share',
    'backup picker already paused',
  ]) {
    for (final leave in [false, true]) {
      testWidgets(
        'foreground $kind pauses guide until exact source returns leave=$leave',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1100, 1500));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final services = Services(),
              identity = Identity(),
              session = Session();
          services.existing = ArchiveDescriptor(
            artifactId: 'backup',
            createdUtcMs: 1,
            scope: PersonalScope('person'),
            counts: {},
          );
          final controller = GuideController(catalog: GuideCatalog());
          await controller.initialize();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
          });
          final picker = Completer<String?>(),
              bytes = Completer<Uint8List?>(),
              share = Completer<ShareOutcome>();
          final navigator = GlobalKey<NavigatorState>();
          final Widget screen = kind == 'recovery share'
              ? RecoverySendHarness(
                  identity: identity,
                  session: session,
                  files: RecoveryFiles(
                    pickBytes: (_) async => null,
                    pickArchive: (_) async => null,
                    releaseArchive: (_) async {},
                    share: (_, _, _) => share.future,
                  ),
                )
              : kind == 'recovery picker'
              ? ReplacementRequestScreen(
                  identity: identity,
                  recoveryIdentity: services,
                  session: session,
                  enrollment: services,
                  service: services,
                  restores: services,
                  files: RecoveryFiles(
                    pickBytes: (_) => bytes.future,
                    pickArchive: (_) async => null,
                    releaseArchive: (_) async {},
                    share: (_, _, _) async => ShareOutcome.dismissed,
                  ),
                )
              : BackupScreen(
                  identity: identity,
                  session: session,
                  backups: services,
                  restores: services,
                  pickArchive: (_) => picker.future,
                  releaseArchive: (_) async {},
                  shareArchive: (_, _) => share.future,
                );
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: GuideScope(
                controller: controller,
                child: GuideLayer(child: screen),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final guide = kind.startsWith('recovery') ? 'new-device' : 'backup';
          controller.start(guide);
          controller.next();
          final wasPaused = kind.endsWith('already paused');
          if (wasPaused) controller.setPaused(true);
          await tester.pumpAndSettle();
          final button = kind == 'recovery share'
              ? 'Send recovery file'
              : kind == 'recovery picker'
              ? 'Read company invitation'
              : kind == 'backup share'
              ? 'Save or share encrypted backup'
              : 'Choose backup to inspect';
          // Invoke the actual business control while the guide is active. The
          // sheet remains foreground: no app lifecycle event is synthesized.
          final control = tester.widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text(button),
              matching: find.byWidgetPredicate(
                (widget) => widget is ButtonStyleButton,
              ),
            ),
          );
          control.onPressed!();
          await tester.pump();
          final pausedDuringTransfer = controller.paused;
          if (leave) {
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other route')),
              ),
            );
            await tester.pumpAndSettle();
          }
          picker.complete(null);
          bytes.complete(null);
          share.complete(ShareOutcome.dismissed);
          await tester.pumpAndSettle();
          expect(pausedDuringTransfer, isTrue);
          expect(controller.paused, wasPaused);
          if (leave) {
            expect(controller.active, isNull);
            navigator.currentState!.pop();
            await tester.pumpAndSettle();
            expect(controller.active, isNull);
          } else {
            expect(controller.active?.definition.id, guide);
            expect(controller.active?.stepIndex, 1);
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final stale in [false, true]) {
    testWidgets(
      'failed backup scope lookup is handled only for current selection stale=$stale',
      (tester) async {
        final companies = DelayedCompanies(),
            services = Services(),
            controller = GuideController(catalog: GuideCatalog());
        await controller.initialize();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: GuideScope(
              controller: controller,
              child: GuideLayer(
                child: BackupScreen(
                  identity: Identity(),
                  session: Session(),
                  companies: companies,
                  backups: services,
                  restores: services,
                  pickArchive: (_) async => null,
                  releaseArchive: (_) async {},
                  shareArchive: (_, _) async => ShareOutcome.dismissed,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pending = Completer<Membership?>();
        companies.nextRead = pending;
        void select(String value) => tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .onChanged!(value);
        select('Company: Company A (a)');
        await tester.pumpAndSettle();
        if (stale) {
          select('Company: Company B (b)');
          await tester.pumpAndSettle();
          select('Company: Company A (a)');
          await tester.pumpAndSettle();
        }
        pending.completeError(const CheckException(CheckError.locked));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (stale) {
          expect(find.byKey(const Key('archive-error')), findsNothing);
          expect(controller.audience.variants['backup'], 'owner');
        } else {
          expect(
            find.text('Unlock your profile and try again.'),
            findsOneWidget,
          );
          expect(controller.active, isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'backup Next and Skip preserve the real passphrase and perform no transfer or attestation',
    (tester) async {
      final identity = Identity(), services = Services();
      services.existing = ArchiveDescriptor(
        artifactId: 'existing-backup',
        createdUtcMs: 1,
        scope: PersonalScope('person'),
        counts: {},
      );
      final controller = GuideController(catalog: GuideCatalog());
      await controller.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: GuideScope(
            controller: controller,
            child: GuideLayer(
              child: BackupScreen(
                identity: identity,
                session: Session(),
                backups: services,
                restores: services,
                pickArchive: (_) async {
                  services.calls.add('pick');
                  return null;
                },
                releaseArchive: (_) async {},
                shareArchive: (_, _) async {
                  services.calls.add('share');
                  return ShareOutcome.opened;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.audience.variants['backup'], 'personal');
      await tester.enterText(
        find.byKey(const Key('archive-passphrase')),
        'draft secret retained',
      );
      controller.start('backup');
      await tester.pumpAndSettle();
      controller.next();
      await tester.pumpAndSettle();
      controller.skip();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('archive-passphrase')))
            .controller!
            .text,
        'draft secret retained',
      );
      expect(services.calls, isEmpty);
      expect(services.existing?.externalCopyConfirmed, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('real restore review explains passive records without applying', (
    tester,
  ) async {
    final services = Services(),
        controller = GuideController(catalog: GuideCatalog());
    await controller.initialize();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: GuideScope(
          controller: controller,
          child: GuideLayer(
            child: RestoreReviewScreen(
              identity: Identity(),
              session: Session(),
              service: services,
              preview: const RestorePreview(
                manifestId: 'real-inspected',
                personId: 'person',
                companyIds: [],
                authorityHistory: {},
                counts: {},
                hashes: {},
                conflicts: [],
                stagingToken: 'staged',
                filesComplete: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.audience.variants['backup'], 'personal');
    controller.start('backup');
    for (var i = 0; i < 4; i++) {
      controller.next();
    }
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Passive restore grants no active membership'),
      findsOneWidget,
    );
    controller.skip();
    expect(services.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'backup actual company scope changes variant and revoked owner cancels guide',
    (tester) async {
      final companies = Companies(),
          services = Services(),
          controller = GuideController(catalog: GuideCatalog());
      await controller.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: GuideScope(
            controller: controller,
            child: GuideLayer(
              child: BackupScreen(
                identity: Identity(),
                session: Session(),
                backups: services,
                restores: services,
                companies: companies,
                pickArchive: (_) async => null,
                releaseArchive: (_) async {},
                shareArchive: (_, _) async => ShareOutcome.opened,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.start('backup');
      expect(controller.active?.definition.variantId, 'personal');
      controller.skip();
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged!('Company: Company A (a)');
      await tester.pumpAndSettle();
      expect(controller.audience.variants['backup'], 'owner');
      controller.start('backup', restart: true);
      companies.owner = false;
      await controller.showDestination();
      await controller.bind(controller.currentContext!);
      await tester.pumpAndSettle();
      expect(controller.active, isNull);
      expect(services.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'recovery selection cancels an old guide while membership validation is delayed',
    (tester) async {
      final companies = DelayedCompanies(),
          services = Services(),
          controller = GuideController(catalog: GuideCatalog());
      final session = Session();
      await controller.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      final files = RecoveryFiles(
        pickBytes: (_) async => null,
        pickArchive: (_) async => null,
        releaseArchive: (_) async {},
        share: (_, _, _) async => ShareOutcome.opened,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GuideScope(
            controller: controller,
            child: GuideLayer(
              child: RecoveryWorkspace(
                identity: Identity(),
                recoveryIdentity: services,
                session: session,
                companies: companies,
                enrollment: services,
                replacement: services,
                handover: services,
                history: services,
                backups: services,
                staffBackups: services,
                restores: services,
                files: files,
                openBackup: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButton<Company>>(find.byType(DropdownButton<Company>))
          .onChanged!(companies.all.first);
      await tester.pumpAndSettle();
      controller.start('new-device');
      final before = await companies.membership(session, 'a');
      final held = Completer<Membership?>();
      companies.nextRead = held;
      final navigation = controller.showDestination();
      await tester.pump();
      tester
          .widget<DropdownButton<Company>>(find.byType(DropdownButton<Company>))
          .onChanged!(companies.all.last);
      await tester.pumpAndSettle();
      held.complete(before);
      await navigation;
      await tester.pumpAndSettle();
      expect(controller.active, isNull);
      expect(services.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'selected owner source teaches freeze consequences without freezing or sharing',
    (tester) async {
      final companies = Companies(),
          services = Services(),
          controller = GuideController(catalog: GuideCatalog());
      await controller.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: GuideScope(
            controller: controller,
            child: GuideLayer(
              child: HandoverScreen(
                identity: Identity(),
                session: Session(),
                company: companies.all.first,
                companies: companies,
                enrollment: services,
                service: services,
                files: RecoveryFiles(
                  pickBytes: (_) async {
                    services.calls.add('pick');
                    return null;
                  },
                  pickArchive: (_) async {
                    services.calls.add('archive');
                    return null;
                  },
                  releaseArchive: (_) async {},
                  share: (_, _, _) async {
                    services.calls.add('share');
                    return ShareOutcome.opened;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.audience.variants['new-device'], 'owner-source');
      controller.start('new-device');
      controller.next();
      controller.next();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('missing acknowledgment does not cancel'),
        findsOneWidget,
      );
      controller.next();
      controller.next();
      controller.skip();
      expect(services.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final outer in [false, true]) {
    testWidgets(
      'recovery Settings returns to exact backup scene and retains host protection outer=$outer',
      (tester) async {
        await mountGuides(
          tester,
          automatic: false,
          outer: outer ? GlobalKey<NavigatorState>() : null,
        );
        await unlockFeature(tester, 'Staff');
        final original = tester.element(find.byType(CheckProfileGate));
        final controller = GuideScope.maybeOf(original)!;
        final registry = GuideScope.registryOf(original);
        final lock = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Lock'))
            .onPressed!;
        await tester.runAsync(() async {
          await tester.tap(find.text('Backup / recovery'));
          await tester.pump();
        });
        await settleFeature(tester);
        await tester.runAsync(() async {
          await tester.tap(find.text('Encrypted backup and passive restore'));
          await tester.pump();
        });
        await settleFeature(tester);
        final source = controller.currentContext!;
        expect(source.destination, GuideDestination.backup);
        final field = tester.element(
          find.byKey(const Key('archive-passphrase')),
        );
        expect(GuideScope.registryOf(field), same(registry));
        expect(FeatureRouteScope.maybeOf(field), isNotNull);
        await tester.enterText(
          find.byKey(const Key('archive-passphrase')),
          'retained real draft',
        );
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Settings'));
          await tester.pump();
        });
        await settleFeature(tester);
        await tester.tap(find.text('Help & Guides'));
        await tester.pumpAndSettle();
        controller.start('backup', restart: true);
        await tester.pumpAndSettle();
        final returned = controller.showDestination();
        await tester.pumpAndSettle();
        await drainGuideFuture(tester, returned);
        await tester.pumpAndSettle();
        expect(controller.currentContext!.token, same(source.token));
        expect(controller.active?.definition.id, 'backup');
        expect(
          GuideScene.maybeContextOf(
            tester.element(find.byKey(const Key('archive-passphrase'))),
          )!.token,
          same(source.token),
        );
        controller.skip();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('archive-passphrase')))
              .controller!
              .text,
          'retained real draft',
        );
        lock();
        await settleFeature(tester);
        expect(find.byKey(const Key('archive-passphrase')), findsNothing);
      },
    );
  }

  for (final owner in [false, true]) {
    testWidgets(
      '${owner ? 'owner target' : 'staff replacement'} guide preserves real form without business actions',
      (tester) async {
        final services = Services(), identity = Identity(), session = Session();
        final controller = GuideController(catalog: GuideCatalog());
        await controller.initialize();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        });
        final files = RecoveryFiles(
          pickBytes: (_) async {
            services.calls.add('pick');
            return null;
          },
          pickArchive: (_) async {
            services.calls.add('archive');
            return null;
          },
          releaseArchive: (_) async {},
          share: (_, _, _) async {
            services.calls.add('share');
            return ShareOutcome.opened;
          },
        );
        final Widget screen = owner
            ? RecoveryUnlockScreen(
                identity: identity,
                recoveryIdentity: services,
                session: session,
                replacement: services,
                handover: services,
                restores: services,
                files: files,
              )
            : ReplacementRequestScreen(
                identity: identity,
                recoveryIdentity: services,
                session: session,
                enrollment: services,
                service: services,
                restores: services,
                files: files,
              );
        await tester.pumpWidget(
          MaterialApp(
            home: GuideScope(
              controller: controller,
              child: GuideLayer(child: screen),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          controller.audience.variants['new-device'],
          owner ? 'owner-target' : 'staff-replacement',
        );
        await tester.enterText(
          find.byType(TextField).first,
          'original identity draft',
        );
        controller.start('new-device');
        await tester.pumpAndSettle();
        controller.next();
        controller.next();
        controller.next();
        await tester.pumpAndSettle();
        if (!owner) {
          expect(
            find.textContaining('archive before Receive replacement grant'),
            findsOneWidget,
          );
        }
        controller.next();
        controller.skip();
        await tester.pumpAndSettle();
        if (owner) {
          await tester.ensureVisible(find.text('Source device lost'));
          await tester.tap(find.text('Source device lost'));
          await tester.pumpAndSettle();
          expect(controller.audience.variants['new-device'], 'owner-recovery');
          controller.start('new-device', restart: true);
          controller.next();
          controller.next();
          await tester.pumpAndSettle();
          expect(
            find.text('Lost-source recovery requires a usable company backup.'),
            findsOneWidget,
          );
          controller.skip();
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'original identity draft',
        );
        expect(services.calls, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
