// ============================================================
//  save_bar.dart - the sticky add/edit action bar
//
//  Owns: the always-visible save button and the unsaved-changes hint. It is
//  placed in Scaffold.bottomNavigationBar so Save is never buried below a
//  long ingredient or step list.
// ============================================================

import 'package:flutter/material.dart';

import '../../theme.dart';

class RecipeSaveBar extends StatelessWidget {
  const RecipeSaveBar({
    super.key,
    required this.dirty,
    required this.saving,
    required this.uploading,
    required this.isEditing,
    required this.onSave,
    required this.onCancel,
  });

  final bool dirty;
  final bool saving;
  final bool uploading;
  final bool isEditing;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Material(
      color: colors.card,
      elevation: 8,
      shadowColor: colors.ink.withValues(alpha: 0.12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: SafeArea(
          top: false,
          // heightFactor keeps this bar shrink-wrapped. Without it Center
          // expands to the full Scaffold height and the bar covers the page.
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  TasteHubSpacing.xl,
                  TasteHubSpacing.md,
                  TasteHubSpacing.xl,
                  TasteHubSpacing.md,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 560;
                    final saveButton = FilledButton.icon(
                      onPressed: saving || uploading ? null : onSave,
                      icon: saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onAccent,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 19),
                      label: Text(
                        saving
                            ? 'Saving...'
                            : isEditing
                            ? 'Save changes'
                            : 'Save recipe',
                      ),
                    );

                    final hint = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: colors.gold),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            uploading
                                ? 'Uploading photo...'
                                : 'You have unsaved changes',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    );

                    if (compact) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (dirty || uploading) ...[
                            hint,
                            const SizedBox(height: TasteHubSpacing.sm),
                          ],
                          Row(
                            children: [
                              TextButton(
                                onPressed: saving ? null : onCancel,
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: TasteHubSpacing.sm),
                              Expanded(child: saveButton),
                            ],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        if (dirty || uploading)
                          Expanded(child: hint)
                        else
                          const Spacer(),
                        TextButton(
                          onPressed: saving ? null : onCancel,
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: TasteHubSpacing.sm),
                        saveButton,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
