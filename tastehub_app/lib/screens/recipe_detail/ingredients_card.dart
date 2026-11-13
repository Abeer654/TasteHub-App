// ============================================================
//  ingredients_card.dart - the ingredient checklist
//
//  Owns: rendering the recipe's ingredient list. Safe to change without
//  touching the hero, rating or form code.
// ============================================================

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/section_card.dart';

class IngredientsCard extends StatelessWidget {
  const IngredientsCard({super.key, required this.ingredients});

  final List<String> ingredients;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return SectionCard(
      title: 'Ingredients',
      icon: Icons.shopping_basket_outlined,
      subtitle:
          '${ingredients.length} item${ingredients.length == 1 ? '' : 's'}',
      child: Column(
        children: [
          for (var i = 0; i < ingredients.length; i++) ...[
            if (i > 0) Divider(color: colors.line.withValues(alpha: 0.7)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      ingredients[i],
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
