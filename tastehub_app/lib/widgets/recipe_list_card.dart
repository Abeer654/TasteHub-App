// ============================================================
//  recipe_list_card.dart - one recipe row, shared by dish and home
//
//  Owns: thumbnail, optional rank badge, title, dish/owner/time line and
//  the rating summary. DishScreen passes a rank; My recipes passes none,
//  so the row shows the dish name instead of a rank.
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
