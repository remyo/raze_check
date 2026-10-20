import 'dart:async';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/src/guides/guide_catalog.dart';
import 'package:raze_check_feature/src/guides/guide_controller.dart';
import 'package:raze_check_feature/src/guides/guide_models.dart';
import 'support/guide_fixture.dart';

void main() {
  for (final change in [
    'none',
    'scene',
    'authority',
    'skip',
    'start',
    'next',
    'back',
    'variant',
  ]) {
    test(
      'native pause resumes only the original bound scene: $change',
      () async {
        final c = GuideController(catalog: GuideCatalog());
        await c.initialize();
        final source = testGuideContext(
          variants: const {'companies': 'personal'},
        );
        await c.bind(source);
        c.start('companies');
        c.next();
        c.setPaused(true);
        c.invalidateScene(source.token);
        if (change == 'authority') c.invalidateAuthority(source.authorityToken);
        if (change == 'skip') c.skip();
        if (change == 'start') c.start('companies', restart: true);
        if (change == 'next') c.next();
        if (change == 'back') c.back();
        c.setPaused(false);
        await c.bind(
          change == 'variant'
              ? testGuideContext(
                  token: source.token,
                  authorityToken: source.authorityToken,
                  variants: const {'welcome': 'public'},
                )
              : change == 'scene'
              ? testGuideContext(
                  authorityToken: source.authorityToken,
                  variants: const {'companies': 'personal'},
                )
              : source,
        );
        if (change == 'none') {
          expect(c.active?.stepIndex, 1);
          expect(c.active?.contextToken, same(source.token));
        } else {
          expect(c.active, isNull);
        }
      },
    );
  }

  for (final cancel in [false, true]) {
    test(
      'synchronous panel handoff waits for validated bind or cancellation: $cancel',
      () async {
        final c = GuideController(catalog: GuideCatalog());
        await c.initialize();
        final authority = Object(), validation = Completer<void>();
        var opened = false, finished = false;
        final destination = testGuideContext(
          authorityToken: authority,
          destination: GuideDestination.createCompany,
          variants: const {'companies': 'personal'},
          validateCurrent: () => validation.future,
        );
        await c.bind(
          testGuideContext(
            authorityToken: authority,
            variants: const {'companies': 'personal'},
            navigation: {
              GuideDestination.createCompany: () => c.navigateToScene(() {
                opened = true;
              }),
            },
          ),
        );
        c.start('companies');
        final request = c.showDestination().then((_) => finished = true);
        await Future<void>.delayed(Duration.zero);
        expect(opened, isTrue);
        expect(finished, isFalse);
        final binding = c.bind(destination);
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        if (cancel) c.skip();
        validation.complete();
        await binding;
        await request;
        expect(c.active?.definition.id, cancel ? isNull : 'companies');
        if (!cancel) expect(c.active!.contextToken, same(destination.token));
      },
    );
  }

  for (final interruption in [
    'none',
    'unrelated',
    'authority',
    'next',
    'skip',
    'start',
    'pause',
    'lock',
  ]) {
    test(
      'controlled origin return preserves only its captured authority: $interruption',
      () async {
        final c = GuideController(catalog: GuideCatalog());
        await c.initialize();
        final authority = Object(),
            origin = Object(),
            returning = Completer<void>();
        var calls = 0;
        await c.bind(
          GuideContext(
            token: Object(),
            authorityToken: authority,
            audience: GuideAudience(
              variants: const {'companies': 'personal', 'welcome': 'public'},
            ),
            validateCurrent: () async {},
            originReturn: GuideOriginReturn(
              token: origin,
              returnToOrigin: () => returning.future,
            ),
            navigation: {
              GuideDestination.createCompany: () async {
                calls++;
                await c.bind(
                  testGuideContext(
                    authorityToken: authority,
                    destination: GuideDestination.createCompany,
                    variants: const {'companies': 'personal'},
                  ),
                );
              },
            },
          ),
        );
        c.start('companies');
        final request = c.showDestination();
        await Future<void>.delayed(Duration.zero);
        await c.bind(
          testGuideContext(
            token: interruption == 'unrelated' ? Object() : origin,
            authorityToken: interruption == 'authority' ? Object() : authority,
            variants: const {'companies': 'personal', 'welcome': 'public'},
          ),
        );
        switch (interruption) {
          case 'next':
            c.next();
          case 'skip':
            c.skip();
          case 'start':
            c.start('welcome');
          case 'pause':
            c.setPaused(true);
            c.setPaused(false);
          case 'lock':
            c.invalidateAuthority(authority);
        }
        returning.complete();
        await request;
        expect(calls, interruption == 'none' ? 1 : 0);
        if (interruption == 'none') {
          expect(c.active?.definition.id, 'companies');
          expect(c.active?.stepIndex, 0);
        } else if (interruption != 'start') {
          expect(c.active, isNull);
        }
        await c.flush();
        c.dispose();
      },
    );
  }
  for (final action in ['skip', 'start', 'next', 'back', 'pause']) {
    test('Show me validation is canceled by $action', () async {
      var validations = 0, calls = 0;
      final gate = Completer<void>();
      final c = GuideController(catalog: GuideCatalog());
      await c.initialize();
      await c.bind(
        testGuideContext(
          variants: const {'companies': 'personal', 'welcome': 'public'},
          validateCurrent: () async {
            if (++validations > 1) await gate.future;
          },
          navigation: {
            GuideDestination.createCompany: () async {
              calls++;
            },
          },
        ),
      );
      c.start('companies');
      final navigation = c.showDestination();
      switch (action) {
        case 'skip':
          c.skip();
        case 'start':
          c.start('welcome');
        case 'next':
          c.next();
        case 'back':
          c.back();
        case 'pause':
          c.setPaused(true);
          c.setPaused(false);
      }
      gate.complete();
      await navigation;
      expect(calls, 0);
    });
  }
  for (final action in ['next', 'back', 'skip', 'start', 'pause']) {
    test('pending Show me position is canceled by $action', () async {
      final gate = Completer<void>(), authority = Object();
      final c = GuideController(catalog: GuideCatalog());
      await c.initialize();
      await c.bind(
        testGuideContext(
          authorityToken: authority,
          variants: const {'companies': 'personal', 'welcome': 'public'},
          navigation: {GuideDestination.createCompany: () => gate.future},
        ),
      );
      c.start('companies');
      final navigation = c.showDestination();
      await Future<void>.delayed(Duration.zero);
      switch (action) {
        case 'next':
          c.next();
        case 'back':
          c.back();
        case 'skip':
          c.skip();
        case 'start':
          c.start('welcome');
        case 'pause':
          c.setPaused(true);
          c.setPaused(false);
      }
      await c.bind(
        testGuideContext(
          authorityToken: authority,
          destination: GuideDestination.createCompany,
          variants: const {'companies': 'personal'},
        ),
      );
      expect(c.active, isNull);
      gate.complete();
      await navigation;
      expect(c.active, isNull);
    });
  }

  test('invitation dismissal suppresses another permitted variant', () async {
    final c = GuideController(catalog: GuideCatalog());
    await c.initialize();
    await c.bind(testGuideContext(variants: const {'review': 'staff'}));
    c.dismissInvitation('review');
    await c.bind(testGuideContext(variants: const {'review': 'owner'}));
    expect(c.shouldInvite('review'), false);
  });
  test('disposed scene rejects pending bind validation', () async {
    final delayed = Completer<void>(), token = Object();
    final c = GuideController(catalog: GuideCatalog());
    await c.initialize();
    final binding = c.bind(
      testGuideContext(token: token, validateCurrent: () => delayed.future),
    );
    c.invalidateScene(token);
    delayed.complete();
    await binding;
    c.start('welcome');
    expect(c.active, isNull);
  });

  test(
    'resume by stable ID, removed step explains restart, dismissal survives revision',
    () async {
      final store = MemoryGuideProgressStore(
        snapshot: GuideProgressSnapshot(
          welcomeDismissed: true,
          entries: [
            const GuideProgress(
              guideId: 'welcome',
              variantId: 'public',
              contentRevision: 99,
              stepId: 'welcome-receipts',
            ),
            const GuideProgress(
              guideId: 'companies',
              variantId: 'personal',
              contentRevision: 1,
              stepId: 'removed',
            ),
            const GuideProgress(
              guideId: 'unknown',
              variantId: 'public',
              contentRevision: 1,
            ),
          ],
        ),
      );
      final c = GuideController(catalog: GuideCatalog(), store: store);
      await c.initialize();
      await c.bind(
        testGuideContext(
          variants: const {'welcome': 'public', 'companies': 'personal'},
        ),
      );
      expect(c.progress.entries.length, 2);
      c.start('welcome');
      expect(c.active!.stepIndex, 2);
      expect(c.progress.welcomeDismissed, true);
      c.start('companies');
      expect(c.active!.stepIndex, 0);
      expect(c.notice, contains('changed'));
      c.dismissInvitation('companies');
      expect(c.shouldInvite('companies'), false);
      await c.flush();
      expect(store.writes, 3);
    },
  );
  test('completion is Viewed and controls never navigate', () async {
    var calls = 0;
    final c = GuideController(catalog: GuideCatalog());
    await c.initialize();
    await c.bind(
      testGuideContext(
        navigation: {
          GuideDestination.createCompany: () async {
            calls++;
          },
        },
      ),
    );
    c.start('welcome');
    for (var i = 0; i < 5; i++) {
      c.next();
    }
    expect(c.active, isNull);
    expect(c.notice, 'Viewed');
    expect(c.progress.entries.single.viewed, true);
    expect(c.progress.welcomeDismissed, true);
    expect(calls, 0);
  });
  test('write failure keeps ordered in-memory progress', () async {
    final store = MemoryGuideProgressStore(failWrite: true);
    final c = GuideController(catalog: GuideCatalog(), store: store);
    await c.initialize();
    await c.bind(testGuideContext());
    c.start('welcome');
    c.next();
    c.next();
    await c.flush();
    expect(c.persistenceFailed, true);
    expect(c.progress.entries.single.stepId, 'welcome-receipts');
  });
  test('stale bind validation never restores old scene', () async {
    final delayed = Completer<void>();
    final c = GuideController(catalog: GuideCatalog());
    await c.initialize();
    final old = c.bind(testGuideContext(validateCurrent: () => delayed.future));
    final token = Object();
    await c.bind(testGuideContext(token: token));
    delayed.complete();
    await old;
    c.start('welcome');
    expect(c.active!.contextToken, same(token));
  });
  for (final wrongAuthority in [false, true]) {
    test(
      'mismatched destination or authority cancels pending intent $wrongAuthority',
      () async {
        final authority = Object(), done = Completer<void>();
        final token = Object();
        final c = GuideController(catalog: GuideCatalog());
        await c.initialize();
        await c.bind(
          testGuideContext(
            token: token,
            authorityToken: authority,
            variants: const {'companies': 'personal'},
            navigation: {GuideDestination.createCompany: () => done.future},
          ),
        );
        c.start('companies');
        final pending = c.showDestination();
        await Future<void>.delayed(Duration.zero);
        c.invalidateScene(token);
        await c.bind(
          testGuideContext(
            authorityToken: wrongAuthority ? Object() : authority,
            destination: wrongAuthority
                ? GuideDestination.createCompany
                : GuideDestination.team,
            variants: const {'companies': 'personal'},
          ),
        );
        expect(c.active, isNull);
        done.complete();
        await pending;
        expect(c.active, isNull);
      },
    );
  }

  test('skip retains position and welcome dismissal', () async {
    final c = GuideController(catalog: GuideCatalog());
    await c.initialize();
    await c.bind(testGuideContext());
    c.start('welcome');
    c.next();
    c.skip();
    expect(c.progress.welcomeDismissed, true);
    c.start('welcome');
    expect(c.active!.stepIndex, 1);
    expect(c.sessionOnly, true);
  });
  test(
    'navigation handshake resumes only matching authority and destination',
    () async {
      final authority = Object(), done = Completer<void>();
      var calls = 0;
      final c = GuideController(catalog: GuideCatalog());
      await c.initialize();
      await c.bind(
        testGuideContext(
          authorityToken: authority,
          variants: const {'companies': 'personal'},
          navigation: {
            GuideDestination.createCompany: () {
              calls++;
              return done.future;
            },
          },
        ),
      );
      c.start('companies');
      c.next();
      c.back();
      expect(calls, 0);
      final pending = c.showDestination();
      await Future<void>.delayed(Duration.zero);
      await c.bind(
        testGuideContext(
          authorityToken: authority,
          destination: GuideDestination.createCompany,
          variants: const {'companies': 'personal'},
        ),
      );
      expect(c.active?.stepIndex, 0);
      c.invalidateAuthority(authority);
      done.complete();
      await pending;
      expect(c.active, isNull);
    },
  );
  test('read and write failures retain memory progress', () async {
    final c = GuideController(
      catalog: GuideCatalog(),
      store: MemoryGuideProgressStore(failRead: true),
    );
    await c.initialize();
    await c.bind(testGuideContext());
    c.start('welcome');
    c.next();
    await c.flush();
    expect(c.persistenceFailed, true);
    expect(c.active!.stepIndex, 1);
  });
}
