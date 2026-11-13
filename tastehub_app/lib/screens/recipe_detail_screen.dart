// ============================================================
//  recipe_detail_screen.dart - one recipe, with rating and editing
//
//  This file is the orchestrator only: it loads the recipe and owns the
//  actions. The visual pieces live in screens/recipe_detail/ so any one
//  section can be handed to another model without sharing the whole screen:
//
//    recipe_hero.dart            main photo + title overlay
//    recipe_overview.dart        quick fact chips
//    ingredients_card.dart       ingredient list
//    steps_card.dart             numbered cooking steps
//    recipe_rating_section.dart  your rating + your rating photo
//    community_ratings.dart      other people's ratings
//    rating_photo_dialog.dart    rate + attach a rating photo
//
//  Only the owner sees Edit/Delete. Any logged-in user may rate.
//  Recipe photos and rating photos are separate concepts on purpose.
// ============================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/session_controller.dart';
import '../theme.dart';
import 'recipe_detail/community_ratings.dart';
import 'recipe_detail/ingredients_card.dart';
import 'recipe_detail/rating_photo_dialog.dart';
import 'recipe_detail/recipe_hero.dart';
import 'recipe_detail/recipe_overview.dart';
import 'recipe_detail/recipe_rating_section.dart';
import 'recipe_detail/steps_card.dart';
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
  int get _currentUserId => widget.session.user?.id ?? 0;

  bool get _hasOtherRatings =>
      _recipe.ratings.any((rating) => rating.userId != _currentUserId);

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

  Future<void> _showRatingPhotoDialog() async {
    final result = await showDialog<RatingPhotoResult>(
      context: context,
      builder: (context) => RatingPhotoDialog(
        api: widget.api,
        initialStars: _recipe.myRating > 0 ? _recipe.myRating : 5,
        initialProof: _recipe.myRatingProofImageRef,
      ),
    );

    if (result == null) return;
    await _rate(result.stars, proofImageRef: result.proofImageRef);
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
    final colors = context.tasteHubColors;
    final busy = _rating || _deleting;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _recipe.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isOwner) ...[
            IconButton(
              onPressed: busy ? null : _edit,
              tooltip: 'Edit recipe',
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: 'More actions',
              enabled: !busy,
              onSelected: (value) {
                if (value == 'delete') _delete();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: colors.error,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Delete recipe',
                        style: TextStyle(color: colors.error),
                      ),
                    ],
                  ),
                ),
              ],
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
      body: RefreshIndicator(
        onRefresh: () => _loadDetail(showSpinner: false),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: TasteHubLayout.pagePadding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: TasteHubLayout.contentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RecipeHero(
                    recipe: _recipe,
                    imageUrl: widget.api.resolveMediaUrl(_recipe.imageRef),
                    canEdit: _isOwner,
                    onAddPhoto: busy ? () {} : _edit,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: TasteHubSpacing.md),
                    _ErrorBanner(
                      message: _error!,
                      onRetry: () => _loadDetail(),
                    ),
                  ],
                  const SizedBox(height: TasteHubSpacing.lg),
                  RecipeOverview(recipe: _recipe),
                  if (_recipe.ingredients.isNotEmpty) ...[
                    const SizedBox(height: TasteHubSpacing.section),
                    IngredientsCard(ingredients: _recipe.ingredients),
                  ],
                  if (_recipe.steps.isNotEmpty) ...[
                    const SizedBox(height: TasteHubSpacing.section),
                    StepsCard(steps: _recipe.steps),
                  ],
                  const SizedBox(height: TasteHubSpacing.section),
                  RecipeRatingSection(
                    recipe: _recipe,
                    busy: busy,
                    onRate: _rate,
                    onEditPhoto: _showRatingPhotoDialog,
                    onOpenPhoto: _openLink,
                    resolveMediaUrl: widget.api.resolveMediaUrl,
                  ),
                  if (_hasOtherRatings) ...[
                    const SizedBox(height: TasteHubSpacing.section),
                    CommunityRatingsCard(
                      ratings: _recipe.ratings,
                      currentUserId: _currentUserId,
                      resolveMediaUrl: widget.api.resolveMediaUrl,
                      onOpenPhoto: _openLink,
                    ),
                  ],
                  if (_buildYoutubeButton(context) != null) ...[
                    const SizedBox(height: TasteHubSpacing.section),
                    _buildYoutubeButton(context)!,
                  ],
                  const SizedBox(height: TasteHubSpacing.md),
                ],
              ),
            ),
          ),
        ),
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
      label: const Text('Watch on YouTube'),
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
        borderRadius: TasteHubRadii.fieldBorder,
        border: Border.all(color: colors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 19, color: colors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
