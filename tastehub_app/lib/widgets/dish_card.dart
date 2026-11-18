// ============================================================
//  dish_card.dart - one dish on the home screen
//
//  Owns: the dish grid card. One layout for every width (H-05): a
//  112dp card with a square photo on the left and a text column on the
//  right. The old tall banner / compact row split is gone - a forced
//  single column just gets narrower cards, never a different shape.
//
//  The card shows, top to bottom: dish name, "N recipes · time range",
//  the "Best: <recipe>" line (or the search matches), and a compact
//  rating. The earned "Top pick"/"New" badge sits 8dp inside the photo's
//  top-left corner.
// ============================================================

import 'package:flutter/material.dart';

import '../models/dish_group.dart';
import '../models/recipe.dart';
import '../theme.dart';
import '../utils/ranking.dart';
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

  /// Fixed card height from H-05.
  static const double height = 112;

  /// Side of the square photo: card height minus the 8dp inset on the
  /// top and bottom edges, so the card's border never touches it.
  static const double photoSize = height - 16;

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
    return 'No ratings yet';
  }

  /// `60 min`, `20-40 min`, or null when no recipe in the dish has a time.
  String? get _timeRange {
    final times =
        group.recipes
            .map((recipe) => recipe.cookingTime)
            .where((time) => time > 0)
            .toList()
          ..sort();

    if (times.isEmpty) return null;
    final min = times.first;
    final max = times.last;
    return min == max ? '$min min' : '$min\u2013$max min';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final top = group.topRecipe;

    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: TasteHubRadii.cardBorder,
        side: BorderSide(color: colors.line),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            // H-05: 8dp to the photo, 12dp gap to the text column. The
            // photo gets its 8dp top/bottom inset from the vertical
            // padding below, so the card's rounded border and 20dp corner
            // stop at the photo instead of cutting across the square
            // image (the border used to run along the photo's top and
            // bottom edges and shave its left corners).
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    // Square photo inside the 112dp card: 112 - 2 * 8.
                    width: photoSize,
                    child: Stack(
                      children: [
                        RecipeThumbnail(
                          imageRef: top == null
                              ? ''
                              : resolveMediaUrl(top.imageRef),
                          dish: group.name,
                          title: group.name,
                          width: photoSize,
                          height: photoSize,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _statusPill(colors: colors, top: top),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _content(context, top: top)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The three text rows plus the rating row, distributed from the top
  /// with the rating anchored 12dp above the card's bottom edge.
  Widget _content(BuildContext context, {required Recipe? top}) {
    final colors = context.tasteHubColors;
    final averageRating = top?.isRated == true ? top!.averageRating : 0.0;
    final ratingCount = top?.isRated == true ? top!.ratingCount : 0;
    final count =
        '${group.recipeCount} recipe${group.recipeCount == 1 ? '' : 's'}';
    final timeRange = _timeRange;

    // Body copy inside a fixed-height card needs the tighter leading the
    // theme's 1.55 would not leave room for.
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.25,
      letterSpacing: 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          group.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 2),
        Text(
          timeRange == null ? count : '$count \u00b7 $timeRange',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle?.copyWith(color: colors.accentOnDark),
        ),
        const SizedBox(height: 2),
        Text(
          _subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle?.copyWith(
            color: _isSearch ? colors.accentOnDark : colors.muted,
            fontWeight: _isSearch ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const Spacer(),
        CompactRating(
          averageRating: averageRating,
          ratingCount: ratingCount,
          size: 14,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// H-01: "Top pick" only when the dish's best recipe earned it
  /// (`v >= 2` and `R >= 4.5`); an unrated dish keeps its "New" pill;
  /// everything else gets no badge at all.
  Widget _statusPill({required TasteHubColors colors, required Recipe? top}) {
    final qualifies = earnsTopPick(top);

    // No recipes, or a real rating that does not clear the bar: a badge
    // that appears on every card means nothing (design principle 1).
    if (top == null || (top.isRated && !qualifies)) {
      return const SizedBox.shrink();
    }

    return _Pill(
      color: qualifies
          ? colors.goldWash.withValues(alpha: 0.94)
          : colors.success.withValues(alpha: 0.92),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (qualifies) ...[
            Icon(Icons.workspace_premium_rounded, size: 13, color: colors.gold),
            const SizedBox(width: 4),
          ],
          Text(
            qualifies ? 'Top pick' : 'New',
            style: TextStyle(
              color: qualifies ? colors.gold : colors.onAccent,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }
}
