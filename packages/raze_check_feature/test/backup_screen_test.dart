import 'dart:typed_data';
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
}
