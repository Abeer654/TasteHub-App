// ============================================================
//  basics_fields.dart - title, dish, ingredient, time and YouTube fields
//
//  Owns: the "Recipe details" form fields and their validation. The photo
//  picker is a separate section; the save button lives in the sticky bar.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';

class RecipeBasicsFields extends StatelessWidget {
  const RecipeBasicsFields({
    super.key,
    required this.title,
    required this.dish,
    required this.mainIngredient,
    required this.cookingTime,
    required this.youtubeUrl,
    required this.isEditing,
    required this.enabled,
  });

  final TextEditingController title;
  final TextEditingController dish;
  final TextEditingController mainIngredient;
  final TextEditingController cookingTime;
  final TextEditingController youtubeUrl;
  final bool isEditing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: title,
          enabled: enabled,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Recipe title *',
            hintText: 'Chicken Biryani',
          ),
          validator: (value) {
            if ((value ?? '').trim().isEmpty) {
              return 'Give the recipe a title.';
            }
            return null;
          },
        ),
        const SizedBox(height: TasteHubSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 620;
            final dishField = TextFormField(
              controller: dish,
              enabled: enabled,
              readOnly: isEditing,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Dish',
                hintText: 'Biryani',
                helperText: isEditing
                    ? 'The dish cannot change after creation.'
                    : 'Recipes with the same dish are ranked together.',
              ),
            );
            final ingredientField = TextFormField(
              controller: mainIngredient,
              enabled: enabled,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Main ingredient',
                hintText: 'rice',
              ),
            );

            if (!wide) {
              return Column(
                children: [
                  dishField,
                  const SizedBox(height: TasteHubSpacing.md),
                  ingredientField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: dishField),
                const SizedBox(width: TasteHubSpacing.md),
                Expanded(child: ingredientField),
              ],
            );
          },
        ),
        const SizedBox(height: TasteHubSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final timeField = TextFormField(
              controller: cookingTime,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Cooking time (minutes)',
                hintText: '60',
                prefixIcon: Icon(Icons.schedule_rounded, size: 19),
              ),
            );
            final youtubeField = TextFormField(
              controller: youtubeUrl,
              enabled: enabled,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'YouTube URL (optional)',
                hintText: 'https://www.youtube.com/...',
                prefixIcon: Icon(Icons.smart_display_outlined, size: 19),
              ),
            );

            if (constraints.maxWidth < 620) {
              return Column(
                children: [
                  timeField,
                  const SizedBox(height: TasteHubSpacing.md),
                  youtubeField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 240, child: timeField),
                const SizedBox(width: TasteHubSpacing.md),
                Expanded(child: youtubeField),
              ],
            );
          },
        ),
      ],
    );
  }
}
