// ============================================================
//  step_editor.dart - editable numbered cooking steps
//
//  Owns: the step inputs and their add/remove controls. The parent screen
//  owns the controller list and the dirty-state flag.
// ============================================================

import 'package:flutter/material.dart';

import '../../theme.dart';

class StepEditor extends StatelessWidget {
  const StepEditor({
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
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
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
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: controllers[i],
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: i == 0
                          ? 'Describe the first step...'
                          : 'Describe step ${i + 1}...',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: enabled ? () => onRemove(i) : null,
                  tooltip: 'Remove step ${i + 1}',
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
            label: const Text('Add step'),
          ),
        ),
      ],
    );
  }
}
