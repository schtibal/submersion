import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/features/buddies/data/repositories/buddy_repository.dart';
import 'package:submersion/features/buddies/domain/entities/buddy.dart';
import 'package:submersion/features/buddies/presentation/providers/buddy_providers.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/dive_buddies_card.dart';
import 'package:submersion/features/dive_roles/domain/entities/dive_role.dart';
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../../helpers/mock_providers.dart';
import '../../../../../helpers/role_sheet.dart';
import '../../../../../helpers/test_database.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));
final _now = DateTime(2026, 1, 1);

final _alice = Buddy(id: 'b1', name: 'Alice', createdAt: _now, updatedAt: _now);
final _bob = Buddy(id: 'b2', name: 'Bob', createdAt: _now, updatedAt: _now);

class _RecordingBuddyRepository extends Fake implements BuddyRepository {
  final saved = <List<BuddyWithRole>>[];

  @override
  Future<void> setBuddiesForDive(
    String diveId,
    List<BuddyWithRole> buddies,
  ) async => saved.add(buddies);
}

class _RecordingDiveRepository extends Fake implements DiveRepository {
  final savedRoles = <List<String>>[];

  @override
  Future<void> setDiverRoles(String diveId, List<String> roleIds) async =>
      savedRoles.add(roleIds);
}

Future<void> _pump(
  WidgetTester tester, {
  required _RecordingBuddyRepository buddies,
  required _RecordingDiveRepository dives,
  required MockCurrentDiverIdNotifier diverIdNotifier,
  List<BuddyWithRole>? linked,
  List<String> diverRoleIds = const [DiveRole.diveGuideId],
}) async {
  tester.view.physicalSize = const Size(640, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final dive = Dive(
    id: 'd1',
    dateTime: DateTime(2026, 3, 15),
    diverRoleIds: diverRoleIds,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentDiverIdProvider.overrideWith((ref) => diverIdNotifier),
        validatedCurrentDiverIdProvider.overrideWith((ref) async => 'diver-1'),
        buddyRepositoryProvider.overrideWithValue(buddies),
        diveRepositoryProvider.overrideWithValue(dives),
        buddiesForDiveProvider('d1').overrideWith(
          (ref) async =>
              linked ??
              [
                BuddyWithRole(buddy: _alice, roles: [DiveRole.builtInBuddy()]),
              ],
        ),
        allBuddiesWithDiveCountProvider.overrideWith(
          (ref) async => [
            BuddyWithDiveCount(buddy: _alice, diveCount: 3),
            BuddyWithDiveCount(buddy: _bob, diveCount: 1),
          ],
        ),
        buddySearchWithDiveCountProvider.overrideWith((ref, q) async => []),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: DiveBuddiesCard(dive: dive)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _add => find.byTooltip(_en.diveLog_detail_addBuddy);
Finder get _edit => find.byTooltip(_en.diveLog_detail_editBuddies);
Finder get _changeRole => find.byTooltip(_en.diveLog_detail_changeRole);
Finder get _remove => find.byTooltip(_en.diveLog_detail_removeBuddy);
Finder get _save => find.text(_en.forms_save);
Finder get _cancel => find.text(_en.forms_cancel);

void main() {
  late _RecordingBuddyRepository buddies;
  late _RecordingDiveRepository dives;
  late MockCurrentDiverIdNotifier diverIdNotifier;

  setUp(() async {
    await setUpTestDatabase();
    await DatabaseService.instance.database.customStatement(
      "INSERT INTO divers (id, name, created_at, updated_at) "
      "VALUES ('diver-1', 'Test Diver', 1000, 1000)",
    );
    diverIdNotifier = MockCurrentDiverIdNotifier();
    await diverIdNotifier.setCurrentDiver('diver-1');
    buddies = _RecordingBuddyRepository();
    dives = _RecordingDiveRepository();
  });

  tearDown(tearDownTestDatabase);

  Future<void> pump(
    WidgetTester tester, {
    List<BuddyWithRole>? linked,
    List<String> diverRoleIds = const [DiveRole.diveGuideId],
  }) => _pump(
    tester,
    buddies: buddies,
    dives: dives,
    diverIdNotifier: diverIdNotifier,
    linked: linked,
    diverRoleIds: diverRoleIds,
  );

  Future<void> enterEdit(WidgetTester tester) async {
    await tester.tap(_edit);
    await tester.pumpAndSettle();
  }

  testWidgets('view mode shows Add and Edit beside the buddies', (
    tester,
  ) async {
    await pump(tester);

    expect(_add, findsOneWidget);
    expect(_edit, findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text(_en.buddies_picker_me), findsOneWidget);
    expect(_remove, findsNothing);
  });

  testWidgets('edit mode: a pencil on every row, an X on all but Me', (
    tester,
  ) async {
    await pump(tester);
    await enterEdit(tester);

    expect(_edit, findsNothing);
    expect(_cancel, findsOneWidget);
    expect(_save, findsOneWidget);
    expect(_changeRole, findsNWidgets(2));
    expect(_remove, findsOneWidget);
    // The X sits on Alice's row, not on Me's.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(ListTile),
        ),
        matching: _remove,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text(_en.buddies_picker_me),
          matching: find.byType(ListTile),
        ),
        matching: _remove,
      ),
      findsNothing,
    );
  });

  testWidgets('edit mode offers Me even when the dive has no role of mine', (
    tester,
  ) async {
    await pump(tester, diverRoleIds: const []);
    expect(find.text(_en.buddies_picker_me), findsNothing);

    await enterEdit(tester);

    expect(find.text(_en.buddies_picker_me), findsOneWidget);
    expect(find.text(_en.buddies_picker_setMyRole), findsOneWidget);
  });

  testWidgets('removing a buddy and cancelling writes nothing', (tester) async {
    await pump(tester);
    await enterEdit(tester);

    await tester.tap(_remove);
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);

    await tester.tap(_cancel);
    await tester.pumpAndSettle();

    expect(buddies.saved, isEmpty);
    expect(dives.savedRoles, isEmpty);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('removing a buddy and saving writes only the buddy list', (
    tester,
  ) async {
    await pump(
      tester,
      linked: [
        BuddyWithRole(buddy: _alice, roles: [DiveRole.builtInBuddy()]),
        BuddyWithRole(buddy: _bob, roles: [DiveRole.builtInBuddy()]),
      ],
    );
    await enterEdit(tester);

    await tester.tap(_remove.first);
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(buddies.saved.single.map((b) => b.buddy.id), ['b2']);
    expect(dives.savedRoles, isEmpty);
    expect(_save, findsNothing);
  });

  testWidgets("the pencil changes a buddy's role in the draft", (tester) async {
    await pump(tester);
    await enterEdit(tester);

    await tester.tap(_changeRole.last);
    await tester.pumpAndSettle();
    await pickOnlyRole(tester, 'Instructor');

    expect(buddies.saved, isEmpty);
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(buddies.saved.single.single.roleIds, [DiveRole.instructorId]);
  });

  testWidgets("Me's pencil changes only the diver's own roles", (tester) async {
    await pump(tester);
    await enterEdit(tester);

    await tester.tap(_changeRole.first);
    await tester.pumpAndSettle();
    await pickOnlyRole(tester, 'Instructor');
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(dives.savedRoles, [
      [DiveRole.instructorId],
    ]);
    expect(buddies.saved, isEmpty);
  });

  testWidgets('Add from view mode saves the picked buddies straight away', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(_add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await pickOnlyRole(tester, 'Buddy');
    await tester.tap(find.text(_en.buddies_picker_done));
    await tester.pumpAndSettle();

    expect(buddies.saved.single.map((b) => b.buddy.id), ['b1', 'b2']);
    expect(_save, findsNothing);
  });

  testWidgets('Add in edit mode joins the draft without saving', (
    tester,
  ) async {
    await pump(tester);
    await enterEdit(tester);

    await tester.tap(_add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await pickOnlyRole(tester, 'Buddy');
    await tester.tap(find.text(_en.buddies_picker_done));
    await tester.pumpAndSettle();

    expect(buddies.saved, isEmpty);
    expect(find.text('Bob'), findsOneWidget);
    expect(_save, findsOneWidget);
  });
}
