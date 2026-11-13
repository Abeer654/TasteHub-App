// ============================================================
//  recipe_overview.dart - the recipe's quick facts
//
//  Owns: owner, cooking time, main ingredient and community rating chips.
//  This is a read-only strip between the hero and the recipe content.
// ============================================================

import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme.dart';
import '../../widgets/rating_stars.dart';

class RecipeOverview extends StatelessWidget {
  const RecipeOverview({super.key, required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final time = recipe.cookingTime > 0
        ? '${recipe.cookingTime} min'
        : 'No time set';
    final ingredient = recipe.mainIngredient.isEmpty
        ? 'Ingredient not set'
        : recipe.mainIngredient;

    return Wrap(
      spacing: TasteHubSpacing.sm,
      runSpacing: TasteHubSpacing.sm,
      children: [
        _MetaChip(
          icon: Icons.person_outline_rounded,
          label: recipe.ownerName.isEmpty ? 'Unknown cook' : recipe.ownerName,
        ),
        _MetaChip(icon: Icons.schedule_rounded, label: time),
        _MetaChip(icon: Icons.egg_alt_outlined, label: ingredient),
        _RatingChip(recipe: recipe),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colors.goldWash,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RatingStars(
            value: recipe.averageRating,
            size: 14,
            color: colors.gold,
          ),
          const SizedBox(width: 7),
          Text(
            recipe.ratingCount == 0
                ? 'No ratings yet'
                : '${recipe.averageRating.toStringAsFixed(1)} from '
                      '${recipe.ratingCount} rating'
                      '${recipe.ratingCount == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.ink, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
