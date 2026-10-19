import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';

class Handle implements SessionHandle {}

class Companies implements CompanyService {
  final session = Handle();
  bool owner = true;
  int staffReads = 0;
  final all = [
    for (final id in ['a', 'b'])
      Company(
        id: id,
        name: 'Company ${id.toUpperCase()}',
        timeZoneId: 'Asia/Tokyo',
        workplaceId: 'w-$id',
        authorityGenerationId: 'g-$id',
        authoritySigningKeyId: 'key-$id',
        rootPublicKey: '',
        rootFingerprint: '123456789abcdef',
        authority: const [],
        creationPersonId: 'p',
        creationOperationId: 'op',
        creationDigest: '',
      ),
  ];
  CommandContext? savedContext;
  Completer<CommandResult<StaffRecord>>? pending;
  @override
  Future<List<Company>> listCompanies(SessionHandle s) async => all;
  @override
  Future<Membership?> membership(SessionHandle s, String c) async => Membership(
    id: 'm',
    companyId: c,
    personId: 'p',
    employeeId: 'owner',
    owner: owner,
    active: true,
    capabilities: Capability.values.toSet(),
    revision: 1,
  );
  @override
  Future<List<StaffRecord>> listStaff(SessionHandle s, String c) async {
    staffReads++;
    return [];
  }

  @override
  Future<List<Membership>> listMemberships(SessionHandle s, String c) async =>
      [];
  @override
  Future<CommandResult<StaffRecord>> createStaff(
    CommandContext context,
    StaffDraft draft,
  ) async {
    savedContext = context;
    return pending!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('personal staff grants do not show operator management actions', (
    tester,
  ) async {
    final service = Companies()..owner = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
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
    );
    await tester.pumpAndSettle();
    expect(find.text('Add staff'), findsNothing);
    expect(
      find.text('This membership has no staff management capability.'),
      findsOneWidget,
    );
    expect(service.staffReads, 0);
  });
  testWidgets(
    'company switch requires explicit keep editing or discard decision',
    (tester) async {
      final service = Companies();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
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
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add staff'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('staff-name')), 'Unsaved A');
      await tester.tap(find.byKey(const Key('company-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Company B').last);
      await tester.pumpAndSettle();
      expect(find.text('Discard this draft?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved A'), findsOneWidget);
      expect(find.text('Company A'), findsWidgets);
      await tester.tap(find.byKey(const Key('company-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Company B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard draft'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved A'), findsNothing);
      expect(find.text('Company B'), findsWidgets);
    },
  );
  testWidgets(
    'queued completion keeps its original company context and cannot populate switched company',
    (tester) async {
      final service = Companies()..pending = Completer();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
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
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add staff'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('staff-name')), 'Queued A');
      tester.testTextInput.hide();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save staff'));
      await tester.pump();
      expect(service.savedContext!.companyId, 'a');
      expect(service.savedContext!.authorityGenerationId, 'g-a');
      await tester.tap(find.byKey(const Key('company-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Company B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard draft'));
      await tester.pumpAndSettle();
      service.pending!.complete(const Rejected(CheckError.locked));
      await tester.pumpAndSettle();
      expect(find.text('Company B'), findsWidgets);
      expect(find.text('Queued A'), findsNothing);
    },
  );
}
