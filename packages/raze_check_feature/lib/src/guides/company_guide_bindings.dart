import 'package:flutter/widgets.dart';
import 'guide_models.dart';
import 'guide_scene.dart';
import 'guide_scope.dart';

/// Maps existing UI decisions only. These variants never grant capabilities.
GuideAudience companyGuideAudience({
  required bool unlocked,
  required bool canCreateCompany,
  required bool owner,
  required bool operatorSession,
  required bool activeMembership,
  required bool canInvite,
  required bool canManageStaff,
  required bool canReview,
  required bool canExport,
}) => GuideAudience(
  variants: {
    'welcome': 'public',
    if (unlocked) ...{
      if (canCreateCompany) 'companies': 'personal',
      if (canInvite)
        'membership': owner ? 'owner' : 'operator'
      else if (canCreateCompany)
        'membership': 'staff',
      if (activeMembership && (owner || canCreateCompany))
        'capture': owner ? 'owner' : 'staff',
      if (activeMembership && canCreateCompany && !owner) 'exchange': 'staff',
      if (canReview)
        'review': owner ? 'owner' : 'operator'
      else if (activeMembership && canCreateCompany && !owner)
        'review': 'staff',
      if (canManageStaff) 'team': owner ? 'owner' : 'operator',
      if (canExport)
        'reports': owner ? 'owner' : 'operator'
      else if (activeMembership && canCreateCompany)
        'reports': 'personal',
    },
  },
);

/// A nested workspace owns one active scene for its actual panel/selection.
/// The company parent supplies a passive context in this branch.
class CompanyGuideScene extends StatefulWidget {
  const CompanyGuideScene({
    super.key,
    required this.identity,
    required this.destination,
    required this.child,
  });
  final Object identity;
  final GuideDestination destination;
  final Widget child;
  @override
  State<CompanyGuideScene> createState() => _CompanyGuideSceneState();
}

class _CompanyGuideSceneState extends State<CompanyGuideScene> {
  GuideContext? _parent, _scene;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = GuideScene.maybeContextOf(context);
    if (!identical(parent, _parent)) {
      _parent = parent;
      _scene = null;
    }
  }

  @override
  void didUpdateWidget(CompanyGuideScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.destination != widget.destination) {
      _scene = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = _parent;
    if (parent == null || GuideScope.maybeOf(context) == null) {
      return widget.child;
    }
    if (_scene == null) {
      final identity = widget.identity, token = Object();
      _scene = GuideContext(
        token: token,
        authorityToken: parent.authorityToken,
        audience: parent.audience,
        destination: widget.destination,
        navigation: const {},
        validateCurrent: () async {
          void check() {
            if (!mounted ||
                widget.identity != identity ||
                !identical(_scene?.token, token) ||
                !identical(_parent, parent)) {
              throw StateError('Expired workflow panel');
            }
          }

          check();
          await parent.validateCurrent();
          check();
        },
      );
    }
    return GuideScene(context: _scene!, child: widget.child);
  }
}
