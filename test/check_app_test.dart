import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check/app/check_app.dart';
import 'package:raze_check/app/local_composition.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_local/raze_check_local.dart';
import '../packages/raze_check_feature/test/guide_entry_test.dart'
    show drainGuideFuture;
import '../packages/raze_check_local/test/support/fake_clock.dart';
import '../packages/raze_check_local/test/support/memory_key_store.dart';
import '../packages/raze_check_local/test/support/temp_paths.dart';

/// Reproduces a lifecycle lock after durable publication but before the caller
/// receives the handle. All persistence and capability checks remain real.
class LockBeforeDelivery implements IdentityService {
  LockBeforeDelivery(this.delegate);
  final IdentityService delegate;
  SessionHandle? issued;
  @override
  Future<SessionHandle> createProfile(String name, String passphrase) async {
    final session = await delegate.createProfile(name, passphrase);
    issued = session;
    delegate.lock();
    return session;
  }

  @override
  Future<List<LocalProfile>> profiles() => delegate.profiles();
  @override
  Future<SessionHandle> unlock(String personId, String passphrase) =>
      delegate.unlock(personId, passphrase);
  @override
  void lock() => delegate.lock();
  @override
  ActorIdentity requireActor(SessionHandle session) =>
      delegate.requireActor(session);
}

Future<void> settleIo(WidgetTester tester) async {
  // Each FutureBuilder layer must mount before its real filesystem I/O runs.
  for (var i = 0; i < 300; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (i > 1 &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.text('Saving…').evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  late AppPaths paths;
  testWidgets(
    'standalone composition opts into welcome before profile creation',
    (tester) async {
      final s = (await tester.runAsync(
        () => LocalComposition.open(paths: paths, secureKeys: MemoryKeyStore()),
      ))!;
      await tester.pumpWidget(CheckApp(composition: Future.value(s)));
      await settleIo(tester);
      expect(find.text('Step 1 of 5'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await settleIo(tester);
      expect(find.text('Create local profile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainGuideFuture(tester, s.close());
    },
  );
  late LocalIdentityService identity;
  setUp(() async {
    paths = await tempPaths();
    final keys = MemoryKeyStore();
    identity = LocalIdentityService(
      keys: keys,
      catalog: ProfileCatalog(paths: paths, keys: keys),
      clock: FakeClock(),
      ids: SecureIds(),
    );
  });
  tearDown(() async => paths.root.delete(recursive: true));
  testWidgets(
    'real setup selects IANA zone and activity keeps the UI idle timer aligned',
    (tester) async {
      final clock = FakeClock();
      final services = (await tester.runAsync(
        () => LocalComposition.open(
          paths: paths,
          secureKeys: MemoryKeyStore(),
          clock: clock,
        ),
      ))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(services.close);
      });
      await tester.pumpWidget(
        CheckApp(
          identity: Future.value(services.identity),
          companies: Future.value(services.companies),
        ),
      );
      await settleIo(tester);
      await tester.tap(find.text('Create local profile'));
      await settleIo(tester);
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Company owner',
      );
      await tester.enterText(
        find.byKey(const Key('profile-passphrase')),
        'a long safe passphrase',
      );
      await tester.enterText(
        find.byKey(const Key('profile-confirm')),
        'a long safe passphrase',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save profile'));
        for (
          var i = 0;
          i < 100 && (await services.identity.profiles()).isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await settleIo(tester);
      await tester.tap(find.text('Create company'));
      await settleIo(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Company name'),
        'UI company',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create company'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Select IANA time zone'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Asia/Tokyo');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Asia/Tokyo'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Create company'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Create company'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await settleIo(tester);
      expect(find.text('UI company'), findsOneWidget);
      expect(find.text('Company owner'), findsOneWidget);
      expect(find.text('Add staff'), findsOneWidget);
      clock.advance(const Duration(minutes: 4));
      await tester.pump(const Duration(minutes: 4));
      await tester.tap(find.text('Add staff'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('staff-name')),
        'Saved after activity',
      );
      tester.testTextInput.hide();
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save staff'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save staff'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await settleIo(tester);
      clock.advance(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('Saved after activity'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      clock.advance(const Duration(minutes: 3));
      await tester.pump(const Duration(minutes: 3));
      await settleIo(tester);
      expect(find.text('UI company'), findsNothing);
      expect(find.text('Unlock company operator'), findsOneWidget);
    },
  );
  testWidgets(
    'startup offers local setup and canceled draft persists no profile',
    (tester) async {
      await tester.pumpWidget(CheckApp(identity: Future.value(identity)));
      await settleIo(tester);
      expect(find.text('Raze Check'), findsOneWidget);
      await tester.tap(find.text('Create local profile'));
      await settleIo(tester);
      await tester.enterText(find.byKey(const Key('profile-name')), 'Alice');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleIo(tester);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('profile-name')))
            .controller!
            .text,
        'Alice',
      );
      await tester.tap(find.text('Cancel'));
      await settleIo(tester);
      expect(await tester.runAsync(identity.profiles), isEmpty);
      expect(find.text('Create local profile'), findsOneWidget);
    },
  );
  testWidgets('setup rejects short secret and mismatched confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(CheckApp(identity: Future.value(identity)));
    await settleIo(tester);
    await tester.tap(find.text('Create local profile'));
    await settleIo(tester);
    await tester.enterText(find.byKey(const Key('profile-name')), 'Alice');
    await tester.enterText(
      find.byKey(const Key('profile-passphrase')),
      'short',
    );
    await tester.enterText(
      find.byKey(const Key('profile-confirm')),
      'different',
    );
    await tester.tap(find.text('Save profile'));
    await settleIo(tester);
    expect(find.text('Use at least 12 characters.'), findsOneWidget);
    expect(find.text('Passphrases must match.'), findsOneWidget);
    expect(await tester.runAsync(identity.profiles), isEmpty);
  });
  testWidgets(
    'created profile reaches unlocked view and explicit lock clears it',
    (tester) async {
      await tester.pumpWidget(CheckApp(identity: Future.value(identity)));
      await settleIo(tester);
      await tester.tap(find.text('Create local profile'));
      await settleIo(tester);
      await tester.enterText(find.byKey(const Key('profile-name')), 'Alice');
      await tester.enterText(
        find.byKey(const Key('profile-passphrase')),
        'a long safe passphrase',
      );
      await tester.enterText(
        find.byKey(const Key('profile-confirm')),
        'a long safe passphrase',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save profile'));
        // Wait for the real worker-isolate KDF and catalog commit.
        for (var i = 0; i < 100 && (await identity.profiles()).isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await settleIo(tester);
      expect(find.text('Profile unlocked'), findsOneWidget);
      await tester.tap(find.text('Lock'));
      await settleIo(tester);
      expect(find.text('Profile unlocked'), findsNothing);
      expect(find.text('Unlock Alice'), findsOneWidget);
    },
  );
  testWidgets(
    'lock after publication refreshes the profile list without reporting rejected setup',
    (tester) async {
      final lockedDelivery = LockBeforeDelivery(identity);
      await tester.pumpWidget(CheckApp(identity: Future.value(lockedDelivery)));
      await settleIo(tester);
      await tester.tap(find.text('Create local profile'));
      await settleIo(tester);
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Published Alice',
      );
      await tester.enterText(
        find.byKey(const Key('profile-passphrase')),
        'a long safe passphrase',
      );
      await tester.enterText(
        find.byKey(const Key('profile-confirm')),
        'a long safe passphrase',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save profile'));
        for (var i = 0; i < 100 && lockedDelivery.issued == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await settleIo(tester);
      expect(find.text('Unlock Published Alice'), findsOneWidget);
      expect(find.text('Profile unlocked'), findsNothing);
      expect(find.byKey(const Key('profile-name')), findsNothing);
      expect(find.text('The session is locked. Unlock again.'), findsNothing);
      expect(await tester.runAsync(identity.profiles), hasLength(1));
      expect(
        () => identity.requireActor(lockedDelivery.issued!),
        throwsA(
          isA<CheckException>().having(
            (e) => e.code,
            'code',
            CheckError.locked,
          ),
        ),
      );
    },
  );
}
