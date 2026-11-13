// ============================================================
//  ai_draft_banner.dart - explains what the AI draft filled in
//
//  Owns: the review banner shown when the form was opened from an AI
//  draft. It never saves anything.
// ============================================================

import 'package:flutter/material.dart';

import '../../theme.dart';

class AiDraftBanner extends StatelessWidget {
  const AiDraftBanner({
    super.key,
    required this.message,
    required this.inferredFields,
    required this.followUpQuestions,
  });

  final String message;
  final List<String> inferredFields;
  final List<String> followUpQuestions;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.all(TasteHubSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.accent.withValues(alpha: 0.1),
            colors.gold.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: TasteHubRadii.cardBorder,
        border: Border.all(color: colors.accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: colors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI draft - review before saving',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (inferredFields.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final field in inferredFields)
                  Chip(
                    label: Text('AI filled: $field'),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: colors.card,
                    side: BorderSide(
                      color: colors.accent.withValues(alpha: 0.25),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (followUpQuestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Worth checking:',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: colors.muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            for (final question in followUpQuestions)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '- $question',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
