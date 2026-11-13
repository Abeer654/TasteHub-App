// ============================================================
//  home_screen.dart - dishes first, then ranked recipes
//
//  The home screen groups every recipe by dish. Tapping a dish opens
//  DishScreen, which ranks the recipes inside that dish. The old
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
import '../widgets/status_views.dart';
import 'ai_recipe_screen.dart';
import 'dish_screen.dart';
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

  List<Recipe> get _visibleRecipes {
    if (!_myRecipesOnly) return _recipes;
    final userId = _myUserId;
    return _recipes
        .where((recipe) => recipe.ownerId == userId)
        .toList(growable: false);
  }

  List<DishGroup> get _groups => groupRecipesByDish(_visibleRecipes);

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
    setState(() => _myRecipesOnly = !_myRecipesOnly);
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
                      'Explain the dish in your own words and review the draft Gemini writes.',
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

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => choice == 'ai'
            ? AiRecipeScreen(api: widget.api)
            : RecipeFormScreen(api: widget.api),
      ),
    );

    if (!mounted) return;
    _load(showSpinner: false);
  }

  Future<void> _logout() async {
    await widget.session.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddOptions,
        tooltip: 'Add a recipe',
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add recipe'),
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
                  _buildSummary(context),
                  Expanded(child: _buildContent(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = context.tasteHubColors;
    final user = widget.session.user;

    return Padding(
      padding: const EdgeInsets.only(top: 34, bottom: 20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.displaySmall,
                  children: [
                    const TextSpan(text: 'Taste'),
                    TextSpan(
                      text: 'Hub',
                      style: TextStyle(color: colors.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Pick a dish, then pick the best recipe.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.muted),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThemeMenu(controller: widget.themeController),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Account',
                onSelected: (value) {
                  if (value == 'logout') _logout();
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Text('Logged in as ${user?.username ?? ''}'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
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
              ),
            ],
          ),
        ],
      ),
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
            hintText: 'Search dishes, recipes or ingredients...',
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
          label: 'All dishes',
          selected: !_myRecipesOnly,
          onTap: _myRecipesOnly ? _toggleMyRecipes : null,
        ),
        _FilterChip(
          label: 'My recipes',
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
          children: [searchField, const SizedBox(height: 12), filters],
        );
      },
    );
  }

  Widget _buildSummary(BuildContext context) {
    final groups = _groups;
    final count = _visibleRecipes.length;

    final String text;
    if (_loading) {
      text = 'Loading...';
    } else if (_query.isNotEmpty) {
      text =
          '$count result${count == 1 ? '' : 's'} in '
          '${groups.length} dish${groups.length == 1 ? '' : 'es'}';
    } else {
      text =
          '${groups.length} dish${groups.length == 1 ? '' : 'es'} · '
          '$count recipe${count == 1 ? '' : 's'}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _myRecipesOnly && !_loading ? 'My recipes · $text' : text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final groups = _groups;

    if (_loading && _recipes.isEmpty) {
      return const LoadingView(message: 'Loading dishes...');
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

    if (groups.isEmpty) {
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
                  secondaryActionLabel: !searching && _myRecipesOnly
                      ? 'Show all dishes'
                      : null,
                  onSecondaryAction: !searching && _myRecipesOnly
                      ? _toggleMyRecipes
                      : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1040
              ? 3
              : constraints.maxWidth >= 680
              ? 2
              : 1;

          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(top: 2, bottom: 96),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              mainAxisExtent: 300,
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

class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Theme: ${controller.label}',
      initialValue: controller.mode,
      onSelected: controller.setMode,
      icon: Icon(Icons.brightness_6_rounded, color: colors.ink, size: 21),
      itemBuilder: (context) => const [
        CheckedPopupMenuItem(
          value: ThemeMode.system,
          child: Text('System theme'),
        ),
        CheckedPopupMenuItem(
          value: ThemeMode.light,
          child: Text('Light theme'),
        ),
        CheckedPopupMenuItem(value: ThemeMode.dark, child: Text('Dark theme')),
      ],
    );
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
