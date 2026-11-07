# Stage 5 — Demo Polish

**Goal:** add AI formatting, real images, YouTube links, a reset script, and a
repeatable demo run. This is the stage that makes the project feel finished.

**Done when:** you can run the full demo twice in a row without touching code.

---

## 1. Prerequisites

- Stage 4 checkpoint passed.
- The app lists, opens, adds, searches, and rates recipes.
- The server and Tailscale connection work.
- You have a Google account for Gemini.

---

## 2. Get a Gemini API key

1. Open <https://aistudio.google.com/app/apikey>.
2. Create an API key.
3. Copy it somewhere safe. Do not commit it.

For a demo, use a restricted key:

- Restrict it to the Gemini API.
- Set a low quota if possible.
- Delete or rotate it after the demo.

The key is passed at build time:

```bash
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://100.x.y.z:8080 \
  --dart-define=GEMINI_API_KEY=YOUR_KEY_HERE
```

Because the key is inside the APK, treat it as public. Never use a billable key
with a high limit.

---

## 3. Add the Gemini service

Create `lib/services/gemini_service.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class GeminiException implements Exception {
  final String message;

  GeminiException(this.message);

  @override
  String toString() => message;
}

class GeminiService {
  GeminiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // If this model is retired, replace it with the current free-tier model
  // shown in Google AI Studio.
  static const _model = 'gemini-2.5-flash';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  Future<Map<String, dynamic>> formatRecipe(String rawText) async {
    if (geminiApiKey.isEmpty) {
      throw GeminiException(
        'GEMINI_API_KEY is not set. Build with '
        '--dart-define=GEMINI_API_KEY=...',
      );
    }
    if (rawText.trim().isEmpty) {
      throw GeminiException('Paste a recipe first.');
    }

    final prompt = '''
You are a recipe formatter. Convert the user's recipe text into strict JSON.
Return ONLY a JSON object. No markdown, no code fences, no explanation.

The JSON object must have exactly these fields:
{
  "title": "short recipe name",
  "dish": "dish category, for example Biryani, Karahi, Dessert",
  "mainIngredient": "main ingredient",
  "ingredients": ["ingredient 1", "ingredient 2"],
  "steps": ["step 1", "step 2"],
  "cookingTime": 45,
  "youtubeUrl": ""
}

Rules:
- ingredients and steps must be arrays of strings.
- cookingTime must be an integer number of minutes. Use 0 if unknown.
- Do not invent a YouTube URL. Leave youtubeUrl empty.
- Keep the recipe text's language. If it is Urdu, keep Urdu.
- If a field is missing, use an empty string or empty array.

Recipe text:
$rawText
''';

    final response = await _client
        .post(
          Uri.parse('$_endpoint?key=$geminiApiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.2,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 400) {
      throw GeminiException(
        'Gemini HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw GeminiException('Gemini returned no candidates.');
    }

    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw GeminiException('Gemini returned an empty response.');
    }

    final text = parts.first['text'] as String? ?? '';
    final jsonText = _extractJson(text);
    final data = jsonDecode(jsonText) as Map<String, dynamic>;
    return _validate(data);
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw GeminiException('Gemini did not return JSON.');
    }
    return text.substring(start, end + 1);
  }

  Map<String, dynamic> _validate(Map<String, dynamic> data) {
    String stringValue(String key) =>
        data[key] is String ? data[key] as String : '';

    List<String> stringList(String key) {
      final value = data[key];
      if (value is! List) return [];
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    int intValue(String key) {
      final value = data[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return {
      'title': stringValue('title'),
      'dish': stringValue('dish').isEmpty ? 'My Recipes' : stringValue('dish'),
      'mainIngredient': stringValue('mainIngredient'),
      'ingredients': stringList('ingredients'),
      'steps': stringList('steps'),
      'cookingTime': intValue('cookingTime'),
      'youtubeUrl': stringValue('youtubeUrl'),
    };
  }
}
```

---

## 4. Add the fallback formatter

The demo must still work if Gemini fails. Create
`lib/services/local_recipe_formatter.dart`:

```dart
class LocalRecipeFormatter {
  static Map<String, dynamic> format(String rawText) {
    final lines = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final title = lines.isNotEmpty ? lines.first : 'My Recipe';
    final ingredients = <String>[];
    final steps = <String>[];
    var mode = '';

    for (final line in lines.skip(1)) {
      final lower = line.toLowerCase();

      if (lower.startsWith('ingredient')) {
        mode = 'ingredients';
        continue;
      }
      if (lower.startsWith('step') ||
          lower.startsWith('method') ||
          lower.startsWith('instruction')) {
        mode = 'steps';
        continue;
      }

      final cleaned = line
          .replaceFirst(RegExp(r'^[-*0-9.\s]+'), '')
          .trim();
      if (cleaned.isEmpty) continue;

      if (mode == 'ingredients') {
        ingredients.add(cleaned);
      } else if (mode == 'steps') {
        steps.add(cleaned);
      } else if (ingredients.isEmpty) {
        ingredients.add(cleaned);
      } else {
        steps.add(cleaned);
      }
    }

    return {
      'title': title,
      'dish': 'My Recipes',
      'mainIngredient': ingredients.isNotEmpty ? ingredients.first : '',
      'ingredients': ingredients,
      'steps': steps,
      'cookingTime': 0,
      'youtubeUrl': '',
    };
  }
}
```

This is intentionally simple. It is a safety net, not a replacement for Gemini.

---

## 5. Add the AI box to the add-recipe screen

Open `lib/screens/recipe_form_screen.dart`.

### 5.1 Add imports

At the top, add:

```dart
import '../services/gemini_service.dart';
import '../services/local_recipe_formatter.dart';
```

### 5.2 Add state

Inside `_RecipeFormScreenState`, add:

```dart
final _aiText = TextEditingController();
bool _formatting = false;
```

In `dispose()`, add:

```dart
_aiText.dispose();
```

### 5.3 Add the formatting method

Add this method inside `_RecipeFormScreenState`:

```dart
Future<void> _formatWithAI() async {
  final raw = _aiText.text.trim();
  if (raw.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Paste a recipe first.')),
    );
    return;
  }

  setState(() => _formatting = true);
  try {
    Map<String, dynamic> data;
    try {
      data = await GeminiService().formatRecipe(raw);
    } catch (error) {
      data = LocalRecipeFormatter.format(raw);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI unavailable, used basic formatting: $error'),
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _title.text = (data['title'] as String?)?.isNotEmpty == true
          ? data['title'] as String
          : _title.text;
      _dish.text = (data['dish'] as String?)?.isNotEmpty == true
          ? data['dish'] as String
          : _dish.text;
      _mainIngredient.text =
          (data['mainIngredient'] as String?) ?? _mainIngredient.text;
      _ingredients.text = (data['ingredients'] as List).join('\n');
      _steps.text = (data['steps'] as List).join('\n');
      _cookingTime.text = '${data['cookingTime'] ?? 0}';
      _youtubeUrl.text =
          (data['youtubeUrl'] as String?) ?? _youtubeUrl.text;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Formatted. Review before saving.')),
    );
  } finally {
    if (mounted) setState(() => _formatting = false);
  }
}
```

### 5.4 Add the AI box to the form

In the `ListView` inside `build()`, put this **above** the title field:

```dart
TextField(
  controller: _aiText,
  maxLines: 6,
  decoration: const InputDecoration(
    labelText: 'Paste a long recipe for AI formatting',
    hintText: 'Paste ingredients, steps, and notes here...',
    border: OutlineInputBorder(),
  ),
),
const SizedBox(height: 8),
OutlinedButton.icon(
  onPressed: _formatting ? null : _formatWithAI,
  icon: _formatting
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : const Icon(Icons.auto_awesome),
  label: Text(_formatting ? 'Formatting...' : 'Format with AI'),
),
const Divider(height: 32),
```

The flow is:

1. Paste a long recipe.
2. Tap **Format with AI**.
3. Gemini fills the form.
4. Review and fix anything.
5. Save to the C++ server.

---

## 6. Add real images

The seed uses these asset paths:

| Recipe | Asset |
|---|---|
| Crispy Fries | `assets/images/fries.jpg` |
| Hydrabadi Pulao | `assets/images/pulao.jpg` |
| Peshawari Karahi | `assets/images/karahi.jpg` |
| spicy chicken tikka | `assets/images/chicken-tikka.jpg` |
| Chicken Biryani | `assets/images/biryani.jpg` |
| Beef Nihari | `assets/images/nihari.jpg` |

Put six photos in `tastehub_app/assets/images/` with those exact names.

Sources:

- your own food photos
- free stock sites such as Unsplash or Pexels (check the license)
- screenshots from recipe videos (only for a private course demo)

Make sure `pubspec.yaml` contains:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
```

Then:

```bash
flutter clean
flutter pub get
```

If an image is missing, the app shows an orange placeholder instead of crashing.

### Using URLs instead of assets

If you prefer network images, change `imageRef` in `seed/recipes.json` to a
direct image URL:

```json
"imageRef": "https://images.unsplash.com/photo-..."
```

Then reset the runtime data:

```bash
./scripts/reset-demo.sh
```

Network images depend on internet access. Local assets are safer for a demo.

---

## 7. YouTube polish

The seed uses YouTube search URLs, for example:

```text
https://www.youtube.com/results?search_query=chicken+biryani+recipe
```

These always open something relevant. If you want a specific video, replace the
URL with:

```text
https://www.youtube.com/watch?v=VIDEO_ID
```

Optional validation before saving: add this helper to the form file:

```dart
bool _looksLikeYouTube(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  return uri.host.contains('youtube.com') || uri.host == 'youtu.be';
}
```

In `_save()`, before building the body:

```dart
final youtubeUrl = _youtubeUrl.text.trim();
if (youtubeUrl.isNotEmpty && !_looksLikeYouTube(youtubeUrl)) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Please enter a valid YouTube URL.')),
  );
  return;
}
```

Then use `'youtubeUrl': youtubeUrl` in the body.

The detail screen already opens the URL with `url_launcher` in external mode.

---

## 8. Reset the demo data safely

`data/recipes.json` is loaded into memory when the server starts. If you reset
the file while the server is running, the server will overwrite it on the next
save.

Correct order:

```bash
# 1. Stop the server with Ctrl+C in its terminal.

# 2. Reset the file.
cd ~/development/TasteHub-App
./scripts/reset-demo.sh

# 3. Start the server again.
./build/tastehub-server --host 0.0.0.0 --port 8080 --data-dir data
```

Do this before every demo rehearsal.

---

## 9. Add the smoke test

Create `tests/smoke_test.py`:

```python
#!/usr/bin/env python3
import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8080"


def request(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            text = response.read().decode()
            return response.status, json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        text = error.read().decode()
        return error.code, json.loads(text) if text else None


def check(condition, message):
    if condition:
        print(f"PASS: {message}")
    else:
        print(f"FAIL: {message}")
        sys.exit(1)


status, health = request("GET", "/api/health")
check(status == 200, "health returns 200")
check(health["status"] == "ok", "health status is ok")
check(health["recipes"] >= 6, "health reports at least 6 recipes")

status, recipes = request("GET", "/api/recipes")
check(status == 200, "list returns 200")
check(isinstance(recipes, list) and len(recipes) >= 6, "list has at least 6 recipes")

status, detail = request("GET", "/api/recipes/5")
check(status == 200, "detail returns 200")
check(detail["title"] == "Chicken Biryani", "recipe 5 is Chicken Biryani")
check(isinstance(detail.get("ingredients"), list), "detail has ingredients")
check(isinstance(detail.get("steps"), list), "detail has steps")

status, search = request("GET", "/api/search?q=biriyani")
check(status == 200, "typo search returns 200")
check(
    any(item["title"] == "Chicken Biryani" for item in search["results"]),
    "typo search finds Biryani",
)

status, search = request("GET", "/api/search?q=chiken")
check(status == 200, "chicken typo search returns 200")
check(len(search["results"]) > 0, "chicken typo search returns results")

body = {
    "dish": "Smoke Test",
    "title": "Smoke Test Curry",
    "mainIngredient": "chicken",
    "ingredients": ["chicken", "spices"],
    "steps": ["mix", "cook"],
    "cookingTime": 20,
    "imageRef": "",
    "youtubeUrl": "",
}
status, created = request("POST", "/api/recipes", body)
check(status == 201, "create returns 201")
recipe_id = created["id"]
check(created["title"] == "Smoke Test Curry", "created recipe has the right title")

status, rating = request("PUT", f"/api/recipes/{recipe_id}/rating", {"stars": 5})
check(status == 200, "rating returns 200")
check(rating["myRating"] == 5, "rating is saved")

status, leaderboard = request("GET", "/api/leaderboard")
check(status == 200, "leaderboard returns 200")
check(
    any(
        item["recipe"]["id"] == recipe_id
        for item in leaderboard["leaderboard"]
    ),
    "new recipe is on the leaderboard",
)

status, updated = request(
    "PUT", f"/api/recipes/{recipe_id}", {"title": "Smoke Test Curry Updated"}
)
check(status == 200, "update returns 200")
check(updated["title"] == "Smoke Test Curry Updated", "title was updated")

status, deleted = request("DELETE", f"/api/recipes/{recipe_id}")
check(status == 200, "delete returns 200")
check(deleted["deleted"] is True, "delete response is correct")

status, missing = request("GET", f"/api/recipes/{recipe_id}")
check(status == 404, "deleted recipe returns 404")

print("\nAll smoke tests passed.")
```

Run it while the server is running:

```bash
cd ~/development/TasteHub-App
python3 tests/smoke_test.py
```

Expected:

```text
PASS: health returns 200
...
All smoke tests passed.
```

The smoke test adds and deletes a recipe. Reset the data afterward if you want a
clean demo.

---

## 10. Full demo script

Rehearse this twice. Time yourself.

### Before the demo

```bash
cd ~/development/TasteHub-App

# Stop the old server first.
./scripts/reset-demo.sh
./build/tastehub-server --host 0.0.0.0 --port 8080 --data-dir data
```

On the phone:

1. Turn on Tailscale.
2. Open `http://100.x.y.z:8080/api/health` in the browser.
3. Confirm `{"recipes":6,"status":"ok"}`.

### Demo flow

1. **Open the app.** Show the recipe list and images.
2. **Open Chicken Biryani.** Show ingredients, steps, rating, and the YouTube
   button.
3. **Search with a typo.** Type `biriyani`. Show that Chicken Biryani is found.
4. **Search again.** Type `chiken`. Show chicken recipes.
5. **Rate a recipe.** Tap 5 stars. Show the average change.
6. **Open the leaderboard.** Show the ranking.
7. **Add a recipe.** Tap **Add recipe**.
8. **Paste a long recipe** into the AI box.
9. **Tap Format with AI.** Show the form being filled.
10. **Pick an image** (on the phone) and paste a YouTube URL.
11. **Save.** Show the new recipe in the list.
12. **Rate the new recipe.** Show it on the leaderboard.
13. **Restart the server.** Stop it with `Ctrl+C`, start it again, and refresh the
    app. Show that the recipe is still there.
14. **Fallback check.** If Tailscale fails, use the same Wi-Fi IP or
    `adb reverse`.

### After the demo

```bash
# Stop the server.
# Reset the data for the next run.
./scripts/reset-demo.sh
```

---

## 11. Final checklist

- [ ] Six seed recipes load with images.
- [ ] `biriyani` finds Chicken Biryani.
- [ ] `chiken` finds chicken recipes.
- [ ] Rating changes the average and the leaderboard.
- [ ] Add recipe works.
- [ ] AI formatting works, and the fallback works when the key is missing.
- [ ] Image picker works on the phone.
- [ ] YouTube button opens the link.
- [ ] The APK works over Tailscale.
- [ ] The same-Wi-Fi fallback works.
- [ ] The `adb reverse` fallback works.
- [ ] Data survives a server restart.
- [ ] `python3 tests/smoke_test.py` passes.
- [ ] The full demo has been run twice without errors.
- [ ] The laptop is set to stay awake.
- [ ] The Gemini key is restricted and will be rotated after the demo.

---

## 12. Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `GEMINI_API_KEY is not set` | Build command missing the define | Add `--dart-define=GEMINI_API_KEY=...` |
| Gemini `400` | Bad prompt or malformed request | Check the key and the model name |
| Gemini `403` | Key restricted or API not enabled | Enable the Generative Language API in Google Cloud |
| Gemini returns no JSON | Model added prose | The app falls back to basic formatting; tighten the prompt |
| AI fills empty fields | Model returned different keys | Check the prompt and `_validate` |
| Images show placeholders | Files missing or wrong names | Add the six files under `assets/images/` |
| Image still missing after adding | Asset bundle not rebuilt | `flutter clean && flutter pub get`, rebuild |
| YouTube button does nothing | Invalid URL or no browser | Check the URL; test in the phone browser |
| Reset does not change the app | Server was running during reset | Stop server, reset, restart |
| Smoke test fails at recipe 5 | Data was changed | `./scripts/reset-demo.sh`, restart server |
| Leaderboard order looks wrong | Average tie | The server tie-breaks by count, then newest |
| App is slow on first load | Network image or cold server | Use local assets; keep the server running |

---

## 13. What to show the grader

The C++ OOP evidence is in the backend:

- `BaseEntity` → `Comment`, `Variant`, `Dish`, `User` (inheritance)
- `protected` fields with getters/setters (encapsulation)
- `Dish` owns `Variant`s; `Variant` owns `Recipe`, ratings, comments
  (composition)
- `RecipeDatabase` and `BackendService` hide storage details (abstraction)
- `BaseEntity::toJson()` called through a `BaseEntity&` (polymorphism)

The demo features are:

- add recipe
- typo-tolerant search
- AI formatting
- images
- YouTube links
- ratings
- leaderboard

---

## 14. Final commit

```bash
cd ~/development/TasteHub-App
git add -A
git commit -m "Stage 5: AI formatting, images, and demo polish"
```

You are done. Run the demo twice, then stop the server and reset the data.
