import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'recovery_shared.dart';

class AuthorityHistoryScreen extends StatefulWidget {
  const AuthorityHistoryScreen({
    super.key,
    required this.identity,
    required this.session,
    required this.company,
    required this.service,
    required this.files,
  });
  final IdentityService identity;
  final SessionHandle session;
  final Company company;
  final AuthorityHistoryService service;
  final RecoveryFiles files;
  @override
  State<AuthorityHistoryScreen> createState() => _AuthorityHistoryState();
}

class _AuthorityHistoryState extends RecoveryState<AuthorityHistoryScreen> {
  @override
  IdentityService get identity => widget.identity;
  @override
  SessionHandle get session => widget.session;
  @override
  Widget build(BuildContext context) => frame('Public authority history', [
    Text(widget.company.name),
    SelectableText(widget.company.rootFingerprint),
    const Text(
      'A phone that missed authority changes needs the missing public certificates before it can verify current messages. Import ordered batches, then retry the original message. History files contain no recovery key, personal records, membership grant, or management activation.',
    ),
    button('Import history from Files', () async {
      final bytes = await widget.files.pickBytes(guard);
      if (bytes == null) return;
      await guard();
      await widget.service.importHistory(session, widget.company.id, bytes);
      message =
          'Verified history saved. Retry the original invitation, grant, or receipt exchange.';
    }),
    button('Export public history to Files', () async {
      final batches = await widget.service.exportHistory(
        session,
        widget.company.id,
      );
      for (var i = 0; i < batches.length; i++) {
        await send(
          widget.files,
          batches[i],
          'authority-${i + 1}.razecheck-history',
        );
      }
    }),
    const Text(
      'This phone cannot know about unseen offline changes. Conflicting branches need reconciliation. Missing historical certificates cannot be recreated from a root key alone.',
    ),
  ]);
}
