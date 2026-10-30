import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_planner/domain/entities/plan_segment.dart';
import 'package:submersion/features/planner/domain/entities/dive_plan.dart'
    as domain;
import 'package:submersion/features/planner/domain/entities/plan_outcome.dart';
import 'package:submersion/features/planner/domain/services/plan_engine.dart';

/// Every issue that happens at a moment in the dive carries the runtime it
/// starts at, so the chart can mark it on the profile (#3738).

const _air = GasMix(o2: 21);
const _ean32 = GasMix(o2: 32);

domain.DivePlan _plan({
  required GasMix gas,
  double depth = 40,
  int minutes = 20,
  double volume = 24,
  double startPressure = 232,
  double reservePressure = 50,
  List<DiveTank> extraTanks = const [],
}) => domain.DivePlan(
  id: 'plan-onset',
  name: 'Onset',
  gfLow: 40,
  gfHigh: 80,
  reservePressure: reservePressure,
  tanks: [
    DiveTank(
      id: 'back',
      volume: volume,
      startPressure: startPressure,
      gasMix: gas,
    ),
    ...extraTanks,
  ],
  segments: [
    PlanSegment.travel(
      id: 'down',
      fromDepth: 0,
      targetDepth: depth,
      tankId: 'back',
      gasMix: gas,
      order: 0,
      ratePerMinute: 20,
    ),
    PlanSegment.hold(
      id: 'bottom',
      depth: depth,
      durationMinutes: minutes,
      tankId: 'back',
      gasMix: gas,
      order: 1,
    ),
  ],
  createdAt: DateTime(2026, 10, 28),
  updatedAt: DateTime(2026, 10, 28),
);

PlanIssue _issue(PlanOutcome outcome, PlanIssueType type) =>
    outcome.issues.firstWhere((i) => i.type == type);

void main() {
  const engine = PlanEngine();

  test('ppO2 starts where the descent passes the working limit', () {
    // EAN32 reaches ppO2 1.4 at 33.75 m; descending at 20 m/min that is
    // 101 s into the dive, well before the 120 s descent ends.
    final outcome = engine.compute(_plan(gas: _ean32));
    final issue = _issue(outcome, PlanIssueType.ppO2High);
    expect(issue.atRuntime, closeTo(101, 2));
    // The message still names the deepest point of the leg.
    expect(issue.atDepth, 40);
  });

  test('a level leg already over the limit starts at the leg', () {
    final outcome = engine.compute(_plan(gas: _ean32));
    final onBottom = outcome.issues.where(
      (i) => i.type == PlanIssueType.ppO2High && i.segmentId == 'bottom',
    );
    expect(onBottom.single.atRuntime, 120);
  });

  test('END starts where the descent passes the END limit', () {
    // Air's END equals its depth, so the 30 m limit is passed 90 s down.
    final outcome = engine.compute(_plan(gas: _air));
    final issue = _issue(outcome, PlanIssueType.endExceeded);
    expect(issue.atRuntime, closeTo(90, 2));
  });

  test('CNS starts where the running total reaches the threshold', () {
    // EAN40 at 25 m is ppO2 1.4, about 0.67 % CNS a minute.
    final outcome = engine.compute(
      _plan(gas: const GasMix(o2: 40), depth: 25, minutes: 130),
    );
    final issue = outcome.issues.firstWhere(
      (i) =>
          i.type == PlanIssueType.cnsWarning ||
          i.type == PlanIssueType.cnsCritical,
    );
    expect(issue.atRuntime, isNotNull);
    expect(issue.atRuntime, greaterThan(0));
    expect(issue.atRuntime, lessThan(outcome.runtimeSeconds));
  });

  test('running out of gas starts before the dive ends, on its tank', () {
    final outcome = engine.compute(
      _plan(gas: _air, depth: 30, volume: 3, startPressure: 100),
    );
    final issue = _issue(outcome, PlanIssueType.gasOut);
    expect(issue.tankId, 'back');
    expect(issue.segmentId, isNull);
    expect(issue.atRuntime, isNotNull);
    expect(issue.atRuntime, lessThan(outcome.runtimeSeconds));
  });

  test('the reserve is reached before the tank would run dry', () {
    final outcome = engine.compute(
      _plan(gas: _air, depth: 30, minutes: 10, reservePressure: 200),
    );
    final issue = _issue(outcome, PlanIssueType.gasReserveViolation);
    expect(issue.tankId, 'back');
    // 232 bar down to 200 bar on a 24 L twinset takes a few minutes on
    // the bottom, not the whole dive.
    expect(issue.atRuntime, greaterThan(0));
    expect(issue.atRuntime, lessThan(outcome.runtimeSeconds));
  });

  test('a hand-set MOD over its limit starts at the switch to that gas', () {
    const back = GasMix(o2: 15, he: 55);
    const ean40 = GasMix(o2: 40);
    final plan = _plan(gas: back, depth: 70, minutes: 25).copyWith(
      tanks: const [
        DiveTank(id: 'back', volume: 24, startPressure: 232, gasMix: back),
        DiveTank(
          id: 'ean40',
          volume: 11.1,
          startPressure: 207,
          gasMix: ean40,
          decoSwitchDepth: 33,
        ),
      ],
    );
    final outcome = engine.compute(plan);
    final switchRow = outcome.schedule.firstWhere(
      (r) => r.tankId == 'ean40' && r.gasSwitch,
    );
    final issue = outcome.issues.firstWhere(
      (i) => i.type == PlanIssueType.ppO2Critical && i.atDepth == 33,
    );
    expect(issue.atRuntime, switchRow.startRuntimeSeconds);
  });

  test('a missing deco gas has no moment of its own', () {
    final outcome = engine.compute(_plan(gas: _air, depth: 45, minutes: 25));
    final issue = _issue(outcome, PlanIssueType.ndlExceededNoDecoGas);
    expect(issue.atRuntime, isNull);
  });
}
