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
  List<Map<String, dynamic>>? recipes,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final prefsStore = await SharedPreferences.getInstance();
  final api = fakeApiClient(requests: requests, recipes: recipes);
  final session = SessionController(api: api, prefs: prefsStore);

  await session.restore();
  if (username != null) await session.login(username, password);

  final theme = ThemeController(prefs: prefsStore);
  await tester.pumpWidget(
    TasteHubApp(api: api, session: session, themeController: theme),
  );
  await tester.pumpAndSettle();

  return (api: api, session: session, theme: theme, prefs: prefsStore);
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
  testWidgets('opens on login and signs in with a demo account', (
    tester,
  ) async {
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

    expect(find.text('Best rated first'), findsOneWidget);
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
    expect(
      find.text('2 matches: Beef Biryani, Chicken Biryani'),
      findsOneWidget,
    );
    expect(find.text('Karahi'), findsNothing);
  });

  testWidgets('opens a recipe and rates it', (tester) async {
    final requests = <http.Request>[];
    await _pumpApp(tester, username: 'junaid', requests: requests);

    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Cooking steps'), findsOneWidget);
    expect(find.text('Marinate the chicken.'), findsOneWidget);
    expect(find.text('Your rating'), findsOneWidget);

    final star = find.byKey(const ValueKey('star-4'));
    await tester.ensureVisible(star);
    await tester.pumpAndSettle();
    await tester.tap(star);
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
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Delete recipe'), findsOneWidget);
  });

  testWidgets('a guest can rate but cannot edit or delete', (tester) async {
    await _pumpApp(tester, username: 'guest', password: 'guest');
    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    expect(find.byKey(const ValueKey('star-4')), findsOneWidget);
    expect(find.byTooltip('Edit recipe'), findsNothing);
    expect(find.byTooltip('More actions'), findsNothing);
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
    expect(find.text('Recipe photo'), findsOneWidget);
    expect(find.text('Save recipe'), findsOneWidget);

    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();

    expect(find.text('Recipe saved.'), findsOneWidget);
    expect(find.text('2 dishes · 5 recipes'), findsOneWidget);
  });

  testWidgets('shows the recipe title and keeps photo concepts separate', (
    tester,
  ) async {
    await _pumpApp(tester, username: 'junaid');
    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Chicken Biryani'),
      ),
      findsOneWidget,
    );
    expect(find.text('No recipe photo yet - add one above'), findsOneWidget);
    expect(find.text('Add rating photo'), findsOneWidget);
    expect(find.text('Your rating photo'), findsNothing);

    final addRatingPhoto = find.text('Add rating photo');
    await tester.ensureVisible(addRatingPhoto);
    await tester.pumpAndSettle();
    await tester.tap(addRatingPhoto);
    await tester.pumpAndSettle();

    expect(find.text('Your rating photo'), findsOneWidget);
    expect(find.textContaining('not as the recipe photo'), findsWidgets);
  });

  testWidgets('shows your rating photo once and hides it from other ratings', (
    tester,
  ) async {
    final recipes = demoRecipeSummaries();
    recipes[0]['myRatingProofImageRef'] = 'https://example.com/my-rating.jpg';
    await _pumpApp(tester, username: 'junaid', recipes: recipes);
    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    expect(find.text('Your rating photo'), findsOneWidget);
    expect(find.text('Change rating photo'), findsOneWidget);
    expect(find.text('Other ratings'), findsOneWidget);
    expect(find.byTooltip('Open rating photo'), findsOneWidget);
  });

  testWidgets('warns before discarding a dirty recipe form', (tester) async {
    await _pumpApp(tester, username: 'junaid');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write it manually'));
    await tester.pumpAndSettle();

    expect(find.text('Recipe details'), findsOneWidget);
    expect(find.text('Recipe photo'), findsOneWidget);
    expect(find.text('You have unsaved changes'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'My Test Curry');
    await tester.pumpAndSettle();
    expect(find.text('You have unsaved changes'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Recipe details'), findsNothing);
    expect(find.text('2 dishes · 4 recipes'), findsOneWidget);
  });

  testWidgets(
    'phone-width dark mode renders detail and form without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, username: 'junaid', prefs: {'theme_mode': 'dark'});
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );

      await _openDish(tester, 'Biryani');
      await _openRecipe(tester, 'Chicken Biryani');
      expect(find.text('Your rating'), findsOneWidget);

      await tester.ensureVisible(find.text('Watch on YouTube'));
      await tester.pumpAndSettle();
      expect(find.text('Watch on YouTube'), findsOneWidget);

      final addRatingPhoto = find.text('Add rating photo');
      await tester.ensureVisible(addRatingPhoto);
      await tester.pumpAndSettle();
      await tester.tap(addRatingPhoto);
      await tester.pumpAndSettle();
      expect(find.text('Your rating photo'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write it manually'));
      await tester.pumpAndSettle();

      expect(find.text('Recipe details'), findsOneWidget);
      expect(find.text('Save recipe'), findsOneWidget);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save recipe'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Recipe details'), findsNothing);
    },
  );

  testWidgets('empty search offers a clear action', (tester) async {
    await _pumpApp(tester, username: 'junaid');

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No matching recipes'), findsOneWidget);
    expect(find.text('Clear search'), findsOneWidget);

    await tester.ensureVisible(find.text('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('2 dishes · 4 recipes'), findsOneWidget);
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
