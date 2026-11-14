// ============================================================
//  dish_card.dart - one dish on the home screen
//
//  Owns: the dish grid card. During a search it reveals the matching
//  recipe names instead of only the top recipe, so a dish with several
//  matches is not reduced to one title.
//
//  Two layouts: the 2/3-up grid uses a tall banner card; a forced
//  single column (narrow window) switches to [horizontal], a compact
//  left-thumbnail row like the My recipes list, so the card never
//  stretches into an empty half-width banner.
// ============================================================

import 'package:flutter/material.dart';

import '../models/dish_group.dart';
import '../models/recipe.dart';
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
    this.horizontal = false,
  });

  final DishGroup group;
  final String Function(String) resolveMediaUrl;
  final VoidCallback onTap;

  /// The active search text, or an empty string on the normal dish grid.
  final String searchQuery;

  /// True in the home grid's single-column mode: lay out as a compact
  /// horizontal row instead of a tall banner card.
  final bool horizontal;

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
        child: horizontal
            ? _horizontalBody(context, top: top, topIsRated: topIsRated)
            : _bannerBody(context, top: top, topIsRated: topIsRated),
      ),
    );
  }

  /// Single-column layout: a fixed-width thumbnail on the left and the
  /// summary on the right, so a full-width cell never leaves a tall
  /// banner card half empty. The Top pick/New badge sits on the photo
  /// (like the banner layout) instead of beside the title, which would
  /// squeeze dish names down to a few characters on phone widths.
  Widget _horizontalBody(
    BuildContext context, {
    required Recipe? top,
    required bool topIsRated,
  }) {
    final colors = context.tasteHubColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 104,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RecipeThumbnail(
                imageRef: top == null ? '' : resolveMediaUrl(top.imageRef),
                dish: group.name,
                title: group.name,
                width: 104,
              ),
              Positioned(top: 10, left: 10, child: _countPill(context)),
              Positioned(
                bottom: 10,
                left: 10,
                child: _statusPill(colors: colors, topIsRated: topIsRated),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TasteHubSpacing.lg,
              TasteHubSpacing.md,
              TasteHubSpacing.lg,
              TasteHubSpacing.lg,
            ),
            child: _content(
              context,
              top: top,
              topIsRated: topIsRated,
              showStatusPill: false,
            ),
          ),
        ),
      ],
    );
  }

  /// Grid layout: full-width photo banner over the dish summary.
  Widget _bannerBody(
    BuildContext context, {
    required Recipe? top,
    required bool topIsRated,
  }) {
    final colors = context.tasteHubColors;

    return Column(
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
            Positioned(top: 12, left: 12, child: _countPill(context)),
            Positioned(
              top: 12,
              right: 12,
              child: _statusPill(colors: colors, topIsRated: topIsRated),
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
            child: _content(
              context,
              top: top,
              topIsRated: topIsRated,
              showStatusPill: false,
            ),
          ),
        ),
      ],
    );
  }

  /// Title, subtitle and rating row shared by both layouts. In the
  /// horizontal layout the Top pick/New pill lives on the thumbnail
  /// instead (there is no photo banner, and a pill beside the title
  /// truncates dish names on phone widths).
  Widget _content(
    BuildContext context, {
    required Recipe? top,
    required bool topIsRated,
    required bool showStatusPill,
  }) {
    final colors = context.tasteHubColors;
    final averageRating = topIsRated ? top!.averageRating : 0.0;
    final ratingCount = topIsRated ? top!.ratingCount : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (showStatusPill) ...[
              const SizedBox(width: 8),
              _statusPill(colors: colors, topIsRated: topIsRated),
            ],
          ],
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _isSearch ? colors.accent : colors.muted,
                  fontWeight: _isSearch ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        const SizedBox(height: TasteHubSpacing.sm),
        Row(
          children: [
            RatingStars(value: averageRating, size: 16),
            const SizedBox(width: 7),
            // Scales down instead of overflowing the row when the label
            // is wider than the space left beside the stars (very narrow
            // cards, or large text scaling).
            Flexible(
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: RatingLabel(
                  averageRating: averageRating,
                  ratingCount: ratingCount,
                  notRatedText: 'New dish',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// How many recipes the dish holds, shown over the photo.
  Widget _countPill(BuildContext context) {
    final colors = context.tasteHubColors;

    return _Pill(
      color: colors.card.withValues(alpha: 0.92),
      child: Text(
        '${group.recipeCount} recipe${group.recipeCount == 1 ? '' : 's'}',
        style: TextStyle(
          color: colors.ink,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  /// Top pick (rated) or New (unrated) badge.
  Widget _statusPill({
    required TasteHubColors colors,
    required bool topIsRated,
  }) {
    return _Pill(
      color: topIsRated
          ? colors.goldWash.withValues(alpha: 0.94)
          : colors.success.withValues(alpha: 0.92),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (topIsRated) ...[
            Icon(Icons.workspace_premium_rounded, size: 13, color: colors.gold),
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
