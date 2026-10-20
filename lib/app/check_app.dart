import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/raze_check_feature.dart';
import 'package:raze_check_local/raze_check_local.dart';
import 'local_composition.dart';
import 'native_transfer.dart';

/// Standalone lifetime/native composition. The feature owns its protected UI.
class CheckApp extends StatefulWidget {
  const CheckApp({
    super.key,
    this.composition,
    this.identity,
    this.companies,
    this.enrollment,
    this.messages,
    this.capture,
    this.attendance,
    this.attendanceMessages,
  });
  final Future<LocalComposition>? composition;
  final Future<IdentityService>? identity;
  final Future<CompanyService>? companies;
  final Future<EnrollmentService>? enrollment;
  final EnrollmentMessagePort? messages;
  final Future<CaptureService>? capture;
  final Future<AttendanceService>? attendance;
  final AttendanceMessagePort? attendanceMessages;
  @override
  State<CheckApp> createState() => _CheckAppState();
}

class _CheckAppState extends State<CheckApp> {
  final navigator = GlobalKey<NavigatorState>();
  final documents = DocumentPort();
  final sharing = SharePort();
  late final Future<LocalComposition>? composition =
      widget.composition ??
      (widget.identity == null ? LocalComposition.open() : null);
  late final Future<Widget> entry = _entry();
  Rect anchor() {
    final box = navigator.currentContext!.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      throw const TransferException('Share position unavailable.');
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> visible(TransferGuard guard) async {
    await guard();
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      throw const TransferException('Return to Raze Check to share.');
    }
  }

  Future<Widget> _entry() async {
    final future = composition;
    if (future == null) {
      return CheckProfileGate(
        identity: await widget.identity!,
        companies: await widget.companies,
        enrollment: await widget.enrollment,
        capture: await widget.capture,
        attendance: await widget.attendance,
        messages: widget.messages,
        attendanceMessages: widget.attendanceMessages,
      );
    }
    final s = await future;
    final files = RecoveryFiles(
      pickBytes: (guard) async {
        await guard();
        final bytes = await documents.pickMessage();
        await guard();
        return bytes;
      },
      pickArchive: (guard) async {
        await guard();
        final file = await documents.pick(DocumentPurpose.archive);
        if (file == null) return null;
        try {
          await guard();
          return file.path;
        } catch (_) {
          await file.delete();
          rethrow;
        }
      },
      releaseArchive: (path) async {
        await File(path).delete();
      },
      share: (bytes, name, guard) => sharing.share(
        bytes,
        name,
        'application/octet-stream',
        guard: () => visible(guard),
        anchor: anchor,
      ),
    );
    return RazeCheckFeature(
      services: CheckServices(
        identity: s.identity,
        companies: s.companies,
        enrollment: s.enrollment,
        capture: s.capture,
        attendance: s.attendance,
        backups: s.archives,
        restores: s.archives,
        handover: s.handover,
        queries: s.queries,
        transfer: (guard) => NativeTransfer(
          context: () => navigator.currentContext!,
          guard: guard,
          documents: documents,
          qr: MobileQrPort(documents),
          sharing: sharing,
        ),
        recoveryIdentity: s.identity,
        replacement: s.replacement,
        history: s.history,
        staffBackups: s.archives,
        files: files,
        shareReport: (report, guard) => sharing.share(
          AttendanceCsv.encode(report),
          'attendance.csv',
          'text/csv',
          guard: () => visible(guard),
          anchor: anchor,
        ),
      ),
      host: CheckFeatureHost(
        guideProgress: s.guideProgress,
        guides: const GuidePresentationConfig(automaticWelcome: true),
        onExit: () => SystemNavigator.pop(),
        iconBuilder: (_) => Image.asset(
          'assets/branding/raze_check_logo_master.png',
          width: 144,
          height: 144,
          semanticLabel: 'Raze Check mascot',
        ),
      ),
    );
  }

  @override
  void dispose() {
    final future = composition;
    if (future != null) {
      unawaited(
        future.then((s) => s.close(), onError: (Object _, StackTrace _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    title: 'Raze Check',
    debugShowCheckedModeBanner: false,
    theme: CheckTheme.light(),
    darkTheme: CheckTheme.dark(),
    home: FutureBuilder<Widget>(
      future: entry,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                profileError(
                  snapshot.error is CheckException
                      ? (snapshot.error as CheckException).code
                      : CheckError.storageFailure,
                ),
              ),
            ),
          );
        }
        return snapshot.data ??
            const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    ),
  );
}
