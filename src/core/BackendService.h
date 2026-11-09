#ifndef BACKENDSERVICE_H
#define BACKENDSERVICE_H

// ============================================================
//  BackendService.h - Stage 1 backend facade
//
//  This is the layer the HTTP server will call in Stage 2. It hides the
//  RecipeDatabase details and returns JSON in the shape documented in API.md.
//
//  Important design choices:
//    - One mutex protects the whole database. cpp-httplib handles requests on
//      several threads, so two requests must never save at the same time.
//    - The service returns JSON copies, never references to in-memory recipes.
//      That keeps a response safe after the lock is released.
//    - Every mutation saves immediately. Saves are atomic inside
//      RecipeDatabase::save() (temp file + rename).
//    - Search is implemented in the shared Search.h matcher, using exact,
//      plural, prefix and Damerau-Levenshtein scoring for typo tolerance.
//      The HTTP layer only formats the ranked results as JSON.
// ============================================================

#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include "AiRecipe.h"
#include "Search.h"

// Carries the HTTP status code that Stage 2 should send to the client.
// Keeping the status attached to the error means the future server does not
// have to translate error messages back into status codes.
class ApiException : public std::runtime_error {
public:
    int status;

    ApiException(int statusCode, const string& message)
        : std::runtime_error(message), status(statusCode) {}
};

class BackendService {
public:
    // The demo has no login. Every rating acts as this user.
    static constexpr int DEMO_USER_ID = 1;

    // Build the service, make sure the data folder exists, copy the seed on
    // first run, then load the JSON database into memory.
    //
    // dataDir is usually "data". seedFile is optional and exists mainly so
    // backend_test can point at seed/recipes.json while using its own test
    // directory instead of touching the real runtime data.
    //
    // recipeExtractor is optional too: production uses Gemini, while tests
    // inject a fake extractor so they never touch the network.
    explicit BackendService(string dataDir, string seedFile = "",
                            std::shared_ptr<RecipeExtractor> recipeExtractor = nullptr)
        : db(dataDir), extractor(std::move(recipeExtractor)) {
        if(!extractor) extractor = std::make_shared<GeminiRecipeExtractor>();
        if(dataDir.empty()) dataDir = ".";

        std::filesystem::path dataPath(dataDir);
        std::filesystem::create_directories(dataPath);

        std::filesystem::path dataFile = dataPath / "recipes.json";
        std::filesystem::path seedPath = seedFile.empty()
            ? dataPath.parent_path() / "seed" / "recipes.json"
            : std::filesystem::path(seedFile);

        // On a fresh clone (or after reset-demo), data/recipes.json may not
        // exist yet. Copy the tracked seed so the demo always starts with data.
        bool needSeed = !std::filesystem::exists(dataFile);
        if(!needSeed){
            try {
                needSeed = std::filesystem::file_size(dataFile) == 0;
            }
            catch(...) {
                needSeed = true;
            }
        }

        if(needSeed && std::filesystem::exists(seedPath)){
            std::filesystem::copy_file(seedPath, dataFile,
                                       std::filesystem::copy_options::overwrite_existing);
        }

        if(!db.load()){
            throw ApiException(500, "Could not load recipes");
        }
    }

    // GET /api/health - cheap readiness check for Stage 2.
    json health(){
        std::lock_guard<std::mutex> lock(mutex);
        return json{{"status", "ok"}, {"recipes", countRecipes()}};
    }

    // GET /api/recipes - every recipe as a summary (no ingredients/steps).
    json listRecipes(){
        std::lock_guard<std::mutex> lock(mutex);

        json result = json::array();
        for(Dish &dish : db.getDishes()){
            for(Variant &variant : dish.getVariants()){
                result.push_back(summaryJson(dish, variant));
            }
        }
        return result;
    }

    // GET /api/recipes/:id - one full recipe, including ratings and proof images.
    json getRecipe(int id){
        std::lock_guard<std::mutex> lock(mutex);

        RecipeRef ref = requireRecipe(id);
        Dish &dish = db.getDishes()[ref.dishIndex];
        Variant &variant = dish.getVariants()[ref.variantIndex];
        return detailJson(dish, variant);
    }

    // body follows the POST /api/recipes shape in API.md.
    // A recipe is a Variant inside a Dish. If the dish does not exist yet,
    // it is created automatically.
    json addRecipe(const json& body){
        std::lock_guard<std::mutex> lock(mutex);
        ensureObject(body);

        // 1. Validate and normalize the request before touching the database.
        string title = tidyName(readString(body, "title", true, ""));
        if(title.empty()) throw ApiException(400, "title is required");

        string dishName = tidyName(readString(body, "dish", false, "My Recipes"));
        if(dishName.empty()) dishName = "My Recipes";

        vector<string> ingredients = readStringArray(body, "ingredients", true);
        vector<string> steps = readStringArray(body, "steps", true);
        if(ingredients.empty()) throw ApiException(400, "ingredients cannot be empty");
        if(steps.empty()) throw ApiException(400, "steps cannot be empty");

        int cookingTime = readInt(body, "cookingTime", false, 0);
        if(cookingTime < 0) throw ApiException(400, "cookingTime must be 0 or more");

        string mainIngredient = readString(body, "mainIngredient", false, "");
        string imageRef = readString(body, "imageRef", false, "");
        string youtubeUrl = readString(body, "youtubeUrl", false, "");

        // Keep the previous state so a failed file save cannot leave an
        // unsaved recipe in memory.
        RecipeDatabase rollbackState = db;

        // 2. Reuse the dish when the name matches (ignoring case); otherwise
        //    create it and add the uploaded recipe as its first variant.
        int dishIndex = db.findDishIndex(dishName);
        if(dishIndex < 0){
            Dish newDish;
            newDish.setId(db.nextDishId());
            newDish.setName(tidyName(dishName));
            newDish.autoSetDate();
            dishIndex = db.addDish(newDish);
        }

        // 3. One dish may not contain two recipes with the same title.
        Dish &dish = db.getDishes()[dishIndex];
        if(dish.hasVariant(title)){
            throw ApiException(409, "A recipe with this title already exists in this dish");
        }

        // 4. Build the Variant, append it, and persist immediately.
        Variant variant;
        variant.setId(db.nextVariantId());
        variant.setName(tidyName(title));
        variant.setOwnerId(DEMO_USER_ID);
        variant.autoSetDate();
        variant.getRecipe().setMainIngredient(tidyName(mainIngredient));
        variant.getRecipe().setIngredients(ingredients);
        variant.getRecipe().setSteps(steps);
        variant.getRecipe().setCookingTime(cookingTime);
        variant.setImageRef(imageRef);
        variant.setYoutubeUrl(youtubeUrl);

        dish.addVariant(variant);
        saveOrThrow(rollbackState);

        return detailJson(dish, dish.getVariants().back());
    }

    // Partial update. Fields that are absent stay unchanged.
    // "dish" cannot be changed after creation.
    json updateRecipe(int id, const json& body){
        std::lock_guard<std::mutex> lock(mutex);
        ensureObject(body);

        RecipeRef ref = requireRecipe(id);
        Dish &dish = db.getDishes()[ref.dishIndex];
        Variant &variant = dish.getVariants()[ref.variantIndex];

        // Validate every supplied field before changing anything. A rejected
        // request must never leave a partially updated recipe in memory.
        if(body.contains("dish")){
            // Moving a recipe to another dish would change its identity, so
            // only accept the current dish name (or no dish field at all).
            string requestedDish = tidyName(readString(body, "dish", false, ""));
            if(!requestedDish.empty()
               && toLowerCase(requestedDish) != toLowerCase(dish.getName())){
                throw ApiException(400, "dish cannot be changed");
            }
        }

        bool hasTitle = body.contains("title");
        string title;
        if(hasTitle){
            title = tidyName(readString(body, "title", true, ""));
            // Case-insensitive duplicate check, but a recipe may keep its own title.
            if(toLowerCase(title) != toLowerCase(variant.getName())
               && dish.hasVariant(title)){
                throw ApiException(409, "A recipe with this title already exists in this dish");
            }
        }

        bool hasMainIngredient = body.contains("mainIngredient");
        string mainIngredient;
        if(hasMainIngredient){
            mainIngredient = tidyName(readString(body, "mainIngredient", false, ""));
        }

        bool hasIngredients = body.contains("ingredients");
        vector<string> ingredients;
        if(hasIngredients){
            ingredients = readStringArray(body, "ingredients", true);
        }

        bool hasSteps = body.contains("steps");
        vector<string> steps;
        if(hasSteps){
            steps = readStringArray(body, "steps", true);
        }

        bool hasCookingTime = body.contains("cookingTime");
        int cookingTime = 0;
        if(hasCookingTime){
            cookingTime = readInt(body, "cookingTime", true, 0);
            if(cookingTime < 0) throw ApiException(400, "cookingTime must be 0 or more");
        }

        bool hasImageRef = body.contains("imageRef");
        string imageRef;
        if(hasImageRef){
            imageRef = readString(body, "imageRef", false, "");
        }

        bool hasYoutubeUrl = body.contains("youtubeUrl");
        string youtubeUrl;
        if(hasYoutubeUrl){
            youtubeUrl = readString(body, "youtubeUrl", false, "");
        }

        // Apply the validated values. Only real changes count, so an update
        // that sends identical data does not rewrite the file.
        RecipeDatabase rollbackState = db;
        bool changed = false;

        if(hasTitle && variant.getName() != title){
            variant.setName(title);
            changed = true;
        }
        if(hasMainIngredient && variant.getRecipe().getMainIngredient() != mainIngredient){
            variant.getRecipe().setMainIngredient(mainIngredient);
            changed = true;
        }
        if(hasIngredients && variant.getRecipe().getIngredients() != ingredients){
            variant.getRecipe().setIngredients(ingredients);
            changed = true;
        }
        if(hasSteps && variant.getRecipe().getSteps() != steps){
            variant.getRecipe().setSteps(steps);
            changed = true;
        }
        if(hasCookingTime && variant.getRecipe().getCookingTime() != cookingTime){
            variant.getRecipe().setCookingTime(cookingTime);
            changed = true;
        }
        if(hasImageRef && variant.getImageRef() != imageRef){
            variant.setImageRef(imageRef);
            changed = true;
        }
        if(hasYoutubeUrl && variant.getYoutubeUrl() != youtubeUrl){
            variant.setYoutubeUrl(youtubeUrl);
            changed = true;
        }

        if(changed){
            variant.markEdited();
            saveOrThrow(rollbackState);
        }

        return detailJson(dish, variant);
    }

    json deleteRecipe(int id){
        std::lock_guard<std::mutex> lock(mutex);

        RecipeRef ref = requireRecipe(id);
        RecipeDatabase rollbackState = db;

        // removeVariant also drops the dish when its last recipe is removed.
        db.removeVariant(ref.dishIndex, ref.variantIndex);
        saveOrThrow(rollbackState);
        return json{{"deleted", true}, {"id", id}};
    }

    // Rate a recipe 1-5. proofImageRef is optional:
    //   - omitted (std::nullopt): keep the existing proof photo
    //   - provided: replace it; an empty string clears it
    // This supports "I cooked this recipe, here is my photo proof".
    json rateRecipe(int id, int stars,
                    std::optional<string> proofImageRef = std::nullopt){
        std::lock_guard<std::mutex> lock(mutex);

        if(stars < 1 || stars > 5){
            throw ApiException(400, "stars must be between 1 and 5");
        }

        RecipeRef ref = requireRecipe(id);
        Variant &variant = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];

        RecipeDatabase rollbackState = db;
        bool changed = false;
        if(proofImageRef.has_value()){
            string proof = trimSpaces(*proofImageRef);
            changed = variant.getRatings().setRatingWithProof(DEMO_USER_ID, stars, proof);
        }
        else {
            changed = variant.getRatings().setRating(DEMO_USER_ID, stars);
        }

        if(changed) saveOrThrow(rollbackState);
        return ratingJson(variant);
    }

    // Typo-tolerant search across dish name, recipe title, main ingredient,
    // ingredients and steps. Every query word must match something.
    json searchRecipes(const string& query){
        std::lock_guard<std::mutex> lock(mutex);

        // findRecipeMatches() lives in Search.h so the console programs and
        // the future HTTP server all share exactly the same ranking rules.
        json results = json::array();
        for(RecipeSearchHit &hit : findRecipeMatches(db, query)){
            Dish &dish = db.getDishes()[hit.ref.dishIndex];
            Variant &variant = dish.getVariants()[hit.ref.variantIndex];
            results.push_back(summaryJson(dish, variant));
        }
        return json{{"query", query}, {"results", results}};
    }

    // POST /api/recipes/parse - turn a natural-language description into a
    // draft recipe. It does NOT save anything: the client shows the draft,
    // the user confirms or edits it, then calls POST /api/recipes.
    json parseRecipeText(const string& text){
        string cleaned = trimSpaces(text);
        if(cleaned.size() < 10){
            throw ApiException(400, "text is required and should describe the dish");
        }

        // Copy the extractor under the lock, then release it before the slow
        // network call. A Gemini request must never block normal API traffic.
        std::shared_ptr<RecipeExtractor> current;
        {
            std::lock_guard<std::mutex> lock(mutex);
            current = extractor;
        }
        if(!current){
            throw ApiException(500, "Recipe extractor is not configured");
        }

        try {
            return recipeDraftJson(current->extract(cleaned));
        }
        catch(const AiServiceError& error){
            throw ApiException(error.status, error.what());
        }
    }

    // GET /api/leaderboard - rated recipes only, best average first.
    // A recipe with no ratings has no place on a leaderboard.
    json leaderboard(){
        std::lock_guard<std::mutex> lock(mutex);

        struct Entry {
            double averageRating;
            int ratingCount;
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

        // Average first, then number of ratings, then newest recipe.
        auto betterEntryFirst = [](const Entry& a, const Entry& b){
            if(a.averageRating != b.averageRating){
                return a.averageRating > b.averageRating;
            }
            if(a.ratingCount != b.ratingCount){
                return a.ratingCount > b.ratingCount;
            }
            return a.createdAt > b.createdAt;
        };
        std::sort(entries.begin(), entries.end(), betterEntryFirst);

        json list = json::array();
        int rank = 1;
        for(Entry &entry : entries){
            json item;
            item["rank"] = rank++;
            item["recipe"] = entry.summary;
            item["averageRating"] = entry.averageRating;
            item["ratingCount"] = entry.ratingCount;
            list.push_back(item);
        }
        return json{{"leaderboard", list}};
    }

private:
    RecipeDatabase db;
    std::shared_ptr<RecipeExtractor> extractor;
    std::mutex mutex;   // guards db and the extractor pointer

    // ---- Internal helpers (the caller already holds mutex) ----

    // Response of POST /api/recipes/parse. "recipe" is exactly the object
    // POST /api/recipes accepts, so the client can preview then save it.
    json recipeDraftJson(const RecipeDraft& draft){
        json recipe;
        recipe["dish"] = draft.dish;
        recipe["title"] = draft.title;
        recipe["mainIngredient"] = draft.mainIngredient;
        recipe["ingredients"] = draft.ingredients;
        recipe["steps"] = draft.steps;
        recipe["cookingTime"] = draft.cookingTime;
        recipe["imageRef"] = draft.imageRef;
        recipe["youtubeUrl"] = draft.youtubeUrl;

        json result;
        result["message"] = draft.message;
        result["recipe"] = recipe;
        result["inferredFields"] = draft.inferredFields;
        result["followUpQuestions"] = draft.followUpQuestions;
        result["source"] = draft.source;
        return result;
    }

    int countRecipes(){
        int count = 0;
        for(Dish &dish : db.getDishes()){
            count += (int)dish.getVariants().size();
        }
        return count;
    }

    // Find a recipe or convert "not found" into the error Stage 2 will send.
    RecipeRef requireRecipe(int id){
        RecipeRef ref = db.findVariantById(id);
        if(ref.dishIndex < 0){
            throw ApiException(404, "Recipe not found");
        }
        return ref;
    }

    // Every mutation persists immediately. If the save fails, restore the
    // previous in-memory state so a rejected request cannot leak into later
    // responses or get written by the next successful save.
    void saveOrThrow(const RecipeDatabase& rollbackState){
        if(db.save()) return;
        db = rollbackState;
        throw ApiException(500, "Could not save recipes");
    }

    void ensureObject(const json& body){
        if(!body.is_object()){
            throw ApiException(400, "Request body must be a JSON object");
        }
    }

    // The three readers below reject wrong JSON types early. They also keep
    // optional fields easy to handle: missing/null returns the default.
    string readString(const json& body, const string& key, bool required,
                      const string& defaultValue){
        if(!body.contains(key) || body[key].is_null()){
            if(required) throw ApiException(400, key + " is required");
            return defaultValue;
        }
        if(!body[key].is_string()){
            throw ApiException(400, key + " must be a string");
        }

        string value = trimSpaces(body[key].get<string>());
        if(required && value.empty()){
            throw ApiException(400, key + " cannot be empty");
        }
        return value;
    }

    int readInt(const json& body, const string& key, bool required, int defaultValue){
        if(!body.contains(key) || body[key].is_null()){
            if(required) throw ApiException(400, key + " is required");
            return defaultValue;
        }
        if(!body[key].is_number_integer()){
            throw ApiException(400, key + " must be an integer");
        }
        return body[key].get<int>();
    }

    vector<string> readStringArray(const json& body, const string& key, bool required){
        vector<string> result;

        if(!body.contains(key) || body[key].is_null()){
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
            string text = trimSpaces(item.get<string>());
            if(text.empty()){
                throw ApiException(400, key + " must not contain empty strings");
            }
            result.push_back(text);
        }

        if(required && result.empty()){
            throw ApiException(400, key + " cannot be empty");
        }
        return result;
    }

    // Rating fields shared by summaries and the rating endpoint. Keeping them
    // in one place guarantees list/search/detail/rate all report the same numbers.
    void addRatingFields(json& j, Variant& variant){
        j["averageRating"] = variant.getRatings().average();
        j["ratingCount"] = variant.getRatings().count();
        j["myRating"] = variant.getRatings().getRating(DEMO_USER_ID);
        j["myRatingProofImageRef"] =
            variant.getRatings().getProofImageRef(DEMO_USER_ID);
    }

    // The JSON shape used by list, search and leaderboard.
    json summaryJson(Dish& dish, Variant& variant){
        json j;
        j["id"] = variant.getId();
        j["title"] = variant.getName();
        j["dish"] = dish.getName();
        j["mainIngredient"] = variant.getRecipe().getMainIngredient();
        j["cookingTime"] = variant.getRecipe().getCookingTime();
        j["imageRef"] = variant.getImageRef();
        j["youtubeUrl"] = variant.getYoutubeUrl();
        addRatingFields(j, variant);
        j["createdAt"] = variant.getCreatedAt();

        if(variant.getUpdatedAt().empty()){
            j["updatedAt"] = nullptr;
        }
        else {
            j["updatedAt"] = variant.getUpdatedAt();
        }
        return j;
    }

    // Detail = summary + ingredients + steps + all ratings (with proof images).
    json detailJson(Dish& dish, Variant& variant){
        json j = summaryJson(dish, variant);
        j["ingredients"] = variant.getRecipe().getIngredients();
        j["steps"] = variant.getRecipe().getSteps();
        j["ratings"] = variant.getRatings().toJson();
        return j;
    }

    // Response of PUT /api/recipes/:id/rating.
    json ratingJson(Variant& variant){
        json j;
        addRatingFields(j, variant);
        return j;
    }
};

#endif
