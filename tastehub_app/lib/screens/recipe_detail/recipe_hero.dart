// ============================================================
//  recipe_hero.dart - the large recipe photo on the detail screen
//
//  Owns: the hero image, the dish/title overlay and the empty-photo state.
//  When the recipe has no main photo, the owner gets a direct "Add photo"
//  shortcut into the edit form. Rating photos never appear here.
// ============================================================

import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme.dart';
import '../../widgets/recipe_thumbnail.dart';

class RecipeHero extends StatelessWidget {
  const RecipeHero({
    super.key,
    required this.recipe,
    required this.imageUrl,
    required this.canEdit,
    required this.onAddPhoto,
  });

  final Recipe recipe;
  final String imageUrl;
  final bool canEdit;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = recipe.imageRef.trim().isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final height = compact ? 232.0 : 300.0;

        return ClipRRect(
          borderRadius: TasteHubRadii.heroBorder,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RecipeThumbnail(
                  imageRef: imageUrl,
                  dish: recipe.dish,
                  title: recipe.title,
                  errorMessage: 'Photo link could not load',
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                      stops: const [0.4, 1],
                    ),
                  ),
                ),
                if (!hasPhoto && canEdit)
                  Positioned(
                    top: 14,
                    right: 14,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        onTap: onAddPhoto,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.add_a_photo_outlined,
                                size: 16,
                                color: Color(0xFF2D241C),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Add photo',
                                style: TextStyle(
                                  color: Color(0xFF2D241C),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          recipe.dish.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        recipe.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 27 : 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          height: 1.08,
                        ),
                      ),
                      if (!hasPhoto) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_not_supported_outlined,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                canEdit
                                    ? 'No recipe photo yet - add one above'
                                    : 'No recipe photo yet',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
