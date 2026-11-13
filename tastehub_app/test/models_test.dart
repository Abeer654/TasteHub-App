import 'package:flutter_test/flutter_test.dart';
import 'package:tastehub_app/models/recipe.dart';
import 'package:tastehub_app/models/recipe_draft.dart';

import 'support/api_fixtures.dart';

void main() {
  group('Recipe', () {
    test('parses every field of a recipe detail response', () {
      final recipe = Recipe.fromJson(recipeDetailJson());

      expect(recipe.id, 1);
      expect(recipe.title, 'Chicken Biryani');
      expect(recipe.dish, 'Biryani');
      expect(recipe.ownerId, 1);
      expect(recipe.ownerName, 'junaid');
      expect(recipe.cookingTime, 60);
      expect(recipe.averageRating, 4.5);
      expect(recipe.ratingCount, 2);
      expect(recipe.myRating, 5);
      expect(recipe.ingredients, ['rice', 'chicken', 'yogurt']);
      expect(recipe.steps, hasLength(2));
      expect(recipe.ratings, hasLength(2));
      expect(recipe.ratings.first.userId, 1);
      expect(recipe.ratings.first.userName, 'junaid');
      expect(recipe.ratings.last.userName, 'guest');
      expect(recipe.ratings.last.stars, 4);
    });

    test('missing optional fields fall back to safe values', () {
      final recipe = Recipe.fromJson({'id': 7, 'title': 'Toast'});

      expect(recipe.id, 7);
      expect(recipe.dish, '');
      expect(recipe.ownerId, 0);
      expect(recipe.ownerName, '');
      expect(recipe.averageRating, 0);
      expect(recipe.ingredients, isEmpty);
      expect(recipe.ratings, isEmpty);
      expect(recipe.cookingTime, 0);
    });

    test('withRating keeps the rest of the recipe intact', () {
      final recipe = Recipe.fromJson(recipeDetailJson());
      final updated = recipe.withRating(
        const RatingSummary(
          averageRating: 3.8,
          ratingCount: 6,
          myRating: 4,
          myRatingProofImageRef: 'proof.jpg',
        ),
      );

      expect(updated.id, recipe.id);
      expect(updated.title, recipe.title);
      expect(updated.ownerId, recipe.ownerId);
      expect(updated.ownerName, recipe.ownerName);
      expect(updated.ingredients, recipe.ingredients);
      expect(updated.averageRating, 3.8);
      expect(updated.ratingCount, 6);
      expect(updated.myRating, 4);
      expect(updated.myRatingProofImageRef, 'proof.jpg');
    });
  });

  group('RecipeInput', () {
    test('trims text and drops blank ingredients and steps', () {
      final input = RecipeInput(
        title: '  Chicken Biryani  ',
        dish: '  ',
        mainIngredient: ' rice ',
        ingredients: ['rice', ' ', 'chicken '],
        steps: [' cook ', ''],
        cookingTime: 60,
      );

      expect(input.toJson(), {
        'title': 'Chicken Biryani',
        'dish': 'My Recipes',
        'mainIngredient': 'rice',
        'ingredients': ['rice', 'chicken'],
        'steps': ['cook'],
        'cookingTime': 60,
        'imageRef': '',
        'youtubeUrl': '',
      });
    });

    test('uses My Recipes when the API omits the dish', () {
      final input = RecipeInput.fromJson({'title': 'Toast'});
      expect(input.dish, 'My Recipes');
    });
  });

  group('RecipeDraft', () {
    test('parses the AI draft and its review metadata', () {
      final draft = RecipeDraft.fromJson({
        'message': 'That sounds delicious.',
        'recipe': {
          'dish': 'Biryani',
          'title': 'Chicken Biryani',
          'mainIngredient': 'rice',
          'ingredients': ['rice', 'chicken'],
          'steps': ['Marinate the chicken.', 'Cook with rice.'],
          'cookingTime': 60,
        },
        'inferredFields': ['cookingTime'],
        'followUpQuestions': ['How much rice did you use?'],
        'source': 'gemini',
      });

      expect(draft.message, 'That sounds delicious.');
      expect(draft.recipe.title, 'Chicken Biryani');
      expect(draft.inferredFields, ['cookingTime']);
      expect(draft.followUpQuestions, hasLength(1));
      expect(draft.source, 'gemini');
    });

    test('rejects a draft without a recipe object', () {
      expect(
        () => RecipeDraft.fromJson({'message': 'Oops'}),
        throwsFormatException,
      );
    });
  });
}
