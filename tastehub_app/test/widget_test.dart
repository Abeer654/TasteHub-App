import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tastehub_app/app.dart';
import 'package:tastehub_app/services/api_client.dart';
import 'package:tastehub_app/services/session_controller.dart';
import 'package:tastehub_app/services/theme_controller.dart';

import 'support/api_fixtures.dart';

typedef _Harness = ({
  ApiClient api,
  SessionController session,
  ThemeController theme,
  SharedPreferences prefs,
});

/// Builds the real app with a mock server and an already-restored session.
/// Pass [username] to start logged in; leave it null to show the login screen.
Future<_Harness> _pumpApp(
  WidgetTester tester, {
  String? username,
  String password = 'tastehub',
  List<http.Request>? requests,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = fakeApiClient(requests: requests);
  final session = SessionController(api: api, prefs: prefs);

  await session.restore();
  if (username != null) await session.login(username, password);

  final theme = ThemeController(prefs: prefs);
  await tester.pumpWidget(
    TasteHubApp(api: api, session: session, themeController: theme),
  );
  await tester.pumpAndSettle();

  return (api: api, session: session, theme: theme, prefs: prefs);
}

Future<void> _openDish(WidgetTester tester, String dish) async {
  await tester.tap(find.text(dish));
  await tester.pumpAndSettle();
}

Future<void> _openRecipe(WidgetTester tester, String title) async {
  final recipe = find.text(title);
  await tester.ensureVisible(recipe);
  await tester.pumpAndSettle();
  await tester.tap(recipe);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on login and signs in with a demo account', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Biryani'), findsNothing);

    final demo = find.text('junaid / tastehub');
    await tester.ensureVisible(demo);
    await tester.tap(demo);
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Biryani'), findsOneWidget);
    expect(find.text('Karahi'), findsOneWidget);
    expect(find.text('2 dishes · 4 recipes'), findsOneWidget);
  });

  testWidgets('groups recipes by dish and drops the global leaderboard', (
    tester,
  ) async {
    await _pumpApp(tester, username: 'junaid');

    expect(find.text('Leaderboard'), findsNothing);
    await _openDish(tester, 'Biryani');

    expect(find.text('Ranked by average rating, then number of ratings.'),
        findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('Top pick'), findsOneWidget);
    expect(find.text('Beef Biryani'), findsOneWidget);
    expect(find.text('Chicken Biryani'), findsOneWidget);

    final beef = tester.getTopLeft(find.text('Beef Biryani')).dy;
    final chicken = tester.getTopLeft(find.text('Chicken Biryani')).dy;
    expect(beef, lessThan(chicken));
  });

  testWidgets('marks an unrated recipe as new and ranks it last', (
    tester,
  ) async {
    await _pumpApp(tester, username: 'junaid');
    await _openDish(tester, 'Karahi');

    expect(find.text('Chicken Karahi'), findsOneWidget);
    expect(find.text('Mutton Karahi'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('New - not rated'), findsOneWidget);

    final chicken = tester.getTopLeft(find.text('Chicken Karahi')).dy;
    final mutton = tester.getTopLeft(find.text('Mutton Karahi')).dy;
    expect(chicken, lessThan(mutton));
  });

  testWidgets('searches and keeps results grouped by dish', (tester) async {
    await _pumpApp(tester, username: 'junaid');

    await tester.enterText(find.byType(TextField), 'biryani');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('2 results in 1 dish'), findsOneWidget);
    expect(find.text('Top: Beef Biryani'), findsOneWidget);
    expect(find.text('Karahi'), findsNothing);
  });

  testWidgets('opens a recipe and rates it', (tester) async {
    final requests = <http.Request>[];
    await _pumpApp(
      tester,
      username: 'junaid',
      requests: requests,
    );

    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Cooking steps'), findsOneWidget);
    expect(find.text('Marinate the chicken.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('star-4')));
    await tester.pumpAndSettle();

    expect(find.text('Rated 4 out of 5.'), findsOneWidget);
    expect(
      requests.where(
        (request) =>
            request.method == 'PUT' &&
            request.url.path == '/api/recipes/1/rating',
      ),
      hasLength(1),
    );
  });

  testWidgets('only the owner sees edit and delete', (tester) async {
    await _pumpApp(tester, username: 'junaid');
    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    expect(find.byTooltip('Edit recipe'), findsOneWidget);
    expect(find.byTooltip('Delete recipe'), findsOneWidget);
  });

  testWidgets('a guest can rate but cannot edit or delete', (tester) async {
    await _pumpApp(tester, username: 'guest', password: 'guest');
    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    expect(find.byKey(const ValueKey('star-4')), findsOneWidget);
    expect(find.byTooltip('Edit recipe'), findsNothing);
    expect(find.byTooltip('Delete recipe'), findsNothing);
  });

  testWidgets('creates a recipe through the AI draft flow', (tester) async {
    await _pumpApp(tester, username: 'junaid');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Describe it with AI'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'I made chicken biryani with rice and chicken.',
    );
    final createButton = find.text('Create AI draft');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.text('AI draft - review before saving'), findsOneWidget);
    expect(find.text('Chicken Biryani'), findsWidgets);

    final saveButton = find.text('Save recipe');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Recipe saved.'), findsOneWidget);
    expect(find.text('2 dishes · 5 recipes'), findsOneWidget);
  });

  testWidgets('switches to dark mode and saves the choice', (tester) async {
    final harness = await _pumpApp(tester, username: 'junaid');

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await tester.tap(find.byTooltip('Theme: System'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<ThemeMode>, 'Dark theme'),
    );
    await tester.pumpAndSettle();

    expect(harness.theme.mode, ThemeMode.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(harness.prefs.getString(ThemeController.modeKey), 'dark');

    final context = tester.element(
      find.text('Pick a dish, then pick the best recipe.'),
    );
    expect(Theme.of(context).brightness, Brightness.dark);
  });
}
