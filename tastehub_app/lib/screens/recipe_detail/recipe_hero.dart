// ============================================================
//  recipe_hero.dart - the large recipe photo on the detail screen
//
//  Owns: the hero image, the dish/title overlay and the empty-photo state.
//  When the recipe has no main photo, the owner gets a direct "Add photo"
//  shortcut into the edit form (scrolling to the photo field there).
//  A null callback dims the shortcut while the screen is busy, instead of
//  silently doing nothing. Rating photos never appear here.
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

  /// Null while a rating or delete is in flight; the button then shows as
  /// disabled rather than swallowing the tap.
  final VoidCallback? onAddPhoto;

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
                  width: constraints.maxWidth,
                  height: height,
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
                // Exactly one add-photo control: a centred button instead of
                // the old corner pill plus an "add one above" caption.
                if (!hasPhoto && canEdit)
                  Positioned.fill(
                    child: Align(
                      alignment: const Alignment(0, -0.35),
                      child: Opacity(
                        opacity: onAddPhoto == null ? 0.55 : 1,
                        child: FilledButton.tonalIcon(
                          onPressed: onAddPhoto,
                          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                          label: const Text('Add a photo'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.92,
                            ),
                            foregroundColor: const Color(0xFF2D241C),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
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
                      if (!hasPhoto && !canEdit) ...[
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
                                'No recipe photo yet',
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
