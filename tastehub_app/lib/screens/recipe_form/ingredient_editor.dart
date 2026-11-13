// ============================================================
//  ingredient_editor.dart - editable ingredient rows
//
//  Owns: the ingredient inputs and their add/remove controls. The parent
//  screen owns the controller list and the dirty-state flag.
// ============================================================

import 'package:flutter/material.dart';

import '../../theme.dart';

class IngredientEditor extends StatelessWidget {
  const IngredientEditor({
    super.key,
    required this.controllers,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final List<TextEditingController> controllers;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Column(
      children: [
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: TasteHubSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controllers[i],
                    enabled: enabled,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'Ingredient ${i + 1}',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 10),
                        child: Icon(
                          Icons.circle,
                          size: 7,
                          color: colors.accent,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: enabled ? () => onRemove(i) : null,
                  tooltip: 'Remove ingredient ${i + 1}',
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add ingredient'),
          ),
        ),
      ],
    );
  }
}
