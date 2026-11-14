// ============================================================
//  recipe_list_card.dart - one recipe row, shared by dish and home
//
//  Owns: thumbnail, optional rank badge, title, dish/owner/time line and
//  the rating summary. DishScreen passes a rank; My recipes passes none,
//  so the row shows the dish name instead of a rank.
//
//  During a search (searchQuery set) the row also reveals why it matched,
//  mirroring what dish_card.dart does for the dish grid.
// ============================================================

import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme.dart';
import 'rating_stars.dart';
import 'recipe_thumbnail.dart';

class RecipeListCard extends StatelessWidget {
  const RecipeListCard({
    super.key,
    required this.recipe,
    required this.imageUrl,
    required this.onTap,
    this.rank,
    this.showOwner = true,
    this.searchQuery = '',
  });

  final Recipe recipe;
  final String imageUrl;
  final VoidCallback onTap;

  /// Position inside a ranked dish list. Leave null for unranked lists such
  /// as My recipes; the metadata line then leads with the dish name.
  final int? rank;

  /// Dish lists already name the dish above the rows, so they show the owner.
  /// My recipes hides the owner because it is always you.
  final bool showOwner;

  /// The active search text, or an empty string on the normal lists.
  final String searchQuery;

  bool get _isSearch => searchQuery.trim().isNotEmpty;

  /// Which part of the recipe matched the search, so a bare result row is
  /// not mistaken for a random card. The server search is fuzzy, so a local
  /// miss falls back to naming the query itself.
  String get _matchLabel {
    final query = searchQuery.trim().toLowerCase();

    if (recipe.title.toLowerCase().contains(query)) {
      return 'Match in the title';
    }
    if (recipe.dish.toLowerCase().contains(query)) {
      return 'Match in dish "${recipe.dish}"';
    }
    for (final ingredient in recipe.ingredients) {
      if (ingredient.toLowerCase().contains(query)) {
        return 'Match: ingredient "$ingredient"';
      }
    }
    if (recipe.steps.any((step) => step.toLowerCase().contains(query))) {
      return 'Match in a cooking step';
    }
    if (recipe.ownerName.toLowerCase().contains(query)) {
      return 'Match: owner "${recipe.ownerName}"';
    }
    return 'Match for "${searchQuery.trim()}"';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final isTop = rank == 1;
    final time = recipe.cookingTime > 0
        ? '${recipe.cookingTime} min'
        : 'Time not set';
    final dish = recipe.dish.trim().isEmpty ? 'Recipes' : recipe.dish.trim();

    final meta = <String>[
      if (rank == null) dish,
      if (showOwner)
        'by ${recipe.ownerName.isEmpty ? 'unknown' : recipe.ownerName}',
      time,
    ].join(' · ');

    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isTop ? colors.gold.withValues(alpha: 0.6) : colors.line,
          width: isTop ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(TasteHubSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: RecipeThumbnail(
                  imageRef: imageUrl,
                  dish: recipe.dish,
                  title: recipe.title,
                  width: 92,
                  height: 92,
                ),
              ),
              const SizedBox(width: TasteHubSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rank != null) ...[
                      Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _RankBadge(rank: rank!, isTop: isTop),
                          if (isTop)
                            Text(
                              'Top pick',
                              style: TextStyle(
                                color: colors.gold,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_isSearch) ...[
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 14,
                            color: colors.accent,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _matchLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        RatingStars(value: recipe.averageRating, size: 15),
                        const SizedBox(width: 7),
                        RatingLabel(
                          averageRating: recipe.averageRating,
                          ratingCount: recipe.ratingCount,
                          notRatedText: 'New - not rated',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: colors.muted,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.isTop});

  final int rank;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: isTop ? colors.goldWash : colors.field,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        rank > 0 ? '#$rank' : 'New',
        style: TextStyle(
          color: isTop ? colors.gold : colors.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
