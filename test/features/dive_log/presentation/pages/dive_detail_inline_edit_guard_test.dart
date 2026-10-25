import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/constants/dive_detail_sections.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/domain/entities/dive_data_source.dart';
import 'package:submersion/features/dive_log/presentation/pages/dive_detail_page.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

class _MockSettingsNotifier extends StateNotifier<AppSettings>
    implements SettingsNotifier {
  _MockSettingsNotifier(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Only the Notes card, so the test reaches it without scrolling.
AppSettings _notesOnly() => AppSettings(
  diveDetailSections: DiveDetailSectionId.values
      .map(
        (id) => DiveDetailSectionConfig(
          id: id,
          visible: id == DiveDetailSectionId.notes,
        ),
      )
      .toList(),
);

Future<void> _pumpPushed(WidgetTester tester, SharedPreferences prefs) async {
  final dive = Dive(id: 'd1', dateTime: DateTime(2026, 3, 15), notes: 'Old');
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        diveProvider(dive.id).overrideWith((ref) async => dive),
        diveDataSourcesProvider(
          dive.id,
        ).overrideWith((ref) async => <DiveDataSource>[]),
        settingsProvider.overrideWith(
          (ref) => _MockSettingsNotifier(_notesOnly()),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DiveDetailPage(diveId: dive.id),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Issue #2976: a card's unsaved draft is not lost to a stray back.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('back with an unsaved notes draft asks first', (tester) async {
    await _pumpPushed(tester, prefs);
    await tester.tap(find.byTooltip(_en.diveLog_detail_editNotes));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_en.forms_discard_title), findsOneWidget);

    await tester.tap(find.text(_en.forms_discard_keepEditing));
    await tester.pumpAndSettle();
    expect(find.byType(DiveDetailPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.forms_discard_discard));
    await tester.pumpAndSettle();
    expect(find.byType(DiveDetailPage), findsNothing);
  });

  testWidgets('back with an unchanged draft leaves without asking', (
    tester,
  ) async {
    await _pumpPushed(tester, prefs);
    await tester.tap(find.byTooltip(_en.diveLog_detail_editNotes));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(_en.forms_discard_title), findsNothing);
    expect(find.byType(DiveDetailPage), findsNothing);
  });
}
