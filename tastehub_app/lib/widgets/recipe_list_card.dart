// ============================================================
//  recipe_list_card.dart - one recipe row, shared by dish and home
//
//  Owns: thumbnail, optional rank badge, title, the meta line and the
//  compact rating. DishScreen passes a rank and keeps the auto height
//  its badge row needs; My recipes uses the fixed 88dp layout from M-02
//  with a ⋮ overflow menu instead of a chevron.
//
//  Meta line, by [RecipeMeta]:
//    owner    "by junaid · 60 min"   (the dish header already names it)
//    sectioned "60 min · rice"       (My recipes, grouped - the section
//                                     header names the dish)
//    listed   "Fries · 60 min"       (My recipes, flat/recent)
//
//  During a search (searchQuery set) the meta line is replaced by the
//  match reason, mirroring what dish_card.dart does for the dish grid.
// ============================================================

import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme.dart';
import '../utils/ranking.dart';
import 'rating_stars.dart';
import 'recipe_thumbnail.dart';

/// What the card's second line says - see the file header.
enum RecipeMeta { owner, sectioned, listed }

class RecipeListCard extends StatelessWidget {
  const RecipeListCard({
    super.key,
    required this.recipe,
    required this.imageUrl,
    required this.onTap,
    this.rank,
    this.meta = RecipeMeta.owner,
    this.searchQuery = '',
    this.onEdit,
    this.onAddPhoto,
    this.onDelete,
  });

  final Recipe recipe;
  final String imageUrl;
  final VoidCallback onTap;

  /// Position inside a ranked dish list. Null on the home screen, where
  /// the card keeps the fixed 88dp height from M-02.
  final int? rank;

  /// Which meta line to render.
  final RecipeMeta meta;

  /// The active search text, or an empty string on the normal lists.
  final String searchQuery;

  /// M-02: the fixed height of an unranked (My recipes) row.
  static const double height = 88;

  /// Optional ⋮ actions. Every action the card is given shows up in the
  /// menu; a card with none renders no trailing button at all.
  final VoidCallback? onEdit;
  final VoidCallback? onAddPhoto;
  final VoidCallback? onDelete;

  bool get _isSearch => searchQuery.trim().isNotEmpty;

  bool get _hasActions =>
      onEdit != null || onAddPhoto != null || onDelete != null;

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

  String get _time => recipe.cookingTime > 0
      ? '${recipe.cookingTime} min'
      : 'Time not set';

  String get _dish => recipe.dish.trim().isEmpty
      ? 'Recipes'
      : recipe.dish.trim();

  String get _meta {
    switch (meta) {
      case RecipeMeta.owner:
        final owner = recipe.ownerName.isEmpty
            ? 'unknown'
            : recipe.ownerName;
        return 'by $owner \u00b7 $_time';
      case RecipeMeta.sectioned:
        final ingredient = recipe.mainIngredient.trim();
        return ingredient.isEmpty ? _time : '$_time \u00b7 $ingredient';
      case RecipeMeta.listed:
        return '$_dish \u00b7 $_time';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final isTop = rank == 1;
    final showBadge = rank != null && rank! > 0;

    // Only the unranked (My recipes) list has a fixed height; the dish
    // list's badge row needs the extra line.
    final height = rank == null ? RecipeListCard.height : null;

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
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              // The fixed 88dp card stretches so the thumbnail and text
              // fill it; the dish list's badge card has no set height, so
              // it centres instead - stretching there would ask the row
              // for an infinite height.
              crossAxisAlignment:
                  height == null
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 72,
                  child: RecipeThumbnail(
                    imageRef: imageUrl,
                    dish: recipe.dish,
                    title: recipe.title,
                    width: 72,
                    height: 72,
                    borderRadius: BorderRadius.circular(12),
                    // M-05: list thumbnails use the smaller 32dp icon.
                    iconSize: 32,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _content(context, showBadge: showBadge, isTop: isTop)),
                if (_hasActions) ...[
                  const SizedBox(width: 4),
                  _overflowMenu(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context, {
    required bool showBadge,
    required bool isTop,
  }) {
    final colors = context.tasteHubColors;

    // Fixed-height rows need tighter leading than the theme default.
    final metaStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.25,
      letterSpacing: 0,
      color: colors.muted,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showBadge) ...[
          Wrap(
            spacing: 7,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RankBadge(rank: rank!, isTop: isTop),
              // H-01: "#1" is a fact, "Top pick" has to be earned - the
              // same rule the dish card uses.
              if (isTop && earnsTopPick(recipe))
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
          const SizedBox(height: 4),
        ],
        Text(
          recipe.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 18,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        if (_isSearch)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.search_rounded,
                size: 14,
                color: colors.accentOnDark,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _matchLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle?.copyWith(
                    color: colors.accentOnDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          )
        else
          Text(
            _meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: metaStyle,
          ),
        const SizedBox(height: 4),
        // G-05: compact rating, or the "New" chip - never a row of five
        // empty stars.
        CompactRating(
          averageRating: recipe.averageRating,
          ratingCount: recipe.ratingCount,
        ),
      ],
    );
  }

  Widget _overflowMenu(BuildContext context) {
    final colors = context.tasteHubColors;

    return PopupMenuButton<String>(
      tooltip: 'More options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(Icons.more_vert_rounded, color: colors.muted, size: 22),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit?.call();
          case 'photo':
            onAddPhoto?.call();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        if (onEdit != null)
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (onAddPhoto != null)
          const PopupMenuItem(value: 'photo', child: Text('Add photo')),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: colors.error)),
          ),
      ],
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
        '#$rank',
        style: TextStyle(
          color: isTop ? colors.gold : colors.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
