// ============================================================
//  rating_photo_dialog.dart - rate and attach a rating photo
//
//  Owns: the rating + photo dialog. This photo is deliberately called a
//  "rating photo": it is shown with the rating, never as the recipe's main
//  photo. The form's RecipePhotoField owns that other concept.
// ============================================================

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/api_exception.dart';
import '../../theme.dart';
import '../../widgets/rating_stars.dart';

typedef RatingPhotoResult = ({int stars, String proofImageRef});

class RatingPhotoDialog extends StatefulWidget {
  const RatingPhotoDialog({
    super.key,
    required this.api,
    required this.initialStars,
    required this.initialProof,
  });

  final ApiClient api;
  final int initialStars;
  final String initialProof;

  @override
  State<RatingPhotoDialog> createState() => _RatingPhotoDialogState();
}

class _RatingPhotoDialogState extends State<RatingPhotoDialog> {
  late int _stars = widget.initialStars;
  late final TextEditingController _proof = TextEditingController(
    text: widget.initialProof,
  );
  bool _uploading = false;
  bool _settingProof = false;
  Uint8List? _preview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _proof.addListener(_onProofChanged);
  }

  @override
  void dispose() {
    _proof
      ..removeListener(_onProofChanged)
      ..dispose();
    super.dispose();
  }

  void _onProofChanged() {
    if (_settingProof) return;
    if (_preview != null) {
      setState(() => _preview = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _pickProof() async {
    const typeGroup = XTypeGroup(
      label: 'Photos',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );

    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [typeGroup]);
    } catch (error) {
      setState(() => _error = 'Could not open the file picker: $error');
      return;
    }
    if (file == null || !mounted) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        setState(() => _error = 'Choose an image smaller than 10 MB.');
        return;
      }
      final ref = await widget.api.uploadImage(bytes, file.name);
      if (!mounted) return;
      setState(() {
        _preview = bytes;
        _settingProof = true;
        _proof.text = ref;
        _settingProof = false;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not upload the photo: $error');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final resolved = widget.api.resolveMediaUrl(_proof.text);

    return AlertDialog(
      title: const Text('Your rating photo'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How many stars? A rating photo is optional - it appears with '
                'your rating, not as the recipe photo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: TasteHubSpacing.lg),
              Center(
                child: StarPicker(
                  value: _stars,
                  onChanged: (value) => setState(() => _stars = value),
                ),
              ),
              const SizedBox(height: TasteHubSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProofPreview(localPreview: _preview, resolvedUrl: resolved),
                  const SizedBox(width: TasteHubSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickProof,
                      icon: _uploading
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_outlined, size: 17),
                      label: Text(
                        _uploading
                            ? 'Uploading...'
                            : _proof.text.trim().isEmpty
                            ? 'Upload rating photo'
                            : 'Replace rating photo',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TasteHubSpacing.md),
              TextField(
                controller: _proof,
                decoration: const InputDecoration(
                  labelText: 'Rating photo URL',
                  hintText: 'https://example.com/my-biryani.jpg',
                  helperText:
                      'Paste a link, or upload from this device. Leave empty '
                      'to remove your rating photo.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: TasteHubSpacing.sm),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _uploading
              ? null
              : () => Navigator.of(context)
                    .pop((stars: _stars, proofImageRef: _proof.text.trim())),
          child: const Text('Save rating'),
        ),
      ],
    );
  }
}

class _ProofPreview extends StatelessWidget {
  const _ProofPreview({required this.localPreview, required this.resolvedUrl});

  final Uint8List? localPreview;
  final String resolvedUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final fallback = Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.add_a_photo_outlined, color: colors.muted, size: 24),
    );

    Widget child = fallback;
    if (localPreview != null) {
      child = Image.memory(
        localPreview!,
        width: 62,
        height: 62,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (resolvedUrl.isNotEmpty) {
      child = Image.network(
        resolvedUrl,
        width: 62,
        height: 62,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: colors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.error.withValues(alpha: 0.25)),
          ),
          child: Icon(
            Icons.broken_image_outlined,
            color: colors.error,
            size: 24,
          ),
        ),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      );
    }

    return ClipRRect(borderRadius: BorderRadius.circular(12), child: child);
  }
}
