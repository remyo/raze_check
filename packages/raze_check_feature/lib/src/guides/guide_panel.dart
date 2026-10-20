import 'package:flutter/material.dart';
import 'guide_artwork.dart';
import 'guide_models.dart';

class GuidePanel extends StatefulWidget {
  const GuidePanel({
    super.key,
    required this.run,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
    this.onShowDestination,
    this.notice,
  });
  final GuideRun run;
  final String? notice;
  final VoidCallback onBack, onNext, onSkip;
  final VoidCallback? onShowDestination;
  @override
  State<GuidePanel> createState() => _GuidePanelState();
}

class _GuidePanelState extends State<GuidePanel> {
  final _nextFocus = FocusNode(debugLabel: 'Guide Next');
  final _skipFocus = FocusNode(debugLabel: 'Guide Skip');
  @override
  void dispose() {
    _nextFocus.dispose();
    _skipFocus.dispose();
    super.dispose();
  }

  Widget _order(double order, Widget child) =>
      FocusTraversalOrder(order: NumericFocusOrder(order), child: child);
  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final step = run.definition.steps[run.stepIndex];
    final counter =
        'Step ${run.stepIndex + 1} of ${run.definition.steps.length}';
    final theme = Theme.of(context);
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final header = Row(
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: counter,
            child: ExcludeSemantics(
              child: Text(counter, style: theme.textTheme.labelLarge),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _order(
          4,
          TextButton(
            focusNode: _skipFocus,
            style: buttonStyle,
            onPressed: widget.onSkip,
            child: const Text('Skip'),
          ),
        ),
      ],
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.notice != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(widget.notice!, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 12),
        ],
        GuideArtwork(guideId: run.definition.id, stepIndex: run.stepIndex),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(step.title, style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 8),
        Text(step.body, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _order(
              1,
              TextButton(
                style: buttonStyle,
                onPressed: run.stepIndex == 0 ? null : widget.onBack,
                child: const Text('Back'),
              ),
            ),
            _order(
              2,
              FilledButton(
                focusNode: _nextFocus,
                style: buttonStyle,
                onPressed: widget.onNext,
                child: Text(
                  run.stepIndex == run.definition.steps.length - 1
                      ? 'Finish'
                      : 'Next',
                ),
              ),
            ),
            if (widget.onShowDestination != null)
              _order(
                3,
                OutlinedButton(
                  style: buttonStyle,
                  onPressed: widget.onShowDestination,
                  child: const Text('Show me'),
                ),
              ),
          ],
        ),
      ],
    );
    final scrollKey = ValueKey('${run.definition.id}-${step.id}');
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // A keyboard can leave less room than the header itself needs.
              // Scroll the whole explanation in short viewports, including its
              // exit and navigation controls, instead of squeezing the body out.
              if (constraints.maxHeight < 200) {
                return SingleChildScrollView(
                  key: scrollKey,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [header, const SizedBox(height: 8), body],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    header,
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(key: scrollKey, child: body),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
