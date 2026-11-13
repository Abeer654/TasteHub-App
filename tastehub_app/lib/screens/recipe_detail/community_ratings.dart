// ============================================================
//  community_ratings.dart - other people's ratings
//
//  Owns: the "Other ratings" card. Your own rating is filtered out here
//  because it already has a dedicated card above; that keeps your rating
//  photo visible exactly once.
// ============================================================

import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme.dart';
import '../../widgets/proof_thumbnail.dart';
import '../../widgets/rating_stars.dart';
import '../../widgets/section_card.dart';

class CommunityRatingsCard extends StatelessWidget {
  const CommunityRatingsCard({
    super.key,
    required this.ratings,
    required this.currentUserId,
    required this.resolveMediaUrl,
    required this.onOpenPhoto,
  });

  final List<Rating> ratings;
  final int currentUserId;
  final String Function(String) resolveMediaUrl;
  final ValueChanged<String> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    final others = ratings
        .where((rating) => rating.userId != currentUserId)
        .toList(growable: false);
    if (others.isEmpty) return const SizedBox.shrink();

    final colors = context.tasteHubColors;

    return SectionCard(
      title: 'Other ratings',
      icon: Icons.people_outline_rounded,
      subtitle:
          '${others.length} other cook${others.length == 1 ? '' : 's'} rated this',
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        children: [
          for (var i = 0; i < others.length; i++) ...[
            if (i > 0) Divider(color: colors.line),
            _RatingRow(
              rating: others[i],
              resolveMediaUrl: resolveMediaUrl,
              onOpenPhoto: onOpenPhoto,
            ),
          ],
        ],
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.rating,
    required this.resolveMediaUrl,
    required this.onOpenPhoto,
  });

  final Rating rating;
  final String Function(String) resolveMediaUrl;
  final ValueChanged<String> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final name = rating.userName.isEmpty
        ? 'User ${rating.userId}'
        : rating.userName;
    final proofUrl = resolveMediaUrl(rating.proofImageRef);
    final canOpenProof =
        proofUrl.startsWith('http://') || proofUrl.startsWith('https://');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: colors.accent.withValues(alpha: 0.1),
            child: Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colors.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          RatingStars(value: rating.stars.toDouble(), size: 15),
          const SizedBox(width: 7),
          Text(
            '${rating.stars}/5',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
          ),
          if (rating.proofImageRef.isNotEmpty) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: canOpenProof ? 'Open rating photo' : 'Rating photo',
              child: InkWell(
                onTap: canOpenProof ? () => onOpenPhoto(proofUrl) : null,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: ProofThumbnail(imageUrl: proofUrl, size: 32),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
