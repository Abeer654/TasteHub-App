import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tastehub_app/app.dart';
import 'package:tastehub_app/screens/recipe_detail/recipe_rating_section.dart';
import 'package:tastehub_app/services/api_client.dart';
import 'package:tastehub_app/services/session_controller.dart';
import 'package:tastehub_app/services/theme_controller.dart';
import 'package:tastehub_app/theme.dart';
import 'package:tastehub_app/widgets/dish_card.dart';
import 'package:tastehub_app/widgets/rating_stars.dart';
import 'package:tastehub_app/widgets/recipe_list_card.dart';
import 'package:tastehub_app/widgets/status_views.dart';

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
    // H-04: the counts moved into the filter chips.
    expect(find.text('All dishes · 2'), findsOneWidget);
    expect(find.text('My recipes · 4'), findsOneWidget);
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
    // H-01: Biryani's best recipe has a single 4.5 rating, so "#1" is a
    // fact but the earned "Top pick" badge must stay hidden.
    expect(find.text('Top pick'), findsNothing);
    expect(find.text('Beef Biryani'), findsOneWidget);
    expect(find.text('Chicken Biryani'), findsOneWidget);

    final beef = tester.getTopLeft(find.text('Beef Biryani')).dy;
    final chicken = tester.getTopLeft(find.text('Chicken Biryani')).dy;
    expect(beef, lessThan(chicken));

    // Karahi's best recipe has 3 ratings at 4.8 - that one earns it.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await _openDish(tester, 'Karahi');
    expect(find.text('Top pick'), findsOneWidget);
  });

  testWidgets('a narrow window keeps the fixed 112dp dish card layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A long dish name would truncate to a couple of characters if the
    // Top pick pill squeezed the title row on a phone-width card.
    final recipes = demoRecipeSummaries();
    for (final recipe in recipes) {
      recipe['dish'] = 'Hydrabadi Pulao';
    }
    await _pumpApp(tester, username: 'junaid', recipes: recipes);

    final cards = tester.widgetList<DishCard>(find.byType(DishCard));
    expect(cards, isNotEmpty);

    // H-05: one card shape at every width - 112dp tall, photo left.
    final box = tester.renderObject<RenderBox>(find.byType(DishCard).first);
    expect(box.size.height, DishCard.height);

    // The status badge lives on the thumbnail (left of the title), so the
    // dish name keeps the whole text column instead of being squeezed
    // into a few characters by the pill.
    final pillCenter = tester.getCenter(find.text('Top pick')).dx;
    final titleLeft = tester.getTopLeft(find.text('Hydrabadi Pulao')).dx;
    expect(
      pillCenter,
      lessThan(titleLeft),
      reason: 'the Top pick badge must sit on the thumbnail, not the title',
    );
    expect(
      tester.getSize(find.text('Hydrabadi Pulao')).width,
      greaterThanOrEqualTo(150),
      reason: 'the dish name must get the full text column',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading shows skeletons at the real card sizes', (tester) async {
    // G-06 (4): placeholders shaped like the cards, not a spinner.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTasteHubTheme(Brightness.light),
        home: const Scaffold(
          body: Column(
            children: [DishCardSkeleton(), RecipeRowSkeleton()],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(DishCardSkeleton)).height,
      DishCard.height,
    );
    expect(
      tester.getSize(find.byType(RecipeRowSkeleton)).height,
      RecipeListCard.height,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('marks an unrated recipe as new and ranks it last', (
    tester,
  ) async {
    await _pumpApp(tester, username: 'junaid');
    await _openDish(tester, 'Karahi');

    expect(find.text('Chicken Karahi'), findsOneWidget);
    expect(find.text('Mutton Karahi'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    // G-05/M-03: the unrated recipe gets the "New" chip, never stars.
    expect(find.text('New'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RecipeListCard),
        matching: find.byType(RatingStars),
      ),
      findsNothing,
    );

    final chicken = tester.getTopLeft(find.text('Chicken Karahi')).dy;
    final mutton = tester.getTopLeft(find.text('Mutton Karahi')).dy;
    expect(chicken, lessThan(mutton));
  });

  testWidgets('searches and keeps results grouped by dish', (tester) async {
    await _pumpApp(tester, username: 'junaid');

    await tester.enterText(find.byType(TextField), 'biryani');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // H-04: the chips carry the counts, so the summary line is gone.
    expect(find.text('All dishes · 1'), findsOneWidget);
    expect(find.text('My recipes · 2'), findsOneWidget);
    expect(
      find.text('2 matches: Beef Biryani, Chicken Biryani'),
      findsOneWidget,
    );
    expect(find.text('Karahi'), findsNothing);
  });

  testWidgets('My recipes lists each recipe instead of dish cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, username: 'junaid');

    await tester.tap(find.textContaining('My recipes'));
    await tester.pumpAndSettle();

    // H-04 counts in the chips, M-04 summary in the subtitle.
    expect(find.text('My recipes · 4'), findsOneWidget);
    expect(find.text('4 recipes'), findsOneWidget);
    expect(find.text('4 need photos'), findsOneWidget);
    expect(find.byType(DishCard), findsNothing);
    expect(find.byType(RecipeListCard), findsNWidgets(4));
    expect(find.text('Chicken Biryani'), findsOneWidget);
    expect(find.text('Beef Biryani'), findsOneWidget);
    expect(find.text('Chicken Karahi'), findsOneWidget);
    expect(find.text('Mutton Karahi'), findsOneWidget);

    // M-01: grouped view puts sticky dish headers over the rows.
    expect(find.text('BIRYANI · 2 recipes'), findsOneWidget);
    expect(find.text('KARAHI · 2 recipes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'biryani');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('My recipes · 2'), findsOneWidget);
    expect(find.text('Chicken Karahi'), findsNothing);

    await tester.tap(find.text('Chicken Biryani'));
    await tester.pumpAndSettle();
    expect(find.text('Ingredients'), findsOneWidget);
  });

  testWidgets('My recipes hides recipes owned by someone else', (tester) async {
    final recipes = demoRecipeSummaries();
    recipes[1]['ownerId'] = 2;
    recipes[1]['ownerName'] = 'guest';

    await _pumpApp(tester, username: 'junaid', recipes: recipes);
    await tester.tap(find.textContaining('My recipes'));
    await tester.pumpAndSettle();

    expect(find.text('My recipes · 3'), findsOneWidget);
    expect(find.text('3 recipes'), findsOneWidget);
    expect(find.text('Beef Biryani'), findsNothing);
    expect(find.text('Chicken Biryani'), findsOneWidget);
  });

  testWidgets('My recipes search shows match context and a way out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, username: 'junaid');

    await tester.tap(find.textContaining('My recipes'));
    await tester.pumpAndSettle();

    // M-04: the slogan is replaced by a live summary.
    expect(find.text('4 recipes'), findsOneWidget);
    expect(find.text('4 need photos'), findsOneWidget);
    expect(find.text('BIRYANI · 2 recipes'), findsOneWidget);
    expect(find.byType(DishCard), findsNothing);

    await tester.enterText(find.byType(TextField), 'biryani');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Your recipes matching "biryani".'), findsOneWidget);
    expect(find.text('All dishes · 1'), findsOneWidget);
    expect(find.text('BIRYANI · 2 recipes'), findsOneWidget);
    expect(find.text('Match in the title'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No matching recipes'), findsOneWidget);
    expect(find.text('Clear search'), findsOneWidget);
    expect(find.text('Show all dishes'), findsOneWidget);

    await tester.ensureVisible(find.text('Show all dishes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show all dishes'));
    await tester.pumpAndSettle();

    expect(find.text('Matching "zzz" across every dish.'), findsOneWidget);
    expect(find.text('Show all dishes'), findsNothing);

    await tester.ensureVisible(find.text('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('All dishes · 2'), findsOneWidget);
    expect(find.text('My recipes · 4'), findsOneWidget);
    expect(
      find.text('Pick a dish, then pick the best recipe.'),
      findsOneWidget,
    );
  });

  testWidgets('opens a recipe and rates it', (tester) async {
    final requests = <http.Request>[];
    // Chicken Biryani belongs to junaid; guest rates someone else's
    // recipe, which is the only kind of rating the API accepts.
    await _pumpApp(tester, username: 'guest', password: 'guest',
        requests: requests);

    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Cooking steps'), findsOneWidget);
    expect(find.text('Marinate the chicken.'), findsOneWidget);
    expect(find.text('Your rating'), findsOneWidget);

    // R-04: the summary row opens the per-star distribution. The same
    // numbers also sit in the overview pill, so scope to this card.
    final summary = find.descendant(
      of: find.byType(RecipeRatingSection),
      matching: find.text('4.0 from 2 ratings'),
    );
    expect(summary, findsOneWidget);
    await tester.ensureVisible(summary);
    await tester.pumpAndSettle();
    await tester.tap(summary);
    await tester.pumpAndSettle();

    expect(find.text('Ratings'), findsOneWidget);
    expect(find.text('5\u2605'), findsOneWidget);
    expect(find.text('4\u2605'), findsOneWidget);
    expect(find.text('1\u2605'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    final star = find.byKey(const ValueKey('star-4'));
    await tester.ensureVisible(star);
    await tester.pumpAndSettle();
    await tester.tap(star);
    await tester.pumpAndSettle();

    // R-04: instant feedback. This guest already had a 5, so Undo is
    // offered; the API has no "remove rating" route for a first rating.
    expect(find.text('Thanks! You rated 4\u2605'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
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

  testWidgets('an author cannot rate their own recipe', (tester) async {
    final requests = <http.Request>[];
    await _pumpApp(tester, username: 'junaid', requests: requests);

    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    // The card becomes a community summary: no star picker, no rating
    // photo controls, and a note explaining the rule.
    expect(find.text('Community rating'), findsOneWidget);
    expect(find.text('Your rating'), findsNothing);
    expect(find.byType(StarPicker), findsNothing);
    expect(find.byKey(const ValueKey('star-4')), findsNothing);
    expect(find.text('Add rating photo'), findsNothing);
    expect(
      find.text('You wrote it, so only others can rate it.'),
      findsOneWidget,
    );

    // Owner-only edit and delete stay untouched.
    expect(find.byTooltip('Edit recipe'), findsOneWidget);

    expect(
      requests.where(
        (request) =>
            request.method == 'PUT' && request.url.path.contains('/rating'),
      ),
      isEmpty,
    );
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
    expect(find.text('All dishes · 2'), findsOneWidget);
    expect(find.text('My recipes · 5'), findsOneWidget);
  });

  testWidgets('shows the recipe title and keeps photo concepts separate', (
    tester,
  ) async {
    // Guest (not the author) so the rating-photo controls are visible.
    await _pumpApp(tester, username: 'guest', password: 'guest');
    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Chicken Biryani'),
      ),
      findsOneWidget,
    );
    expect(find.text('No recipe photo yet'), findsOneWidget);
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
    // The proof belongs to a rating on someone else's recipe: junaid
    // cannot rate his own recipe, so guest owns this one.
    recipes[0]['ownerId'] = 2;
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
    expect(find.text('All dishes · 2'), findsOneWidget);
  });

  testWidgets('Add photo opens the form on the photo section', (tester) async {
    await _pumpApp(tester, username: 'junaid');
    await _openDish(tester, 'Biryani');
    await _openRecipe(tester, 'Chicken Biryani');

    final addPhoto = find.text('Add a photo');
    expect(addPhoto, findsOneWidget);
    await tester.ensureVisible(addPhoto);
    await tester.pumpAndSettle();
    await tester.tap(addPhoto);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Edit recipe'),
      ),
      findsOneWidget,
    );

    // The photo card is scrolled near the top instead of staying below
    // the fold behind the hero and details card.
    expect(tester.getRect(find.text('Recipe photo')).top, lessThan(300));
  });

  testWidgets('rejects an incomplete YouTube link instead of saving it', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await _pumpApp(tester, username: 'junaid', requests: requests);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write it manually'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Test Curry');

    final youtube = find.widgetWithText(
      TextField,
      'https://www.youtube.com/watch?v=...',
    );
    await tester.ensureVisible(youtube);
    await tester.pumpAndSettle();
    await tester.enterText(youtube, 'youtube.com/watch?v=abc');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();

    // E-02: no scheme and a playlist/search link never open one video.
    expect(
      find.text('Paste a link to a single YouTube video.'),
      findsOneWidget,
    );
    expect(
      requests.where(
        (request) =>
            request.method == 'POST' && request.url.path == '/api/recipes',
      ),
      isEmpty,
    );
  });

  testWidgets(
    'phone-width dark mode renders detail and form without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpApp(
        tester,
        username: 'guest',
        password: 'guest',
        prefs: {'theme_mode': 'dark'},
      );
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

    expect(find.text('All dishes · 2'), findsOneWidget);
  });

  testWidgets('switches to dark mode and saves the choice', (tester) async {
    final harness = await _pumpApp(tester, username: 'junaid');

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    // H-03: the theme toggle now lives inside the avatar menu.
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<ThemeMode>, 'Theme: Dark'),
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

  testWidgets('header collapses into a 56dp bar after 56dp of scroll', (
    tester,
  ) async {
    // The default two-dish fixture fits on screen, so scroll only works
    // with a list that overflows the viewport.
    final recipes = [
      for (var i = 0; i < 12; i++)
        recipeSummaryJson(id: 100 + i, title: 'Recipe $i', dish: 'Dish $i'),
    ];
    await _pumpApp(tester, username: 'junaid', recipes: recipes);

    final tagline = find.text('Pick a dish, then pick the best recipe.');
    final search = find.byType(TextField);
    final account = find.byTooltip('Account');

    expect(tagline, findsOneWidget);
    expect(search, findsOneWidget);
    expect(account, findsOneWidget);

    final restTop = tester.getTopLeft(search).dy;

    // Still under the threshold: the expanded header must stay put.
    await tester.drag(find.byType(GridView).first, const Offset(0, -30));
    await tester.pumpAndSettle();
    expect(tagline, findsOneWidget);
    expect(tester.getTopLeft(search).dy, restTop);

    // Past 56dp: the bar collapses, the subtitle goes, and both the
    // avatar and the pinned search field stay on screen (H-03).
    await tester.drag(find.byType(GridView).first, const Offset(0, -100));
    await tester.pumpAndSettle();

    expect(tagline, findsNothing);
    expect(account, findsOneWidget);
    expect(search, findsOneWidget);
    expect(tester.getTopLeft(search).dy, lessThan(restTop));
  });

  testWidgets('rating stars expose one spoken rating label', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTasteHubTheme(Brightness.light),
          home: const Scaffold(
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [RatingStars(value: 4.5), RatingStars(value: 0)],
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Rated 4.5 out of 5 stars'), findsOneWidget);
      expect(find.bySemanticsLabel('No rating yet'), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });
}
