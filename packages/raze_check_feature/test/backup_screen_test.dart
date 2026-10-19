import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/src/recovery/backup_screen.dart';

class _Session implements SessionHandle {}

class _Identity implements IdentityService {
  @override
  ActorIdentity requireActor(SessionHandle session) => ActorIdentity(
    personId: 'person',
    installationId: 'installation',
    signingKeyId: 'key',
    publicKey: Uint8List(32),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backup implements BackupService {
  int calls = 0;
  @override
  String get storageDescription => 'Private app storage';
  @override
  Future<ArchiveDescriptor?> last(SessionHandle session) async => null;
  @override
  Future<ArchiveDescriptor> create(
    SessionHandle session,
    ExportScope scope,
    String pass,
  ) async {
    calls++;
    return ArchiveDescriptor(
      artifactId: 'backup',
      createdUtcMs: 1,
      scope: scope,
      counts: {},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Restore implements RestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingRestore extends _Restore {
  final result = Completer<RestoreResult>();
  bool applying = false, discarding = false, discarded = false;
  @override
  Future<RestorePreview> inspect(
    SessionHandle session,
    String path,
    String passphrase,
  ) async => const RestorePreview(
    manifestId: 'archive',
    personId: 'source-person',
    companyIds: ['company'],
    authorityHistory: {},
    counts: {},
    hashes: {},
    conflicts: [],
    stagingToken: 'staging',
    filesComplete: true,
  );
  @override
  Future<RestoreResult> apply(RestorePreview preview, RestoreChoice choice) {
    applying = true;
    return result.future;
  }

  @override
  Future<void> discard(RestorePreview preview) async {
    discarding = true;
    // The adapter's apply/discard race is covered against real SQLite; this
    // controllable boundary verifies that navigation awaits queued cleanup.
    await result.future;
    discarded = true;
  }
}

void main() {
  testWidgets(
    'requires confirmed passphrase and explains internal versus external copy',
    (tester) async {
      final backup = _Backup();
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            identity: _Identity(),
            session: _Session(),
            backups: backup,
            restores: _Restore(),
            pickArchive: (_) async => null,
            releaseArchive: (_) async {},
            shareArchive: (_, _) async => ShareOutcome.opened,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('archive-passphrase')),
        'long enough passphrase',
      );
      await tester.enterText(
        find.byKey(const Key('archive-confirm')),
        'different passphrase',
      );
      await tester.tap(find.text('Create encrypted backup'));
      await tester.pumpAndSettle();
      expect(backup.calls, 0);
      await tester.enterText(
        find.byKey(const Key('archive-confirm')),
        'long enough passphrase',
      );
      await tester.tap(find.text('Create encrypted backup'));
      await tester.pumpAndSettle();
      expect(backup.calls, 1);
      expect(find.textContaining('Created in this app'), findsOneWidget);
      expect(find.textContaining('uninstall'), findsWidgets);
    },
  );
  testWidgets(
    'leaving review during apply awaits queued discard without navigation errors',
    (tester) async {
      final restore = _PendingRestore();
      var released = false;
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            identity: _Identity(),
            session: _Session(),
            backups: _Backup(),
            restores: restore,
            pickArchive: (_) async => 'selected',
            releaseArchive: (_) async {
              released = true;
            },
            shareArchive: (_, _) async => ShareOutcome.opened,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose backup to inspect'));
      await tester.tap(find.text('Choose backup to inspect'));
      await tester.pumpAndSettle();
      expect(released, true);
      expect(find.text('Review restore'), findsOneWidget);
      await tester.ensureVisible(find.text('Restore verified records'));
      await tester.tap(find.text('Restore verified records'));
      await tester.pump();
      expect(restore.applying, true);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Backup and restore'), findsOneWidget);
      expect(restore.discarding, true);
      expect(restore.discarded, false);
      expect(tester.takeException(), isNull);
      restore.result.complete(const RestoreResult('archive', duplicate: false));
      await tester.pumpAndSettle();
      expect(restore.discarded, true);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
