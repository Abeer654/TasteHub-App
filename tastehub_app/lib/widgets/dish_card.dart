// ============================================================
//  dish_card.dart - one dish on the home screen
//
//  A dish is a group of recipes. The card shows the current top
//  recipe's photo, the dish name, how many recipes it has and its
//  best rating.
// ============================================================

import 'package:flutter/material.dart';

import '../models/dish_group.dart';
import '../theme.dart';
import 'recipe_thumbnail.dart';
import 'rating_stars.dart';

class DishCard extends StatelessWidget {
  const DishCard({
    super.key,
    required this.group,
    required this.resolveImage,
    required this.onTap,
  });

  final DishGroup group;
  final String Function(String) resolveImage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final top = group.topRecipe;
    final topIsRated = top != null && top.isRated;

    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.line),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                RecipeThumbnail(
                  imageRef: top == null ? '' : resolveImage(top.imageRef),
                  dish: group.name,
                  title: group.name,
                  height: 152,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.card.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${group.recipeCount} recipe${group.recipeCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (!topIsRated)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.success.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'New',
                        style: TextStyle(
                          color: colors.onAccent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      topIsRated
                          ? 'Top: ${top.title}'
                          : 'No ratings yet - be the first',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.muted),
                    ),
                    const Spacer(),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        RatingStars(
                          value: topIsRated ? top.averageRating : 0,
                          size: 16,
                        ),
                        const SizedBox(width: 7),
                        RatingLabel(
                          averageRating: topIsRated ? top.averageRating : 0,
                          ratingCount: topIsRated ? top.ratingCount : 0,
                          notRatedText: 'New dish',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
