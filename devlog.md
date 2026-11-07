# TasteHub Devlog

## 2026-11-07 — Stage 1: backend brain

### Status

Stage 1 is complete at the backend level.

There is no HTTP server yet. The current entry point is `backend_test.cpp`, which
acts like a temporary client and calls `BackendService` directly. Stage 2 will
replace those direct calls with `cpp-httplib` routes.

What works today:

- Load the 6 demo recipes from `seed/recipes.json`.
- List recipes.
- Get one recipe with ingredients, steps, ratings and proof images.
- Add a recipe (variant) to an existing dish or a new dish.
- Store `imageRef` and `youtubeUrl` with a recipe.
- Edit a recipe.
- Delete a recipe. Empty dishes are removed automatically.
- Search dish names, recipe titles, ingredients and steps with typo tolerance.
- Rate a recipe 1–5 with an optional proof image.
- Update an existing rating without creating a second rating for the same user.
- Rank rated recipes on the leaderboard.
- Persist everything to JSON with atomic saves.
- Keep the old console programs compiling.

### Data flow

```text
backend_test.cpp
      |
      v
BackendService.h          <-- validation, mutex, JSON shapes, fuzzy search
      |
      v
RecipeCore.h              <-- OOP model + RecipeDatabase storage
      |
      v
data/backend-test/recipes.json   (test copy)
data/recipes.json                (real demo data, not touched by tests)
seed/recipes.json                (tracked clean seed)
```

In Stage 2 the top box becomes `server.cpp`, but everything below it stays the
same.

### Files in Stage 1

| File | Role |
|---|---|
| `RecipeCore.h` | Domain classes and JSON storage |
| `BackendService.h` | Backend facade used by the test and future HTTP server |
| `backend_test.cpp` | Stage 1 acceptance test |
| `API.md` | Frozen request/response contract |
| `seed/recipes.json` | Clean tracked demo data |
| `scripts/reset-demo.sh` | Restores `data/recipes.json` from the seed |
| `tests/smoke_test.py` | Stage 2 HTTP smoke test (not used yet) |

### OOP evidence in the code

- **Inheritance:** `BaseEntity` is the parent of `Comment`, `Variant`, `Dish`
  and `User`.
- **Encapsulation:** fields are `protected`; access goes through getters and
  setters.
- **Composition:** `Dish` owns `Variant`s. `Variant` owns a `Recipe`, ratings,
  reactions and comments.
- **Abstraction:** `RecipeDatabase` hides file storage; `BackendService` hides
  database operations behind API-shaped methods.
- **Polymorphism:** `BaseEntity` now has:

```cpp
virtual ~BaseEntity() = default;
virtual json toJson() = 0;
```

`Comment`, `Variant`, `Dish` and `User` implement `toJson()` with `override`.
`RecipeDatabase::save()` deliberately calls it through a base reference:

```cpp
BaseEntity &entity = d;
j["dishes"].push_back(entity.toJson());
```

That line is the runtime proof that virtual dispatch is working.

### Why the model changed

The original console model could not survive a server round-trip with images and
YouTube links. `Variant` now stores:

```cpp
string imageRef;      // asset path, web URL, or local phone path
string youtubeUrl;
```

Both fields are written by `Variant::toJson()` and read by
`Variant::fromJson()`. Before this change, any save would have silently deleted
those fields from `data/recipes.json`.

`Recipe` also exposes `getIngredients()` and `getSteps()` so the search and JSON
code does not need to serialize a whole recipe just to read its arrays.

### Ratings with image proof

A rating is still one 1–5 star value per user per recipe, but each `Rating` can
now carry an optional proof photo:

```cpp
class Rating {
public:
    int userId = 0;
    int stars = 0;
    string proofImageRef;
};
```

Semantics:

- One user has one rating per recipe.
- Sending a new star value updates that rating.
- `proofImageRef` is optional.
- If the proof image is omitted, the existing proof image is kept.
- Sending an empty string clears the proof image.

The JSON for a rating now looks like this:

```json
{
  "userId": 1,
  "stars": 5,
  "proofImageRef": "https://example.com/proofs/my-biryani.jpg"
}
```

Recipe summaries expose the demo user's own rating:

```json
{
  "averageRating": 4.5,
  "ratingCount": 2,
  "myRating": 5,
  "myRatingProofImageRef": "https://example.com/proofs/my-biryani.jpg"
}
```

Recipe detail also exposes the complete ratings array, so the future Flutter UI
can show the proof images attached by other users.

This is why the Stage 1 API has no separate like/dislike endpoint. The requested
"vote" is the star rating, and the proof image is part of that rating. The old
`Reactions` class remains in `RecipeCore.h` for OOP evidence but is not exposed
by `BackendService`.

### Fuzzy search

Search is implemented in `BackendService`, not in the HTTP layer.

For every query word, the service scores the best matching word in:

- recipe title
- dish name
- main ingredient
- each ingredient
- each step

Scoring:

| Match | Score |
|---|---:|
| exact word | 100 |
| text word starts with query | 85 |
| query starts with text word | 75 |
| Levenshtein distance 1 | 60 |
| Levenshtein distance 2 (query length ≥ 5) | 40 |
| trigram similarity ≥ 0.5 | 30–50 |

Title matches are multiplied by 3, dish and main-ingredient matches by 2.
Ingredient and step matches use the base score.

Every query word must match something, otherwise the recipe is excluded. This is
AND-style search, which avoids returning everything for a multi-word query.

Short queries are protected from fuzzy noise. Edit distance and trigram matching
only run when the query word is at least 4 characters, so `oil` does not
fuzzy-match `boil`.

Examples verified by the test:

| Query | Result |
|---|---|
| `biriyani` | Chicken Biryani |
| `chiken` | Chicken Biryani and spicy chicken tikka |
| `karai` | Peshawari Karahi |
| `peshawri` | Peshawari Karahi |
| `xyz` | no results |

Results are sorted by score first, then average rating, rating count and id.
That keeps the best textual match first while using rating quality as a
tie-breaker.

### BackendService methods

| Method | Purpose |
|---|---|
| `health()` | Server health and recipe count |
| `listRecipes()` | All recipe summaries |
| `getRecipe(id)` | One recipe with ingredients, steps and ratings |
| `addRecipe(body)` | Add a recipe/variant to a dish |
| `updateRecipe(id, body)` | Partial edit; dish cannot be changed |
| `deleteRecipe(id)` | Delete a recipe; remove an empty dish |
| `rateRecipe(id, stars, proof)` | Rate 1–5 with optional proof image |
| `searchRecipes(query)` | Typo-tolerant search |
| `leaderboard()` | Rated recipes ranked by average, count, newest |

Every public method locks one `std::mutex`. Private helpers assume the lock is
already held. This matters because `cpp-httplib` serves requests on multiple
threads, so two requests must never read and write the JSON file at the same
time.

The service returns JSON copies, not references to in-memory recipes. That is
why it is safe to release the lock before the HTTP layer writes the response.

### Validation and errors

`BackendService` throws `ApiException(status, message)`:

| Status | Meaning |
|---|---|
| `400` | Invalid input or wrong JSON type |
| `404` | Recipe not found |
| `409` | Duplicate title in the same dish |
| `500` | Load or save failure |

Validated rules:

- `title`, `ingredients` and `steps` are required on create.
- `dish` defaults to `My Recipes`.
- `cookingTime` must be an integer ≥ 0.
- `stars` must be 1–5.
- Ingredient and step arrays cannot be empty or contain empty strings.
- `dish` cannot be changed by an update.
- Deleting the last recipe in a dish deletes the dish.

The Stage 2 server will catch `ApiException` and turn it into:

```json
{ "error": "Recipe not found" }
```

### Storage and atomic saves

Runtime path:

```text
data/recipes.json
```

Seed path:

```text
seed/recipes.json
```

`RecipeDatabase` now accepts a data folder:

```cpp
RecipeDatabase db("data");
```

The default `"."` keeps the old console programs working.

A save is now atomic:

1. Serialize the complete database to a string.
2. Make a backup of the previous file.
3. Write the new text to `recipes.json.tmp`.
4. Flush and close.
5. `std::rename` the temp file over `recipes.json`.

If the process dies mid-write, the old `recipes.json` stays intact.

The loader also guards missing arrays. A partial or hand-edited JSON file will
not crash on `variants`, `ratings`, `votes` or `comments`.

### Data and test isolation

`backend_test.cpp` never writes to `data/recipes.json`.

It uses:

```text
data/backend-test/recipes.json
```

The test copies `seed/recipes.json` into that folder, runs all checks, then
deletes the folder. This makes the test repeatable and keeps the demo data clean.

The seed contains 6 recipes:

| id | Recipe | Ratings |
|---|---|---|
| 1 | Crispy Fries | none |
| 2 | Hydrabadi Pulao | 3 |
| 3 | Peshawari Karahi | 4 |
| 4 | spicy chicken tikka | none |
| 5 | Chicken Biryani | 5, 4 |
| 6 | Beef Nihari | 4 |

### Build and run Stage 1

From the repository root:

```bash
g++ -std=c++17 -O2 -Wall -Wextra -pthread backend_test.cpp -o backend_test
./backend_test
```

Expected:

```text
PASS: health status is ok
...
ALL STAGE 1 CHECKS PASSED
```

Run it twice to prove the test cleans up after itself.

Check that the old console programs still compile:

```bash
g++ -std=c++17 -O2 upload.cpp -o /tmp/opencode/upload
g++ -std=c++17 -O2 search.cpp -o /tmp/opencode/search
g++ -std=c++17 -O2 rating.cpp -o /tmp/opencode/rating
```

### What the test proves

`backend_test.cpp` checks more than happy paths:

- seed loading and recipe counts
- recipe detail fields
- image and YouTube preservation
- four typo searches
- add to existing dish and new dish
- duplicate title rejection
- missing/invalid field rejection
- rating with and without proof
- rating update semantics
- leaderboard ordering
- recipe edits and `updatedAt`
- dish-change rejection
- persistence across a service restart
- delete behavior and empty-dish cleanup
- no leftover `.tmp` save file

### Known limitations

- No HTTP server yet. That is Stage 2.
- No authentication. Everything uses demo user `1`.
- No comment API. `Comment` remains for OOP evidence.
- No like/dislike API. `Reactions` remains for OOP evidence.
- No image upload server. `imageRef` and `proofImageRef` store paths or URLs.
- The old console programs still read `./recipes.json` by default. They compile,
  but the demo does not run them.
- The old console `search.cpp` still uses the original exact/prefix search.
  Typo-tolerant search lives in `BackendService` and is what Stage 2 exposes.
- `UserDatabase` is unchanged and is not used by Stage 1 because the demo has no
  login. It keeps the old non-atomic save path for now.
- Multi-process access is not locked. One server process is assumed.
- `RecipeCore.h` still defines non-inline free functions, so each executable
  must stay a single translation unit.

### Next step

Stage 2 adds:

- `httplib.h`
- `server.cpp`
- `CMakeLists.txt`

The server will call only `BackendService` public methods. No recipe logic should
move into the HTTP layer.
