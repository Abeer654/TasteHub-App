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
    test('puts the highest average first, then the most rated', () {
      final recipes = [
        _recipe(id: 1, averageRating: 4.0, ratingCount: 9),
        _recipe(id: 2, averageRating: 4.8, ratingCount: 1),
        _recipe(id: 3, averageRating: 4.0, ratingCount: 2),
      ];

      final ranked = rankRecipes(recipes);

      expect(ranked.map((recipe) => recipe.id), [2, 1, 3]);
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
