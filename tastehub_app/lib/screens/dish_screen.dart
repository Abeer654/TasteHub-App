// ============================================================
//  dish_screen.dart - one dish and its ranked recipes
//
//  Ranking is done by utils/ranking.dart with the same rules as the
//  server: average desc, rating count desc, newest first, unrated
//  recipes last and marked "New".
// ============================================================

import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/session_controller.dart';
import '../theme.dart';
import '../utils/ranking.dart';
import '../widgets/rating_stars.dart';
import '../widgets/recipe_thumbnail.dart';
import '../widgets/status_views.dart';
import 'recipe_detail_screen.dart';
import 'recipe_form_screen.dart';

class DishScreen extends StatefulWidget {
  const DishScreen({
    super.key,
    required this.api,
    required this.session,
    required this.dish,
    this.initialRecipes,
  });

  final ApiClient api;
  final SessionController session;
  final String dish;
  final List<Recipe>? initialRecipes;

  @override
  State<DishScreen> createState() => _DishScreenState();
}

class _DishScreenState extends State<DishScreen> {
  List<Recipe> _recipes = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialRecipes != null) {
      _recipes = _forThisDish(widget.initialRecipes!);
      _loading = false;
    }
    _load(showSpinner: widget.initialRecipes == null);
  }

  List<Recipe> _forThisDish(Iterable<Recipe> recipes) {
    return rankRecipes(
      recipes.where(
        (recipe) =>
            recipe.dish.toLowerCase() == widget.dish.toLowerCase(),
      ),
    );
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final all = await widget.api.listRecipes();
      if (!mounted) return;
      setState(() {
        _recipes = _forThisDish(all);
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

  Future<void> _openRecipe(Recipe recipe) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetailScreen(
          api: widget.api,
          session: widget.session,
          recipe: recipe,
        ),
      ),
    );
    if (!mounted) return;
    await _load(showSpinner: false);
  }

  Future<void> _addRecipe() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RecipeFormScreen(
          api: widget.api,
          initialDish: widget.dish,
        ),
      ),
    );
    if (!mounted) return;
    if (changed == true) await _load(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Scaffold(
      appBar: AppBar(title: Text(widget.dish)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRecipe,
        icon: const Icon(Icons.add_rounded),
        label: Text('Add to ${widget.dish}'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: RefreshIndicator(
            onRefresh: () => _load(showSpinner: false),
            child: _loading && _recipes.isEmpty
                ? const LoadingView()
                : _error != null && _recipes.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.6,
                        child: StatusView(
                          icon: Icons.cloud_off_rounded,
                          title: 'Cannot load this dish',
                          message: _error!,
                          actionLabel: 'Try again',
                          onAction: _load,
                          isError: true,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                    children: [
                      _DishHeader(
                        dish: widget.dish,
                        recipes: _recipes,
                        resolveImage: widget.api.resolveMediaUrl,
                      ),
                      const SizedBox(height: 18),
                      if (_recipes.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text(
                            'No recipes in this dish yet.',
                            textAlign: TextAlign.center,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: colors.muted),
                          ),
                        )
                      else ...[
                        Text(
                          'Ranked by average rating, then number of ratings.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: colors.muted),
                        ),
                        const SizedBox(height: 12),
                        for (var i = 0; i < _recipes.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _RecipeRow(
                              recipe: _recipes[i],
                              rank: _recipes[i].isRated ? i + 1 : 0,
                              imageUrl: widget.api.resolveMediaUrl(
                                _recipes[i].imageRef,
                              ),
                              onTap: () => _openRecipe(_recipes[i]),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _DishHeader extends StatelessWidget {
  const _DishHeader({
    required this.dish,
    required this.recipes,
    required this.resolveImage,
  });

  final String dish;
  final List<Recipe> recipes;
  final String Function(String) resolveImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final top = recipes.isEmpty ? null : recipes.first;
    final rated = top != null && top.isRated;

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RecipeThumbnail(
            imageRef: top == null ? '' : resolveImage(top.imageRef),
            dish: dish,
            title: dish,
            height: 220,
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dish,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${recipes.length} recipe${recipes.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (rated)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RatingStars(value: top.averageRating, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${top.averageRating.toStringAsFixed(1)} from '
                            '${top.ratingCount} rating${top.ratingCount == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      )
                    else
                      Text(
                        'No ratings yet',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: colors.success),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    required this.recipe,
    required this.rank,
    required this.imageUrl,
    required this.onTap,
  });

  final Recipe recipe;
  final int rank;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final isTop = rank == 1;
    final time = recipe.cookingTime > 0
        ? '${recipe.cookingTime} min'
        : 'No time set';

    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isTop ? colors.gold.withValues(alpha: 0.6) : colors.line,
          width: isTop ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: RecipeThumbnail(
                  imageRef: imageUrl,
                  dish: recipe.dish,
                  title: recipe.title,
                  width: 92,
                  height: 92,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _RankBadge(rank: rank, isTop: isTop),
                        if (isTop) ...[
                          const SizedBox(width: 7),
                          Text(
                            'Top pick',
                            style: TextStyle(
                              color: colors.gold,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'by ${recipe.ownerName.isEmpty ? 'unknown' : recipe.ownerName}'
                      ' · $time',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        RatingStars(value: recipe.averageRating, size: 15),
                        const SizedBox(width: 7),
                        RatingLabel(
                          averageRating: recipe.averageRating,
                          ratingCount: recipe.ratingCount,
                          notRatedText: 'New - not rated',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.isTop});

  final int rank;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: isTop ? colors.goldWash : colors.field,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        rank > 0 ? '#$rank' : 'New',
        style: TextStyle(
          color: isTop ? colors.gold : colors.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
