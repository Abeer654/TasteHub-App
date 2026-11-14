// ============================================================
//  dish_screen.dart - one dish and its ranked recipes
//
//  Owns: the dish header, the "Best rated first" explainer and the recipe
//  list. Ranking itself is utils/ranking.dart, with the same rules as the
//  server: average desc, rating count desc, newest first, unrated last.
// ============================================================

import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/session_controller.dart';
import '../theme.dart';
import '../utils/ranking.dart';
import '../widgets/rating_stars.dart';
import '../widgets/recipe_list_card.dart';
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
        (recipe) => recipe.dish.toLowerCase() == widget.dish.toLowerCase(),
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
        builder: (_) =>
            RecipeFormScreen(api: widget.api, initialDish: widget.dish),
      ),
    );
    if (!mounted) return;
    if (changed == true) await _load(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    final horizontal = compact ? TasteHubSpacing.lg : TasteHubSpacing.xl;

    return Scaffold(
      appBar: AppBar(title: Text(widget.dish)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRecipe,
        tooltip: 'Add a recipe to ${widget.dish}',
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add recipe'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: RefreshIndicator(
            onRefresh: () => _load(showSpinner: false),
            child: _loading && _recipes.isEmpty
                ? const LoadingView(message: 'Loading recipes...')
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
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      TasteHubSpacing.sm,
                      horizontal,
                      110,
                    ),
                    children: [
                      _DishHeader(
                        dish: widget.dish,
                        recipes: _recipes,
                        resolveMediaUrl: widget.api.resolveMediaUrl,
                      ),
                      const SizedBox(height: TasteHubSpacing.lg),
                      if (_recipes.isEmpty)
                        SizedBox(
                          height: 300,
                          child: StatusView(
                            icon: Icons.ramen_dining_outlined,
                            title: 'No recipes in ${widget.dish} yet',
                            message:
                                'Add the first one and it will appear at the '
                                'top of this dish.',
                            actionLabel: 'Add recipe',
                            actionIcon: Icons.add_rounded,
                            onAction: _addRecipe,
                          ),
                        )
                      else ...[
                        const _RankingExplainer(),
                        const SizedBox(height: TasteHubSpacing.md),
                        for (var i = 0; i < _recipes.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i == _recipes.length - 1
                                  ? 0
                                  : TasteHubSpacing.md,
                            ),
                            child: RecipeListCard(
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

class _RankingExplainer extends StatelessWidget {
  const _RankingExplainer();

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Row(
      children: [
        Icon(Icons.sort_rounded, size: 16, color: colors.muted),
        const SizedBox(width: 6),
        Text(
          'Best rated first',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.ink, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message:
              'Sorted by average rating, then by number of ratings. '
              'New recipes without ratings come last.',
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: colors.muted,
          ),
        ),
      ],
    );
  }
}

class _DishHeader extends StatelessWidget {
  const _DishHeader({
    required this.dish,
    required this.recipes,
    required this.resolveMediaUrl,
  });

  final String dish;
  final List<Recipe> recipes;
  final String Function(String) resolveMediaUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final top = recipes.isEmpty ? null : recipes.first;
    final compact = MediaQuery.sizeOf(context).width < 640;

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: TasteHubRadii.heroBorder,
        border: Border.all(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RecipeThumbnail(
            imageRef: top == null ? '' : resolveMediaUrl(top.imageRef),
            dish: dish,
            title: dish,
            height: compact ? 190 : 220,
          ),
          Padding(
            padding: const EdgeInsets.all(TasteHubSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dish, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: TasteHubSpacing.lg,
                  runSpacing: TasteHubSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${recipes.length} recipe'
                      '${recipes.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (top != null && top.isRated)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RatingStars(value: top.averageRating, size: 17),
                          const SizedBox(width: 7),
                          Text(
                            '${top.averageRating.toStringAsFixed(1)} from '
                            '${top.ratingCount} rating'
                            '${top.ratingCount == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'No ratings yet - be the first',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.success,
                          fontWeight: FontWeight.w600,
                        ),
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
