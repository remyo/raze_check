import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:raze_check_feature/src/guides/guide_layer.dart';
import '../../raze_check_local/test/support/two_device_fixture.dart';
import 'support/dashboard_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_feature/src/guides/company_guide_bindings.dart';
import 'package:raze_check_feature/src/guides/guide_catalog.dart';
import 'package:raze_check_feature/src/guides/guide_controller.dart';
import 'package:raze_check_feature/src/guides/guide_models.dart';
import 'package:raze_check_feature/src/guides/guide_scope.dart';
import 'company_context_test.dart' show Companies;

void main() {
  for (final owner in [false, true]) {
    testWidgets(
      'real ${owner ? "owner" : "staff"} guides navigate and explain without business writes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1100, 1500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = (await tester.runAsync(dashboardFixture))!;
        final pair = fixture.pair,
            device = owner ? fixture.pair.manager : fixture.pair.staff;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(pair.dispose);
        });
        if (!owner) {
          // Seed the existing persisted membership shape with management grants
          // while retaining a normal personal session. UI mode must still win.
          await tester.runAsync(() async {
            final member = (await device.companies.membership(
              device.session,
              pair.companyId,
            ))!;
            final updated = Membership(
              id: member.id,
              companyId: member.companyId,
              personId: member.personId,
              employeeId: member.employeeId,
              owner: false,
              active: true,
              capabilities: Capability.values
                  .where((c) => !AccessPolicy.ownerOnly.contains(c))
                  .toSet(),
              revision: member.revision + 1,
            );
            final row = StoredRecord(
              updated.id,
              pair.companyId,
              'membership',
              updated.revision,
              Uint8List.fromList(utf8.encode(jsonEncode(updated.toJson()))),
            );
            await device.storage.repo.commit(
              CommandContext(
                companyId: pair.companyId,
                session: device.session,
                operationId: 'guide-fixture-grants',
                authorityGenerationId: pair.company.authorityGenerationId,
              ),
              requestDigest: Uint8List(32),
              build: (_) async => Mutation([row], [], [], row),
            );
          });
        }
        final messages = CountedMessages(),
            companies = ObservedCompanies(device.companies);
        final attendance = ObservedAttendance(
          featureServices(device).attendance,
        );
        final controller = await mountWorkflow(
          tester,
          device,
          companies: companies,
          messages: messages,
          attendance: attendance,
        );
        final before = await tester.runAsync(
          () => businessRows(device, pair.companyId),
        );
        if (!owner) {
          expect(controller.audience.variants['review'], 'staff');
          expect(controller.audience.variants.containsKey('team'), isFalse);
          expect(controller.audience.variants['membership'], 'staff');
          expect(find.text('Invite staff'), findsNothing);
        }
        final ids = owner
            ? [
                'companies',
                'membership',
                'capture',
                'review',
                'team',
                'reports',
              ]
            : [
                'companies',
                'membership',
                'capture',
                'exchange',
                'review',
                'reports',
              ];
        for (final id in ids) {
          controller.start(id, restart: true);
          expect(controller.active?.definition.id, id);
          final destination =
              controller.active!.definition.steps.first.destination!;
          unawaited(controller.showDestination());
          await settleGuide(
            tester,
            () =>
                controller.currentContext?.destination == destination &&
                controller.active?.definition.id == id,
          );
          expect(
            find.text(
              'Step 1 of ${controller.active!.definition.steps.length}',
            ),
            findsOneWidget,
          );
          final token = controller.currentContext!.token;
          controller.next();
          controller.back();
          while (controller.active != null) {
            controller.next();
          }
          controller.start(id, restart: true);
          controller.skip();
          expect(controller.currentContext!.token, same(token));
          if (destination == GuideDestination.createCompany) {
            tester
                .widget<CompanySetupScreen>(find.byType(CompanySetupScreen))
                .onCancel();
          } else if (destination == GuideDestination.reports) {
            await tester.pageBack();
          } else if (destination == GuideDestination.team) {
            final list = tester.widget<StaffListScreen>(
              find.byType(StaffListScreen),
            );
            final oldScene = controller.currentContext!;
            list.onSelect(list.staff.first);
            await settleGuide(
              tester,
              () =>
                  controller.currentContext != null &&
                  !identical(controller.currentContext!.token, oldScene.token),
            );
            expect(find.byType(StaffDetailScreen), findsOneWidget);
            expect(controller.currentContext!.navigation, isEmpty);
            await expectLater(oldScene.validateCurrent(), throwsStateError);
            tester
                .widget<StaffDetailScreen>(find.byType(StaffDetailScreen))
                .onCancel();
            await settleGuide(
              tester,
              () => find.byType(StaffListScreen).evaluate().isNotEmpty,
            );
            await tester.tap(find.text('Overview'));
          } else {
            if (destination == GuideDestination.attendance) {
              final queue = tester.widget<ReviewQueueScreen>(
                find.byType(ReviewQueueScreen),
              );
              final queueScene = controller.currentContext!;
              if (queue.records.isNotEmpty) {
                queue.onSelect(queue.records.first);
                await settleGuide(
                  tester,
                  () =>
                      find
                          .byType(AttendanceDetailScreen)
                          .evaluate()
                          .isNotEmpty &&
                      controller.currentContext != null,
                );
                expect(
                  controller.currentContext!.token,
                  isNot(same(queueScene.token)),
                );
                await expectLater(
                  queueScene.validateCurrent(),
                  throwsStateError,
                );
              }
            }
            await tester.tap(find.text('Back to company'));
          }
          await settleGuide(
            tester,
            () =>
                controller.currentContext != null &&
                controller.currentContext!.destination == null,
          );
          await settleFeature(tester);
        }
        expect(
          await tester.runAsync(() => businessRows(device, pair.companyId)),
          before,
        );
        expect(messages.scanCalls, 0);
        expect(messages.shareCalls, 0);
        expect(companies.commandCalls, 0);
        expect(attendance.reviewCalls, 0);
        expect(attendance.importCalls, 0);
        expect(attendance.otherCalls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }

  testWidgets(
    'missing receipt and attendance selection stay explanatory; outbox changes scene',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pair = (await tester.runAsync(TwoDeviceFixture.create))!;
      await tester.runAsync(pair.enrollStaff);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(pair.dispose);
      });
      final messages = CountedMessages();
      final attendance = ObservedAttendance(
        featureServices(pair.staff).attendance,
      );
      final guides = await mountWorkflow(
        tester,
        pair.staff,
        messages: messages,
        attendance: attendance,
      );
      final before = await tester.runAsync(
        () => businessRows(pair.staff, pair.companyId),
      );
      guides.start('capture');
      unawaited(guides.showDestination());
      await settleGuide(
        tester,
        () =>
            guides.currentContext?.destination == GuideDestination.capture &&
            guides.active != null,
      );
      expect(find.text('Check in'), findsOneWidget);
      expect(find.text('Share receipt'), findsNothing);
      guides.next();
      guides.next();
      guides.next();
      await tester.pumpAndSettle();
      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('guide-highlight'))),
        Size.zero,
      );
      guides.skip();
      await tester.tap(find.text('Receipt outbox'));
      await settleGuide(
        tester,
        () =>
            guides.currentContext != null &&
            find.byType(ReceiptOutboxScreen).evaluate().isNotEmpty,
      );
      final outbox = guides.currentContext!;
      expect(find.byType(ReceiptOutboxScreen), findsOneWidget);
      await tester.tap(find.text('Back to capture'));
      await settleGuide(
        tester,
        () =>
            guides.currentContext != null &&
            !identical(guides.currentContext!.token, outbox.token),
      );
      await expectLater(outbox.validateCurrent(), throwsStateError);
      await tester.tap(find.text('Back to company'));
      await settleGuide(
        tester,
        () =>
            guides.currentContext != null &&
            guides.currentContext!.destination == null,
      );
      guides.start('review');
      unawaited(guides.showDestination());
      await settleGuide(
        tester,
        () =>
            guides.currentContext?.destination == GuideDestination.attendance &&
            guides.active != null,
      );
      expect(find.byType(AttendanceDetailScreen), findsNothing);
      guides.next();
      guides.next();
      guides.next();
      guides.skip();
      expect(
        await tester.runAsync(() => businessRows(pair.staff, pair.companyId)),
        before,
      );
      expect(messages.scanCalls, 0);
      expect(attendance.importCalls, 0);
      expect(attendance.reviewCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'restricted operator permission reload cancels late Show me and removes stale guides',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pair = (await tester.runAsync(TwoDeviceFixture.create))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(pair.dispose);
      });
      final operatorSession = (await tester.runAsync(() async {
        final staff =
            (await pair.manager.companies.createStaff(
                      pair.context('guide-operator'),
                      const StaffDraft(name: 'Guide operator'),
                    )
                    as Committed<StaffRecord>)
                .value;
        await pair.manager.companies.grantCapabilities(
          pair.context('guide-capabilities'),
          staff.membershipId,
          {Capability.manageStaff, Capability.manageMemberships},
        );
        await pair.manager.companies.activateOperator(
          pair.context('guide-credential'),
          staff.membershipId,
          'a strong operator passphrase',
        );
        return pair.manager.companies.unlockOperator(
          pair.companyId,
          staff.membershipId,
          'a strong operator passphrase',
        );
      }))!;
      final companies = ObservedCompanies(pair.manager.companies),
          messages = CountedMessages();
      final attendance = ObservedAttendance(
        featureServices(pair.manager).attendance,
      );
      final guides = await mountWorkflow(
        tester,
        pair.manager,
        session: operatorSession,
        personal: false,
        companies: companies,
        messages: messages,
        attendance: attendance,
      );
      expect(guides.audience.variants['team'], 'operator');
      expect(guides.audience.variants['membership'], 'operator');
      expect(guides.audience.variants.containsKey('companies'), isFalse);
      expect(guides.audience.variants.containsKey('capture'), isFalse);
      expect(guides.audience.variants.containsKey('review'), isFalse);
      expect(guides.audience.variants.containsKey('reports'), isFalse);
      guides.start('membership');
      unawaited(guides.showDestination());
      await settleGuide(
        tester,
        () =>
            guides.currentContext?.destination ==
                GuideDestination.joinCompany &&
            guides.active != null,
      );
      expect(find.text('Create invitation'), findsOneWidget);
      expect(find.text('Membership active'), findsNothing);
      guides.next();
      guides.back();
      guides.skip();
      final reload = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Back to company'),
          )
          .onPressed!;
      reload();
      await settleGuide(
        tester,
        () =>
            guides.currentContext != null &&
            guides.currentContext!.destination == null,
      );
      final source = guides.currentContext!;
      final member = (await tester.runAsync(
        () =>
            pair.manager.companies.membership(operatorSession, pair.companyId),
      ))!;
      final before = await tester.runAsync(
        () => businessRows(pair.manager, pair.companyId),
      );
      final hold = Completer<Membership?>();
      companies.delayed = hold;
      guides.start('team');
      final lateNavigation = guides.showDestination();
      await tester.pump();
      companies.overrideMember = Membership(
        id: member.id,
        companyId: member.companyId,
        personId: member.personId,
        employeeId: member.employeeId,
        owner: false,
        active: true,
        capabilities: {Capability.manageMemberships},
        revision: member.revision + 1,
      );
      reload();
      await settleGuide(
        tester,
        () =>
            guides.currentContext != null &&
            !identical(
              guides.currentContext!.authorityToken,
              source.authorityToken,
            ),
      );
      hold.complete(member);
      await tester.runAsync(() => lateNavigation);
      await tester.pumpAndSettle();
      expect(guides.active, isNull);
      expect(guides.audience.variants.containsKey('team'), isFalse);
      expect(find.byType(StaffListScreen), findsNothing);
      await expectLater(source.validateCurrent(), throwsStateError);
      expect(
        await tester.runAsync(() => businessRows(pair.manager, pair.companyId)),
        before,
      );
      expect(companies.commandCalls, 0);
      expect(messages.scanCalls, 0);
      expect(attendance.reviewCalls, 0);
      expect(attendance.importCalls, 0);
    },
  );

  testWidgets(
    'report validation cannot push after cancellation or steal a newer request',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pair = (await tester.runAsync(TwoDeviceFixture.create))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(pair.dispose);
      });
      final companies = ObservedCompanies(pair.manager.companies);
      final guides = await mountWorkflow(
        tester,
        pair.manager,
        companies: companies,
        messages: CountedMessages(),
        attendance: ObservedAttendance(
          featureServices(pair.manager).attendance,
        ),
      );
      final member = (await tester.runAsync(
        () => pair.manager.companies.membership(
          pair.manager.session,
          pair.companyId,
        ),
      ))!;
      for (final cancel in [
        'skip',
        'next',
        'back',
        'start',
        'pause',
        'supersede',
      ]) {
        final source = guides.currentContext!;
        final heldOld = Completer<Membership?>();
        companies.delayed = heldOld;
        companies.readsBeforeDelay = 1;
        guides.start('reports', restart: true);
        final oldNavigation = guides.showDestination();
        await settleGuide(tester, () => companies.delayed == null);
        Completer<Membership?>? heldNew;
        Future<void>? newNavigation;
        switch (cancel) {
          case 'skip':
            guides.skip();
          case 'next':
            guides.next();
          case 'back':
            guides.back();
          case 'start':
            guides.start('team');
          case 'pause':
            guides.setPaused(true);
            guides.setPaused(false);
          case 'supersede':
            heldNew = Completer<Membership?>();
            companies.delayed = heldNew;
            companies.readsBeforeDelay = 1;
            guides.start('team');
            newNavigation = guides.showDestination();
            await settleGuide(tester, () => companies.delayed == null);
        }
        heldOld.complete(member);
        await tester.pumpAndSettle();
        expect(
          find.byType(AttendanceReportScreen),
          findsNothing,
          reason: cancel,
        );
        expect(guides.currentContext!.token, same(source.token));
        if (heldNew != null) {
          heldNew.complete(member);
          await settleGuide(
            tester,
            () =>
                guides.currentContext?.destination == GuideDestination.team &&
                guides.active?.definition.id == 'team',
          );
          await newNavigation;
        }
        await oldNavigation;
      }
      expect(companies.commandCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  for (final cancel in [
    'skip',
    'next',
    'back',
    'start',
    'pause',
    'supersede',
  ]) {
    testWidgets(
      'second navigation validation retains original request: $cancel',
      (tester) async {
        final base = Companies(),
            guides = GuideController(catalog: GuideCatalog());
        final companies = ObservedCompanies(base);
        await guides.initialize();
        await tester.pumpWidget(
          MaterialApp(
            home: GuideScope(
              controller: guides,
              child: Scaffold(
                body: CompanyWorkspace(
                  companies: companies,
                  session: base.session,
                  ids: SecureIds(),
                  onAuthorizedActivity: () {},
                  onSessionChanged: (_) {},
                  onLocked: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final source = guides.currentContext!;
        final member = await base.membership(base.session, 'a');
        final heldOld = Completer<Membership?>();
        companies.delayed = heldOld;
        companies.readsBeforeDelay = 1;
        guides.start('companies');
        final oldNavigation = guides.showDestination();
        await tester.pump();
        expect(
          companies.delayed,
          isNull,
          reason: 'The second validation is awaiting the old read',
        );
        Completer<Membership?>? heldNew;
        Future<void>? newNavigation;
        switch (cancel) {
          case 'skip':
            guides.skip();
          case 'next':
            guides.next();
          case 'back':
            guides.back();
          case 'start':
            guides.start('team');
          case 'pause':
            guides.setPaused(true);
            guides.setPaused(false);
          case 'supersede':
            heldNew = Completer<Membership?>();
            companies.delayed = heldNew;
            companies.readsBeforeDelay = 1;
            guides.start('team');
            newNavigation = guides.showDestination();
            await tester.pump();
            expect(companies.delayed, isNull);
        }
        heldOld.complete(member);
        await tester.pumpAndSettle();
        expect(
          find.byType(CompanySetupScreen),
          findsNothing,
          reason: 'An obsolete request must never open its form',
        );
        expect(guides.currentContext!.token, same(source.token));
        if (heldNew != null) {
          heldNew.complete(member);
          await tester.pumpAndSettle();
          await newNavigation;
          expect(guides.active?.definition.id, 'team');
          expect(guides.currentContext!.destination, GuideDestination.team);
        }
        await oldNavigation;
        expect(companies.commandCalls, 0);
      },
    );
  }

  testWidgets(
    'late company validation cannot open destination after ordinary company switch',
    (tester) async {
      final base = Companies();
      final companies = ObservedCompanies(base);
      final guides = GuideController(catalog: GuideCatalog());
      await guides.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: GuideScope(
            controller: guides,
            child: Scaffold(
              body: CompanyWorkspace(
                companies: companies,
                session: base.session,
                ids: SecureIds(),
                onAuthorizedActivity: () {},
                onSessionChanged: (_) {},
                onLocked: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final source = guides.currentContext!;
      final member = await base.membership(base.session, 'a');
      final hold = Completer<Membership?>();
      companies.delayed = hold;
      guides.start('companies');
      final pending = guides.showDestination();
      await tester.pump();
      tester
          .widget<CompanySwitcher>(find.byType(CompanySwitcher))
          .onSelected(base.all.last);
      await tester.pumpAndSettle();
      hold.complete(member);
      await pending;
      await tester.pumpAndSettle();
      expect(find.byType(CompanySetupScreen), findsNothing);
      expect(guides.active, isNull);
      expect(
        guides.currentContext!.authorityToken,
        isNot(same(source.authorityToken)),
      );
      expect(
        tester
            .widget<CompanySwitcher>(find.byType(CompanySwitcher))
            .selected!
            .id,
        'b',
      );
      expect(companies.commandCalls, 0);
    },
  );

  testWidgets(
    'ordinary transfer choices pause then resume the exact original guide',
    (tester) async {
      final base = Companies();
      final guides = GuideController(catalog: GuideCatalog());
      await guides.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: GuideScope(
            controller: guides,
            child: GuideLayer(
              child: Scaffold(
                body: CompanyWorkspace(
                  companies: base,
                  session: base.session,
                  ids: SecureIds(),
                  onAuthorizedActivity: () {},
                  onSessionChanged: (_) {},
                  onLocked: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final source = guides.currentContext!;
      final transfer = CountingTransfer();
      final transferContext = tester.element(find.byType(CompanyWorkspace));
      final port = FeatureMessagePort(
        context: () => transferContext,
        create: (_) => transfer,
      );
      guides.start('companies');
      guides.next();
      await tester.pumpAndSettle();
      final operation = port.receiveFor({MessageKind.invitation}, () async {});
      await tester.pumpAndSettle();
      expect(guides.paused, isTrue);
      expect(find.text('Step 2 of 4'), findsNothing);
      expect(find.text('Scan QR'), findsOneWidget);
      Navigator.of(tester.element(find.text('Scan QR'))).pop();
      await tester.pumpAndSettle();
      await operation;
      await tester.pumpAndSettle();
      expect(guides.paused, isFalse);
      expect(guides.currentContext!.token, same(source.token));
      expect(guides.active?.stepIndex, 1);
      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(transfer.calls, 0);
    },
  );

  test('audiences follow existing presentation eligibility', () {
    Map<String, String> audience({
      bool unlocked = true,
      bool personal = true,
      bool owner = false,
      bool active = true,
      bool invite = false,
      bool manage = false,
      bool review = false,
      bool export = false,
    }) => companyGuideAudience(
      unlocked: unlocked,
      canCreateCompany: personal,
      owner: owner,
      operatorSession: !personal,
      activeMembership: active,
      canInvite: invite,
      canManageStaff: manage,
      canReview: review,
      canExport: export,
    ).variants;
    expect(audience(unlocked: false), {'welcome': 'public'});
    expect(audience(active: false)['companies'], 'personal');
    expect(audience(active: false).containsKey('capture'), isFalse);
    expect(audience()['review'], 'staff');
    expect(audience().containsKey('team'), isFalse);
    expect(
      audience(
        owner: true,
        invite: true,
        manage: true,
        review: true,
        export: true,
      )['capture'],
      'owner',
    );
    final restricted = audience(personal: false, manage: true);
    expect(restricted['team'], 'operator');
    expect(restricted.containsKey('review'), isFalse);
    expect(restricted.containsKey('companies'), isFalse);
    expect(restricted.containsKey('reports'), isFalse);
  });

  testWidgets(
    'personal staff stored grants do not enable operator guides; company and panel changes invalidate scenes',
    (tester) async {
      final service = Companies()..owner = false;
      final controller = GuideController(catalog: GuideCatalog());
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: GuideScope(
            controller: controller,
            child: Scaffold(
              body: CompanyWorkspace(
                companies: service,
                session: service.session,
                ids: SecureIds(),
                onAuthorizedActivity: () {},
                onSessionChanged: (_) {},
                onLocked: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.audience.variants['review'], 'staff');
      expect(controller.audience.variants.containsKey('team'), isFalse);
      final source = controller.currentContext!;
      controller.start('companies');
      final navigation = controller.showDestination();
      await tester.pumpAndSettle();
      await navigation;
      expect(find.byType(CompanySetupScreen), findsOneWidget);
      expect(controller.active?.definition.id, 'companies');
      expect(controller.currentContext!.token, isNot(same(source.token)));
      expect(
        controller.currentContext!.authorityToken,
        same(source.authorityToken),
      );
      await expectLater(source.validateCurrent(), throwsStateError);
      final setup = controller.currentContext!;
      tester
          .widget<CompanySetupScreen>(find.byType(CompanySetupScreen))
          .onCancel();
      await tester.pumpAndSettle();
      tester
          .widget<CompanySwitcher>(find.byType(CompanySwitcher))
          .onSelected(service.all.last);
      await tester.pumpAndSettle();
      expect(
        controller.currentContext!.authorityToken,
        isNot(same(setup.authorityToken)),
      );
      await expectLater(setup.validateCurrent(), throwsStateError);
      expect(controller.active, isNull);
      expect(service.staffReads, 0);
    },
  );
}

class CountedMessages implements EnrollmentMessagePort, AttendanceMessagePort {
  int scanCalls = 0, shareCalls = 0;
  @override
  Future<Uint8List?> receive() async {
    scanCalls++;
    return null;
  }

  @override
  Future<void> send(Uint8List bytes) async {
    shareCalls++;
  }
}

class ObservedCompanies implements CompanyService {
  ObservedCompanies(this.delegate);
  final CompanyService delegate;
  int commandCalls = 0;
  Completer<Membership?>? delayed;
  int readsBeforeDelay = 0;
  Membership? overrideMember;
  @override
  Future<List<Company>> listCompanies(SessionHandle session) =>
      delegate.listCompanies(session);
  @override
  Future<Membership?> membership(SessionHandle session, String company) {
    if (delayed != null && readsBeforeDelay > 0) {
      readsBeforeDelay--;
      return delegate.membership(session, company);
    }
    final hold = delayed;
    delayed = null;
    return hold?.future ??
        (overrideMember != null
            ? Future.value(overrideMember)
            : delegate.membership(session, company));
  }

  @override
  Future<List<StaffRecord>> listStaff(SessionHandle session, String company) =>
      delegate.listStaff(session, company);
  @override
  Future<List<Membership>> listMemberships(
    SessionHandle session,
    String company,
  ) => delegate.listMemberships(session, company);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    commandCalls++;
    throw StateError('Guide invoked company command: ${invocation.memberName}');
  }
}

class ObservedAttendance implements AttendanceService {
  ObservedAttendance(this.delegate);
  final AttendanceService delegate;
  int reviewCalls = 0, importCalls = 0, otherCalls = 0;
  @override
  Future<List<AttendanceSubject>> subjects(SessionHandle s, String c) =>
      delegate.subjects(s, c);
  @override
  Future<List<AttendanceRecord>> list(SessionHandle s, String c) =>
      delegate.list(s, c);
  @override
  Future<AttendanceRecord> get(SessionHandle s, String c, String e) =>
      delegate.get(s, c, e);
  @override
  Future<List<DecisionRecord>> history(SessionHandle s, String c, String e) =>
      delegate.history(s, c, e);
  @override
  Future<List<SignedMessage>> exchangeMessages(
    SessionHandle s,
    String c,
    String e,
  ) => delegate.exchangeMessages(s, c, e);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #decide) {
      reviewCalls++;
    } else if (invocation.memberName == #importReceipt) {
      importCalls++;
    } else {
      otherCalls++;
    }
    throw StateError(
      'Guide invoked attendance command: ${invocation.memberName}',
    );
  }
}

Future<List<String>> businessRows(
  EnrollmentDevice device,
  String company,
) async {
  final snapshot = await device.storage.repo.snapshot(CompanyScope(company));
  final rows =
      [
            ...snapshot.records,
            ...snapshot.events,
            ...snapshot.outbox,
            ...snapshot.authorityHistory,
            ...snapshot.recovery,
          ]
          .map(
            (r) => '${r.kind}/${r.id}/${r.revision}/${base64Encode(r.payload)}',
          )
          .toList()
        ..sort();
  rows.add(
    'operations:${snapshot.operations.length};journal:${snapshot.journal.length}',
  );
  return rows;
}

Future<GuideController> mountWorkflow(
  WidgetTester tester,
  EnrollmentDevice device, {
  SessionHandle? session,
  bool personal = true,
  ObservedCompanies? companies,
  required CountedMessages messages,
  required ObservedAttendance attendance,
}) async {
  final guides = GuideController(catalog: GuideCatalog());
  await guides.initialize();
  final services = featureServices(device);
  await tester.pumpWidget(
    MaterialApp(
      home: GuideScope(
        controller: guides,
        child: GuideLayer(
          child: Scaffold(
            body: CompanyWorkspace(
              companies: companies ?? device.companies,
              session: session ?? device.session,
              ids: SecureIds(),
              canCreateCompany: personal,
              services: services,
              host: CheckFeatureHost(onExit: () {}),
              capture: services.capture,
              enrollment: services.enrollment,
              messages: messages,
              attendance: attendance,
              attendanceMessages: messages,
              onAuthorizedActivity: () {},
              onSessionChanged: (_) {},
              onLocked: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await settleGuide(tester, () => guides.currentContext != null);
  await settleFeature(tester);
  return guides;
}

Future<void> settleGuide(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    do {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    } while ((!ready() ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
            find.byType(LinearProgressIndicator).evaluate().isNotEmpty) &&
        DateTime.now().isBefore(deadline));
  });
  await tester.pumpAndSettle();
  expect(ready(), isTrue);
}

class CountingTransfer extends TestTransfer {
  int calls = 0;
  @override
  Future<Uint8List?> scan({required Set<MessageKind> allowed}) async {
    calls++;
    return null;
  }

  @override
  Future<Uint8List?> pickMessage() async {
    calls++;
    return null;
  }

  @override
  Future<Uint8List?> decodePickedImage() async {
    calls++;
    return null;
  }
}
