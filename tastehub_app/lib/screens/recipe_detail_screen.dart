// ============================================================
//  recipe_detail_screen.dart - one recipe, with rating and editing
//
//  Only the owner sees Edit/Delete. Any logged-in user may rate and
//  attach a proof photo. Photos can be uploaded from the device or
//  referenced by URL.
// ============================================================

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/session_controller.dart';
import '../theme.dart';
import '../widgets/rating_stars.dart';
import '../widgets/recipe_thumbnail.dart';
import 'recipe_form_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({
    super.key,
    required this.api,
    required this.session,
    required this.recipe,
  });

  final ApiClient api;
  final SessionController session;

  /// The summary from the list. The full detail replaces it after loading.
  final Recipe recipe;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  late Recipe _recipe = widget.recipe;
  bool _loading = true;
  bool _rating = false;
  bool _deleting = false;
  String? _error;

  bool get _isOwner => widget.session.user?.id == _recipe.ownerId;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final detail = await widget.api.getRecipe(widget.recipe.id);
      if (!mounted) return;
      setState(() {
        _recipe = detail;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? context.tasteHubColors.error : null,
        ),
      );
  }

  Future<void> _rate(int stars, {String? proofImageRef}) async {
    if (_rating) return;
    setState(() => _rating = true);

    try {
      final summary = await widget.api.rateRecipe(
        _recipe.id,
        stars,
        proofImageRef: proofImageRef,
      );
      if (!mounted) return;
      setState(() => _recipe = _recipe.withRating(summary));
      _snack('Rated $stars out of 5.');
      _loadDetail(showSpinner: false);
    } on ApiException catch (error) {
      _snack(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _rating = false);
    }
  }

  Future<void> _showProofDialog() async {
    final result = await showDialog<({int stars, String proof})>(
      context: context,
      builder: (context) => _ProofDialog(
        api: widget.api,
        initialStars: _recipe.myRating > 0 ? _recipe.myRating : 5,
        initialProof: _recipe.myRatingProofImageRef,
      ),
    );

    if (result == null) return;
    await _rate(result.stars, proofImageRef: result.proof);
  }

  Future<void> _openLink(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) {
      _snack('That link does not look valid.', isError: true);
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _snack('Could not open the link.', isError: true);
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RecipeFormScreen(api: widget.api, existing: _recipe),
      ),
    );

    if (changed == true) {
      await _loadDetail();
    }
  }

  Future<void> _delete() async {
    final colors = context.tasteHubColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recipe?'),
        content: Text(
          '"${_recipe.title}" will be removed permanently. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.api.deleteRecipe(_recipe.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Deleted "${_recipe.title}".')));
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _deleting = false);
      _snack(error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _rating || _deleting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipe'),
        actions: [
          if (_isOwner) ...[
            IconButton(
              onPressed: busy ? null : _edit,
              tooltip: 'Edit recipe',
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              onPressed: busy ? null : _delete,
              tooltip: 'Delete recipe',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
          const SizedBox(width: 8),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(context),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: _error!, onRetry: () => _loadDetail()),
                ],
                const SizedBox(height: 22),
                _buildMeta(context),
                const SizedBox(height: 22),
                _buildRatingCard(context),
                if (_recipe.ingredients.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _SectionCard(
                    title: 'Ingredients',
                    icon: Icons.shopping_basket_outlined,
                    child: Column(
                      children: [
                        for (final ingredient in _recipe.ingredients)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: context.tasteHubColors.success,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    ingredient,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_recipe.steps.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _SectionCard(
                    title: 'Cooking steps',
                    icon: Icons.local_fire_department_outlined,
                    child: Column(
                      children: [
                        for (var i = 0; i < _recipe.steps.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: context.tasteHubColors.accent
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      color:
                                          context.tasteHubColors.accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _recipe.steps[i],
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_recipe.ratings.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _SectionCard(
                    title: 'Ratings',
                    icon: Icons.star_outline_rounded,
                    child: Column(
                      children: [
                        for (final rating in _recipe.ratings)
                          _RatingRow(
                            rating: rating,
                            api: widget.api,
                            onOpenLink: _openLink,
                          ),
                      ],
                    ),
                  ),
                ],
                if (_buildYoutubeButton(context) != null) ...[
                  const SizedBox(height: 26),
                  _buildYoutubeButton(context)!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final colors = context.tasteHubColors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          RecipeThumbnail(
            imageRef: widget.api.resolveMediaUrl(_recipe.imageRef),
            dish: _recipe.dish,
            title: _recipe.title,
            height: 280,
            width: double.infinity,
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, colors.ink.withValues(alpha: 0.7)],
                  stops: const [0.45, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _recipe.dish.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  _recipe.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeta(BuildContext context) {
    final time = _recipe.cookingTime > 0
        ? '${_recipe.cookingTime} minutes'
        : 'No time set';
    final ingredient = _recipe.mainIngredient.isEmpty
        ? 'Ingredient not set'
        : _recipe.mainIngredient;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MetaChip(icon: Icons.person_outline_rounded, label: 'by ${_recipe.ownerName}'),
        _MetaChip(icon: Icons.schedule_rounded, label: time),
        _MetaChip(icon: Icons.egg_alt_outlined, label: ingredient),
        if (_recipe.ratingCount > 0)
          _MetaChip(
            icon: Icons.star_rounded,
            label:
                '${_recipe.averageRating.toStringAsFixed(1)} from ${_recipe.ratingCount} rating${_recipe.ratingCount == 1 ? '' : 's'}',
          ),
      ],
    );
  }

  Widget _buildRatingCard(BuildContext context) {
    final colors = context.tasteHubColors;
    final hasProof = _recipe.myRatingProofImageRef.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR RATING',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _recipe.myRating > 0
                        ? '${_recipe.myRating} out of 5'
                        : 'Tap a star to rate',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              StarPicker(
                value: _recipe.myRating,
                onChanged: _rating ? (_) {} : (value) => _rate(value),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RatingStars(value: _recipe.averageRating, size: 18),
                  const SizedBox(width: 8),
                  RatingLabel(
                    averageRating: _recipe.averageRating,
                    ratingCount: _recipe.ratingCount,
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: _rating ? null : _showProofDialog,
                icon: Icon(
                  hasProof
                      ? Icons.photo_library_rounded
                      : Icons.add_a_photo_outlined,
                  size: 17,
                ),
                label: Text(hasProof ? 'Edit proof' : 'Add proof'),
              ),
            ],
          ),
          if (hasProof)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  _ProofThumb(
                    imageUrl: widget.api.resolveMediaUrl(
                      _recipe.myRatingProofImageRef,
                    ),
                    size: 40,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _recipe.myRatingProofImageRef,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (_recipe.myRatingProofImageRef.startsWith('http'))
                    IconButton(
                      onPressed: () => _openLink(_recipe.myRatingProofImageRef),
                      tooltip: 'Open proof photo',
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildYoutubeButton(BuildContext context) {
    final uri = Uri.tryParse(_recipe.youtubeUrl);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }

    return FilledButton.icon(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      onPressed: () => _openLink(uri.toString()),
      icon: const Icon(Icons.smart_display_rounded),
      label: const Text('Find it on YouTube'),
    );
  }
}

class _ProofDialog extends StatefulWidget {
  const _ProofDialog({
    required this.api,
    required this.initialStars,
    required this.initialProof,
  });

  final ApiClient api;
  final int initialStars;
  final String initialProof;

  @override
  State<_ProofDialog> createState() => _ProofDialogState();
}

class _ProofDialogState extends State<_ProofDialog> {
  late int _stars = widget.initialStars;
  late final TextEditingController _proof = TextEditingController(
    text: widget.initialProof,
  );
  bool _uploading = false;
  Uint8List? _preview;
  String? _error;

  @override
  void dispose() {
    _proof.dispose();
    super.dispose();
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
        _proof.text = ref;
        _preview = bytes;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final resolved = widget.api.resolveMediaUrl(_proof.text);

    Widget preview = Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.photo_outlined, color: colors.muted, size: 24),
    );

    if (_preview != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(_preview!, width: 54, height: 54, fit: BoxFit.cover),
      );
    } else if (resolved.isNotEmpty) {
      // Keep the static placeholder above as the error fallback. Referring
      // to `preview` here would recurse forever when the URL fails to load.
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          resolved,
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colors.field,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.broken_image_outlined,
              color: colors.muted,
              size: 24,
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Rate with a proof photo'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How many stars? Attach a real photo from this device, or '
                'paste an image URL. Both prove you cooked it.',
              ),
              const SizedBox(height: 14),
              Center(
                child: StarPicker(
                  value: _stars,
                  onChanged: (value) => setState(() => _stars = value),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  preview,
                  const SizedBox(width: 12),
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
                        _uploading ? 'Uploading...' : 'Upload proof photo',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _proof,
                decoration: const InputDecoration(
                  labelText: 'Proof image URL or /uploads/... path',
                  hintText: 'https://example.com/my-biryani.jpg',
                  helperText: 'Leave empty to remove an existing proof.',
                ),
                onChanged: (_) {
                  if (_preview != null) setState(() => _preview = null);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.error),
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
              : () => Navigator.of(context).pop((
                  stars: _stars,
                  proof: _proof.text.trim(),
                )),
          child: const Text('Save rating'),
        ),
      ],
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.rating,
    required this.api,
    required this.onOpenLink,
  });

  final Rating rating;
  final ApiClient api;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final name = rating.userName.isEmpty ? 'User ${rating.userId}' : rating.userName;
    final proofUrl = api.resolveMediaUrl(rating.proofImageRef);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
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
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          RatingStars(value: rating.stars.toDouble(), size: 16),
          const SizedBox(width: 8),
          Text(
            '${rating.stars}/5',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (rating.proofImageRef.isNotEmpty) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: proofUrl.startsWith('http')
                  ? () => onOpenLink(rating.proofImageRef)
                  : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: _ProofThumb(imageUrl: proofUrl, size: 30),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.accent),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: colors.accent),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 19, color: colors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ProofThumb extends StatelessWidget {
  const _ProofThumb({required this.imageUrl, required this.size});

  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colors.line),
      ),
      child: Icon(
        Icons.photo_library_outlined,
        size: size * 0.45,
        color: colors.muted,
      ),
    );

    if (imageUrl.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}
