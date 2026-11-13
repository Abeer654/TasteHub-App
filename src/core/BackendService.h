#ifndef BACKENDSERVICE_H
#define BACKENDSERVICE_H

// ============================================================
//  BackendService.h - the backend facade used by console and HTTP
//
//  All recipe, account, storage, search and AI logic lives behind this
//  class. The HTTP layer only turns requests into calls and JSON is the
//  only data shape that leaves this file.
//
//  Important design choices:
//    - One mutex protects the whole database. cpp-httplib handles requests on
//      several threads, so two requests must never save at the same time.
//    - The service returns JSON copies, never references to in-memory recipes.
//      That keeps a response safe after the lock is released.
//    - Every mutation saves immediately. Saves are atomic inside
//      RecipeDatabase::save() and UserDatabase::save().
//    - Authentication uses the existing UserDatabase session hash. A bearer
//      token is random, only its SHA-256 hash is stored, and one account has
//      one active session.
// ============================================================

#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include "AiRecipe.h"
#include "Search.h"
#include "Storage.h"

// Carries the HTTP status code that the server should send to the client.
class ApiException : public std::runtime_error {
public:
    int status;

    ApiException(int statusCode, const string& message)
        : std::runtime_error(message), status(statusCode) {}
};

class BackendService {
public:
    // Build the service, make sure the data folder exists, copy the tracked
    // seed files on first run, then load the JSON databases into memory.
    //
    // dataDir is usually "data". seedFile and usersSeedFile are optional and
    // exist mainly so backend_test can use its own test directory instead of
    // touching the real runtime data.
    //
    // recipeExtractor is optional too: production uses Gemini, while tests
    // inject a fake extractor so they never touch the network.
    explicit BackendService(string dataDir, string seedFile = "",
                            std::shared_ptr<RecipeExtractor> recipeExtractor = nullptr,
                            string usersSeedFile = "")
        : db(dataDir), users(dataDir), extractor(std::move(recipeExtractor)) {
        if(!extractor) extractor = std::make_shared<GeminiRecipeExtractor>();
        if(dataDir.empty()) dataDir = ".";

        std::filesystem::path dataPath(dataDir);
        std::filesystem::create_directories(dataPath);

        std::filesystem::path seedFolder =
            dataPath.parent_path() / "seed";

        std::filesystem::path recipeSeed = seedFile.empty()
            ? seedFolder / "recipes.json"
            : std::filesystem::path(seedFile);

        std::filesystem::path userSeed = usersSeedFile.empty()
            ? seedFolder / "users.json"
            : std::filesystem::path(usersSeedFile);

        copySeedWhenRuntimeFileIsMissing(dataPath / "recipes.json", recipeSeed);
        copySeedWhenRuntimeFileIsMissing(dataPath / "users.json", userSeed);

        if(!db.load()){
            throw ApiException(500, "Could not load recipes");
        }
        if(!users.load()){
            throw ApiException(500, "Could not load users");
        }
    }

    // GET /api/health - cheap readiness check.
    json health(){
        std::lock_guard<std::mutex> lock(mutex);
        return json{{"status", "ok"},
                    {"recipes", countRecipes()},
                    {"users", users.getUsers().size()}};
    }

    // ------------------------------------------------------------
    //  Authentication
    // ------------------------------------------------------------

    // POST /api/auth/signup - create an account and log it in immediately.
    json signup(const json& body){
        std::lock_guard<std::mutex> lock(mutex);
        ensureObject(body);

        string username = readString(body, "username", true, "");
        string password = readString(body, "password", true, "");

        if(!isValidUsername(username)){
            throw ApiException(400,
                "Username must be 3-20 characters and start with a letter or number");
        }
        if(password.size() < 6 || password.size() > 64){
            throw ApiException(400, "Password must be 6-64 characters");
        }
        if(users.findIndexByUsername(username) != -1){
            throw ApiException(409, "This username is already taken");
        }

        UserDatabase rollback = users;
        User user;
        user.setId(users.nextUserId());
        user.setUsername(username);
        user.autoSetDate();
        user.setPassword(password);

        string token = randomHex(24);
        user.startSession(token);
        users.addUser(user);

        if(!users.save()){
            users = rollback;
            throw ApiException(500, "Could not save the account");
        }

        return authJson(users.getUsers().back(), token);
    }

    // POST /api/auth/login - password login with one active session.
    json login(const json& body){
        std::lock_guard<std::mutex> lock(mutex);
        ensureObject(body);

        string username = readString(body, "username", true, "");
        string password = readString(body, "password", true, "");
        int index = users.findIndexByUsername(username);

        if(index == -1 || !users.getUsers()[index].checkPassword(password)){
            throw ApiException(401, "Wrong username or password");
        }

        UserDatabase rollback = users;
        User& user = users.getUsers()[index];
        string token = randomHex(24);
        user.startSession(token);      // a second login replaces the first session

        if(!users.save()){
            users = rollback;
            throw ApiException(500, "Could not save the login");
        }

        return authJson(user, token);
    }

    // POST /api/auth/logout - forget this device's session.
    json logout(const string& token){
        std::lock_guard<std::mutex> lock(mutex);
        int userId = requireUserId(token);
        int index = users.findIndexById(userId);

        UserDatabase rollback = users;
        users.getUsers()[index].endSession();
        if(!users.save()){
            users = rollback;
            throw ApiException(500, "Could not log out");
        }

        return json{{"loggedOut", true}};
    }

    // GET /api/auth/me - validate the token and return the account.
    json me(const string& token){
        std::lock_guard<std::mutex> lock(mutex);
        int userId = requireUserId(token);
        int index = users.findIndexById(userId);
        return json{{"user", userJson(users.getUsers()[index])}};
    }

    // ------------------------------------------------------------
    //  Recipe reads (public; a token only personalises myRating)
    // ------------------------------------------------------------

    json listRecipes(const string& token = ""){
        std::lock_guard<std::mutex> lock(mutex);
        int viewerId = userIdForToken(token);

        json result = json::array();
        for(Dish &dish : db.getDishes()){
            for(Variant &variant : dish.getVariants()){
                result.push_back(summaryJson(dish, variant, viewerId));
            }
        }
        return result;
    }

    json getRecipe(int id, const string& token = ""){
        std::lock_guard<std::mutex> lock(mutex);
        int viewerId = userIdForToken(token);

        RecipeRef ref = requireRecipe(id);
        Dish &dish = db.getDishes()[ref.dishIndex];
        Variant &variant = dish.getVariants()[ref.variantIndex];
        return detailJson(dish, variant, viewerId);
    }

    // ------------------------------------------------------------
    //  Recipe writes (login required)
    // ------------------------------------------------------------

    // body follows the POST /api/recipes shape in API.md.
    // A recipe is a Variant inside a Dish. If the dish does not exist yet,
    // it is created automatically.
    json addRecipe(const json& body, const string& token){
        std::lock_guard<std::mutex> lock(mutex);
        int userId = requireUserId(token);
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
        variant.setOwnerId(userId);
        variant.autoSetDate();
        variant.getRecipe().setMainIngredient(tidyName(mainIngredient));
        variant.getRecipe().setIngredients(ingredients);
        variant.getRecipe().setSteps(steps);
        variant.getRecipe().setCookingTime(cookingTime);
        variant.setImageRef(imageRef);
        variant.setYoutubeUrl(youtubeUrl);

        dish.addVariant(variant);
        saveOrThrow(rollbackState);

        return detailJson(dish, dish.getVariants().back(), userId);
    }

    // Partial update. Fields that are absent stay unchanged.
    // Only the recipe owner may edit it; dish cannot change after creation.
    json updateRecipe(int id, const json& body, const string& token){
        std::lock_guard<std::mutex> lock(mutex);
        int userId = requireUserId(token);
        ensureObject(body);

        RecipeRef ref = requireRecipe(id);
        Dish &dish = db.getDishes()[ref.dishIndex];
        Variant &variant = dish.getVariants()[ref.variantIndex];
        requireOwner(variant, userId, "edit");

        // Validate every supplied field before changing anything. A rejected
        // request must never leave a partially updated recipe in memory.
        if(body.contains("dish")){
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

        return detailJson(dish, variant, userId);
    }

    json deleteRecipe(int id, const string& token){
        std::lock_guard<std::mutex> lock(mutex);
        int userId = requireUserId(token);

        RecipeRef ref = requireRecipe(id);
        Dish &dish = db.getDishes()[ref.dishIndex];
        Variant &variant = dish.getVariants()[ref.variantIndex];
        requireOwner(variant, userId, "delete");

        RecipeDatabase rollbackState = db;

        // removeVariant also drops the dish when its last recipe is removed.
        db.removeVariant(ref.dishIndex, ref.variantIndex);
        saveOrThrow(rollbackState);
        return json{{"deleted", true}, {"id", id}};
    }

    // Rate a recipe 1-5. proofImageRef is optional:
    //   - omitted (std::nullopt): keep the existing proof photo
    //   - provided: replace it; an empty string clears it
    // Any logged-in user may rate, including the recipe owner.
    json rateRecipe(int id, int stars,
                    std::optional<string> proofImageRef,
                    const string& token){
        std::lock_guard<std::mutex> lock(mutex);
        int userId = requireUserId(token);

        if(stars < 1 || stars > 5){
            throw ApiException(400, "stars must be between 1 and 5");
        }

        RecipeRef ref = requireRecipe(id);
        Variant &variant = db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex];

        RecipeDatabase rollbackState = db;
        bool changed = false;
        if(proofImageRef.has_value()){
            string proof = trimSpaces(*proofImageRef);
            changed = variant.getRatings().setRatingWithProof(userId, stars, proof);
        }
        else {
            changed = variant.getRatings().setRating(userId, stars);
        }

        if(changed) saveOrThrow(rollbackState);
        return ratingJson(variant, userId);
    }

    // Typo-tolerant search across dish name, recipe title, main ingredient,
    // ingredients and steps. Every query word must match something.
    json searchRecipes(const string& query, const string& token = ""){
        std::lock_guard<std::mutex> lock(mutex);
        int viewerId = userIdForToken(token);

        json results = json::array();
        for(RecipeSearchHit &hit : findRecipeMatches(db, query)){
            Dish &dish = db.getDishes()[hit.ref.dishIndex];
            Variant &variant = dish.getVariants()[hit.ref.variantIndex];
            results.push_back(summaryJson(dish, variant, viewerId));
        }
        return json{{"query", query}, {"results", results}};
    }

    // POST /api/recipes/parse - turn a natural-language description into a
    // draft recipe. It does NOT save anything.
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

    // GET /api/leaderboard?dish=...
    //
    // Ranking inside one dish: rated recipes first by average descending,
    // then rating count descending, then newest first. Unrated recipes follow
    // with rank 0 so the app can show them as "New". Without a dish filter the
    // result is the old global list of rated recipes.
    json leaderboard(const string& requestedDish = "", const string& token = ""){
        std::lock_guard<std::mutex> lock(mutex);
        int viewerId = userIdForToken(token);

        string dishFilter = tidyName(requestedDish);
        bool oneDish = !dishFilter.empty();

        struct Entry {
            double averageRating;
            int ratingCount;
            string createdAt;
            json summary;
        };
        vector<Entry> rated;
        vector<Entry> unrated;

        for(Dish &dish : db.getDishes()){
            if(oneDish && toLowerCase(dish.getName()) != toLowerCase(dishFilter)){
                continue;
            }
            for(Variant &variant : dish.getVariants()){
                Entry entry{variant.getRatings().average(),
                            variant.getRatings().count(),
                            variant.getCreatedAt(),
                            summaryJson(dish, variant, viewerId)};
                if(entry.ratingCount == 0){
                    if(oneDish) unrated.push_back(entry);
                }
                else {
                    rated.push_back(entry);
                }
            }
        }

        auto betterEntryFirst = [](const Entry& a, const Entry& b){
            if(a.averageRating != b.averageRating){
                return a.averageRating > b.averageRating;
            }
            if(a.ratingCount != b.ratingCount){
                return a.ratingCount > b.ratingCount;
            }
            return a.createdAt > b.createdAt;
        };
        std::sort(rated.begin(), rated.end(), betterEntryFirst);

        auto newestFirst = [](const Entry& a, const Entry& b){
            return a.createdAt > b.createdAt;
        };
        std::sort(unrated.begin(), unrated.end(), newestFirst);

        json list = json::array();
        int rank = 1;
        for(Entry &entry : rated){
            list.push_back(leaderboardEntryJson(entry.summary, rank++,
                                                entry.averageRating,
                                                entry.ratingCount, false));
        }
        if(oneDish){
            for(Entry &entry : unrated){
                list.push_back(leaderboardEntryJson(entry.summary, 0,
                                                    entry.averageRating, 0, true));
            }
        }

        json result{{"leaderboard", list}};
        if(oneDish) result["dish"] = dishFilter;
        return result;
    }

private:
    RecipeDatabase db;
    UserDatabase users;
    std::shared_ptr<RecipeExtractor> extractor;
    std::mutex mutex;   // guards db, users and the extractor pointer

    // ---- Internal helpers (the caller already holds mutex) ----

    static void copySeedWhenRuntimeFileIsMissing(
        const std::filesystem::path& runtimeFile,
        const std::filesystem::path& seedFile){
        if(!std::filesystem::exists(seedFile)) return;

        bool missing = !std::filesystem::exists(runtimeFile);
        if(!missing){
            try {
                missing = std::filesystem::file_size(runtimeFile) == 0;
            }
            catch(...) {
                missing = true;
            }
        }

        if(missing){
            std::filesystem::copy_file(
                seedFile, runtimeFile,
                std::filesystem::copy_options::overwrite_existing);
        }
    }

    json userJson(User& user){
        return json{{"id", user.getId()}, {"username", user.getUsername()}};
    }

    json authJson(User& user, const string& token){
        return json{{"token", token}, {"user", userJson(user)}};
    }

    // 0 means anonymous. A random or stale token therefore behaves like a
    // public read instead of breaking browsing after a demo reset.
    int userIdForToken(const string& token){
        if(token.empty()) return 0;
        for(User &user : users.getUsers()){
            if(user.checkSession(token)) return user.getId();
        }
        return 0;
    }

    int requireUserId(const string& token){
        int userId = userIdForToken(token);
        if(userId == 0){
            throw ApiException(401, "Login required");
        }
        return userId;
    }

    void requireOwner(Variant& variant, int userId, const string& action){
        if(variant.getOwnerId() != userId){
            throw ApiException(403, "Only the recipe owner can " + action + " this recipe");
        }
    }

    json leaderboardEntryJson(const json& recipe, int rank,
                              double averageRating, int ratingCount,
                              bool isNew){
        json item;
        item["rank"] = rank;
        item["recipe"] = recipe;
        item["averageRating"] = averageRating;
        item["ratingCount"] = ratingCount;
        item["isNew"] = isNew;
        return item;
    }

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

    // Find a recipe or convert "not found" into the API error.
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
    void addRatingFields(json& j, Variant& variant, int viewerId){
        j["averageRating"] = variant.getRatings().average();
        j["ratingCount"] = variant.getRatings().count();
        j["myRating"] = variant.getRatings().getRating(viewerId);
        j["myRatingProofImageRef"] =
            variant.getRatings().getProofImageRef(viewerId);
    }

    // The JSON shape used by list, search, dish rankings and leaderboard.
    json summaryJson(Dish& dish, Variant& variant, int viewerId){
        json j;
        j["id"] = variant.getId();
        j["title"] = variant.getName();
        j["dish"] = dish.getName();
        j["ownerId"] = variant.getOwnerId();
        j["ownerName"] = users.nameOf(variant.getOwnerId());
        j["mainIngredient"] = variant.getRecipe().getMainIngredient();
        j["cookingTime"] = variant.getRecipe().getCookingTime();
        j["imageRef"] = variant.getImageRef();
        j["youtubeUrl"] = variant.getYoutubeUrl();
        addRatingFields(j, variant, viewerId);
        j["createdAt"] = variant.getCreatedAt();

        if(variant.getUpdatedAt().empty()){
            j["updatedAt"] = nullptr;
        }
        else {
            j["updatedAt"] = variant.getUpdatedAt();
        }
        return j;
    }

    // Detail = summary + ingredients + steps + all ratings with usernames.
    json detailJson(Dish& dish, Variant& variant, int viewerId){
        json j = summaryJson(dish, variant, viewerId);
        j["ingredients"] = variant.getRecipe().getIngredients();
        j["steps"] = variant.getRecipe().getSteps();

        json ratings = json::array();
        for(Rating &rating : variant.getRatings().getList()){
            json item;
            item["userId"] = rating.userId;
            item["userName"] = users.nameOf(rating.userId);
            item["stars"] = rating.stars;
            item["proofImageRef"] = rating.proofImageRef;
            ratings.push_back(item);
        }
        j["ratings"] = ratings;
        return j;
    }

    // Response of PUT /api/recipes/:id/rating.
    json ratingJson(Variant& variant, int viewerId){
        json j;
        addRatingFields(j, variant, viewerId);
        return j;
    }
};

#endif
