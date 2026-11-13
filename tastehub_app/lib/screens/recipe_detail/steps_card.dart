// ============================================================
//  steps_card.dart - the numbered cooking steps
//
//  Owns: the step list and its numbered markers. Safe to change without
//  touching ingredients, ratings or the hero.
// ============================================================

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/section_card.dart';

class StepsCard extends StatelessWidget {
  const StepsCard({super.key, required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return SectionCard(
      title: 'Cooking steps',
      icon: Icons.local_fire_department_outlined,
      subtitle: '${steps.length} step${steps.length == 1 ? '' : 's'}',
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? 0 : TasteHubSpacing.md,
                bottom: TasteHubSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        steps[i],
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
