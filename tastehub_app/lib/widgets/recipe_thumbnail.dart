// ============================================================
//  recipe_thumbnail.dart - network image with a graceful fallback
//
//  Pass an already-resolved URL (ApiClient.resolveMediaUrl). Empty
//  references and broken loads show a stable warm gradient with a food
//  icon chosen from the dish name (H-06/M-05) - seed recipes use this
//  until a user uploads a photo or adds an image URL. No placeholder
//  shows a letter any more.
// ============================================================

import 'package:flutter/material.dart';

const List<List<Color>> _palettes = [
  [Color(0xFFB65A36), Color(0xFFE0A15A)],
  [Color(0xFF5B7B4B), Color(0xFFA9BE7A)],
  [Color(0xFF8B4A5E), Color(0xFFD5909A)],
  [Color(0xFF3F6A72), Color(0xFF7FB0B3)],
  [Color(0xFF9A6B2F), Color(0xFFD8B36A)],
  [Color(0xFF6B4E7A), Color(0xFFAD8FBC)],
];

/// H-06: dish name → food icon, matched on substrings so "Chicken Biryani"
/// and "Fried Fish" both land on the right one. Anything unrecognised falls
/// back to generic cutlery, never to a letter.
IconData dishIconFor(String dish) {
  final name = dish.toLowerCase();

  bool hasAny(List<String> words) => words.any(name.contains);

  if (hasAny(const [
    'biryani',
    'pulao',
    'rice',
    'risotto',
    'paella',
    'fried rice',
  ])) {
    return Icons.rice_bowl_rounded;
  }
  if (hasAny(const ['fish', 'prawn', 'shrimp', 'salmon', 'seafood'])) {
    return Icons.set_meal_rounded;
  }
  if (hasAny(const ['fries', 'burger', 'fastfood', 'fast food', 'nugget'])) {
    return Icons.fastfood_rounded;
  }
  if (hasAny(const ['noodle', 'ramen', 'pasta', 'spaghetti', 'chow'])) {
    return Icons.ramen_dining_rounded;
  }
  if (hasAny(const ['pizza'])) return Icons.local_pizza_rounded;
  if (hasAny(const [
    'cake',
    'dessert',
    'sweet',
    'ice cream',
    'icecream',
    'donut',
    'kheer',
  ])) {
    return Icons.cake_rounded;
  }
  if (hasAny(const ['egg', 'breakfast', 'pancake', 'toast'])) {
    return Icons.free_breakfast_rounded;
  }
  if (hasAny(const [
    'kebab',
    'kabab',
    'tikka',
    'chicken',
    'mutton',
    'beef',
    'karahi',
    'korma',
    'curry',
    'steak',
    'grill',
    'meat',
  ])) {
    return Icons.lunch_dining_rounded;
  }
  if (hasAny(const ['soup', 'stew', 'dal', 'daal', 'shorba'])) {
    return Icons.ramen_dining_rounded;
  }

  return Icons.restaurant_rounded;
}

class RecipeThumbnail extends StatelessWidget {
  const RecipeThumbnail({
    super.key,
    required this.imageRef,
    required this.dish,
    required this.title,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    this.errorMessage,
    this.iconSize = 48,
  });

  final String imageRef;
  final String dish;
  final String title;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  /// When set, a failed network image shows this message instead of the
  /// placeholder icon. Small thumbnails leave it null to stay compact.
  final String? errorMessage;

  /// Placeholder food icon size: 48dp on heroes and cards (H-06),
  /// 32dp in list thumbnails (M-05).
  final double iconSize;

  bool get _isNetworkImage =>
      imageRef.startsWith('http://') || imageRef.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    // Decode near the on-screen size: lists would otherwise hold full-size
    // uploads in memory. Only one dimension is set so the aspect ratio is
    // preserved; an unsized widget (nothing to scale for) decodes as-is.
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final int? cacheWidth = width != null
        ? (width! * pixelRatio).round()
        : null;
    final int? cacheHeight = width == null && height != null
        ? (height! * pixelRatio).round()
        : null;

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: _isNetworkImage
            ? Image.network(
                imageRef,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(broken: true),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _placeholder();
                },
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder({bool broken = false}) {
    final seed = (dish.isNotEmpty ? dish : title).codeUnits.fold<int>(
      0,
      (total, unit) => total + unit,
    );
    final palette = _palettes[seed % _palettes.length];
    final icon = dishIconFor(dish.isNotEmpty ? dish : title);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palette,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -18,
            bottom: -26,
            child: Icon(
              Icons.restaurant_menu_rounded,
              size: 150,
              color: Colors.white.withValues(alpha: 0.13),
            ),
          ),
          Center(
            child: broken && errorMessage != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          size: 44,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : Icon(
                    icon,
                    size: iconSize,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
          ),
        ],
      ),
    );
  }
}
