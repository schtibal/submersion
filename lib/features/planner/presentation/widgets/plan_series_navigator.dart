import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/planner/domain/entities/plan_outcome.dart';
import 'package:submersion/features/planner/domain/entities/plan_series.dart';
import 'package:submersion/features/planner/domain/utils/hours_minutes.dart';
import 'package:submersion/features/planner/presentation/providers/plan_series_providers.dart';
import 'package:submersion/features/planner/presentation/widgets/planned_dive_icon.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// The bar across the top of the dive profile that moves between the dives
/// of a repetitive series (issue #3565):
///
///               1:00               1:30
///   [(diver) A Wreck]  ~~  [(diver) B]  ~~  [(diver) C]   (+)
///
/// Each planned dive is an outlined diver, its letter and any name the diver
/// gave it; each surface interval is its time above two waves. Tapping a
/// dive selects it; + adds a dive after the last one. The selected dive can
/// be removed from its chip. A dot marks a dive with a warning. Wider than
/// the screen, the dives scroll by touch or mouse drag behind faded edges,
/// keeping the selected dive in view.
class PlanSeriesNavigator extends ConsumerStatefulWidget {
  const PlanSeriesNavigator({super.key});

  @override
  ConsumerState<PlanSeriesNavigator> createState() =>
      _PlanSeriesNavigatorState();
}

class _PlanSeriesNavigatorState extends ConsumerState<PlanSeriesNavigator> {
  final _scrollController = ScrollController();
  final _chipKeys = <String, GlobalKey>{};

  static const _fadeWidth = 16.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String diveId) =>
      _chipKeys.putIfAbsent(diveId, GlobalKey.new);

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final series = ref.read(planSeriesNotifierProvider);
      final chip = _chipKeys[series.selected.state.id]?.currentContext;
      if (chip == null) return;
      Scrollable.ensureVisible(
        chip,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _confirmRemove(int index) async {
    final l10n = context.l10n;
    final letter = seriesDiveLetter(index);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.plannerSeries_removeDive(letter)),
        content: Text(l10n.plannerSeries_removeDive_message(letter)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.common_action_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.common_action_remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(planSeriesNotifierProvider.notifier).removeDive(index);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      planSeriesNotifierProvider.select((s) => s.selected.state.id),
      (_, _) => _revealSelected(),
    );
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final series = ref.watch(planSeriesNotifierProvider);
    final results = ref.watch(planSeriesResultsProvider);
    final canAdd = ref.watch(canAddSeriesDiveProvider);
    final notifier = ref.read(planSeriesNotifierProvider.notifier);
    final selected = series.selectedIndex;

    final items = <Widget>[];
    for (var i = 0; i < series.dives.length; i++) {
      final dive = series.dives[i];
      if (i > 0) {
        items.add(
          _SurfaceIntervalMark(
            interval:
                dive.state.surfaceInterval ?? defaultSeriesSurfaceInterval,
          ),
        );
      }
      final hasIssues =
          i < results.length &&
          results[i].outcome.issues.any(
            (issue) => issue.severity != PlanIssueSeverity.info,
          );
      items.add(
        _DiveChip(
          key: _keyFor(dive.state.id),
          letter: seriesDiveLetter(i),
          name: dive.name,
          selected: i == selected,
          hasIssues: hasIssues,
          onSelected: () => notifier.select(i),
          onRemove: i == selected && series.isSeries
              ? () => _confirmRemove(i)
              : null,
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final edge = bounds.width <= 0
                  ? 0.0
                  : (_fadeWidth / bounds.width).clamp(0.0, 0.5);
              return LinearGradient(
                colors: const [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, edge, 1 - edge, 1],
              ).createShader(bounds);
            },
            child: ScrollConfiguration(
              // Desktop mice drag the bar too, not only touch.
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: _fadeWidth),
                child: Row(children: items),
              ),
            ),
          ),
        ),
        IconButton.filledTonal(
          icon: const Icon(Icons.add),
          tooltip: l10n.plannerSeries_addDive,
          onPressed: canAdd ? notifier.addDive : null,
          color: theme.colorScheme.onSecondaryContainer,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _DiveChip extends StatelessWidget {
  const _DiveChip({
    super.key,
    required this.letter,
    this.name,
    required this.selected,
    required this.hasIssues,
    required this.onSelected,
    this.onRemove,
  });

  final String letter;
  final String? name;
  final bool selected;
  final bool hasIssues;
  final VoidCallback onSelected;
  final VoidCallback? onRemove;

  /// Widest a dive's name runs on its chip before it is cut short.
  static const _maxNameWidth = 160.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final name = this.name;
    return Semantics(
      label: hasIssues ? l10n.plannerSeries_hasIssues(letter) : null,
      child: Badge(
        isLabelVisible: hasIssues,
        smallSize: 8,
        backgroundColor: theme.colorScheme.error,
        child: InputChip(
          avatar: const PlannedDiveIcon(),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                letter,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (name != null) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxNameWidth),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          tooltip: name == null
              ? l10n.plannerSeries_dive(letter)
              : l10n.plannerSeries_diveNamed(letter, name),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onSelected(),
          onDeleted: onRemove,
          deleteButtonTooltipMessage: l10n.plannerSeries_removeDive(letter),
        ),
      ),
    );
  }
}

/// The surface interval between two dives, as dive computers show it: the
/// time above the sea. A passive separator.
class _SurfaceIntervalMark extends StatelessWidget {
  const _SurfaceIntervalMark({required this.interval});

  final Duration interval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = formatHoursMinutes(interval);
    return Tooltip(
      message: context.l10n.plannerSeries_surfaceIntervalValue(time),
      excludeFromSemantics: true,
      child: Semantics(
        label: context.l10n.plannerSeries_surfaceIntervalValue(time),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              _TwoWaves(color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top two of [Icons.waves]' four lines: the surface, not the deep.
class _TwoWaves extends StatelessWidget {
  const _TwoWaves({required this.color});

  final Color color;

  static const _size = 28.0;

  @override
  Widget build(BuildContext context) {
    // The glyph's lines sit at 16-28% and 34-47% of its height; the window
    // shows 12-51%, stopping short of the third line at 52%.
    return ClipRect(
      child: Align(
        alignment: const Alignment(0, -0.6),
        heightFactor: 0.39,
        child: Icon(Icons.waves, size: _size, color: color),
      ),
    );
  }
}
