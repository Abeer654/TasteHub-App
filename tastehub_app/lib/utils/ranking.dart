// ============================================================
//  ranking.dart - the one place that decides recipe order
//
//  Rules (same as BackendService::leaderboard):
//    1. rated recipes before unrated ones
//    2. higher average rating first
//    3. more ratings first
//    4. newer recipe first
//
//  Unrated recipes are marked "New" in the UI and ranked after the
//  rated ones, newest first.
// ============================================================

import '../models/dish_group.dart';
import '../models/recipe.dart';

int compareRecipes(Recipe a, Recipe b) {
  final aRated = a.ratingCount > 0;
  final bRated = b.ratingCount > 0;

  if (aRated != bRated) return aRated ? -1 : 1;

  if (aRated && bRated) {
    final average = b.averageRating.compareTo(a.averageRating);
    if (average != 0) return average;

    final count = b.ratingCount.compareTo(a.ratingCount);
    if (count != 0) return count;
  }

  return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
}

/// Returns a new ranked list; the input list is not modified.
List<Recipe> rankRecipes(Iterable<Recipe> recipes) {
  final ranked = recipes.toList(growable: false);
  return ranked..sort(compareRecipes);
}

/// Groups recipes by dish name (case-insensitive) and ranks each group.
/// Dish groups are sorted alphabetically to keep the home screen stable.
List<DishGroup> groupRecipesByDish(Iterable<Recipe> recipes) {
  final groups = <String, List<Recipe>>{};
  final displayNames = <String, String>{};

  for (final recipe in recipes) {
    final name = recipe.dish.trim().isEmpty ? 'Recipes' : recipe.dish.trim();
    final key = name.toLowerCase();
    // Keep the first spelling that was seen, so "Biryani" and "biryani"
    // merge without the display name flipping to whichever came last.
    displayNames.putIfAbsent(key, () => name);
    groups.putIfAbsent(key, () => []).add(recipe);
  }

  final result = groups.entries.map((entry) {
    return DishGroup(
      name: displayNames[entry.key]!,
      recipes: rankRecipes(entry.value),
    );
  }).toList();

  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}
