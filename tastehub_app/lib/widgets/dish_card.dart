// ============================================================
//  dish_card.dart - one dish on the home screen
//
//  Owns: the dish grid card. During a search it reveals the matching
//  recipe names instead of only the top recipe, so a dish with several
//  matches is not reduced to one title.
// ============================================================

import 'package:flutter/material.dart';

import '../models/dish_group.dart';
import '../theme.dart';
import 'rating_stars.dart';
import 'recipe_thumbnail.dart';

class DishCard extends StatelessWidget {
  const DishCard({
    super.key,
    required this.group,
    required this.resolveMediaUrl,
    required this.onTap,
    this.searchQuery = '',
  });

  final DishGroup group;
  final String Function(String) resolveMediaUrl;
  final VoidCallback onTap;

  /// The active search text, or an empty string on the normal dish grid.
  final String searchQuery;

  bool get _isSearch => searchQuery.trim().isNotEmpty;

  String get _subtitle {
    final top = group.topRecipe;

    if (_isSearch) {
      final titles = group.recipes.map((recipe) => recipe.title).toList();
      if (titles.length == 1) return 'Match: ${titles.first}';
      final shown = titles.take(2).join(', ');
      final extra = titles.length > 2 ? ' +${titles.length - 2} more' : '';
      return '${titles.length} matches: $shown$extra';
    }

    if (top == null) return 'No recipes yet';
    if (top.isRated) return 'Best: ${top.title}';
    return 'No ratings yet - be the first to rate';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final top = group.topRecipe;
    final topIsRated = top != null && top.isRated;

    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: TasteHubRadii.cardBorder,
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
                  imageRef: top == null ? '' : resolveMediaUrl(top.imageRef),
                  dish: group.name,
                  title: group.name,
                  height: 152,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _Pill(
                    color: colors.card.withValues(alpha: 0.92),
                    child: Text(
                      '${group.recipeCount} recipe'
                      '${group.recipeCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: _Pill(
                    color: topIsRated
                        ? colors.goldWash.withValues(alpha: 0.94)
                        : colors.success.withValues(alpha: 0.92),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (topIsRated) ...[
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 13,
                            color: colors.gold,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          topIsRated ? 'Top pick' : 'New',
                          style: TextStyle(
                            color: topIsRated ? colors.gold : colors.onAccent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  TasteHubSpacing.lg,
                  TasteHubSpacing.md,
                  TasteHubSpacing.lg,
                  TasteHubSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: TasteHubSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isSearch) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.search_rounded,
                              size: 14,
                              color: colors.accent,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            _subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _isSearch
                                      ? colors.accent
                                      : colors.muted,
                                  fontWeight: _isSearch
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const SizedBox(height: TasteHubSpacing.sm),
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

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }
}
