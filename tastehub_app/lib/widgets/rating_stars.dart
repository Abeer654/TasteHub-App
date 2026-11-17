// ============================================================
//  rating_stars.dart - read-only stars, compact card ratings and the
//  tap-to-rate picker
//
//  G-05 rule: detail screens may draw the full five-star row; cards use
//  CompactRating (one star + "4.5 (2)") and unrated recipes show the
//  outlined "New" chip. Five empty stars appear nowhere.
// ============================================================

import 'package:flutter/material.dart';

import '../theme.dart';

class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.value,
    this.size = 17,
    this.color,
  });

  final double value;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final starColor = color ?? context.tasteHubColors.gold;

    // One labelled node reads better than five unlabelled star icons.
    return Semantics(
      label: value > 0
          ? 'Rated ${value.toStringAsFixed(1)} out of 5 stars'
          : 'No rating yet',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (index) {
          final threshold = index + 1;
          final IconData icon;
          if (value >= threshold) {
            icon = Icons.star_rounded;
          } else if (value >= threshold - 0.5) {
            icon = Icons.star_half_rounded;
          } else {
            icon = Icons.star_outline_rounded;
          }

          return Icon(icon, size: size, color: starColor);
        }),
      ),
    );
  }
}

class StarPicker extends StatelessWidget {
  const StarPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 36,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final stars = index + 1;
        final selected = stars <= value;

        return IconButton(
          key: ValueKey('star-$stars'),
          onPressed: () => onChanged(stars),
          tooltip: 'Rate $stars out of 5',
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: size + 4,
            height: size + 4,
          ),
          icon: Icon(
            selected ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: selected
                ? colors.gold
                : colors.muted.withValues(alpha: 0.55),
          ),
        );
      }),
    );
  }
}

/// M-03: outlined "New" pill for a recipe nobody has rated yet.
///
/// Replaces the five empty stars a card used to draw - an empty star row
/// carries no information (design principle 1).
class NewRatingChip extends StatelessWidget {
  const NewRatingChip({super.key, this.label = 'New'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Semantics(
      label: 'Not rated yet',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.accentOnDark),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.accentOnDark,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// G-05: what cards show instead of a five-star row - one star plus
/// `4.5 (2)`, or the [NewRatingChip] when nothing has rated yet.
class CompactRating extends StatelessWidget {
  const CompactRating({
    super.key,
    required this.averageRating,
    required this.ratingCount,
    this.size = 14,
  });

  final double averageRating;
  final int ratingCount;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    if (ratingCount == 0) return const NewRatingChip();

    return Semantics(
      label: 'Rated ${averageRating.toStringAsFixed(1)} out of 5 from '
          '$ratingCount rating${ratingCount == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: size + 3, color: colors.gold),
          const SizedBox(width: 4),
          Text(
            '${averageRating.toStringAsFixed(1)} ($ratingCount)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w600,
              fontSize: size,
            ),
          ),
        ],
      ),
    );
  }
}
