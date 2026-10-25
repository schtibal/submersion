import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/database/database.dart' show AppDatabase;
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/dive_equipment_card.dart';
import 'package:submersion/features/equipment/data/repositories/equipment_repository_impl.dart';
import 'package:submersion/features/equipment/domain/entities/equipment_item.dart';
import 'package:submersion/features/equipment/domain/entities/gear_link.dart';
import 'package:submersion/features/equipment/domain/models/equipment_arrangement.dart';
import 'package:submersion/features/equipment/presentation/providers/equipment_arrangement_provider.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../../helpers/mock_providers.dart';
import '../../../../../helpers/test_database.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

const _mask = EquipmentItem(
  id: 'mask',
  name: 'Cressi mask',
  type: EquipmentType.mask,
);
const _fins = EquipmentItem(id: 'fins', name: 'Jets', type: EquipmentType.fins);
const _reg = EquipmentItem(
  id: 'reg',
  name: 'Cold water reg',
  type: EquipmentType.regulator,
);

Finder get _add => find.byTooltip(_en.diveLog_detail_addEquipment);
Finder get _edit => find.byTooltip(_en.diveLog_detail_editEquipment);
Finder get _remove => find.byTooltip(_en.diveLog_edit_tooltip_removeEquipment);
Finder get _save => find.text(_en.forms_save);
Finder get _cancel => find.text(_en.forms_cancel);

void main() {
  late AppDatabase db;
  late DiveRepository repository;

  setUp(() async {
    db = await setUpTestDatabase();
    repository = DiveRepository();
    for (final gear in [_mask, _fins, _reg]) {
      await EquipmentRepository().createEquipment(gear);
    }
  });
  tearDown(tearDownTestDatabase);

  Future<Set<String>> gearOnDive() async => {
    for (final r in await (db.select(
      db.diveEquipment,
    )..where((t) => t.diveId.equals('d1'))).get())
      r.equipmentId,
  };

  Future<void> pump(
    WidgetTester tester, {
    List<EquipmentItem> gear = const [_mask, _fins],
    // False hands the card the dive as created and never refreshes it, the
    // moment between a save and the reloaded dive, held open.
    bool liveDive = true,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final created = await repository.createDive(
      Dive(id: 'd1', dateTime: DateTime(2026, 3, 28), gear: looseGear(gear)),
    );
    final base = await getBaseOverrides();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...base,
          diveRepositoryProvider.overrideWithValue(repository),
          equipmentArrangementProvider.overrideWithValue(
            EquipmentArrangement.defaults.copyWith(groupByType: false),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              // The card refreshes through the dive, as on the page.
              child: liveDive
                  ? Consumer(
                      builder: (context, ref, _) {
                        final dive = ref.watch(diveProvider('d1')).value;
                        if (dive == null) return const SizedBox.shrink();
                        return DiveEquipmentCard(dive: dive);
                      },
                    )
                  : DiveEquipmentCard(dive: created),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'after Save the removed gear never shows while the dive reloads',
    (tester) async {
      await pump(tester, liveDive: false);
      await tester.tap(_edit);
      await tester.pumpAndSettle();
      final jetsRow = find.ancestor(
        of: find.text('Jets'),
        matching: find.byType(ListTile),
      );
      await tester.tap(find.descendant(of: jetsRow, matching: _remove));
      await tester.pumpAndSettle();

      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(_save, findsNothing);
      expect(find.text('Jets'), findsNothing);
      expect(find.text('Cressi mask'), findsOneWidget);
    },
  );

  testWidgets('after a view-mode Add the new gear shows before the reload', (
    tester,
  ) async {
    await pump(tester, liveDive: false);

    await tester.tap(_add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cold water reg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.equipment_components_pickerConfirm(1)));
    await tester.pumpAndSettle();

    expect(find.text('Cold water reg'), findsOneWidget);
  });

  testWidgets('view mode shows Add and Edit beside the gear', (tester) async {
    await pump(tester);

    expect(_add, findsOneWidget);
    expect(_edit, findsOneWidget);
    expect(find.text('Jets'), findsOneWidget);
    expect(_remove, findsNothing);
  });

  testWidgets('a dive with no gear shows the card with its empty text', (
    tester,
  ) async {
    await pump(tester, gear: const []);

    expect(find.text(_en.diveLog_detail_noEquipment), findsOneWidget);
    expect(_add, findsOneWidget);
  });

  testWidgets('edit mode gives every row an X and writes nothing on Cancel', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(_edit);
    await tester.pumpAndSettle();

    expect(_edit, findsNothing);
    expect(_remove, findsNWidgets(2));
    expect(_save, findsOneWidget);

    await tester.tap(_remove.last);
    await tester.pumpAndSettle();
    expect(_remove, findsOneWidget);

    await tester.tap(_cancel);
    await tester.pumpAndSettle();

    expect(await gearOnDive(), {'mask', 'fins'});
    expect(find.text('Jets'), findsOneWidget);
    expect(find.text('Cressi mask'), findsOneWidget);
  });

  testWidgets('removing a row and saving writes the remaining gear', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(_edit);
    await tester.pumpAndSettle();

    final jetsRow = find.ancestor(
      of: find.text('Jets'),
      matching: find.byType(ListTile),
    );
    await tester.tap(find.descendant(of: jetsRow, matching: _remove));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(await gearOnDive(), {'mask'});
    expect(_save, findsNothing);
    expect(find.text('Jets'), findsNothing);
  });

  testWidgets('Add from view mode saves the picked gear straight away', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(_add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cold water reg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.equipment_components_pickerConfirm(1)));
    await tester.pumpAndSettle();

    expect(await gearOnDive(), {'mask', 'fins', 'reg'});
    expect(find.text('Cold water reg'), findsOneWidget);
  });

  testWidgets('Add in edit mode joins the draft without saving', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(_edit);
    await tester.pumpAndSettle();

    await tester.tap(_add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cold water reg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.equipment_components_pickerConfirm(1)));
    await tester.pumpAndSettle();

    expect(await gearOnDive(), {'mask', 'fins'});
    expect(find.text('Cold water reg'), findsOneWidget);

    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(await gearOnDive(), {'mask', 'fins', 'reg'});
  });
}
