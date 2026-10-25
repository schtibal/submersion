import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_repository_provider.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/dive_notes_card.dart';
import 'package:submersion/features/dive_log/presentation/widgets/inline_edit/inline_edit_session.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

class _RecordingDiveRepository extends Fake implements DiveRepository {
  final saved = <(String, String)>[];
  Object? failWith;

  @override
  Future<void> setNotes(String diveId, String notes) async {
    if (failWith != null) throw failWith!;
    saved.add((diveId, notes));
  }
}

Dive _dive(String notes) =>
    Dive(id: 'd1', dateTime: DateTime(2026, 3, 15, 10), notes: notes);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _RecordingDiveRepository repository, {
  String notes = 'Eagle rays at 18 m',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [diveRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: DiveNotesCard(dive: _dive(notes))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(DiveNotesCard)));
}

Finder get _editButton => find.byTooltip(_en.diveLog_detail_editNotes);
Finder get _field => find.byType(TextField);

void main() {
  late _RecordingDiveRepository repository;

  setUp(() => repository = _RecordingDiveRepository());

  testWidgets('view mode shows the notes and an Edit icon', (tester) async {
    await _pump(tester, repository);

    expect(find.text('Eagle rays at 18 m'), findsOneWidget);
    expect(_editButton, findsOneWidget);
    expect(_field, findsNothing);
  });

  testWidgets('a dive without notes still shows its empty text', (
    tester,
  ) async {
    await _pump(tester, repository, notes: '');

    expect(find.text(_en.diveLog_detail_noNotes), findsOneWidget);
    expect(_editButton, findsOneWidget);
  });

  testWidgets('Edit swaps the icon for Cancel and Save over a text field', (
    tester,
  ) async {
    await _pump(tester, repository);

    await tester.tap(_editButton);
    await tester.pumpAndSettle();

    expect(_editButton, findsNothing);
    expect(find.text(_en.forms_cancel), findsOneWidget);
    expect(find.text(_en.forms_save), findsOneWidget);
    expect(
      tester.widget<TextField>(_field).controller!.text,
      'Eagle rays at 18 m',
    );
  });

  testWidgets('Cancel discards the draft and writes nothing', (tester) async {
    await _pump(tester, repository);
    await tester.tap(_editButton);
    await tester.pumpAndSettle();

    await tester.enterText(_field, 'Something else');
    await tester.tap(find.text(_en.forms_cancel));
    await tester.pumpAndSettle();

    expect(repository.saved, isEmpty);
    expect(find.text('Eagle rays at 18 m'), findsOneWidget);
    expect(_editButton, findsOneWidget);
  });

  testWidgets('Save writes only the notes and shows the saved text', (
    tester,
  ) async {
    await _pump(tester, repository);
    await tester.tap(_editButton);
    await tester.pumpAndSettle();

    await tester.enterText(_field, 'Eagle rays at 18 m\nViz 10 m');
    await tester.tap(find.text(_en.forms_save));
    await tester.pumpAndSettle();

    expect(repository.saved, [('d1', 'Eagle rays at 18 m\nViz 10 m')]);
    expect(_field, findsNothing);
    expect(find.text('Eagle rays at 18 m\nViz 10 m'), findsOneWidget);
  });

  testWidgets('a failed save keeps the draft open and says why', (
    tester,
  ) async {
    repository.failWith = StateError('disk full');
    await _pump(tester, repository);
    await tester.tap(_editButton);
    await tester.pumpAndSettle();

    await tester.enterText(_field, 'Draft');
    await tester.tap(find.text(_en.forms_save));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(_field).controller!.text, 'Draft');
    expect(find.textContaining('disk full'), findsOneWidget);
  });

  testWidgets('the edit session tracks whether the draft changed', (
    tester,
  ) async {
    final container = await _pump(tester, repository);
    InlineEditSession? session() =>
        container.read(inlineEditNotifierProvider('d1'));

    await tester.tap(_editButton);
    await tester.pumpAndSettle();
    expect(session()?.card, InlineEditCard.notes);
    expect(session()?.dirty, isFalse);

    await tester.enterText(_field, 'Changed');
    await tester.pump();
    expect(session()?.dirty, isTrue);

    await tester.tap(find.text(_en.forms_cancel));
    await tester.pumpAndSettle();
    expect(session(), isNull);
  });

  testWidgets('dragging the grip makes the field taller', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, repository);
    await tester.tap(_editButton);
    await tester.pumpAndSettle();
    final before = tester.getSize(_field).height;

    await tester.drag(
      find.bySemanticsLabel(_en.diveLog_detail_resizeNotes),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(_field).height, greaterThan(before + 80));
    semantics.dispose();
  });
}
