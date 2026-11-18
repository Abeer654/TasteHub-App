// ============================================================
//  home_screen.dart - all dishes, or a flat list of your recipes
//
//  All dishes groups every recipe by dish. Tapping a dish opens
//  DishScreen, which ranks the recipes inside that dish. My recipes
//  skips the grouping and lists one card per recipe you own. The old
//  global leaderboard tab is intentionally gone.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dish_group.dart';
import '../models/recipe.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/session_controller.dart';
import '../services/theme_controller.dart';
import '../theme.dart';
import '../utils/ranking.dart';
import '../widgets/dish_card.dart';
import '../widgets/recipe_list_card.dart';
import '../widgets/status_views.dart';
import 'ai_recipe_screen.dart';
import 'dish_screen.dart';
import 'recipe_detail_screen.dart';
import 'recipe_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.session,
    required this.themeController,
  });

  final ApiClient api;
  final SessionController session;
  final ThemeController themeController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchTimer;
  int _requestNumber = 0;
  List<Recipe> _recipes = const [];
  bool _loading = true;
  bool _myRecipesOnly = false;

  /// M-04: the "N need photos" line in the subtitle is a toggle.
  bool _needsPhotosOnly = false;

  /// M-01: how My recipes is grouped - Grouped | Flat | Recent.
  String _myView = 'grouped';

  /// H-03: the header shrinks into a 56dp bar once the list has scrolled
  /// past [_collapseAfter] dp.
  bool _collapsed = false;
  static const double _collapseAfter = 56;

  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  int? get _myUserId => widget.session.user?.id;

  /// Recipes you own, before any search or photo filter.
  List<Recipe> get _myRecipes {
    final userId = _myUserId;
    return _recipes
        .where((recipe) => recipe.ownerId == userId)
        .toList(growable: false);
  }

  List<Recipe> get _visibleRecipes {
    var list = _myRecipesOnly ? _myRecipes : _recipes;

    // M-04's photo filter only exists while the subtitle is showing it,
    // i.e. in My recipes with an idle search.
    if (_myRecipesOnly && _query.isEmpty && _needsPhotosOnly) {
      list = list
          .where((recipe) => recipe.imageRef.trim().isEmpty)
          .toList(growable: false);
    }

    return list;
  }

  List<DishGroup> get _groups => groupRecipesByDish(_visibleRecipes);

  /// H-04: the counts live inside the filter chips, so there is no
  /// separate "8 dishes · 21 recipes" line any more. Both numbers are
  /// computed from what the server returned (search included) and update
  /// as soon as data changes.
  int get _allDishCount => groupRecipesByDish(_recipes).length;

  int get _myRecipeCount => _myRecipes.length;

  /// M-04: recipes of yours that still need a photo.
  int get _needPhotosCount => _myRecipes
      .where((recipe) => recipe.imageRef.trim().isEmpty)
      .length;

  /// H-03: set once the user has opened or added a recipe, after which
  /// the slogan under the wordmark never comes back (persisted).
  static const String _taglineSeenKey = 'tagline_seen';

  bool get _taglineSeen =>
      widget.session.prefs.getBool(_taglineSeenKey) ?? false;

  Future<void> _markTaglineSeen() async {
    if (_taglineSeen) return;
    await widget.session.prefs.setBool(_taglineSeenKey, true);
    if (mounted) setState(() {});
  }

  /// The line under the wordmark follows what the screen is doing now
  /// instead of always talking about picking a dish. My recipes replaces
  /// it with the dynamic summary built in [_buildSubtitle].
  ///
  /// H-03: the slogan itself is one-shot - once a recipe has been opened
  /// or added it returns '' and the header shows nothing underneath.
  /// Search context always shows, because it describes the current list.
  String get _tagline {
    if (_query.isNotEmpty) {
      return _myRecipesOnly
          ? 'Your recipes matching "$_query".'
          : 'Matching "$_query" across every dish.';
    }
    return _taglineSeen ? '' : 'Pick a dish, then pick the best recipe.';
  }

  Future<void> _load({bool showSpinner = true}) async {
    final request = ++_requestNumber;

    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final recipes = _query.isEmpty
          ? await widget.api.listRecipes()
          : await widget.api.search(_query);

      if (!mounted || request != _requestNumber) return;
      setState(() {
        _recipes = recipes;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      _showError(request, error.message);
    } catch (error) {
      _showError(request, 'Something went wrong: $error');
    }
  }

  void _showError(int request, String message) {
    if (!mounted || request != _requestNumber) return;

    final hadData = _recipes.isNotEmpty;
    setState(() {
      _loading = false;
      _error = message;
    });

    if (hadData) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: context.tasteHubColors.error,
          ),
        );
    }
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 320), () {
      final text = value.trim();
      if (text == _query) return;
      _query = text;
      _load();
    });
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _searchController.clear();
    if (_query.isEmpty) return;
    _query = '';
    _load();
  }

  void _toggleMyRecipes() {
    setState(() {
      _myRecipesOnly = !_myRecipesOnly;
      // The photo filter belongs to My recipes only.
      _needsPhotosOnly = false;
    });
  }

  void _toggleNeedsPhotos() {
    setState(() => _needsPhotosOnly = !_needsPhotosOnly);
  }

  Future<void> _openDish(DishGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DishScreen(
          api: widget.api,
          session: widget.session,
          dish: group.name,
          initialRecipes: _recipes,
        ),
      ),
    );
    if (!mounted) return;
    _load(showSpinner: false);
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
    // H-03: opening a recipe once is enough to retire the slogan.
    await _markTaglineSeen();
    if (!mounted) return;
    _load(showSpinner: false);
  }

  Future<void> _showAddOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add a recipe',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Write it yourself, or let AI create a draft to review.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const _SheetIcon(icon: Icons.edit_note_rounded),
                    title: const Text('Write it manually'),
                    subtitle: const Text(
                      'Choose an existing dish or create a new one.',
                    ),
                    onTap: () => Navigator.of(context).pop('manual'),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const _SheetIcon(icon: Icons.auto_awesome_rounded),
                    title: const Text('Describe it with AI'),
                    subtitle: const Text(
                      'Describe it in your own words, then review the '
                      'AI-written draft.',
                    ),
                    onTap: () => Navigator.of(context).pop('ai'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => choice == 'ai'
            ? AiRecipeScreen(api: widget.api)
            : RecipeFormScreen(api: widget.api),
      ),
    );

    if (!mounted) return;
    // H-03: saving a recipe retires the slogan for good.
    if (changed == true) await _markTaglineSeen();
    if (!mounted) return;
    _load(showSpinner: false);
  }

  Future<void> _logout() async {
    await widget.session.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        tooltip: 'Add a recipe',
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  _buildToolbar(context),
                  // H-03: scrolling the list past 56dp collapses the
                  // header above; the search field stays pinned because
                  // it lives outside this scrollable.
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        final shouldCollapse =
                            notification.metrics.pixels >= _collapseAfter;
                        if (shouldCollapse == _collapsed) return false;
                        setState(() => _collapsed = shouldCollapse);
                        return false;
                      },
                      child: _buildContent(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// H-03: expanded wordmark + tagline at the top of the list, a 56dp
  /// bar with a 22sp wordmark once scrolled. The theme toggle lives in
  /// the avatar menu now, not as its own icon.
  Widget _buildHeader(BuildContext context) {
    final colors = context.tasteHubColors;
    final user = widget.session.user;
    final subtitle = _buildSubtitle(context);

    final accountMenu = PopupMenuButton<Object>(
      tooltip: 'Account',
      initialValue: widget.themeController.mode,
      onSelected: (value) {
        if (value is ThemeMode) {
          widget.themeController.setMode(value);
        } else if (value == 'logout') {
          _logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<Object>(
          enabled: false,
          child: Text('Logged in as ${user?.username ?? ''}'),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<ThemeMode>(
          value: ThemeMode.system,
          checked: widget.themeController.mode == ThemeMode.system,
          child: const Text('Theme: System'),
        ),
        CheckedPopupMenuItem<ThemeMode>(
          value: ThemeMode.light,
          checked: widget.themeController.mode == ThemeMode.light,
          child: const Text('Theme: Light'),
        ),
        CheckedPopupMenuItem<ThemeMode>(
          value: ThemeMode.dark,
          checked: widget.themeController.mode == ThemeMode.dark,
          child: const Text('Theme: Dark'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: 'logout',
          child: Text('Log out'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: colors.accent.withValues(alpha: 0.12),
              child: Text(
                (user?.username.isNotEmpty ?? false)
                    ? user!.username.characters.first.toUpperCase()
                    : '?',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              user?.username ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 17,
              color: colors.muted,
            ),
          ],
        ),
      ),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: _collapsed
          ? SizedBox(
              height: 56,
              child: Row(
                children: [
                  _wordmark(context, 22),
                  const Spacer(),
                  accountMenu,
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 10),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _wordmark(context, 32),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        subtitle,
                      ],
                    ],
                  ),
                  accountMenu,
                ],
              ),
            ),
    );
  }

  /// The TasteHub wordmark; 32sp expanded and 22sp collapsed (H-03).
  /// Tracking keeps the theme's -4% display tightening at either size.
  Widget _wordmark(BuildContext context, double size) {
    final colors = context.tasteHubColors;

    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
          fontSize: size,
          letterSpacing: size * -0.04,
        ),
        children: [
          const TextSpan(text: 'Taste'),
          TextSpan(text: 'Hub', style: TextStyle(color: colors.accent)),
        ],
      ),
    );
  }

  /// M-04: My recipes gets a dynamic summary instead of a slogan -
  /// `4 recipes · 4 need photos`. The second half is a toggle that
  /// filters the list down to photo-less recipes, and disappears when
  /// there is nothing to fix.
  ///
  /// H-03: returns null when there is no line to show (the slogan has
  /// been retired) so the header can drop the gap as well.
  Widget? _buildSubtitle(BuildContext context) {
    final colors = context.tasteHubColors;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: colors.muted,
      letterSpacing: 0,
    );

    if (!(_myRecipesOnly && _query.isEmpty)) {
      final line = _tagline;
      return line.isEmpty ? null : Text(line, style: style);
    }

    final total = _myRecipeCount;
    final needPhotos = _needPhotosCount;

    return Wrap(
      spacing: 0,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$total recipe${total == 1 ? '' : 's'}', style: style),
        if (needPhotos > 0) ...[
          Text(' \u00b7 ', style: style),
          InkWell(
            onTap: _toggleNeedsPhotos,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '$needPhotos need photo${needPhotos == 1 ? '' : 's'}',
                style: style?.copyWith(
                  color: colors.accentOnDark,
                  fontWeight: FontWeight.w700,
                  decoration: _needsPhotosOnly
                      ? TextDecoration.underline
                      : TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colors = context.tasteHubColors;

    final searchField = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchController,
      builder: (context, value, _) {
        return TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          onSubmitted: (value) {
            _searchTimer?.cancel();
            final text = value.trim();
            if (text == _query) return;
            _query = text;
            _load();
          },
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search recipes or ingredients',
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    onPressed: _clearSearch,
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: colors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: colors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: colors.accent, width: 1.6),
            ),
          ),
        );
      },
    );

    final filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChip(
          label: 'All dishes · $_allDishCount',
          selected: !_myRecipesOnly,
          onTap: _myRecipesOnly ? _toggleMyRecipes : null,
        ),
        _FilterChip(
          label: 'My recipes · $_myRecipeCount',
          selected: _myRecipesOnly,
          onTap: _myRecipesOnly ? null : _toggleMyRecipes,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 14),
              filters,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [searchField, const SizedBox(height: 10), filters],
        );
      },
    );
  }

  /// Grid breakpoints shared by the real dish grid and its skeleton, so
  /// loading and loaded layouts line up exactly.
  int _columnsFor(double width) => width >= 1040 ? 3 : width >= 600 ? 2 : 1;

  /// G-06 (4): dish-card placeholders in the same grid the data uses.
  Widget _skeletonGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 16, bottom: 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: DishCard.height,
          ),
          itemCount: columns * 2,
          itemBuilder: (context, index) => const DishCardSkeleton(),
        );
      },
    );
  }

  /// G-06 (4): recipe-row placeholders for My recipes.
  Widget _skeletonRows() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 96),
      itemCount: 5,
      separatorBuilder: (context, index) =>
          const SizedBox(height: TasteHubSpacing.md),
      itemBuilder: (context, index) => const RecipeRowSkeleton(),
    );
  }

  Widget _buildContent(BuildContext context) {
    final recipes = _visibleRecipes;
    final groups = _groups;

    if (_loading && _recipes.isEmpty) {
      // G-06 (4): skeleton cards at the real size, never a spinner.
      return _myRecipesOnly ? _skeletonRows() : _skeletonGrid();
    }

    if (_error != null && _recipes.isEmpty) {
      return StatusView(
        icon: Icons.cloud_off_rounded,
        title: 'Cannot load recipes',
        message: _error!,
        actionLabel: 'Try again',
        onAction: () => _load(),
        isError: true,
      );
    }

    if (recipes.isEmpty) {
      final searching = _query.isNotEmpty;
      final title = searching
          ? 'No matching recipes'
          : _myRecipesOnly
          ? 'No recipes of your own yet'
          : 'No recipes yet';
      final message = searching
          ? 'Nothing matched "$_query". Try a shorter or different word.'
          : _myRecipesOnly
          ? 'Add one with the button below, or switch back to all dishes.'
          : 'Add the first recipe to get the demo started.';

      return RefreshIndicator(
        onRefresh: () => _load(showSpinner: false),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: TasteHubSpacing.lg),
                child: StatusView(
                  icon: searching
                      ? Icons.search_off_rounded
                      : Icons.ramen_dining_outlined,
                  title: title,
                  message: message,
                  actionLabel: searching ? 'Clear search' : 'Add recipe',
                  actionIcon: searching
                      ? Icons.close_rounded
                      : Icons.add_rounded,
                  onAction: searching ? _clearSearch : _showAddOptions,
                  secondaryActionLabel: _myRecipesOnly
                      ? 'Show all dishes'
                      : null,
                  onSecondaryAction: _myRecipesOnly ? _toggleMyRecipes : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_myRecipesOnly) {
      return _buildMyRecipeList(recipes);
    }

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _columnsFor(constraints.maxWidth);

          // Every dish card is the same fixed-height row (H-05), so the
          // grid cell is the card height in every column count.
          const extent = DishCard.height;

          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            // Bottom padding clears the FloatingActionButton so it never
            // sits on the last card: 56dp FAB + 16dp gap + 24dp margin.
            padding: const EdgeInsets.only(top: 16, bottom: 96),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              mainAxisExtent: extent,
            ),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              return DishCard(
                group: groups[index],
                resolveMediaUrl: widget.api.resolveMediaUrl,
                searchQuery: _query,
                onTap: () => _openDish(groups[index]),
              );
            },
          );
        },
      ),
    );
  }

  /// My recipes (M-01): three views over the same rows - Grouped with
  /// sticky dish headers, Flat in server order, and Recent newest first.
  /// The counts live in the filter chips (H-04) and the summary in the
  /// subtitle (M-04), so this list is only rows.
  Widget _buildMyRecipeList(List<Recipe> recipes) {
    final colors = context.tasteHubColors;

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const maxWidth = 900.0;
          final sidePadding = constraints.maxWidth > maxWidth
              ? (constraints.maxWidth - maxWidth) / 2
              : 0.0;

          final slivers = <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _MyViewPicker(
                      value: _myView,
                      onChanged: (view) => setState(() => _myView = view),
                    ),
                  ],
                ),
              ),
            ),
          ];

          if (_myView == 'grouped') {
            for (final group in _groupMyRecipes(recipes)) {
              slivers.add(
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SectionHeaderDelegate(
                    title:
                        '${group.name.toUpperCase()} \u00b7 '
                        '${group.recipes.length} recipe'
                        '${group.recipes.length == 1 ? '' : 's'}',
                    colors: colors,
                  ),
                ),
              );
              slivers.add(_myRecipeSliver(group.recipes));
            }
          } else {
            final rows = _myView == 'recent'
                ? _sortedByRecency(recipes)
                : recipes;
            slivers.add(_myRecipeSliver(rows));
          }

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(sidePadding, 16, sidePadding, 96),
                sliver: SliverMainAxisGroup(slivers: slivers),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _myRecipeSliver(List<Recipe> recipes) {
    final grouped = _myView == 'grouped';

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final recipe = recipes[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: TasteHubSpacing.md),
            child: RecipeListCard(
              recipe: recipe,
              imageUrl: widget.api.resolveMediaUrl(recipe.imageRef),
              // Grouped rows sit under a dish header, so they name the
              // main ingredient instead; Flat/Recent have no header.
              meta: grouped ? RecipeMeta.sectioned : RecipeMeta.listed,
              searchQuery: _query,
              onTap: () => _openRecipe(recipe),
              onEdit: () => _editRecipe(recipe),
              onAddPhoto: () => _addPhotoToRecipe(recipe),
              onDelete: () => _deleteRecipe(recipe),
            ),
          );
        },
        childCount: recipes.length,
      ),
    );
  }

  /// M-01: dishes ordered by their newest recipe, recipes inside a dish
  /// newest first.
  List<({String name, List<Recipe> recipes})> _groupMyRecipes(
    List<Recipe> recipes,
  ) {
    final byDish = <String, List<Recipe>>{};
    final names = <String, String>{};

    for (final recipe in recipes) {
      final name = recipe.dish.trim().isEmpty
          ? 'Recipes'
          : recipe.dish.trim();
      final key = name.toLowerCase();
      names.putIfAbsent(key, () => name);
      byDish.putIfAbsent(key, () => []).add(recipe);
    }

    final groups = byDish.entries
        .map(
          (entry) => (
            name: names[entry.key]!,
            recipes: _sortedByRecency(entry.value),
          ),
        )
        .toList(growable: false);

    final sortedGroups = groups.toList();
    sortedGroups.sort(
      (a, b) => _createdAt(b.recipes.first).compareTo(
        _createdAt(a.recipes.first),
      ),
    );
    return sortedGroups;
  }

  String _createdAt(Recipe recipe) => recipe.createdAt ?? '';

  List<Recipe> _sortedByRecency(List<Recipe> recipes) {
    final sorted = recipes.toList();
    sorted.sort((a, b) => _createdAt(b).compareTo(_createdAt(a)));
    return sorted;
  }

  Future<void> _editRecipe(Recipe recipe) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RecipeFormScreen(api: widget.api, existing: recipe),
      ),
    );
    if (!mounted || changed != true) return;
    _load(showSpinner: false);
  }

  Future<void> _addPhotoToRecipe(Recipe recipe) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RecipeFormScreen(
          api: widget.api,
          existing: recipe,
          scrollToPhoto: true,
        ),
      ),
    );
    if (!mounted || changed != true) return;
    _load(showSpinner: false);
  }

  /// M-02: deleting a whole recipe is irreversible, so it keeps a
  /// confirmation dialog (design principle 6).
  Future<void> _deleteRecipe(Recipe recipe) async {
    final colors = context.tasteHubColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${recipe.title}"?'),
        content: const Text("This can't be undone."),
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

    try {
      await widget.api.deleteRecipe(recipe.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Deleted "${recipe.title}".')));
      _load(showSpinner: false);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: context.tasteHubColors.error,
          ),
        );
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Material(
      color: selected ? colors.accent : colors.card,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? colors.accent : colors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.onAccent : colors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// M-01: the Grouped | Flat | Recent switch above the My recipes list.
class _MyViewPicker extends StatelessWidget {
  const _MyViewPicker({required this.value, required this.onChanged});

  static const List<(String, String)> _options = [
    ('grouped', 'Grouped'),
    ('flat', 'Flat'),
    ('recent', 'Recent'),
  ];

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (id, label) in _options)
            InkWell(
              onTap: () => onChanged(id),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: value == id ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: value == id ? colors.onAccent : colors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// M-01: `FRIES · 3 recipes` - a pinned section header that keeps the
/// dish name visible while its rows scroll underneath.
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SectionHeaderDelegate({required this.title, required this.colors});

  final String title;
  final TasteHubColors colors;

  static const double _height = 30;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: colors.background,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.accentOnDark,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          height: 1.2,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) {
    return oldDelegate.title != title || oldDelegate.colors != colors;
  }
}

class _SheetIcon extends StatelessWidget {
  const _SheetIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: colors.accent, size: 23),
    );
  }
}
