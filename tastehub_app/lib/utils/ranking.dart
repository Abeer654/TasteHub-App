// ============================================================
//  ranking.dart - the one place that decides recipe order
//
//  Ordering follows D-05 (tastehub-ui-decisions.md §2):
//
//      score = (v / (v + m)) * R + (m / (v + m)) * C      m = 3
//
//  where v is a recipe's rating count, R its average, and C the global
//  average across every rated recipe. A single 5-star vote therefore
//  cannot outrank a recipe that many people rated - the smooth pulls
//  thin evidence back toward the site average.
//
//  Rules, in order:
//    1. rated recipes before unrated ones (unrated would otherwise
//       score exactly C and float above weak but real ratings)
//    2. higher Bayesian score first
//    3. more ratings first
//    4. newer recipe first
//
//  The same helpers decide the "Best: ..." line, the dish page order
//  and whether a dish has earned its "Top pick" badge, so the card and
//  the dish screen can never disagree.
// ============================================================

import '../models/dish_group.dart';
import '../models/recipe.dart';

/// m - minimum votes before a rating stops being pure noise.
const double minVotes = 3;

/// Modified badge rule (decisions §2): the spec's `v >= 3` would empty
/// every badge on the sample data, where the highest count is 2.
const int badgeMinRatings = 2;
const double badgeMinAverage = 4.5;

/// Global mean C: total stars divided by total ratings.
double globalMeanRating(Iterable<Recipe> recipes, {double orElse = 3.5}) {
  var stars = 0.0;
  var ratings = 0;

  for (final recipe in recipes) {
    if (recipe.ratingCount <= 0) continue;
    stars += recipe.averageRating * recipe.ratingCount;
    ratings += recipe.ratingCount;
  }

  return ratings == 0 ? orElse : stars / ratings;
}

/// D-05 smoothed score for one recipe against the global mean.
double bayesianScore(Recipe recipe, double globalMean) {
  final votes = recipe.ratingCount.toDouble();
  final weight = votes / (votes + minVotes);
  return weight * recipe.averageRating + (1 - weight) * globalMean;
}

/// H-01: the badge has to be earned. A dish earns "Top pick" only when
/// its best recipe (the group's first, already ordered by
/// [bayesianScore]) clears both thresholds.
bool earnsTopPick(Recipe? best) {
  if (best == null || !best.isRated) return false;
  return best.ratingCount >= badgeMinRatings &&
      best.averageRating >= badgeMinAverage;
}

int compareRecipes(Recipe a, Recipe b, double globalMean) {
  final aRated = a.isRated;
  final bRated = b.isRated;

  if (aRated != bRated) return aRated ? -1 : 1;

  if (aRated && bRated) {
    final score = bayesianScore(b, globalMean).compareTo(
      bayesianScore(a, globalMean),
    );
    if (score != 0) return score;

    final count = b.ratingCount.compareTo(a.ratingCount);
    if (count != 0) return count;
  }

  return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
}

/// Returns a new ranked list; the input list is not modified.
///
/// Pass [globalMean] when the list is only a slice of the data (the dish
/// page ranks one dish but must still smooth against the whole app).
List<Recipe> rankRecipes(Iterable<Recipe> recipes, {double? globalMean}) {
  final ranked = recipes.toList(growable: false);
  final mean = globalMean ?? globalMeanRating(ranked);
  return ranked..sort((a, b) => compareRecipes(a, b, mean));
}

/// Groups recipes by dish name (case-insensitive) and ranks each group.
/// Dish groups are sorted alphabetically to keep the home screen stable.
List<DishGroup> groupRecipesByDish(Iterable<Recipe> recipes) {
  final groups = <String, List<Recipe>>{};
  final displayNames = <String, String>{};
  final all = recipes.toList(growable: false);

  for (final recipe in all) {
    final name = recipe.dish.trim().isEmpty ? 'Recipes' : recipe.dish.trim();
    final key = name.toLowerCase();
    // Keep the first spelling that was seen, so "Biryani" and "biryani"
    // merge without the display name flipping to whichever came last.
    displayNames.putIfAbsent(key, () => name);
    groups.putIfAbsent(key, () => []).add(recipe);
  }

  // One global mean for every dish, so two cards compare like for like.
  final mean = globalMeanRating(all);

  final result = groups.entries.map((entry) {
    return DishGroup(
      name: displayNames[entry.key]!,
      recipes: rankRecipes(entry.value, globalMean: mean),
    );
  }).toList();

  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}
