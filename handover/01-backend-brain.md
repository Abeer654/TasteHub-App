# Stage 1 — Backend Brain

**Goal:** turn the existing console code into a reusable C++ backend that can
list, add, edit, delete, search, rate, and rank recipes — with no HTTP and no
Flutter yet.

**Done when:** `./backend_test` prints correct JSON, typo search works, ratings
persist, and the old console programs still compile.

---

## 1. What you start with

- `RecipeCore.h` — OOP model and JSON storage.
- `ConsoleTools.h` — console login/menu code. **Do not include this in the server.**
- `upload.cpp`, `search.cpp`, `rating.cpp` — three console programs.
- `output/recipes.json` — old seed data with mixed dates.
- `seed/recipes.json` — already cleaned: 6 recipes, ISO dates, images, YouTube URLs.
- `data/recipes.json` — runtime copy (gitignored).
- `scripts/clean_seed.py` — rebuilds the seed if needed.
- `scripts/reset-demo.sh` — resets runtime data.

The seed currently contains:

| id | Recipe | Ratings |
|---|---|---|
| 1 | Crispy Fries | none |
| 2 | Hydrabadi Pulao | 3 |
| 3 | Peshawari Karahi | 4 |
| 4 | spicy chicken tikka | none |
| 5 | Chicken Biryani | 5, 4 |
| 6 | Beef Nihari | 4 |

That gives the leaderboard useful data and gives search a real Biryani to find.

---

## 2. Baseline commit

Run from the repository root:

```bash
cd ~/development/TasteHub-App
git status
git add -A
git commit -m "Baseline before Stage 1"
```

If the commit says there is nothing to commit, that is fine. Continue.

---

## 3. Verify the folders and seed

```bash
mkdir -p seed data scripts
ls -l seed/recipes.json data/recipes.json scripts/reset-demo.sh
```

If `seed/recipes.json` is missing, rebuild it:

```bash
python3 scripts/clean_seed.py
```

Reset runtime data whenever you want a clean demo:

```bash
./scripts/reset-demo.sh
```

Check that the dates are ISO:

```bash
grep -m3 createdAt seed/recipes.json
```

You should see values like `2026-10-10T20:06:00Z`.

---

## 4. Patch `RecipeCore.h`

Make the following changes in order. Use the exact "Find" text to locate each
place.

### 4.1 Add the `<cstdio>` include

**Find:**

```cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <ctime>
#include <random>
#include "json.hpp"
```

**Replace with:**

```cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <ctime>
#include <cstdio>
#include <random>
#include "json.hpp"
```

`<cstdio>` is for `std::rename`, used by the atomic save.

### 4.2 Make dates ISO-8601 UTC

**Find:**

```cpp
string currentTimeText(){
    time_t now = time(0);
    tm *t = localtime(&now);          // t points to the broken-down time (year, month, ...)
    return to_string(t->tm_year + 1900) + "-" + twoDigits(t->tm_mon + 1) + "-" + twoDigits(t->tm_mday)
         + "T" + twoDigits(t->tm_hour) + ":" + twoDigits(t->tm_min) + ":" + twoDigits(t->tm_sec);
}
```

**Replace with:**

```cpp
string currentTimeText(){
    time_t now = time(0);
    tm t;
#ifdef _WIN32
    gmtime_s(&t, &now);
#else
    gmtime_r(&now, &t);
#endif
    char buffer[32];
    strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &t);
    return string(buffer);
}
```

This always produces `2026-11-06T12:30:00Z`. Flutter can parse it directly.

### 4.3 Make `BaseEntity` abstract and polymorphic

**Find:**

```cpp
class BaseEntity {
protected:
    int id = 0;
    string createdAt;

public:
    void setId(int newId){
```

**Replace with:**

```cpp
class BaseEntity {
protected:
    int id = 0;
    string createdAt;

public:
    virtual ~BaseEntity() = default;
    virtual json toJson() = 0;

    void setId(int newId){
```

Then add `override` to the four derived `toJson()` methods:

| Class | Find | Replace |
|---|---|---|
| `Comment` | `json toJson(){` inside `class Comment` | `json toJson() override {` |
| `Variant` | `json toJson(){` inside `class Variant` | `json toJson() override {` |
| `Dish` | `json toJson(){` inside `class Dish` | `json toJson() override {` |
| `User` | `json toJson(){` inside `class User` | `json toJson() override {` |

There are several `json toJson(){` lines in the file. Change the one inside each
class listed above. Do not change `Reactions`, `Ratings`, or `Recipe`; they do
not inherit from `BaseEntity`.

### 4.4 Add `imageRef`, `youtubeUrl`, and `getUpdatedAt` to `Variant`

**Find this part of `class Variant`:**

```cpp
protected:
    string name;
    Recipe recipe;
    int ownerId = 0;
    string updatedAt;            // empty until the recipe is edited
    Ratings ratings;
    Reactions reactions;         // likes / dislikes of the recipe
    vector<Comment> comments;
```

**Replace with:**

```cpp
protected:
    string name;
    Recipe recipe;
    int ownerId = 0;
    string updatedAt;            // empty until the recipe is edited
    Ratings ratings;
    Reactions reactions;         // likes / dislikes of the recipe
    vector<Comment> comments;
    string imageRef;             // asset path, web URL, or local phone path
    string youtubeUrl;           // YouTube link
```

**Find `getOwnerId()` inside `Variant`:**

```cpp
    int getOwnerId(){
        return ownerId;
    }
```

**Add after it:**

```cpp
    string getUpdatedAt(){
        return updatedAt;
    }

    void setImageRef(string value){
        imageRef = value;
    }

    string getImageRef(){
        return imageRef;
    }

    void setYoutubeUrl(string value){
        youtubeUrl = value;
    }

    string getYoutubeUrl(){
        return youtubeUrl;
    }
```

**Find the end of `Variant::toJson()`:**

```cpp
        for(Comment &c : comments){
            j["comments"].push_back(c.toJson());
        }
        return j;
```

**Replace with:**

```cpp
        for(Comment &c : comments){
            j["comments"].push_back(c.toJson());
        }
        j["imageRef"] = imageRef;
        j["youtubeUrl"] = youtubeUrl;
        return j;
```

**Find this line in `Variant::fromJson()`:**

```cpp
        updatedAt = j.value("updatedAt", string(""));
```

**Add after it:**

```cpp
        imageRef = j.value("imageRef", string(""));
        youtubeUrl = j.value("youtubeUrl", string(""));
```

### 4.5 Guard missing JSON arrays

Old data may not have every field. Guard the arrays so the server does not crash.

**In `Dish::fromJson`, find:**

```cpp
        variants.clear();
        for(json &vj : j["variants"]){
            Variant v;
            v.fromJson(vj);
            variants.push_back(v);
        }
```

**Replace with:**

```cpp
        variants.clear();
        if(j.contains("variants") && j["variants"].is_array()){
            for(json &vj : j["variants"]){
                Variant v;
                v.fromJson(vj);
                variants.push_back(v);
            }
        }
```

**In `Variant::fromJson`, find:**

```cpp
        // old recipes have no ratings / votes / comments yet
        if(j.contains("ratings")) ratings.fromJson(j["ratings"]);
        if(j.contains("votes")) reactions.fromJson(j["votes"]);
        comments.clear();
        if(j.contains("comments")){
            for(json &cj : j["comments"]){
```

**Replace with:**

```cpp
        // old recipes have no ratings / votes / comments yet
        if(j.contains("ratings") && j["ratings"].is_array()) ratings.fromJson(j["ratings"]);
        if(j.contains("votes") && j["votes"].is_array()) reactions.fromJson(j["votes"]);
        comments.clear();
        if(j.contains("comments") && j["comments"].is_array()){
            for(json &cj : j["comments"]){
```

**In `Comment::fromJson`, find:**

```cpp
        if(j.contains("votes")) reactions.fromJson(j["votes"]);
```

**Replace with:**

```cpp
        if(j.contains("votes") && j["votes"].is_array()) reactions.fromJson(j["votes"]);
```

### 4.6 Add the data-folder constructor to `RecipeDatabase`

**Find:**

```cpp
    string fileName = "recipes.json";
    string backupName = "recipes.backup.json";

public:
    // Returns false only if the file exists but is damaged/unreadable
    bool load(){
```

**Replace with:**

```cpp
    string fileName = "recipes.json";
    string backupName = "recipes.backup.json";

public:
    explicit RecipeDatabase(string dataFolder = "."){
        if(dataFolder.empty()) dataFolder = ".";
        fileName = dataFolder + "/recipes.json";
        backupName = dataFolder + "/recipes.backup.json";
    }

    // Returns false only if the file exists but is damaged/unreadable
    bool load(){
```

The default `"."` keeps the old console programs working exactly as before.

### 4.7 Demonstrate polymorphism in `RecipeDatabase::save`

**Find:**

```cpp
        for(Dish &d : dishes){
            j["dishes"].push_back(d.toJson());
        }
```

**Replace with:**

```cpp
        for(Dish &d : dishes){
            BaseEntity &entity = d;          // virtual dispatch: calls Dish::toJson()
            j["dishes"].push_back(entity.toJson());
        }
```

This is the line that proves polymorphism at runtime. The HTTP server and the
test program both go through `RecipeDatabase::save()`.

### 4.8 Make saves atomic

**Find:**

```cpp
        string text = jsonToText(j);      // make the text FIRST, so a problem can never empty the file
        makeBackupOf(fileName, backupName);

        ofstream outFile(fileName);
        if(!outFile){
            cout << "ERROR: could not write to " << fileName << "\n";
            return false;
        }
        outFile << text;
        outFile.close();
        return !outFile.fail();
```

**Replace with:**

```cpp
        string text = jsonToText(j);      // make the text FIRST, so a problem can never empty the file
        makeBackupOf(fileName, backupName);

        string tempName = fileName + ".tmp";
        {
            ofstream outFile(tempName);
            if(!outFile){
                cout << "ERROR: could not write to " << tempName << "\n";
                return false;
            }
            outFile << text;
            outFile.flush();
            if(!outFile){
                cout << "ERROR: could not write to " << tempName << "\n";
                return false;
            }
        }

        if(std::rename(tempName.c_str(), fileName.c_str()) != 0){
            cout << "ERROR: could not replace " << fileName << "\n";
            return false;
        }
        return true;
```

The old file stays intact until the new file is fully written.

### 4.9 Do not split into multiple `.cpp` files yet

`RecipeCore.h` defines free functions (not `inline`). Every program must stay a
single translation unit for now. That is why `backend_test.cpp` includes
`BackendService.h`, and `server.cpp` will include it too. Do not add a second
`.cpp` that includes `RecipeCore.h` into the same executable.

If you later split the code, mark the free functions `inline` or move them into
a `.cpp` file.

---

## 5. Create `BackendService.h`

Create a new file named `BackendService.h` in the repository root and paste this
complete code.

```cpp
#ifndef BACKENDSERVICE_H
#define BACKENDSERVICE_H

#include <algorithm>
#include <filesystem>
#include <mutex>
#include <set>
#include <stdexcept>
#include "RecipeCore.h"

class ApiException : public std::runtime_error {
public:
    int status;

    ApiException(int statusCode, const string& message)
        : std::runtime_error(message), status(statusCode) {}
};

class BackendService {
public:
    static constexpr int DEMO_USER_ID = 1;

    explicit BackendService(string dataDir) : db(dataDir), dataDir(dataDir) {
        std::filesystem::path dataPath(dataDir);
        std::filesystem::create_directories(dataPath);

        std::filesystem::path dataFile = dataPath / "recipes.json";
        std::filesystem::path seedFile = dataPath.parent_path() / "seed" / "recipes.json";

        if(!std::filesystem::exists(dataFile) && std::filesystem::exists(seedFile)){
            std::filesystem::copy_file(seedFile, dataFile);
        }

        if(!db.load()){
            throw ApiException(500, "Could not load recipes");
        }
    }

    json health() {
        std::lock_guard<std::mutex> lock(mutex);
        return json{{"status", "ok"}, {"recipes", countRecipes()}};
    }

    json listRecipes() {
        std::lock_guard<std::mutex> lock(mutex);
        json result = json::array();
        for(Dish &dish : db.getDishes()){
            for(Variant &variant : dish.getVariants()){
                result.push_back(summaryJson(dish, variant));
            }
        }
        return result;
    }

    json getRecipe(int id) {
        std::lock_guard<std::mutex> lock(mutex);
        RecipeRef ref = requireRecipe(id);
        Dish &dish = db.getDishes()[ref.dishIndex];
        Variant &variant = dish.getVariants()[ref.variantIndex];
        return detailJson(dish, variant);
    }

    json addRecipe(const json& body) {
        std::lock_guard<std::mutex> lock(mutex);

        string title = tidyName(body.value("title", string("")));
        if(title.empty()) throw ApiException(400, "title is required");

        string dishName = tidyName(body.value("dish", string("My Recipes")));
        if(dishName.empty()) dishName = "My Recipes";

        vector<string> ingredients = readStringArray(body, "ingredients", true);
        vector<string> steps = readStringArray(body, "steps", true);
        if(ingredients.empty()) throw ApiException(400, "ingredients cannot be empty");
        if(steps.empty()) throw ApiException(400, "steps cannot be empty");

        int cookingTime = body.value("cookingTime", 0);
        if(cookingTime < 0) throw ApiException(400, "cookingTime must be 0 or more");

        int dishIndex = db.findDishIndex(dishName);
        if(dishIndex < 0){
            Dish newDish;
            newDish.setId(db.nextDishId());
            newDish.setName(dishName);
            newDish.autoSetDate();
            dishIndex = db.addDish(newDish);
        }

        Dish &dish = db.getDishes()[dishIndex];
        if(dish.hasVariant(title)){
            throw ApiException(409, "A recipe with this title already exists in this dish");
        }

        Variant variant;
        variant.setId(db.nextVariantId());
        variant.setName(title);
        variant.setOwnerId(DEMO_USER_ID);
        variant.autoSetDate();
        variant.getRecipe().setMainIngredient(body.value("mainIngredient", string("")));
        variant.getRecipe().setIngredients(ingredients);
        variant.getRecipe().setSteps(steps);
        variant.getRecipe().setCookingTime(cookingTime);
        variant.setImageRef(body.value("imageRef", string("")));
        variant.setYoutubeUrl(body.value("youtubeUrl", string("")));

        dish.addVariant(variant);
        saveOrThrow();

        return detailJson(dish, dish.getVariants().back());
    }

    json updateRecipe(int id, const json& body) {
        std::lock_guard<std::mutex> lock(mutex);
        RecipeRef ref = requireRecipe(id);
        Dish &dish = db.getDishes()[ref.dishIndex];
        Variant &variant = dish.getVariants()[ref.variantIndex];

        if(body.contains("title")){
            string title = tidyName(body["title"].get<string>());
            if(title.empty()) throw ApiException(400, "title cannot be empty");
            if(toLowerCase(title) != toLowerCase(variant.getName()) && dish.hasVariant(title)){
                throw ApiException(409, "A recipe with this title already exists in this dish");
            }
            variant.setName(title);
        }
        if(body.contains("mainIngredient")){
            variant.getRecipe().setMainIngredient(body["mainIngredient"].get<string>());
        }
        if(body.contains("ingredients")){
            variant.getRecipe().setIngredients(readStringArray(body, "ingredients", true));
        }
        if(body.contains("steps")){
            variant.getRecipe().setSteps(readStringArray(body, "steps", true));
        }
        if(body.contains("cookingTime")){
            int cookingTime = body["cookingTime"].get<int>();
            if(cookingTime < 0) throw ApiException(400, "cookingTime must be 0 or more");
            variant.getRecipe().setCookingTime(cookingTime);
        }
        if(body.contains("imageRef")){
            variant.setImageRef(body["imageRef"].get<string>());
        }
        if(body.contains("youtubeUrl")){
            variant.setYoutubeUrl(body["youtubeUrl"].get<string>());
        }

        variant.markEdited();
        saveOrThrow();
        return detailJson(dish, variant);
    }

    json deleteRecipe(int id) {
        std::lock_guard<std::mutex> lock(mutex);
        RecipeRef ref = requireRecipe(id);
        db.removeVariant(ref.dishIndex, ref.variantIndex);
        saveOrThrow();
        return json{{"deleted", true}, {"id", id}};
    }

    json rateRecipe(int id, int stars) {
        std::lock_guard<std::mutex> lock(mutex);
        if(stars < 1 || stars > 5){
            throw ApiException(400, "stars must be between 1 and 5");
        }
        RecipeRef ref = requireRecipe(id);
        Variant &variant = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];
        variant.getRatings().setRating(DEMO_USER_ID, stars);
        saveOrThrow();
        return ratingJson(variant);
    }

    json searchRecipes(const string& query) {
        std::lock_guard<std::mutex> lock(mutex);

        vector<string> words = searchWords(query);
        json results = json::array();
        if(words.empty()){
            return json{{"query", query}, {"results", results}};
        }

        struct Hit {
            int score;
            double average;
            int count;
            int id;
            json summary;
        };
        vector<Hit> hits;

        for(Dish &dish : db.getDishes()){
            for(Variant &variant : dish.getVariants()){
                int score = scoreRecipe(dish, variant, words);
                if(score > 0){
                    hits.push_back(Hit{score, variant.getRatings().average(),
                                       variant.getRatings().count(), variant.getId(),
                                       summaryJson(dish, variant)});
                }
            }
        }

        std::sort(hits.begin(), hits.end(), [](const Hit& a, const Hit& b){
            if(a.score != b.score) return a.score > b.score;
            if(a.average != b.average) return a.average > b.average;
            if(a.count != b.count) return a.count > b.count;
            return a.id < b.id;
        });

        for(Hit &hit : hits) results.push_back(hit.summary);
        return json{{"query", query}, {"results", results}};
    }

    json leaderboard() {
        std::lock_guard<std::mutex> lock(mutex);

        struct Entry {
            double average;
            int count;
            string createdAt;
            json summary;
        };
        vector<Entry> entries;

        for(Dish &dish : db.getDishes()){
            for(Variant &variant : dish.getVariants()){
                if(variant.getRatings().count() == 0) continue;
                entries.push_back(Entry{variant.getRatings().average(),
                                        variant.getRatings().count(),
                                        variant.getCreatedAt(),
                                        summaryJson(dish, variant)});
            }
        }

        std::sort(entries.begin(), entries.end(), [](const Entry& a, const Entry& b){
            if(a.average != b.average) return a.average > b.average;
            if(a.count != b.count) return a.count > b.count;
            return a.createdAt > b.createdAt;
        });

        json list = json::array();
        int rank = 1;
        for(Entry &entry : entries){
            json item;
            item["rank"] = rank++;
            item["recipe"] = entry.summary;
            item["averageRating"] = entry.average;
            item["ratingCount"] = entry.count;
            list.push_back(item);
        }
        return json{{"leaderboard", list}};
    }

private:
    RecipeDatabase db;
    string dataDir;
    std::mutex mutex;

    int countRecipes() {
        int count = 0;
        for(Dish &dish : db.getDishes()) count += (int)dish.getVariants().size();
        return count;
    }

    RecipeRef requireRecipe(int id) {
        RecipeRef ref = db.findVariantById(id);
        if(ref.dishIndex < 0){
            throw ApiException(404, "Recipe not found");
        }
        return ref;
    }

    void saveOrThrow() {
        if(!db.save()){
            throw ApiException(500, "Could not save recipes");
        }
    }

    json summaryJson(Dish& dish, Variant& variant) {
        json j;
        j["id"] = variant.getId();
        j["title"] = variant.getName();
        j["dish"] = dish.getName();
        j["mainIngredient"] = variant.getRecipe().getMainIngredient();
        j["cookingTime"] = variant.getRecipe().getCookingTime();
        j["imageRef"] = variant.getImageRef();
        j["youtubeUrl"] = variant.getYoutubeUrl();
        j["averageRating"] = variant.getRatings().average();
        j["ratingCount"] = variant.getRatings().count();
        j["myRating"] = variant.getRatings().getRating(DEMO_USER_ID);
        j["createdAt"] = variant.getCreatedAt();
        if(variant.getUpdatedAt().empty()){
            j["updatedAt"] = nullptr;
        } else {
            j["updatedAt"] = variant.getUpdatedAt();
        }
        return j;
    }

    json detailJson(Dish& dish, Variant& variant) {
        json j = summaryJson(dish, variant);
        json recipe = variant.getRecipe().toJson();
        j["ingredients"] = recipe.value("ingredients", json::array());
        j["steps"] = recipe.value("steps", json::array());
        return j;
    }

    json ratingJson(Variant& variant) {
        json j;
        j["averageRating"] = variant.getRatings().average();
        j["ratingCount"] = variant.getRatings().count();
        j["myRating"] = variant.getRatings().getRating(DEMO_USER_ID);
        return j;
    }

    vector<string> readStringArray(const json& body, const string& key, bool required) {
        vector<string> result;
        if(!body.contains(key)){
            if(required) throw ApiException(400, key + " is required");
            return result;
        }
        if(!body[key].is_array()){
            throw ApiException(400, key + " must be an array of strings");
        }
        for(const json& item : body[key]){
            if(!item.is_string()){
                throw ApiException(400, key + " must contain only strings");
            }
            result.push_back(item.get<string>());
        }
        return result;
    }

    int bestWordScore(const string& query, const string& text) {
        int best = 0;
        for(const string& word : splitWords(text)){
            best = std::max(best, wordScore(query, word));
        }
        return best;
    }

    int wordScore(const string& query, const string& word) {
        if(query == word) return 100;
        if(word.rfind(query, 0) == 0) return 85;
        if(query.rfind(word, 0) == 0) return 75;

        int distance = levenshtein(query, word);
        if(distance == 1) return 60;
        if(distance == 2 && query.size() >= 4) return 40;

        double similarity = trigramSimilarity(query, word);
        if(similarity >= 0.5) return (int)(30 + similarity * 20);
        return 0;
    }

    int levenshtein(const string& a, const string& b) {
        vector<int> previous(b.size() + 1);
        vector<int> current(b.size() + 1);
        for(size_t j = 0; j <= b.size(); j++) previous[j] = (int)j;

        for(size_t i = 1; i <= a.size(); i++){
            current[0] = (int)i;
            for(size_t j = 1; j <= b.size(); j++){
                int cost = (a[i - 1] == b[j - 1]) ? 0 : 1;
                current[j] = std::min({previous[j] + 1,
                                       current[j - 1] + 1,
                                       previous[j - 1] + cost});
            }
            previous.swap(current);
        }
        return previous[b.size()];
    }

    double trigramSimilarity(const string& a, const string& b) {
        if(a.size() < 3 || b.size() < 3) return 0.0;

        std::set<string> first;
        std::set<string> second;
        for(size_t i = 0; i + 3 <= a.size(); i++) first.insert(a.substr(i, 3));
        for(size_t i = 0; i + 3 <= b.size(); i++) second.insert(b.substr(i, 3));

        int common = 0;
        for(const string& trigram : first){
            if(second.count(trigram)) common++;
        }
        return (2.0 * common) / (first.size() + second.size());
    }

    int scoreRecipe(Dish& dish, Variant& variant, const vector<string>& words) {
        json recipe = variant.getRecipe().toJson();
        int total = 0;

        for(const string& word : words){
            int best = 0;
            best = std::max(best, bestWordScore(word, variant.getName()) * 3);
            best = std::max(best, bestWordScore(word, dish.getName()) * 2);
            best = std::max(best, bestWordScore(word, variant.getRecipe().getMainIngredient()) * 2);

            for(const json& ingredient : recipe["ingredients"]){
                best = std::max(best, bestWordScore(word, ingredient.get<string>()));
            }
            for(const json& step : recipe["steps"]){
                best = std::max(best, bestWordScore(word, step.get<string>()));
            }

            if(best == 0) return 0;
            total += best;
        }
        return total;
    }
};

#endif
```

### What this class does

- Loads `data/recipes.json` once at startup.
- Copies `seed/recipes.json` into `data/` if the runtime file is missing.
- Locks a mutex around every public operation.
- Saves after every add, edit, delete, and rating.
- Returns API-shaped JSON, not raw storage JSON.
- Uses `DEMO_USER_ID = 1` for ratings.
- Allows self-rating because the demo has one user.
- Implements fuzzy search with exact, prefix, Levenshtein, and trigram scoring.
- Implements the leaderboard ordering: average, count, newest.

---

## 6. Create `backend_test.cpp`

Create `backend_test.cpp` in the repository root:

```cpp
#include <ctime>
#include <iostream>
#include "BackendService.h"
using namespace std;

int main(){
    try {
        BackendService service("data");

        cout << "HEALTH\n" << service.health().dump(2) << "\n\n";
        cout << "LIST\n" << service.listRecipes().dump(2) << "\n\n";
        cout << "SEARCH biriyani\n" << service.searchRecipes("biriyani").dump(2) << "\n\n";
        cout << "GET 5\n" << service.getRecipe(5).dump(2) << "\n\n";
        cout << "RATE 5\n" << service.rateRecipe(5, 5).dump(2) << "\n\n";
        cout << "LEADERBOARD\n" << service.leaderboard().dump(2) << "\n\n";

        string suffix = to_string(time(0));
        json body = {
            {"dish", "Test Dish"},
            {"title", "Test Recipe " + suffix},
            {"mainIngredient", "test"},
            {"ingredients", {"test"}},
            {"steps", {"do the test"}},
            {"cookingTime", 1},
            {"imageRef", ""},
            {"youtubeUrl", ""}
        };

        json added = service.addRecipe(body);
        int id = added["id"].get<int>();
        cout << "ADDED\n" << added.dump(2) << "\n\n";

        cout << "UPDATE\n"
             << service.updateRecipe(id, {{"title", "Updated Test Recipe " + suffix}}).dump(2)
             << "\n\n";
        cout << "DELETE\n" << service.deleteRecipe(id).dump(2) << "\n";
    }
    catch(const ApiException& e){
        cerr << "API ERROR " << e.status << ": " << e.what() << "\n";
        return 1;
    }
    catch(const std::exception& e){
        cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
```

The test uses recipe id `5` because `seed/recipes.json` contains Chicken Biryani
as id 5. If you deleted it, run `./scripts/reset-demo.sh` first.

---

## 7. Build and run the backend test

From the repository root:

```bash
g++ -std=c++17 -O2 -Wall -Wextra -pthread backend_test.cpp -o backend_test
./backend_test
```

Expected output (shortened):

```text
HEALTH
{
  "recipes": 6,
  "status": "ok"
}

LIST
[ ... 6 recipe summaries ... ]

SEARCH biriyani
{
  "query": "biriyani",
  "results": [
    {
      "title": "Chicken Biryani",
      ...
    }
  ]
}

RATE 5
{
  "averageRating": 4.5,
  "myRating": 5,
  "ratingCount": 2
}

LEADERBOARD
{
  "leaderboard": [
    {
      "averageRating": 4.5,
      "rank": 1,
      "ratingCount": 2,
      "recipe": { "title": "Chicken Biryani", ... }
    },
    ...
  ]
}
```

If the linker complains about `std::filesystem`, add `-lstdc++fs`:

```bash
g++ -std=c++17 -O2 -Wall -Wextra -pthread backend_test.cpp -o backend_test -lstdc++fs
```

---

## 8. Check the old console programs still compile

```bash
g++ -std=c++17 -O2 upload.cpp -o upload
g++ -std=c++17 -O2 search.cpp -o search
g++ -std=c++17 -O2 rating.cpp -o rating
```

They still read `recipes.json` from the current folder by default. If you want
them to use `data/`, change this line in each `main()`:

```cpp
RecipeDatabase db;
```

to:

```cpp
RecipeDatabase db("data");
```

Do not run the console login flow for the demo. The server does not use it.

---

## 9. Checkpoint

Tick every item before moving to Stage 2:

- [ ] `./backend_test` exits with code `0`.
- [ ] `HEALTH` says `"recipes": 6`.
- [ ] `LIST` contains 6 recipes.
- [ ] `SEARCH biriyani` returns **Chicken Biryani**.
- [ ] `SEARCH chiken` returns chicken recipes.
- [ ] `RATE 5` returns `averageRating` and `ratingCount`.
- [ ] `LEADERBOARD` rank 1 is Chicken Biryani.
- [ ] `ADDED`, `UPDATE`, and `DELETE` print JSON without errors.
- [ ] Running `./backend_test` a second time still works.
- [ ] `data/recipes.json` exists and contains the changes.
- [ ] `upload.cpp`, `search.cpp`, and `rating.cpp` still compile.

Reset the demo data after testing:

```bash
./scripts/reset-demo.sh
```

---

## 10. Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `multiple definition of ...` | Two `.cpp` files include `RecipeCore.h` in one executable | Keep one `.cpp` per binary, or mark the free functions `inline` |
| `undefined reference to std::filesystem::...` | Old GCC needs the filesystem library | Add `-lstdc++fs` |
| `Could not load recipes` | `data/recipes.json` is damaged | `./scripts/reset-demo.sh` |
| `data/recipes.json` is not created | You ran from the wrong folder | Run from the repo root; seed is at `seed/recipes.json` |
| `SEARCH biriyani` returns nothing | Seed was not cleaned or recipe 5 was deleted | `./scripts/reset-demo.sh`, then rebuild |
| `json::type_error` | A request field has the wrong type | Send numbers as numbers, arrays as arrays |
| Rating does not change | User 1 already gave that exact rating | Try a different star value |
| Old console program cannot find data | It reads `./recipes.json` by default | Change `RecipeDatabase db;` to `RecipeDatabase db("data");` |

---

## 11. Handoff to Stage 2

Stage 2 will add:

- `httplib.h`
- `server.cpp`
- `CMakeLists.txt`

The server will call only the public `BackendService` methods you just built.
Keep `BackendService.h` and `RecipeCore.h` unchanged during Stage 2 unless a
compile error proves a real bug.

**Commit:**

```bash
git add -A
git commit -m "Stage 1: backend brain and clean seed"
```
