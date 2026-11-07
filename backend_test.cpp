// ============================================================
//  backend_test.cpp - Stage 1 acceptance test
//
//  This program is the "user" of BackendService for now. It runs the same
//  operations the future HTTP server will call, checks the results, and
//  prints PASS/FAIL lines.
//
//  It uses data/backend-test instead of data/ so the real demo data is never
//  modified. The folder is deleted when the test finishes.
//
//  Build:  g++ -std=c++17 -O2 -Wall -Wextra -pthread backend_test.cpp -o backend_test
//  Run:    ./backend_test
// ============================================================

#include <cmath>
#include <ctime>
#include <filesystem>
#include <functional>
#include <iostream>
#include <memory>
#include "BackendService.h"

using namespace std;

static int failureCount = 0;

static void check(bool condition, const string& message){
    if(condition){
        cout << "PASS: " << message << "\n";
    }
    else {
        cout << "FAIL: " << message << "\n";
        failureCount++;
    }
}

static void expectApiError(int expectedStatus, const string& message,
                           const function<void()>& action){
    try {
        action();
        cout << "FAIL: " << message << " (no error was thrown)\n";
        failureCount++;
    }
    catch(const ApiException& e){
        if(e.status == expectedStatus){
            cout << "PASS: " << message << "\n";
        }
        else {
            cout << "FAIL: " << message << " (expected " << expectedStatus
                 << ", got " << e.status << ": " << e.what() << ")\n";
            failureCount++;
        }
    }
    catch(const std::exception& e){
        cout << "FAIL: " << message << " (wrong exception: " << e.what() << ")\n";
        failureCount++;
    }
}

static bool containsRecipeId(const json& results, int id){
    for(const json& item : results){
        if(item.value("id", -1) == id) return true;
    }
    return false;
}

// Used by the console-search check below: RecipeCore returns RecipeRefs, not JSON.
static bool refsContainRecipeId(RecipeDatabase& db, const vector<RecipeRef>& refs, int id){
    for(const RecipeRef& ref : refs){
        if(db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex].getId() == id){
            return true;
        }
    }
    return false;
}

static int leaderboardRank(const json& leaderboard, int id){
    for(const json& entry : leaderboard["leaderboard"]){
        if(entry["recipe"].value("id", -1) == id){
            return entry.value("rank", -1);
        }
    }
    return -1;
}

static json findRating(const json& ratings, int userId){
    for(const json& rating : ratings){
        if(rating.value("userId", -1) == userId) return rating;
    }
    return json();
}

int main(){
    const string testDir = "data/backend-test";
    const string seedFile = "seed/recipes.json";

    // Always start from a clean copy of the tracked seed.
    std::filesystem::remove_all(testDir);

    try {
        unique_ptr<BackendService> service =
            make_unique<BackendService>(testDir, seedFile);

        // ----------------------------------------------------
        // 1. Seed data loads correctly
        // ----------------------------------------------------
        json health = service->health();
        check(health.value("status", "") == "ok", "health status is ok");
        check(health.value("recipes", 0) == 6, "health reports 6 seed recipes");

        json list = service->listRecipes();
        check(list.is_array() && list.size() == 6, "list returns 6 seed recipes");

        json detail = service->getRecipe(5);
        check(detail.value("title", "") == "Chicken Biryani",
              "recipe 5 is Chicken Biryani");
        check(detail.value("dish", "") == "Biryani",
              "recipe 5 belongs to the Biryani dish");
        check(detail["ingredients"].is_array() && detail["ingredients"].size() >= 3,
              "recipe 5 has ingredients");
        check(detail["steps"].is_array() && detail["steps"].size() >= 2,
              "recipe 5 has steps");
        check(detail.value("imageRef", "") == "asset:assets/images/biryani.jpg",
              "recipe 5 keeps its imageRef");
        check(!detail.value("youtubeUrl", "").empty(),
              "recipe 5 keeps its youtubeUrl");
        check(detail.value("myRating", 0) == 5,
              "recipe 5 shows the demo user's rating");
        check(detail.value("ratingCount", 0) == 2,
              "recipe 5 shows the total rating count");
        check(std::abs(detail.value("averageRating", 0.0) - 4.5) < 0.001,
              "recipe 5 average rating is 4.5");
        check(detail["ratings"].is_array() && detail["ratings"].size() == 2,
              "recipe detail includes the ratings list");
        check(detail.value("myRatingProofImageRef", "") == "",
              "recipe 5 starts without a proof image");

        expectApiError(404, "unknown recipe returns 404", [&]{
            service->getRecipe(999999);
        });

        // ----------------------------------------------------
        // 2. Typo-tolerant search
        // ----------------------------------------------------
        json search = service->searchRecipes("biriyani");
        check(!search["results"].empty() && search["results"][0].value("id", -1) == 5,
              "search 'biriyani' finds Chicken Biryani");

        search = service->searchRecipes("chiken");
        check(containsRecipeId(search["results"], 5),
              "search 'chiken' finds Chicken Biryani");
        check(containsRecipeId(search["results"], 4),
              "search 'chiken' finds spicy chicken tikka");

        search = service->searchRecipes("karai");
        check(containsRecipeId(search["results"], 3),
              "search 'karai' finds Peshawari Karahi");

        search = service->searchRecipes("peshawri");
        check(containsRecipeId(search["results"], 3),
              "search 'peshawri' finds Peshawari Karahi");

        search = service->searchRecipes("briyani");
        check(!search["results"].empty() && search["results"][0].value("id", -1) == 5,
              "search 'briyani' handles swapped letters");

        search = service->searchRecipes("chiken biryani");
        check(!search["results"].empty() && search["results"][0].value("id", -1) == 5,
              "multi-word typo search ranks Chicken Biryani first");

        search = service->searchRecipes("biryani recipe");
        check(containsRecipeId(search["results"], 5),
              "search ignores the filler word 'recipe'");

        search = service->searchRecipes("how to make biryani");
        check(containsRecipeId(search["results"], 5),
              "search ignores common question filler words");

        search = service->searchRecipes("fries");
        check(search["results"].size() == 1
                  && search["results"][0].value("id", -1) == 1,
              "search 'fries' does not match unrelated 'fry' steps");

        search = service->searchRecipes("ticka");
        check(search["results"].size() == 1
                  && search["results"][0].value("id", -1) == 4,
              "search 'ticka' does not match unrelated 'thick' steps");

        search = service->searchRecipes("tomato");
        check(search["results"].size() == 1
                  && search["results"][0].value("id", -1) == 3,
              "search 'tomato' does not match 'potato'");

        search = service->searchRecipes("frys");
        check(search["results"].size() == 1
                  && search["results"][0].value("id", -1) == 1,
              "search 'frys' finds Crispy Fries only");

        search = service->searchRecipes("bif nihari");
        check(containsRecipeId(search["results"], 6),
              "short typo 'bif' finds Beef Nihari");

        search = service->searchRecipes("potatos");
        check(containsRecipeId(search["results"], 1),
              "plural typo 'potatos' finds Crispy Fries");

        search = service->searchRecipes("chiken");
        check(!containsRecipeId(search["results"], 6),
              "search 'chiken' does not match unrelated 'thick' steps");

        // The console programs call the free searchRecipes() function in
        // RecipeCore. It must use the same fuzzy matcher as the backend.
        RecipeDatabase consoleDb(testDir);
        check(consoleDb.load(), "console search database loads");
        SearchResult consoleHits = searchRecipes(consoleDb, "chiken");
        check(refsContainRecipeId(consoleDb, consoleHits.best, 5),
              "console search uses the same fuzzy matcher");

        search = service->searchRecipes("xyz");
        check(search["results"].empty(), "search 'xyz' returns no results");

        search = service->searchRecipes("");
        check(search["results"].empty(), "empty search returns no results");

        // ----------------------------------------------------
        // 3. Rating with a proof image, and image preservation
        // ----------------------------------------------------
        json rating = service->rateRecipe(
            5, 5, string("https://example.com/proofs/biryani.jpg"));

        check(rating.value("myRating", 0) == 5,
              "rating response includes myRating");
        check(rating.value("ratingCount", 0) == 2,
              "rating response includes ratingCount");
        check(std::abs(rating.value("averageRating", 0.0) - 4.5) < 0.001,
              "rating response includes averageRating");
        check(rating.value("myRatingProofImageRef", "")
                  == "https://example.com/proofs/biryani.jpg",
              "rating response includes the proof image");

        detail = service->getRecipe(5);
        check(detail.value("myRatingProofImageRef", "")
                  == "https://example.com/proofs/biryani.jpg",
              "proof image is visible in recipe detail");

        // This is the regression test for the old data-loss bug.
        string rawText = readWholeFile(testDir + "/recipes.json");
        check(rawText.find("asset:assets/images/biryani.jpg") != string::npos,
              "saving a rating preserves the recipe imageRef");
        check(rawText.find("https://www.youtube.com/results?search_query=chicken+biryani+recipe")
                  != string::npos,
              "saving a rating preserves the recipe youtubeUrl");
        check(rawText.find("https://example.com/proofs/biryani.jpg") != string::npos,
              "saving a rating writes the proof image to JSON");

        expectApiError(400, "rating below 1 returns 400", [&]{
            service->rateRecipe(5, 0);
        });
        expectApiError(400, "rating above 5 returns 400", [&]{
            service->rateRecipe(5, 6);
        });
        expectApiError(404, "rating an unknown recipe returns 404", [&]{
            service->rateRecipe(999999, 5);
        });

        // ----------------------------------------------------
        // 4. Add recipes with image and YouTube fields
        // ----------------------------------------------------
        string suffix = to_string(time(0));
        string newTitle = "Test Biryani " + suffix;

        json body = {
            {"dish", "Biryani"},
            {"title", newTitle},
            {"mainIngredient", "rice"},
            {"ingredients", {"rice", "chicken", "yogurt"}},
            {"steps", {"marinate the chicken", "cook the rice", "layer and serve"}},
            {"cookingTime", 45},
            {"imageRef", "https://example.com/images/test-biryani.jpg"},
            {"youtubeUrl", "https://www.youtube.com/watch?v=test-biryani"}
        };

        json added = service->addRecipe(body);
        int newId = added.value("id", -1);
        check(newId > 0, "adding a recipe returns a new id");
        check(added.value("dish", "") == "Biryani",
              "added recipe is attached to the requested dish");
        check(added.value("title", "") == newTitle,
              "added recipe keeps its title");
        check(added.value("imageRef", "")
                  == "https://example.com/images/test-biryani.jpg",
              "added recipe keeps its imageRef");
        check(added.value("youtubeUrl", "")
                  == "https://www.youtube.com/watch?v=test-biryani",
              "added recipe keeps its youtubeUrl");
        check(added["ingredients"].size() == 3, "added recipe has ingredients");
        check(added["steps"].size() == 3, "added recipe has steps");
        check(added["updatedAt"].is_null(), "new recipe starts with updatedAt null");
        check(!added.value("createdAt", "").empty()
                  && added.value("createdAt", "").back() == 'Z',
              "new recipe timestamp is UTC ISO-8601");

        string newDishName = "Test Dishes " + suffix;
        json newDishBody = {
            {"dish", newDishName},
            {"title", "Test Dish Recipe " + suffix},
            {"mainIngredient", "test"},
            {"ingredients", {"test ingredient"}},
            {"steps", {"test step"}},
            {"cookingTime", 1}
        };

        json newDishRecipe = service->addRecipe(newDishBody);
        int newDishRecipeId = newDishRecipe.value("id", -1);
        check(newDishRecipe.value("dish", "") == newDishName,
              "adding a recipe creates a new dish when needed");
        check(newDishRecipe.value("imageRef", "") == "",
              "imageRef is optional when adding a recipe");
        check(newDishRecipe.value("youtubeUrl", "") == "",
              "youtubeUrl is optional when adding a recipe");

        expectApiError(409, "duplicate title in the same dish returns 409", [&]{
            json duplicate = {
                {"dish", "Biryani"},
                {"title", "Chicken Biryani"},
                {"ingredients", {"rice"}},
                {"steps", {"cook"}}
            };
            service->addRecipe(duplicate);
        });

        expectApiError(400, "missing title returns 400", [&]{
            json invalid = {
                {"dish", "Biryani"},
                {"ingredients", {"rice"}},
                {"steps", {"cook"}}
            };
            service->addRecipe(invalid);
        });

        expectApiError(400, "missing ingredients returns 400", [&]{
            json invalid = {
                {"dish", "Biryani"},
                {"title", "No Ingredients " + suffix},
                {"steps", {"cook"}}
            };
            service->addRecipe(invalid);
        });

        expectApiError(400, "negative cookingTime returns 400", [&]{
            json invalid = {
                {"dish", "Biryani"},
                {"title", "Negative Time " + suffix},
                {"ingredients", {"rice"}},
                {"steps", {"cook"}},
                {"cookingTime", -5}
            };
            service->addRecipe(invalid);
        });

        expectApiError(400, "wrong title type returns 400", [&]{
            json invalid = {
                {"dish", "Biryani"},
                {"title", 12345},
                {"ingredients", {"rice"}},
                {"steps", {"cook"}}
            };
            service->addRecipe(invalid);
        });

        // ----------------------------------------------------
        // 5. Rating updates and leaderboard
        // ----------------------------------------------------
        rating = service->rateRecipe(
            newId, 5, string("https://example.com/proofs/test-biryani.jpg"));
        check(std::abs(rating.value("averageRating", 0.0) - 5.0) < 0.001,
              "new recipe rating average is 5.0");
        check(rating.value("ratingCount", 0) == 1,
              "one user gives one rating, not two");
        check(rating.value("myRating", 0) == 5,
              "new recipe shows myRating 5");
        check(rating.value("myRatingProofImageRef", "")
                  == "https://example.com/proofs/test-biryani.jpg",
              "new recipe keeps its proof image");

        json leaderboard = service->leaderboard();
        check(leaderboardRank(leaderboard, newId) == 1,
              "new 5-star recipe is rank 1 on the leaderboard");

        rating = service->rateRecipe(
            newId, 3, string("https://example.com/proofs/updated.jpg"));
        check(std::abs(rating.value("averageRating", 0.0) - 3.0) < 0.001,
              "changing a rating updates the average");
        check(rating.value("ratingCount", 0) == 1,
              "changing a rating does not increase ratingCount");
        check(rating.value("myRatingProofImageRef", "")
                  == "https://example.com/proofs/updated.jpg",
              "changing a rating can replace the proof image");

        rating = service->rateRecipe(newId, 4);
        check(std::abs(rating.value("averageRating", 0.0) - 4.0) < 0.001,
              "rating without a proof image still updates the stars");
        check(rating.value("myRatingProofImageRef", "")
                  == "https://example.com/proofs/updated.jpg",
              "omitting the proof image keeps the existing proof");

        leaderboard = service->leaderboard();
        check(leaderboardRank(leaderboard, 5) == 1,
              "Chicken Biryani is back at rank 1 after the new rating drops");
        check(leaderboardRank(leaderboard, newId) > 1,
              "the new recipe falls below the leaderboard leader");

        // ----------------------------------------------------
        // 6. Update and validation
        // ----------------------------------------------------
        json updateBody = {
            {"title", "Updated Test Biryani " + suffix},
            {"mainIngredient", "basmati rice"},
            {"ingredients", {"rice", "chicken", "saffron"}},
            {"steps", {"marinate", "layer", "cook"}},
            {"cookingTime", 50},
            {"imageRef", "https://example.com/images/updated-biryani.jpg"},
            {"youtubeUrl", "https://youtu.be/updated-biryani"}
        };

        string originalCreatedAt = added.value("createdAt", "");
        json updated = service->updateRecipe(newId, updateBody);
        check(updated.value("title", "") == "Updated Test Biryani " + suffix,
              "update changes the title");
        check(updated.value("mainIngredient", "") == "basmati rice",
              "update changes the main ingredient");
        check(updated.value("cookingTime", 0) == 50,
              "update changes the cooking time");
        check(updated.value("imageRef", "")
                  == "https://example.com/images/updated-biryani.jpg",
              "update changes the imageRef");
        check(updated.value("youtubeUrl", "")
                  == "https://youtu.be/updated-biryani",
              "update changes the youtubeUrl");
        check(updated["ingredients"].size() == 3 && updated["steps"].size() == 3,
              "update changes ingredients and steps");
        check(!updated["updatedAt"].is_null()
                  && updated.value("updatedAt", "").back() == 'Z',
              "update sets a UTC updatedAt");
        check(updated.value("createdAt", "") == originalCreatedAt,
              "update does not change createdAt");

        expectApiError(400, "changing the dish returns 400", [&]{
            service->updateRecipe(newId, json{{"dish", "Another Dish"}});
        });

        expectApiError(400, "empty update ingredients returns 400", [&]{
            service->updateRecipe(newId, json{{"ingredients", json::array()}});
        });

        expectApiError(400, "wrong cookingTime type returns 400", [&]{
            service->updateRecipe(newId, json{{"cookingTime", "long"}});
        });

        expectApiError(409, "updating to a duplicate title returns 409", [&]{
            service->updateRecipe(newId, json{{"title", "Chicken Biryani"}});
        });

        expectApiError(404, "updating an unknown recipe returns 404", [&]{
            service->updateRecipe(999999, json{{"title", "Nothing"}});
        });

        detail = service->getRecipe(newId);
        check(detail["ratings"].size() == 1,
              "new recipe has exactly one rating after updates");
        json myRating = findRating(detail["ratings"], 1);
        check(!myRating.is_null() && myRating.value("stars", 0) == 4,
              "recipe detail exposes the rating stars");
        check(!myRating.is_null()
                  && myRating.value("proofImageRef", "")
                     == "https://example.com/proofs/updated.jpg",
              "recipe detail exposes the rating proof image");

        search = service->searchRecipes("Updated Test Biryani");
        check(containsRecipeId(search["results"], newId),
              "search finds the updated recipe title");
        search = service->searchRecipes(newDishName);
        check(containsRecipeId(search["results"], newDishRecipeId),
              "search finds recipes by dish name");

        // ----------------------------------------------------
        // 7. Persistence across a restart
        // ----------------------------------------------------
        service.reset();
        service = make_unique<BackendService>(testDir);

        health = service->health();
        check(health.value("recipes", 0) == 8,
              "reloaded database has the two added recipes");

        detail = service->getRecipe(newId);
        check(detail.value("title", "") == "Updated Test Biryani " + suffix,
              "updated title survives reload");
        check(detail.value("imageRef", "")
                  == "https://example.com/images/updated-biryani.jpg",
              "updated imageRef survives reload");
        check(detail.value("youtubeUrl", "")
                  == "https://youtu.be/updated-biryani",
              "updated youtubeUrl survives reload");
        check(detail.value("myRating", 0) == 4,
              "rating survives reload");
        check(detail.value("myRatingProofImageRef", "")
                  == "https://example.com/proofs/updated.jpg",
              "rating proof image survives reload");

        detail = service->getRecipe(5);
        check(detail.value("imageRef", "") == "asset:assets/images/biryani.jpg",
              "seed imageRef survives a full save/reload cycle");
        check(detail.value("myRatingProofImageRef", "")
                  == "https://example.com/proofs/biryani.jpg",
              "seed recipe proof image survives reload");

        detail = service->getRecipe(newDishRecipeId);
        check(detail.value("dish", "") == newDishName,
              "new dish survives reload");

        search = service->searchRecipes("biriyani");
        check(containsRecipeId(search["results"], 5),
              "typo search still works after reload");

        // ----------------------------------------------------
        // 8. Delete and cleanup behavior
        // ----------------------------------------------------
        json deleted = service->deleteRecipe(newId);
        check(deleted.value("deleted", false) == true,
              "delete confirms the recipe was removed");
        expectApiError(404, "deleted recipe returns 404", [&]{
            service->getRecipe(newId);
        });
        expectApiError(404, "deleting an unknown recipe returns 404", [&]{
            service->deleteRecipe(999999);
        });

        deleted = service->deleteRecipe(newDishRecipeId);
        check(deleted.value("deleted", false) == true,
              "delete removes the recipe in the new dish");

        list = service->listRecipes();
        check(list.size() == 6, "list is back to the 6 seed recipes");

        search = service->searchRecipes(newDishName);
        check(search["results"].empty(),
              "empty dish is removed and no longer searchable");

        check(!std::filesystem::exists(testDir + "/recipes.json.tmp"),
              "no temporary save file is left behind");

        // ----------------------------------------------------
        // 9. Shut down and remove test data
        // ----------------------------------------------------
        service.reset();
        std::filesystem::remove_all(testDir);

        if(failureCount == 0){
            cout << "\nALL STAGE 1 CHECKS PASSED\n";
            return 0;
        }

        cout << "\n" << failureCount << " CHECK(S) FAILED\n";
        return 1;
    }
    catch(const ApiException& e){
        cerr << "\nUNEXPECTED API ERROR " << e.status << ": " << e.what() << "\n";
    }
    catch(const std::exception& e){
        cerr << "\nUNEXPECTED ERROR: " << e.what() << "\n";
    }

    std::filesystem::remove_all(testDir);
    return 1;
}
