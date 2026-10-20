import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../host/check_feature_host.dart';
import 'guide_invitation.dart';
import 'guide_models.dart';
import 'guide_scene.dart';
import 'guide_scope.dart';

/// Educational eligibility for the actual recovery page, never a grant.
GuideAudience recoveryGuideAudience({
  required bool restrictedOperator,
  required bool owner,
  required bool canExportStaffRecovery,
  required String recoveryVariant,
}) => GuideAudience(
  variants: {
    'welcome': 'public',
    if (!restrictedOperator) 'backup': owner ? 'owner' : 'personal',
    if (switch (recoveryVariant) {
      'staff-replacement' => !restrictedOperator || canExportStaffRecovery,
      'owner-source' => !restrictedOperator && owner,
      'owner-target' || 'owner-recovery' => !restrictedOperator,
      _ => false,
    })
      'new-device': recoveryVariant,
  },
);

bool recoveryExportAllowed(Membership? member) =>
    member != null &&
    AccessPolicy.eligible(member, Capability.manageMemberships) &&
    AccessPolicy.eligible(member, Capability.exportAttendance);

bool sameRecoveryMembership(Membership? a, Membership? b) =>
    a?.id == b?.id &&
    a?.companyId == b?.companyId &&
    a?.personId == b?.personId &&
    a?.employeeId == b?.employeeId &&
    a?.revision == b?.revision &&
    a?.owner == b?.owner &&
    a?.active == b?.active &&
    (a == null
        ? b == null
        : b != null &&
              a.capabilities.length == b.capabilities.length &&
              a.capabilities.containsAll(b.capabilities));

/// Carries only presentation and existing host routing across sibling routes.
class RecoveryGuideRoutes extends InheritedWidget {
  const RecoveryGuideRoutes({
    super.key,
    required this.host,
    required this.openSettings,
    required super.child,
  });
  final CheckFeatureHost host;
  final void Function(BuildContext) openSettings;
  static RecoveryGuideRoutes? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RecoveryGuideRoutes>();
  @override
  bool updateShouldNotify(RecoveryGuideRoutes oldWidget) =>
      host != oldWidget.host || openSettings != oldWidget.openSettings;
}

Future<void> openRecoveryPage(BuildContext source, Widget page, String name) {
  final routes = RecoveryGuideRoutes.maybeOf(source);
  final parent = GuideSceneBinding.maybeOf(source);
  Widget child = page;
  if (parent != null) {
    child = GuideSceneBinding(
      guideContext: parent.guideContext,
      registry: parent.registry,
      child: child,
    );
  }
  if (routes != null) {
    child = RecoveryGuideRoutes(
      host: routes.host,
      openSettings: routes.openSettings,
      child: child,
    );
  }
  return (routes?.host ?? CheckFeatureHost(onExit: () {})).open(
    source,
    child,
    name,
  );
}

/// Native callbacks can stay in the foreground, so lifecycle visibility alone
/// is not a pause boundary. Keep the exact source and the existing guard.
Future<T> withRecoveryGuidePaused<T>(
  BuildContext source,
  Future<T> Function() action,
  Future<void> Function() guard,
) async {
  final guides = GuideScope.maybeOf(source);
  final original = GuideScene.maybeContextOf(source);
  final wasPaused = guides?.paused ?? false;
  guides?.setPaused(true);
  try {
    return await action();
  } finally {
    try {
      await guard();
      await original?.validateCurrent();
      if (!source.mounted ||
          (original != null &&
              (!identical(guides?.currentContext?.token, original.token) ||
                  !identical(
                    guides?.currentContext?.authorityToken,
                    original.authorityToken,
                  )))) {
        throw StateError('Native recovery source changed');
      }
    } catch (_) {
      if (original != null) {
        guides?.invalidateAuthority(original.authorityToken);
      }
    } finally {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!wasPaused &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
        guides?.setPaused(false);
      }
    }
  }
}

class RecoveryGuideSettings extends StatelessWidget {
  const RecoveryGuideSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final routes = RecoveryGuideRoutes.maybeOf(context);
    return routes == null
        ? const SizedBox.shrink()
        : IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => routes.openSettings(context),
          );
  }
}

/// Every actual page owns its scene; captured ancestors remain passive.
class RecoveryGuideScene extends StatefulWidget {
  const RecoveryGuideScene({
    super.key,
    required this.identity,
    required this.audience,
    required this.validate,
    required this.guideId,
    required this.child,
  });
  final Object identity;
  final GuideAudience audience;
  final Future<void> Function() validate;
  final String guideId;
  final Widget child;
  @override
  State<RecoveryGuideScene> createState() => _RecoveryGuideSceneState();
}

class _RecoveryGuideSceneState extends State<RecoveryGuideScene> {
  GuideContext? _parent, _scene;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = GuideScene.maybeContextOf(context);
    if (!identical(_parent, parent)) {
      _parent = parent;
      _scene = null;
    }
  }

  @override
  void didUpdateWidget(RecoveryGuideScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.audience.variants[widget.guideId] !=
            widget.audience.variants[widget.guideId]) {
      _scene = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = GuideScope.maybeOf(context);
    if (controller == null) return widget.child;
    if (_scene == null) {
      final token = Object(), identity = widget.identity, parent = _parent;
      final destination = widget.guideId == 'backup'
          ? GuideDestination.backup
          : GuideDestination.recovery;
      Future<void> validate() async {
        void check() {
          if (!mounted ||
              widget.identity != identity ||
              !identical(_scene?.token, token) ||
              !identical(_parent, parent)) {
            throw StateError('Expired recovery scene');
          }
        }

        check();
        await parent?.validateCurrent();
        await widget.validate();
        check();
      }

      _scene = GuideContext(
        token: token,
        authorityToken: Object(),
        audience: GuideAudience(
          variants: {
            'welcome': 'public',
            widget.guideId: ?widget.audience.variants[widget.guideId],
          },
        ),
        destination: destination,
        validateCurrent: validate,
        navigation: {
          destination: () => controller.navigateToScene(() {
            controller.bind(_scene!);
          }, validateCurrent: validate),
        },
      );
    }
    return GuideScene(context: _scene!, child: widget.child);
  }
}

class RecoveryGuideInvitation extends StatelessWidget {
  const RecoveryGuideInvitation({super.key, required this.guideId});
  final String guideId;
  @override
  Widget build(BuildContext context) => GuideInvitation(guideId: guideId);
}
