// ============================================================
//  proof_thumbnail.dart - a small rating-photo thumbnail
//
//  Owns: rendering a rating photo (not the recipe photo) with a stable
//  fallback for empty or broken URLs. Used beside "Your rating" and in the
//  community ratings list.
// ============================================================

import 'package:flutter/material.dart';

import '../theme.dart';

class ProofThumbnail extends StatelessWidget {
  const ProofThumbnail({
    super.key,
    required this.imageUrl,
    this.size = 42,
    this.borderRadius = 10,
  });

  /// Already resolved with ApiClient.resolveMediaUrl.
  final String imageUrl;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: colors.line),
      ),
      child: Icon(
        Icons.photo_library_outlined,
        size: size * 0.42,
        color: colors.muted,
      ),
    );

    if (imageUrl.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}
