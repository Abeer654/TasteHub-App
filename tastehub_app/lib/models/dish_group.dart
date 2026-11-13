// ============================================================
//  dish_group.dart - recipes that belong to the same dish
// ============================================================

import 'recipe.dart';

class DishGroup {
  const DishGroup({required this.name, required this.recipes});

  final String name;
  final List<Recipe> recipes;

  bool get isRated => recipes.any((recipe) => recipe.isRated);

  /// Top-ranked recipe, or null for a dish with no recipes.
  Recipe? get topRecipe => recipes.isEmpty ? null : recipes.first;

  int get recipeCount => recipes.length;
}
