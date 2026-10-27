import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/planner/domain/entities/plan_outcome.dart';
import 'package:submersion/features/planner/domain/entities/plan_series.dart';
import 'package:submersion/features/planner/domain/utils/hours_minutes.dart';
import 'package:submersion/features/planner/presentation/providers/plan_series_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// The bar across the top of the dive profile that moves between the dives
/// of a repetitive series (issue #3565):
///
///   <  [Dive A] -1:00- [Dive B] -1:00- [Dive C]  >  (+)
///
/// Tapping a dive selects it; the arrows step through the dives; + adds a
/// dive after the last one. The selected dive can be removed from its chip.
/// A dot marks a dive with a warning. Wider than the screen, the dives
/// scroll by touch or mouse drag behind faded edges, keeping the selected
/// dive in view.
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
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: l10n.plannerSeries_previousDive,
          onPressed: selected > 0 ? notifier.previous : null,
        ),
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
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: l10n.plannerSeries_nextDive,
          onPressed: selected < series.dives.length - 1 ? notifier.next : null,
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
    required this.selected,
    required this.hasIssues,
    required this.onSelected,
    this.onRemove,
  });

  final String letter;
  final bool selected;
  final bool hasIssues;
  final VoidCallback onSelected;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = l10n.plannerSeries_dive(letter);
    return Semantics(
      label: hasIssues ? l10n.plannerSeries_hasIssues(letter) : null,
      child: Badge(
        isLabelVisible: hasIssues,
        smallSize: 8,
        backgroundColor: Theme.of(context).colorScheme.error,
        child: InputChip(
          label: Text(label),
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

/// The surface interval between two dives: a passive separator.
class _SurfaceIntervalMark extends StatelessWidget {
  const _SurfaceIntervalMark({required this.interval});

  final Duration interval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '— ${formatHoursMinutes(interval)} —',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}
