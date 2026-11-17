import 'package:flutter_test/flutter_test.dart';
import 'package:tastehub_app/models/recipe.dart';
import 'package:tastehub_app/utils/ranking.dart';

import 'support/api_fixtures.dart';

Recipe _recipe({
  required int id,
  String title = 'Recipe',
  String dish = 'Biryani',
  double averageRating = 0,
  int ratingCount = 0,
  String? createdAt = '2026-10-20T18:00:00Z',
}) {
  return Recipe.fromJson(
    recipeSummaryJson(
      id: id,
      title: title,
      dish: dish,
      averageRating: averageRating,
      ratingCount: ratingCount,
      myRating: 0,
      createdAt: createdAt,
    ),
  );
}

void main() {
  group('rankRecipes', () {
    test('smooths with the global mean instead of trusting the raw average', () {
      // A lone 4.8 and a well-evidenced 4.0: raw averages put 4.8 first,
      // D-05 pulls the thin sample back toward the global mean (4.07) and
      // lets the vote count decide.
      final recipes = [
        _recipe(id: 1, averageRating: 4.0, ratingCount: 9),
        _recipe(id: 2, averageRating: 4.8, ratingCount: 1),
        _recipe(id: 3, averageRating: 4.0, ratingCount: 2),
      ];

      final ranked = rankRecipes(recipes);

      expect(ranked.map((recipe) => recipe.id), [2, 3, 1]);
      expect(globalMeanRating(recipes), closeTo(4.07, 0.01));
      expect(
        bayesianScore(recipes[0], globalMeanRating(recipes)),
        lessThan(bayesianScore(recipes[1], globalMeanRating(recipes))),
      );
    });

    test('breaks a full tie with the newest recipe', () {
      final recipes = [
        _recipe(
          id: 1,
          averageRating: 4.5,
          ratingCount: 2,
          createdAt: '2026-10-20T18:00:00Z',
        ),
        _recipe(
          id: 2,
          averageRating: 4.5,
          ratingCount: 2,
          createdAt: '2026-11-01T18:00:00Z',
        ),
      ];

      final ranked = rankRecipes(recipes);

      expect(ranked.first.id, 2);
    });

    test('puts unrated recipes last, newest first', () {
      final recipes = [
        _recipe(
          id: 1,
          averageRating: 0,
          ratingCount: 0,
          createdAt: '2026-10-01T18:00:00Z',
        ),
        _recipe(id: 2, averageRating: 3.0, ratingCount: 1),
        _recipe(
          id: 3,
          averageRating: 0,
          ratingCount: 0,
          createdAt: '2026-11-01T18:00:00Z',
        ),
      ];

      final ranked = rankRecipes(recipes);

      expect(ranked.map((recipe) => recipe.id), [2, 3, 1]);
    });

    test('does not modify the input list', () {
      final recipes = [
        _recipe(id: 1, averageRating: 1, ratingCount: 1),
        _recipe(id: 2, averageRating: 5, ratingCount: 1),
      ];

      rankRecipes(recipes);

      expect(recipes.map((recipe) => recipe.id), [1, 2]);
    });
  });

  group('earnsTopPick (H-01 with the modified D-05 threshold)', () {
    test('needs at least 2 ratings averaging 4.5 or better', () {
      expect(earnsTopPick(null), isFalse);
      // One glowing vote is not evidence.
      expect(
        earnsTopPick(_recipe(id: 1, averageRating: 5, ratingCount: 1)),
        isFalse,
      );
      // Plenty of votes, not a strong enough average.
      expect(
        earnsTopPick(_recipe(id: 1, averageRating: 4.4, ratingCount: 5)),
        isFalse,
      );
      // Unrated recipes never earn it.
      expect(
        earnsTopPick(_recipe(id: 1, averageRating: 0, ratingCount: 0)),
        isFalse,
      );
      expect(
        earnsTopPick(_recipe(id: 1, averageRating: 4.5, ratingCount: 2)),
        isTrue,
      );
      expect(
        earnsTopPick(_recipe(id: 1, averageRating: 4.8, ratingCount: 3)),
        isTrue,
      );
    });
  });

  group('groupRecipesByDish', () {
    test('merges dish names case-insensitively and ranks each dish', () {
      final groups = groupRecipesByDish([
        _recipe(
          id: 1,
          title: 'Chicken',
          dish: 'Biryani',
          averageRating: 4,
          ratingCount: 2,
        ),
        _recipe(
          id: 2,
          title: 'Beef',
          dish: 'biryani',
          averageRating: 4.8,
          ratingCount: 1,
        ),
        _recipe(
          id: 3,
          title: 'Karahi',
          dish: 'Karahi',
          averageRating: 4.5,
          ratingCount: 1,
        ),
      ]);

      expect(groups.map((group) => group.name), ['Biryani', 'Karahi']);
      expect(groups.first.recipes.map((recipe) => recipe.title), [
        'Beef',
        'Chicken',
      ]);
      expect(groups.first.recipeCount, 2);
      expect(groups.first.topRecipe?.title, 'Beef');
    });

    test('keeps a recipe with a blank dish in a fallback group', () {
      final groups = groupRecipesByDish([
        _recipe(id: 1, title: 'Toast', dish: '  '),
      ]);

      expect(groups.single.name, 'Recipes');
    });
  });
}
