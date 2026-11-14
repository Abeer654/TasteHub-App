// ============================================================
//  rating_stars.dart - read-only stars and the tap-to-rate picker
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

/// Compact "4.5 (2)" style label used beside [RatingStars].
class RatingLabel extends StatelessWidget {
  const RatingLabel({
    super.key,
    required this.averageRating,
    required this.ratingCount,
    this.notRatedText = 'Not rated yet',
  });

  final double averageRating;
  final int ratingCount;
  final String notRatedText;

  @override
  Widget build(BuildContext context) {
    if (ratingCount == 0) {
      return Text(notRatedText, style: Theme.of(context).textTheme.bodySmall);
    }

    return Text(
      '${averageRating.toStringAsFixed(1)} ($ratingCount)',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.tasteHubColors.ink,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
