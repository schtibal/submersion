import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_planner/presentation/providers/dive_planner_providers.dart';
import 'package:submersion/features/planner/domain/services/plan_issue_grouping.dart';
import 'package:submersion/features/planner/domain/services/plan_issue_markers.dart';
import 'package:submersion/features/planner/presentation/providers/plan_canvas_providers.dart';

/// Where the shown plan's warnings start, for the chart to mark (#3738).
/// Taken from [activePlanOutcomeProvider], the outcome the warnings list
/// shows, so a marker and its list row always agree. Empty while the chart
/// draws the bailout picture, which is a different dive from the one the
/// warnings describe.
final planIssueMarkersProvider = Provider<List<PlanIssueMarker>>((ref) {
  if (ref.watch(chartDisplayModeProvider) == ChartDisplayMode.bailout) {
    return const [];
  }
  return planIssueMarkers(ref.watch(activePlanOutcomeProvider).issues);
});

/// The warnings-list rows picked out on the chart and in the list: a
/// marker tapped on the chart or a row tapped in the list. Empty when
/// nothing is picked. Opening another plan clears it.
final highlightedPlanIssuesProvider = StateProvider<Set<PlanIssueKey>>((ref) {
  ref.watch(divePlanNotifierProvider.select((s) => s.id));
  return const {};
});
