import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/map_style.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/features/dive_planner/presentation/providers/dive_planner_providers.dart';
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/features/planner/presentation/pages/plan_canvas_page.dart';
import 'package:submersion/features/planner/presentation/providers/plan_series_providers.dart';
import 'package:submersion/features/planner/presentation/widgets/plan_series_navigator.dart';
import 'package:submersion/features/planner/presentation/widgets/plan_surface_interval_card.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

import '../../../helpers/mock_providers.dart';
import '../../../helpers/test_app.dart';
import '../../../helpers/test_database.dart';

class _TestSettingsNotifier extends StateNotifier<AppSettings>
    implements SettingsNotifier {
  _TestSettingsNotifier() : super(const AppSettings());

  @override
  Future<void> setMapStyle(MapStyle style) async =>
      state = state.copyWith(mapStyle: style);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The repetitive series UI on the plan canvas (issue #3565): the navigator,
/// the Surface interval card, Fill, and Save held back for a series.
void main() {
  setUp(() async {
    await setUpTestDatabase();
  });

  tearDown(() {
    DatabaseService.instance.resetForTesting();
  });

  Widget harness() => testApp(
    overrides: [
      settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
      currentDiverIdProvider.overrideWith(
        (ref) => MockCurrentDiverIdNotifier(),
      ),
    ],
    locale: const Locale('en'),
    child: const PlanCanvasPage(),
  );

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PlanCanvasPage)));

  Future<void> pumpPlan(WidgetTester tester, Size size) async {
    await setSize(tester, size);
    await tester.pumpWidget(harness());
    containerOf(tester)
        .read(divePlanNotifierProvider.notifier)
        .addSimplePlan(maxDepth: 30, bottomTimeMinutes: 20);
    await tester.pumpAndSettle();
  }

  Future<void> addDive(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add a dive'));
    await tester.pumpAndSettle();
  }

  Finder navigatorText(String text) => find.descendant(
    of: find.byType(PlanSeriesNavigator),
    matching: find.text(text),
  );

  for (final (name, size) in [
    ('desktop', const Size(1400, 900)),
    ('phone', const Size(420, 900)),
  ]) {
    group('on $name', () {
      testWidgets('a new plan shows Dive A and the add button', (tester) async {
        await pumpPlan(tester, size);
        expect(navigatorText('Dive A'), findsOneWidget);
        expect(find.byTooltip('Add a dive'), findsOneWidget);
      });

      testWidgets('+ adds Dive B after a 1:00 surface interval', (
        tester,
      ) async {
        await pumpPlan(tester, size);
        await addDive(tester);

        expect(navigatorText('Dive B'), findsOneWidget);
        expect(navigatorText('— 1:00 —'), findsOneWidget);
        final series = containerOf(tester).read(planSeriesNotifierProvider);
        expect(series.selectedIndex, 1);
      });

      testWidgets('the surface interval card shows only after Dive A', (
        tester,
      ) async {
        await pumpPlan(tester, size);
        expect(find.text('Surface interval'), findsNothing);

        await addDive(tester);
        expect(find.text('Surface interval'), findsOneWidget);

        await tester.tap(navigatorText('Dive A'));
        await tester.pumpAndSettle();
        expect(find.text('Surface interval'), findsNothing);
      });

      testWidgets('Save is held back while the plan is a series', (
        tester,
      ) async {
        await pumpPlan(tester, size);
        IconButton save() => tester.widget<IconButton>(
          find.ancestor(
            of: find.byWidgetPredicate(
              (w) =>
                  w is Icon &&
                  (w.icon == Icons.save || w.icon == Icons.save_outlined),
            ),
            matching: find.byType(IconButton),
          ),
        );
        expect(save().onPressed, isNotNull);

        await addDive(tester);
        // An edited dive, so only the series holds Save back.
        containerOf(
          tester,
        ).read(divePlanNotifierProvider.notifier).updateGradientFactors(30, 70);
        await tester.pumpAndSettle();
        expect(
          containerOf(tester).read(divePlanNotifierProvider).isDirty,
          isTrue,
        );
        expect(save().onPressed, isNull);
        expect(save().tooltip, "A series of dives can't be saved yet");
      });
    });
  }

  testWidgets('typing a surface interval sets it on the dive', (tester) async {
    await pumpPlan(tester, const Size(1400, 900));
    await addDive(tester);

    await tester.enterText(
      find.byKey(const Key('surfaceIntervalField')),
      '2:30',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final c = containerOf(tester);
    expect(
      c.read(divePlanNotifierProvider).surfaceInterval,
      const Duration(hours: 2, minutes: 30),
    );
    expect(navigatorText('— 2:30 —'), findsOneWidget);
  });

  testWidgets('an invalid surface interval is flagged, not applied', (
    tester,
  ) async {
    await pumpPlan(tester, const Size(1400, 900));
    await addDive(tester);

    await tester.enterText(
      find.byKey(const Key('surfaceIntervalField')),
      '1:75',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Enter a time as h:mm'), findsOneWidget);
    expect(
      containerOf(tester).read(divePlanNotifierProvider).surfaceInterval,
      const Duration(hours: 1),
    );
  });

  testWidgets('the steppers move the surface interval 15 minutes', (
    tester,
  ) async {
    await pumpPlan(tester, const Size(1400, 900));
    await addDive(tester);

    await tester.tap(find.byTooltip('15 minutes more'));
    await tester.pumpAndSettle();
    expect(
      containerOf(tester).read(divePlanNotifierProvider).surfaceInterval,
      const Duration(hours: 1, minutes: 15),
    );
    expect(find.byType(PlanSurfaceIntervalCard), findsOneWidget);
  });

  testWidgets('Fill all tanks refills the carried tanks', (tester) async {
    await pumpPlan(tester, const Size(1400, 900));
    final c = containerOf(tester);
    final full = c.read(divePlanNotifierProvider).tanks.first.startPressure;
    expect(find.text('Fill all tanks'), findsNothing);

    await addDive(tester);
    expect(
      c.read(divePlanNotifierProvider).tanks.first.startPressure,
      lessThan(full!),
    );
    expect(find.text('Fill all tanks'), findsOneWidget);

    await tester.tap(find.text('Fill all tanks'));
    await tester.pumpAndSettle();
    expect(c.read(divePlanNotifierProvider).tanks.first.startPressure, full);
    expect(find.text('Fill all tanks'), findsNothing);
  });

  testWidgets('a single tank fills from its own Fill button', (tester) async {
    await pumpPlan(tester, const Size(1400, 900));
    final c = containerOf(tester);
    final full = c.read(divePlanNotifierProvider).tanks.first.startPressure;
    await addDive(tester);

    final tank = c.read(divePlanNotifierProvider).tanks.first;
    await tester.tap(find.byTooltip('Fill ${tank.name ?? tank.gasMix.name}'));
    await tester.pumpAndSettle();
    expect(c.read(divePlanNotifierProvider).tanks.first.startPressure, full);
  });

  testWidgets('the selected dive is removed after confirming', (tester) async {
    await pumpPlan(tester, const Size(1400, 900));
    await addDive(tester);

    await tester.tap(find.byTooltip('Remove Dive B'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(navigatorText('Dive B'), findsNothing);
    expect(
      containerOf(tester).read(planSeriesNotifierProvider).isSeries,
      isFalse,
    );
  });

  testWidgets('the arrows step between dives', (tester) async {
    await pumpPlan(tester, const Size(1400, 900));
    await addDive(tester);
    final c = containerOf(tester);

    await tester.tap(find.byTooltip('Previous dive'));
    await tester.pumpAndSettle();
    expect(c.read(planSeriesNotifierProvider).selectedIndex, 0);

    await tester.tap(find.byTooltip('Next dive'));
    await tester.pumpAndSettle();
    expect(c.read(planSeriesNotifierProvider).selectedIndex, 1);
  });
}
