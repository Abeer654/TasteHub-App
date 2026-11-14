// ============================================================
//  recipe_thumbnail.dart - network image with a graceful fallback
//
//  Pass an already-resolved URL (ApiClient.resolveMediaUrl). Empty
//  references and broken loads show a stable warm gradient with the
//  recipe's first letter, which is what seed recipes use until a user
//  uploads a photo or adds an image URL.
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
  });

  final String imageRef;
  final String dish;
  final String title;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  /// When set, a failed network image shows this message instead of the
  /// letter placeholder. Small thumbnails leave it null to stay compact.
  final String? errorMessage;

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
    final initial = title.trim().isNotEmpty
        ? title.trim().characters.first.toUpperCase()
        : 'T';

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
                : Text(
                    initial,
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.72),
                      height: 1,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
