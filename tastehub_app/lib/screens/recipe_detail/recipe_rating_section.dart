// ============================================================
//  recipe_rating_section.dart - your rating and rating photo
//
//  Owns: the compact "Your rating" card. The star row saves a rating
//  directly; "Add rating photo" opens the separate rating-photo dialog.
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
    required this.onRate,
    required this.onEditPhoto,
    required this.onOpenPhoto,
    required this.resolveMediaUrl,
  });

  final Recipe recipe;
  final bool busy;
  final ValueChanged<int> onRate;
  final VoidCallback onEditPhoto;
  final ValueChanged<String> onOpenPhoto;
  final String Function(String) resolveMediaUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
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
              final community = _CommunitySummary(recipe: recipe);
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

class _CommunitySummary extends StatelessWidget {
  const _CommunitySummary({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    if (recipe.ratingCount == 0) {
      return Row(
        children: [
          Icon(Icons.people_outline_rounded, size: 16, color: colors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'No community ratings yet - yours could be the first.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        RatingStars(value: recipe.averageRating, size: 16),
        Text(
          '${recipe.averageRating.toStringAsFixed(1)} average · '
          '${recipe.ratingCount} rating${recipe.ratingCount == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
        ),
      ],
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
