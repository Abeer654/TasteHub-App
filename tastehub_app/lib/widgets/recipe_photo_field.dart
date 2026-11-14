// ============================================================
//  recipe_photo_field.dart - the recipe's main photo picker
//
//  Owns: the preview, the upload/replace/remove buttons and the image URL
//  field. It is deliberately separate from the rating photo dialog: this
//  photo appears on the dish card and at the top of the recipe.
//
//  The parent owns upload state and the controller; this widget only
//  renders. Pass [onChanged] to mark the form dirty when the URL is typed.
// ============================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

class RecipePhotoField extends StatelessWidget {
  const RecipePhotoField({
    super.key,
    required this.controller,
    required this.resolveMediaUrl,
    required this.onPick,
    required this.onRemove,
    this.onChanged,
    this.localPreview,
    this.uploading = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String Function(String) resolveMediaUrl;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final ValueChanged<String>? onChanged;
  final Uint8List? localPreview;
  final bool uploading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final rawRef = value.text.trim();
        final hasRef = rawRef.isNotEmpty;
        final resolved = hasRef ? resolveMediaUrl(rawRef) : '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 480;
                final preview = ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: compact ? double.infinity : 148,
                    height: compact ? 156 : 108,
                    child: _preview(context, resolved: resolved),
                  ),
                );
                final controls = _controls(context, hasRef: hasRef);

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      preview,
                      const SizedBox(height: TasteHubSpacing.md),
                      controls,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    preview,
                    const SizedBox(width: TasteHubSpacing.lg),
                    Expanded(child: controls),
                  ],
                );
              },
            ),
            const SizedBox(height: TasteHubSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: colors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'This is the main recipe photo. Your rating photo is added '
                    'separately when you rate the dish.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context, {required bool hasRef}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: TasteHubSpacing.sm,
          runSpacing: TasteHubSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: !enabled || uploading ? null : onPick,
              icon: uploading
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library_outlined, size: 17),
              label: Text(
                uploading
                    ? 'Uploading...'
                    : hasRef
                    ? 'Replace photo'
                    : 'Upload photo',
              ),
            ),
            if (hasRef || localPreview != null)
              TextButton(
                onPressed: enabled ? onRemove : null,
                child: const Text('Remove'),
              ),
          ],
        ),
        const SizedBox(height: TasteHubSpacing.md),
        TextField(
          controller: controller,
          enabled: enabled,
          // Last field of the photo section: keep the preview visible above
          // the keyboard instead of jumping to the next card.
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          decoration: const InputDecoration(
            labelText: 'Recipe photo URL',
            hintText: 'https://... or an uploaded /uploads/... path',
            helperText: 'Paste a link, or upload a JPG/PNG/WebP (max 10 MB).',
          ),
        ),
      ],
    );
  }

  Widget _preview(BuildContext context, {required String resolved}) {
    if (localPreview != null) {
      return Image.memory(
        localPreview!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context, broken: false),
      );
    }

    if (resolved.isNotEmpty) {
      return Image.network(
        resolved,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context, broken: true),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(context, broken: false),
      );
    }

    return _placeholder(context, broken: false);
  }

  Widget _placeholder(BuildContext context, {required bool broken}) {
    final colors = context.tasteHubColors;

    return Container(
      color: colors.field,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(TasteHubSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            broken
                ? Icons.broken_image_outlined
                : Icons.add_photo_alternate_outlined,
            size: 28,
            color: broken ? colors.error : colors.muted,
          ),
          const SizedBox(height: TasteHubSpacing.xs),
          Text(
            broken ? 'Photo link could not load' : 'No recipe photo yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: broken ? colors.error : colors.muted),
          ),
        ],
      ),
    );
  }
}
