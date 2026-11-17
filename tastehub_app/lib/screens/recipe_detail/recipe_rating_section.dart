// ============================================================
//  recipe_rating_section.dart - your rating and rating photo
//
//  Owns: the compact "Your rating" card. The star row saves a rating
//  directly; "Add rating photo" opens the separate rating-photo dialog.
//
//  R-04: the summary row (stars + "4.5 from 2 ratings") is the handle for
//  the rating-distribution bottom sheet, so both the author and a rater
//  see the same breakdown. Authors still get no rating control at all
//  (D-04), only the numbers.
//
//  Authors cannot rate their own recipe (the API answers 403), so with
//  canRate = false the card drops every rating control and only reports
//  what the community decided.
//
//  Important: this card is the only place your own rating photo appears.
//  It is intentionally different from the recipe's main photo.
// ============================================================

import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme.dart';
import '../../widgets/proof_thumbnail.dart';
import '../../widgets/rating_stars.dart';
import '../../widgets/section_card.dart';

class RecipeRatingSection extends StatelessWidget {
  const RecipeRatingSection({
    super.key,
    required this.recipe,
    required this.busy,
    required this.canRate,
    required this.onRate,
    required this.onEditPhoto,
    required this.onOpenPhoto,
    required this.resolveMediaUrl,
  });

  final Recipe recipe;
  final bool busy;
  final bool canRate;
  final ValueChanged<int> onRate;
  final VoidCallback onEditPhoto;
  final ValueChanged<String> onOpenPhoto;
  final String Function(String) resolveMediaUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    // The author's variant: no star picker, no rating photo - just the
    // community numbers this recipe actually has.
    if (!canRate) {
      return SectionCard(
        title: 'Community rating',
        icon: Icons.people_outline_rounded,
        subtitle: 'You wrote it, so only others can rate it.',
        child: _CommunitySummary(
          recipe: recipe,
          canRate: false,
          onOpen: () => showRatingDistribution(context, recipe),
        ),
      );
    }

    final hasProof = recipe.myRatingProofImageRef.isNotEmpty;
    final ratingPhotoUrl = resolveMediaUrl(recipe.myRatingProofImageRef);

    return SectionCard(
      title: 'Your rating',
      icon: Icons.star_rounded,
      subtitle: 'Saved instantly. You can change it any time.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR STARS',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    recipe.myRating > 0
                        ? 'You rated ${recipe.myRating} out of 5'
                        : 'Tap a star to rate',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              );
              final picker = StarPicker(
                value: recipe.myRating,
                size: 30,
                onChanged: busy ? (_) {} : onRate,
              );

              if (constraints.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: TasteHubSpacing.md),
                    picker,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: TasteHubSpacing.md),
                  picker,
                ],
              );
            },
          ),
          const SizedBox(height: TasteHubSpacing.lg),
          Divider(color: colors.line),
          const SizedBox(height: TasteHubSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final community = _CommunitySummary(
                recipe: recipe,
                canRate: true,
                onOpen: () => showRatingDistribution(context, recipe),
              );
              final button = TextButton.icon(
                onPressed: busy ? null : onEditPhoto,
                icon: Icon(
                  hasProof
                      ? Icons.photo_library_rounded
                      : Icons.add_a_photo_outlined,
                  size: 17,
                ),
                label: Text(
                  hasProof ? 'Change rating photo' : 'Add rating photo',
                ),
              );

              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    community,
                    const SizedBox(height: TasteHubSpacing.sm),
                    button,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: community),
                  const SizedBox(width: TasteHubSpacing.md),
                  button,
                ],
              );
            },
          ),
          const SizedBox(height: TasteHubSpacing.sm),
          if (hasProof)
            _YourRatingPhoto(
              imageUrl: ratingPhotoUrl,
              onEdit: busy ? null : onEditPhoto,
              onOpen: onOpenPhoto,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: colors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'A rating photo is optional. It appears with your rating, '
                    'not as the recipe photo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// R-04: the summary row - five stars plus `4.5 from 2 ratings` - and the
/// entry point to the distribution sheet. Authors get the same row with
/// no rating control anywhere on the card.
class _CommunitySummary extends StatelessWidget {
  const _CommunitySummary({
    required this.recipe,
    required this.canRate,
    required this.onOpen,
  });

  final Recipe recipe;
  final bool canRate;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    final Widget copy;
    if (recipe.ratingCount == 0) {
      copy = Row(
        children: [
          Icon(Icons.people_outline_rounded, size: 16, color: colors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              canRate
                  ? 'No community ratings yet - yours could be the first.'
                  : 'No community ratings yet.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    } else {
      copy = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RatingStars(value: recipe.averageRating, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${recipe.averageRating.toStringAsFixed(1)} from '
              '${recipe.ratingCount} '
              'rating${recipe.ratingCount == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.bar_chart_rounded, size: 15, color: colors.muted),
        ],
      );
    }

    // Tapping the numbers opens the per-star breakdown (R-04). With no
    // ratings the sheet simply says so, so the target stays put.
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: copy,
      ),
    );
  }
}

/// R-04: five rows, 5★ down to 1★, with a bar and a count each.
void showRatingDistribution(BuildContext context, Recipe recipe) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _DistributionSheet(recipe: recipe),
  );
}

class _DistributionSheet extends StatelessWidget {
  const _DistributionSheet({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    // Per-star counts come from the detail payload's ratings list; the
    // summary numbers are what the server computed over the same rows.
    final counts = List<int>.filled(6, 0);
    for (final rating in recipe.ratings) {
      if (rating.stars >= 1 && rating.stars <= 5) counts[rating.stars]++;
    }
    final total = recipe.ratings.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ratings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              recipe.ratingCount == 0
                  ? 'No ratings yet'
                  : '${recipe.averageRating.toStringAsFixed(1)} average · '
                        '${recipe.ratingCount} '
                        'rating${recipe.ratingCount == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            for (var stars = 5; stars >= 1; stars--)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '$stars\u2605',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(
                              color: colors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: SizedBox(
                          height: 9,
                          child: LayoutBuilder(
                            builder: (context, constraints) => Row(
                              children: [
                                Container(
                                  width: total == 0
                                      ? 0
                                      : constraints.maxWidth *
                                            (counts[stars] / total),
                                  color: colors.gold,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${counts[stars]}',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(
                              color: colors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            if (total == 0)
              Text(
                'Be the first to rate this recipe.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _YourRatingPhoto extends StatelessWidget {
  const _YourRatingPhoto({
    required this.imageUrl,
    required this.onEdit,
    required this.onOpen,
  });

  final String imageUrl;
  final VoidCallback? onEdit;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final resolved = imageUrl;
    final canOpen =
        resolved.startsWith('http://') || resolved.startsWith('https://');

    return Container(
      padding: const EdgeInsets.all(TasteHubSpacing.md),
      decoration: BoxDecoration(
        color: colors.field.withValues(alpha: 0.65),
        borderRadius: TasteHubRadii.fieldBorder,
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          ProofThumbnail(imageUrl: resolved, size: 56),
          const SizedBox(width: TasteHubSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your rating photo',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Shown only with your rating - never as the recipe photo.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (canOpen)
                  TextButton.icon(
                    onPressed: () => onOpen(imageUrl),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Open full photo'),
                  ),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Change')),
        ],
      ),
    );
  }
}
