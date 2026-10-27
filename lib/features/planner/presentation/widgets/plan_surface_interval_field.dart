import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_planner/presentation/providers/dive_planner_providers.dart';
import 'package:submersion/features/planner/domain/entities/plan_series.dart';
import 'package:submersion/features/planner/domain/utils/hours_minutes.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// The surface interval before the selected dive (issue #3565), in h:mm with
/// 15-minute steppers.
///
/// The interval is the source of truth for when the dive starts: the end
/// of the dive before it plus this.
class PlanSurfaceIntervalField extends ConsumerStatefulWidget {
  const PlanSurfaceIntervalField({super.key});

  @override
  ConsumerState<PlanSurfaceIntervalField> createState() =>
      _PlanSurfaceIntervalFieldState();
}

class _PlanSurfaceIntervalFieldState
    extends ConsumerState<PlanSurfaceIntervalField> {
  static const _step = Duration(minutes: 15);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _show(_interval);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Duration get _interval =>
      ref.read(divePlanNotifierProvider).surfaceInterval ??
      defaultSeriesSurfaceInterval;

  void _show(Duration interval) {
    final text = formatHoursMinutes(interval);
    if (_controller.text != text) _controller.text = text;
  }

  void _set(Duration interval) {
    setState(() => _invalid = false);
    _show(interval);
    if (interval != ref.read(divePlanNotifierProvider).surfaceInterval) {
      ref.read(divePlanNotifierProvider.notifier).setSurfaceInterval(interval);
    }
  }

  void _commit() {
    final parsed = parseHoursMinutes(_controller.text);
    if (parsed == null) {
      setState(() => _invalid = true);
      return;
    }
    _set(parsed);
  }

  void _stepBy(Duration delta) {
    final next = _interval + delta;
    _set(next.isNegative ? Duration.zero : next);
  }

  @override
  Widget build(BuildContext context) {
    // Follow changes made elsewhere (another dive selected, a followed
    // dive) without fighting the diver's typing.
    ref.listen(divePlanNotifierProvider.select((s) => s.surfaceInterval), (
      _,
      next,
    ) {
      if (_focusNode.hasFocus) return;
      if (_invalid) setState(() => _invalid = false);
      _show(next ?? defaultSeriesSurfaceInterval);
    });

    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const ExcludeSemantics(child: Icon(Icons.timer_outlined, size: 18)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.plannerSeries_surfaceInterval,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              tooltip: l10n.plannerSeries_surfaceInterval_decrease,
              onPressed: () => _stepBy(-_step),
            ),
            Expanded(
              child: TextField(
                key: const Key('surfaceIntervalField'),
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: 'h:mm',
                  errorText: _invalid
                      ? l10n.plannerSeries_surfaceInterval_invalid
                      : null,
                ),
                onChanged: (_) {
                  if (_invalid) setState(() => _invalid = false);
                },
                onSubmitted: (_) => _commit(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: l10n.plannerSeries_surfaceInterval_increase,
              onPressed: () => _stepBy(_step),
            ),
          ],
        ),
      ],
    );
  }
}
