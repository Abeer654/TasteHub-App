# Stage 4 — Flutter App

**Goal:** build the Android app that talks to the C++ server: list recipes, open
one, add one, search with typos, rate, and show the leaderboard.

**Done when:** the app works on the Linux desktop against `localhost`, then the
APK works on the phone over Tailscale.

---

## 1. Prerequisites

- Stage 3 checkpoint passed (phone browser can open `/api/health`).
- Flutter is installed:

```bash
flutter --version
```

- The server is running:

```bash
cd ~/development/TasteHub-App
./build/tastehub-server --host 0.0.0.0 --port 8080 --data-dir data
```

- You know your API URL:
  - desktop test: `http://127.0.0.1:8080`
  - phone over Tailscale: `http://100.x.y.z:8080`
  - phone over Tailscale Serve: `https://my-laptop.tailnet-name.ts.net`

---

## 2. Install Android tooling

Flutter is installed, but this machine does not have the Android SDK/JDK yet.

### 2.1 Install Android Studio

```bash
sudo snap install android-studio --classic
```

Open Android Studio and go to **SDK Manager** (More Actions → SDK Manager).
Install:

- Android SDK Platform 35 (or the latest stable)
- Android SDK Build-Tools
- Android SDK Platform-Tools
- Android SDK Command-line Tools

### 2.2 Set environment variables

Add these to `~/.bashrc`:

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"
```

Reload:

```bash
source ~/.bashrc
```

### 2.3 Point Flutter at the SDK

```bash
flutter config --android-sdk "$ANDROID_HOME"
flutter doctor --android-licenses
flutter doctor -v
```

`flutter doctor` should show Android toolchain as OK. The NDK is **not**
required for this project.

If Flutter complains about Java, install JDK 17:

```bash
sudo apt install openjdk-17-jdk
flutter config --jdk-dir /usr/lib/jvm/java-17-openjdk-amd64
```

### 2.4 Linux desktop dependencies (for fast UI testing)

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
flutter config --enable-linux-desktop
```

---

## 3. Create the Flutter project

Create the Flutter app inside the project repository so everything stays in one
Git history:

```bash
cd ~/development/TasteHub-App
flutter create tastehub_app
cd tastehub_app
flutter pub add http image_picker url_launcher path_provider path
```

Create the folders:

```bash
mkdir -p lib/api lib/models lib/screens lib/widgets assets/images
```

---

## 4. Add the API URL configuration

Create `lib/config.dart`:

```dart
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8080',
);

// Used in Stage 5.
const String geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: '',
);
```

Do not put a trailing slash in `API_BASE_URL`.

---

## 5. Create the recipe model

Create `lib/models/recipe.dart`:

```dart
class Recipe {
  final int id;
  final String title;
  final String dish;
  final String mainIngredient;
  final int cookingTime;
  final String imageRef;
  final String youtubeUrl;
  final double averageRating;
  final int ratingCount;
  final int myRating;
  final String createdAt;
  final String? updatedAt;
  final List<String> ingredients;
  final List<String> steps;

  const Recipe({
    required this.id,
    required this.title,
    required this.dish,
    required this.mainIngredient,
    required this.cookingTime,
    required this.imageRef,
    required this.youtubeUrl,
    required this.averageRating,
    required this.ratingCount,
    required this.myRating,
    required this.createdAt,
    this.updatedAt,
    this.ingredients = const <String>[],
    this.steps = const <String>[],
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      dish: json['dish'] as String? ?? '',
      mainIngredient: json['mainIngredient'] as String? ?? '',
      cookingTime: (json['cookingTime'] as num?)?.toInt() ?? 0,
      imageRef: json['imageRef'] as String? ?? '',
      youtubeUrl: json['youtubeUrl'] as String? ?? '',
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      myRating: (json['myRating'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String?,
      ingredients: (json['ingredients'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const <String>[],
      steps: (json['steps'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const <String>[],
    );
  }
}

class LeaderboardEntry {
  final int rank;
  final Recipe recipe;
  final double averageRating;
  final int ratingCount;

  const LeaderboardEntry({
    required this.rank,
    required this.recipe,
    required this.averageRating,
    required this.ratingCount,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      recipe: Recipe.fromJson(json['recipe'] as Map<String, dynamic>),
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
    );
  }
}
```

---

## 6. Create the API client

Create `lib/api/api_client.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/recipe.dart';

class ApiException implements Exception {
  final int status;
  final String message;

  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 10);

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse('$apiBaseUrl$path');
    return query == null ? base : base.replace(queryParameters: query);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = _uri(path, query);
    const headers = {'Content-Type': 'application/json'};
    late http.Response response;

    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: headers).timeout(_timeout);
        break;
      case 'POST':
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(_timeout);
        break;
      case 'PUT':
        response = await _client
            .put(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(_timeout);
        break;
      case 'DELETE':
        response =
            await _client.delete(uri, headers: headers).timeout(_timeout);
        break;
      default:
        throw ArgumentError('Unsupported method $method');
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode >= 400) {
      final message = decoded is Map && decoded['error'] is String
          ? decoded['error'] as String
          : 'HTTP ${response.statusCode}';
      throw ApiException(response.statusCode, message);
    }
    return decoded;
  }

  Future<List<Recipe>> listRecipes() async {
    final data = await _request('GET', '/api/recipes');
    return (data as List)
        .map((item) => Recipe.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Recipe> getRecipe(int id) async {
    final data = await _request('GET', '/api/recipes/$id');
    return Recipe.fromJson(data as Map<String, dynamic>);
  }

  Future<Recipe> addRecipe(Map<String, dynamic> body) async {
    final data = await _request('POST', '/api/recipes', body: body);
    return Recipe.fromJson(data as Map<String, dynamic>);
  }

  Future<Recipe> updateRecipe(int id, Map<String, dynamic> body) async {
    final data = await _request('PUT', '/api/recipes/$id', body: body);
    return Recipe.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteRecipe(int id) async {
    await _request('DELETE', '/api/recipes/$id');
  }

  Future<List<Recipe>> searchRecipes(String query) async {
    final data = await _request(
      'GET',
      '/api/search',
      query: {'q': query},
    );
    final results = (data as Map<String, dynamic>)['results'] as List;
    return results
        .map((item) => Recipe.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> rateRecipe(int id, int stars) async {
    final data = await _request(
      'PUT',
      '/api/recipes/$id/rating',
      body: {'stars': stars},
    );
    return data as Map<String, dynamic>;
  }

  Future<List<LeaderboardEntry>> leaderboard() async {
    final data = await _request('GET', '/api/leaderboard');
    final list = (data as Map<String, dynamic>)['leaderboard'] as List;
    return list
        .map((item) =>
            LeaderboardEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> health() async {
    final data = await _request('GET', '/api/health');
    return data as Map<String, dynamic>;
  }
}
```

---

## 7. Create small widgets

### 7.1 `lib/widgets/recipe_image.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';

class RecipeImage extends StatelessWidget {
  final String imageRef;
  final BoxFit fit;

  const RecipeImage({
    super.key,
    required this.imageRef,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (imageRef.isEmpty) return _placeholder();

    if (imageRef.startsWith('asset:')) {
      return Image.asset(
        imageRef.substring(6),
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    if (imageRef.startsWith('http://') || imageRef.startsWith('https://')) {
      return Image.network(
        imageRef,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    final file = File(imageRef);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: Colors.deepOrange.shade100,
      child: const Center(
        child: Icon(Icons.restaurant, size: 36, color: Colors.deepOrange),
      ),
    );
  }
}
```

### 7.2 `lib/widgets/rating_stars.dart`

```dart
import 'package:flutter/material.dart';

class RatingStars extends StatelessWidget {
  final double rating;
  final int count;
  final int myRating;
  final ValueChanged<int>? onRate;

  const RatingStars({
    super.key,
    required this.rating,
    required this.count,
    this.myRating = 0,
    this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final shown = onRate != null ? myRating : rating.round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          if (onRate == null)
            Icon(
              i <= shown ? Icons.star : Icons.star_border,
              size: 18,
              color: Colors.amber,
            )
          else
            IconButton(
              onPressed: () => onRate!(i),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(
                i <= shown ? Icons.star : Icons.star_border,
                size: 22,
                color: Colors.amber,
              ),
            ),
        const SizedBox(width: 6),
        Text('${rating.toStringAsFixed(1)} ($count)'),
      ],
    );
  }
}
```

### 7.3 `lib/widgets/error_view.dart`

```dart
import 'package:flutter/material.dart';

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
```

### 7.4 `lib/widgets/recipe_card.dart`

```dart
import 'package:flutter/material.dart';

import '../models/recipe.dart';
import 'rating_stars.dart';
import 'recipe_image.dart';

class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onTap;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: RecipeImage(imageRef: recipe.imageRef),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${recipe.dish} · ${recipe.cookingTime} min',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    RatingStars(
                      rating: recipe.averageRating,
                      count: recipe.ratingCount,
                      myRating: recipe.myRating,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 8. Create the screens

### 8.1 `lib/screens/recipe_list_screen.dart`

```dart
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/recipe.dart';
import '../widgets/error_view.dart';
import '../widgets/recipe_card.dart';
import 'recipe_detail_screen.dart';

class RecipeListScreen extends StatefulWidget {
  final ApiClient api;
  final int refreshTick;

  const RecipeListScreen({
    super.key,
    required this.api,
    required this.refreshTick,
  });

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  late Future<List<Recipe>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.listRecipes();
  }

  @override
  void didUpdateWidget(covariant RecipeListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _load();
    }
  }

  void _load() {
    setState(() {
      _future = widget.api.listRecipes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TasteHub'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<Recipe>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: '${snapshot.error}',
              onRetry: _load,
            );
          }

          final recipes = snapshot.data ?? const <Recipe>[];
          if (recipes.isEmpty) {
            return const Center(
              child: Text('No recipes yet. Tap "Add recipe".'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: recipes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final recipe = recipes[index];
                return RecipeCard(
                  recipe: recipe,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeDetailScreen(
                          api: widget.api,
                          recipeId: recipe.id,
                        ),
                      ),
                    );
                    _load();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
```

### 8.2 `lib/screens/recipe_detail_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../models/recipe.dart';
import '../widgets/error_view.dart';
import '../widgets/rating_stars.dart';
import '../widgets/recipe_image.dart';

class RecipeDetailScreen extends StatefulWidget {
  final ApiClient api;
  final int recipeId;

  const RecipeDetailScreen({
    super.key,
    required this.api,
    required this.recipeId,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  late Future<Recipe> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getRecipe(widget.recipeId);
  }

  void _load() {
    setState(() {
      _future = widget.api.getRecipe(widget.recipeId);
    });
  }

  Future<void> _rate(int stars) async {
    try {
      await widget.api.rateRecipe(widget.recipeId, stars);
      _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _openYouTube(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recipe')),
      body: FutureBuilder<Recipe>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: '${snapshot.error}',
              onRetry: _load,
            );
          }

          final recipe = snapshot.data!;
          return ListView(
            children: [
              SizedBox(
                height: 240,
                width: double.infinity,
                child: RecipeImage(imageRef: recipe.imageRef),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${recipe.dish} · ${recipe.cookingTime} min · '
                      '${recipe.mainIngredient}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    RatingStars(
                      rating: recipe.averageRating,
                      count: recipe.ratingCount,
                      myRating: recipe.myRating,
                      onRate: _rate,
                    ),
                    const SizedBox(height: 16),
                    if (recipe.youtubeUrl.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () => _openYouTube(recipe.youtubeUrl),
                        icon: const Icon(Icons.play_circle),
                        label: const Text('Watch on YouTube'),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Ingredients',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    for (final item in recipe.ingredients)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(item),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Steps',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < recipe.steps.length; i++)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${i + 1}'),
                        ),
                        title: Text(recipe.steps[i]),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

### 8.3 `lib/screens/recipe_form_screen.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../models/recipe.dart';

class RecipeFormScreen extends StatefulWidget {
  final ApiClient api;
  final Recipe? recipe;

  const RecipeFormScreen({
    super.key,
    required this.api,
    this.recipe,
  });

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final _title = TextEditingController();
  final _dish = TextEditingController();
  final _mainIngredient = TextEditingController();
  final _cookingTime = TextEditingController();
  final _ingredients = TextEditingController();
  final _steps = TextEditingController();
  final _imageRef = TextEditingController();
  final _youtubeUrl = TextEditingController();

  bool _saving = false;

  bool get _isEditing => widget.recipe != null;

  @override
  void initState() {
    super.initState();
    final recipe = widget.recipe;
    if (recipe != null) {
      _title.text = recipe.title;
      _dish.text = recipe.dish;
      _mainIngredient.text = recipe.mainIngredient;
      _cookingTime.text = '${recipe.cookingTime}';
      _ingredients.text = recipe.ingredients.join('\n');
      _steps.text = recipe.steps.join('\n');
      _imageRef.text = recipe.imageRef;
      _youtubeUrl.text = recipe.youtubeUrl;
    } else {
      _dish.text = 'My Recipes';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _dish.dispose();
    _mainIngredient.dispose();
    _cookingTime.dispose();
    _ingredients.dispose();
    _steps.dispose();
    _imageRef.dispose();
    _youtubeUrl.dispose();
    super.dispose();
  }

  List<String> _lines(TextEditingController controller) {
    return controller.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<void> _pickImage() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Image picker is for Android. Type a path or URL for desktop.',
          ),
        ),
      );
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;

    final directory = await getApplicationDocumentsDirectory();
    final extension = p.extension(picked.path);
    final newPath =
        '${directory.path}/recipe_${DateTime.now().millisecondsSinceEpoch}$extension';
    await File(picked.path).copy(newPath);

    if (!mounted) return;
    setState(() {
      _imageRef.text = newPath;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final body = {
        'dish': _dish.text.trim().isEmpty ? 'My Recipes' : _dish.text.trim(),
        'title': title,
        'mainIngredient': _mainIngredient.text.trim(),
        'ingredients': _lines(_ingredients),
        'steps': _lines(_steps),
        'cookingTime': int.tryParse(_cookingTime.text.trim()) ?? 0,
        'imageRef': _imageRef.text.trim(),
        'youtubeUrl': _youtubeUrl.text.trim(),
      };

      if (_isEditing) {
        await widget.api.updateRecipe(widget.recipe!.id, body);
      } else {
        await widget.api.addRecipe(body);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit recipe' : 'Add recipe'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dish,
            enabled: !_isEditing,
            decoration: const InputDecoration(
              labelText: 'Dish (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mainIngredient,
            decoration: const InputDecoration(
              labelText: 'Main ingredient',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cookingTime,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cooking time (minutes)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ingredients,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Ingredients (one per line)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _steps,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Steps (one per line)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _imageRef,
            decoration: InputDecoration(
              labelText: 'Image path or URL',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                tooltip: 'Pick image',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _youtubeUrl,
            decoration: const InputDecoration(
              labelText: 'YouTube URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Saving...' : 'Save recipe'),
          ),
        ],
      ),
    );
  }
}
```

### 8.4 `lib/screens/search_screen.dart`

```dart
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/recipe.dart';
import '../widgets/error_view.dart';
import '../widgets/recipe_card.dart';
import 'recipe_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final ApiClient api;

  const SearchScreen({super.key, required this.api});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Future<List<Recipe>>? _future;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _future = widget.api.searchRecipes(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Try "biriyani" or "chiken"',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _search, child: const Text('Search')),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Recipe>>(
              future: _future,
              builder: (context, snapshot) {
                if (_future == null) {
                  return const Center(
                    child: Text('Search by recipe, ingredient, or step.'),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ErrorView(
                    message: '${snapshot.error}',
                    onRetry: _search,
                  );
                }

                final recipes = snapshot.data ?? const <Recipe>[];
                if (recipes.isEmpty) {
                  return const Center(child: Text('No matches.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: recipes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final recipe = recipes[index];
                    return RecipeCard(
                      recipe: recipe,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RecipeDetailScreen(
                              api: widget.api,
                              recipeId: recipe.id,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

### 8.5 `lib/screens/leaderboard_screen.dart`

```dart
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/recipe.dart';
import '../widgets/error_view.dart';
import '../widgets/recipe_image.dart';
import 'recipe_detail_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  final ApiClient api;
  final int refreshTick;

  const LeaderboardScreen({
    super.key,
    required this.api,
    required this.refreshTick,
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late Future<List<LeaderboardEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.leaderboard();
  }

  @override
  void didUpdateWidget(covariant LeaderboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _load();
    }
  }

  void _load() {
    setState(() {
      _future = widget.api.leaderboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<LeaderboardEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: '${snapshot.error}',
              onRetry: _load,
            );
          }

          final entries = snapshot.data ?? const <LeaderboardEntry>[];
          if (entries.isEmpty) {
            return const Center(child: Text('No ratings yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeDetailScreen(
                          api: widget.api,
                          recipeId: entry.recipe.id,
                        ),
                      ),
                    );
                  },
                  leading: CircleAvatar(
                    child: Text('${entry.rank}'),
                  ),
                  title: Text(entry.recipe.title),
                  subtitle: Text(
                    '${entry.averageRating.toStringAsFixed(1)} / 5 · '
                    '${entry.ratingCount} ratings',
                  ),
                  trailing: SizedBox(
                    width: 56,
                    height: 56,
                    child: RecipeImage(imageRef: entry.recipe.imageRef),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

---

## 9. Create `lib/main.dart`

Replace the generated `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/recipe_form_screen.dart';
import 'screens/recipe_list_screen.dart';
import 'screens/search_screen.dart';

void main() {
  runApp(const TasteHubApp());
}

class TasteHubApp extends StatelessWidget {
  const TasteHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TasteHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _api = ApiClient();
  int _index = 0;
  int _refreshTick = 0;

  void _refresh() {
    setState(() {
      _refreshTick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          RecipeListScreen(api: _api, refreshTick: _refreshTick),
          SearchScreen(api: _api),
          LeaderboardScreen(api: _api, refreshTick: _refreshTick),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          setState(() {
            _index = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu),
            label: 'Recipes',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard),
            label: 'Leaderboard',
          ),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecipeFormScreen(api: _api),
                  ),
                );
                if (created == true) _refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add recipe'),
            )
          : null,
    );
  }
}
```

---

## 10. Configure assets

Edit `pubspec.yaml` and add the assets section under `flutter:`:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
```

For Stage 4, the folder may be empty. The app uses a placeholder when an image
is missing. Stage 5 adds the actual images.

---

## 11. Configure Android

### 11.1 Internet permission

Open `android/app/src/main/AndroidManifest.xml` and add this inside `<manifest>`,
before `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### 11.2 Cleartext HTTP for the debug build

Create or edit `android/app/src/debug/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:usesCleartextTraffic="true" />
</manifest>
```

If you use Tailscale Serve HTTPS, you do not need cleartext.

---

## 12. Test on the Linux desktop first

This is faster than rebuilding the APK for every UI change.

```bash
cd ~/development/TasteHub-App/tastehub_app
flutter pub get
flutter run -d linux \
  --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

The backend must be running on the laptop. You should see the recipe list.

Test:

- [ ] List shows 6 recipes.
- [ ] Tap a recipe → detail shows ingredients and steps.
- [ ] Tap the stars → rating changes.
- [ ] Search `biriyani` → Chicken Biryani.
- [ ] Search `chiken` → chicken recipes.
- [ ] Add a recipe → it appears in the list.
- [ ] Leaderboard shows rated recipes.
- [ ] Restart the server → data is still there.

Image picking is Android-only in this guide. On Linux, type an asset path or
URL into the image field to test the placeholder/network image path.

---

## 13. Build and install the APK

### Option A — debug APK (recommended for the demo)

```bash
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://100.x.y.z:8080
```

APK:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Install over USB:

```bash
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Or copy the APK to the phone and install it manually.

### Option B — release APK with Tailscale Serve HTTPS

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://my-laptop.tailnet-name.ts.net
```

APK:

```text
build/app/outputs/flutter-apk/app-release.apk
```

For a course demo, the debug APK is enough. A release build needs signing
configuration only if you publish it.

---

## 14. Checkpoint

- [ ] `flutter doctor -v` shows Android toolchain OK.
- [ ] App runs on Linux desktop against `127.0.0.1:8080`.
- [ ] App lists all 6 seed recipes.
- [ ] Detail screen shows ingredients, steps, and rating.
- [ ] Rating a recipe updates the average.
- [ ] Search is typo-tolerant (`biriyani`, `chiken`).
- [ ] Add recipe creates a new recipe on the server.
- [ ] Leaderboard shows the rated recipes in order.
- [ ] APK builds and installs on the phone.
- [ ] Phone app reaches the server over Tailscale.
- [ ] Restarting the server keeps the data.

---

## 15. Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `No Android SDK found` | `ANDROID_HOME` not set | Set it and run `flutter config --android-sdk "$ANDROID_HOME"` |
| `flutter doctor` Java error | Wrong JDK | Install JDK 17 and set `flutter config --jdk-dir ...` |
| Gradle build fails | Stale build | `flutter clean && flutter pub get && flutter build apk --debug` |
| `Cleartext HTTP traffic not permitted` | Debug manifest missing | Add `usesCleartextTraffic="true"` |
| `Connection refused` | Server not running or wrong URL | Start the server; check `API_BASE_URL` |
| `SocketException: Network is unreachable` | Tailscale off on the phone | Turn on Tailscale |
| `FormatException` / `type 'Null' is not a subtype` | API shape changed | Compare with `API.md`; check the server response |
| `Image asset not found` | Asset missing | Add the image in Stage 5 or use a URL |
| Image picker does nothing on Linux | `image_picker` is Android/iOS only | Test image picking on the phone |
| `setState() called after dispose` | Async result after leaving the screen | The code already checks `mounted`; keep those checks |
| Keyboard covers the form | Long form | Scroll the form; `ListView` handles it |
| App shows old data | List not refreshed | Pull to refresh or tap the refresh icon |

---

## 16. Handoff to Stage 5

Stage 5 adds:

- Gemini AI formatting of long recipe text.
- Real seed images.
- YouTube validation and polish.
- A demo reset script and smoke test.
- A repeatable demo script.

**Commit:**

```bash
cd ~/development/TasteHub-App
git add -A
git commit -m "Stage 4: Flutter app"
```
