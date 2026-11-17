// ============================================================
//  backend_test.cpp - Stage 1 acceptance test
//
//  This program is the "user" of BackendService for now. It runs the same
//  operations the HTTP server and console call, checks the results, and
//  prints PASS/FAIL lines.
//
//  It uses data/backend-test instead of data/ so the real demo data is never
//  modified. The folder is deleted when the test finishes.
//
//  Build:  make
//  Run:    ./build/backend_test
// ============================================================

#include <cmath>
#include <ctime>
#include <filesystem>
#include <functional>
#include <iostream>
#include <memory>
#include "core/BackendService.h"

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

static int leaderboardRank(const json& leaderboard, int id){
    for(const json& entry : leaderboard["leaderboard"]){
        if(entry["recipe"].value("id", -1) == id){
            return entry.value("rank", -1);
        }
    }
    return -1;
}

static json findLeaderboardEntry(const json& leaderboard, int id){
    for(const json& entry : leaderboard["leaderboard"]){
        if(entry["recipe"].value("id", -1) == id) return entry;
    }
    return json();
}

static json findRating(const json& ratings, int userId){
    for(const json& rating : ratings){
        if(rating.value("userId", -1) == userId) return rating;
    }
    return json();
}

static string tokenFrom(const json& login){
    return login.value("token", "");
}

// Offline stand-in for Gemini. The acceptance test must never need a network
// connection or a real API key.
class FakeRecipeExtractor : public RecipeExtractor {
public:
    RecipeDraft extract(const string& userText) override {
        if(userText.find("explode") != string::npos){
            throw AiServiceError(502, "fake Gemini failure");
        }

        RecipeDraft draft;
        draft.dish = "Biryani";
        draft.title = "Chicken Biryani";
        draft.mainIngredient = "rice";
        draft.ingredients = {"rice", "chicken", "yogurt", "spices", "onion"};
        draft.steps = {"marinate the chicken", "fry the onions",
                       "layer rice and chicken", "cook on low heat"};
        draft.cookingTime = 60;
        draft.message = "That sounds like a classic Chicken Biryani.";
        draft.inferredFields = {"cookingTime"};
        draft.followUpQuestions = {"How much rice did you use?"};
        draft.source = "fake";
        return draft;
    }
};

int main(){
    const string testDir = "data/backend-test";
    const string recipeSeed = "seed/recipes.json";
    const string userSeed = "seed/users.json";

    // Always start from a clean copy of the tracked seed.
    std::filesystem::remove_all(testDir);

    try {
        unique_ptr<BackendService> service =
            make_unique<BackendService>(testDir, recipeSeed,
                                        make_shared<FakeRecipeExtractor>(),
                                        userSeed);

        // ----------------------------------------------------
        // 1. Seed data and accounts
        // ----------------------------------------------------
        json health = service->health();
        check(health.value("status", "") == "ok", "health status is ok");
        check(health.value("recipes", 0) == 18,
              "health reports 18 seed recipes");
        check(health.value("users", 0) == 3,
              "health reports the three demo accounts");

        json junaidLogin = service->login(
            json{{"username", "junaid"}, {"password", "tastehub"}});
        string junaid = tokenFrom(junaidLogin);
        check(junaid.size() > 20, "junaid can log in");
        check(junaidLogin["user"].value("id", 0) == 1,
              "junaid has user id 1");
        check(junaidLogin["user"].value("username", "") == "junaid",
              "login response includes the username");
        check(!junaidLogin.contains("passwordHash"),
              "login response never exposes a password hash");

        json guestLogin = service->login(
            json{{"username", "guest"}, {"password", "guest"}});
        string guest = tokenFrom(guestLogin);
        check(guest.size() > 20, "guest can log in");
        check(service->me(junaid)["user"].value("id", 0) == 1,
              "me returns the current account");
        check(service->me(guest)["user"].value("id", 0) == 2,
              "me returns the second account");

        expectApiError(401, "wrong password returns 401", [&]{
            service->login(json{{"username", "junaid"}, {"password", "nope"}});
        });
        expectApiError(401, "unknown login returns 401", [&]{
            service->login(json{{"username", "nobody"}, {"password", "secret"}});
        });
        expectApiError(401, "me without a token returns 401", [&]{
            service->me("");
        });

        json signup = service->signup(
            json{{"username", "newdemo"}, {"password", "newdemo123"}});
        string newUser = tokenFrom(signup);
        check(signup["user"].value("id", 0) > 2,
              "signup assigns a new user id");
        expectApiError(409, "duplicate username returns 409", [&]{
            service->signup(
                json{{"username", "JUNAID"}, {"password", "another123"}});
        });
        expectApiError(400, "short username returns 400", [&]{
            service->signup(json{{"username", "ab"}, {"password", "secret123"}});
        });
        expectApiError(400, "short password returns 400", [&]{
            service->signup(json{{"username", "shortpw"}, {"password", "123"}});
        });

        // Logging in again invalidates the first token.
        json relogin = service->login(
            json{{"username", "junaid"}, {"password", "tastehub"}});
        string junaid2 = tokenFrom(relogin);
        check(junaid2 != junaid, "a second login creates a new token");
        expectApiError(401, "the previous session token stops working", [&]{
            service->me(junaid);
        });
        junaid = junaid2;

        service->logout(newUser);
        expectApiError(401, "logout invalidates the token", [&]{
            service->me(newUser);
        });

        // ----------------------------------------------------
        // 2. Seed recipes, owners and per-user ratings
        // ----------------------------------------------------
        json list = service->listRecipes();
        check(list.is_array() && list.size() == 18,
              "list returns 18 seed recipes");
        check(list[0].value("ownerName", "") == "junaid",
              "list includes ownerName");
        check(list[0].value("myRating", -1) == 0,
              "anonymous list starts with myRating 0");

        json mine = service->listRecipes(junaid);
        // Self-ratings are banned, so the first recipe (junaid's own)
        // shows no rating for him...
        check(mine[0].value("myRating", -1) == 0,
              "an owner has no self-rating in the list");
        // ...while his cross-rating on guest's Beef Biryani is visible.
        bool junaidCrossRating = false;
        for(const json& recipe : mine){
            if(recipe.value("id", -1) == 15 &&
               recipe.value("myRating", -1) == 4){
                junaidCrossRating = true;
            }
        }
        check(junaidCrossRating,
              "junaid sees his cross-rating in the list");

        json detail = service->getRecipe(5);
        check(detail.value("title", "") == "Chicken Biryani",
              "recipe 5 is Chicken Biryani");
        check(detail.value("dish", "") == "Biryani",
              "recipe 5 belongs to the Biryani dish");
        check(detail.value("ownerId", 0) == 1,
              "recipe 5 belongs to junaid");
        check(detail.value("ownerName", "") == "junaid",
              "recipe detail includes ownerName");
        check(detail["ingredients"].is_array() && detail["ingredients"].size() >= 3,
              "recipe 5 has ingredients");
        check(detail["steps"].is_array() && detail["steps"].size() >= 2,
              "recipe 5 has steps");
        check(detail.value("imageRef", "")
                    .rfind("https://upload.wikimedia.org/", 0) == 0,
              "seed recipes ship with a hosted photo URL");
        check(detail.value("youtubeUrl", "").empty(),
              "seed recipes carry no youtube url");
        check(detail.value("myRating", -1) == 0,
              "anonymous detail has myRating 0");
        check(detail.value("ratingCount", 0) == 2,
              "recipe 5 shows the total rating count");
        check(std::abs(detail.value("averageRating", 0.0) - 5.0) < 0.001,
              "recipe 5 average rating is 5.0");
        check(detail["ratings"].is_array() && detail["ratings"].size() == 2,
              "recipe detail includes the ratings list");
        // After the self-rating ban, recipe 5's first rating was re-homed
        // to the critic account (its author junaid may not rate it).
        bool criticRated = false;
        bool guestRated = false;
        for(const json& entry : detail["ratings"]){
            if(entry.value("userName", "") == "critic") criticRated = true;
            if(entry.value("userName", "") == "guest") guestRated = true;
        }
        check(criticRated && guestRated,
              "rating entries include usernames");
        check(detail.value("myRatingProofImageRef", "") == "",
              "recipe 5 starts without a proof image");

        json junaidDetail = service->getRecipe(5, junaid);
        json guestDetail = service->getRecipe(2, guest);
        check(junaidDetail.value("myRating", 0) == 0,
              "junaid has no rating on his own recipe");
        check(guestDetail.value("myRating", 0) == 4,
              "guest sees a different myRating on recipe 2");

        expectApiError(404, "unknown recipe returns 404", [&]{
            service->getRecipe(999999);
        });

        // ----------------------------------------------------
        // 3. Typo-tolerant search
        // ----------------------------------------------------
        json search = service->searchRecipes("biriyani");
        check(!search["results"].empty() && search["results"][0].value("id", -1) == 5,
              "search 'biriyani' finds Chicken Biryani first");

        search = service->searchRecipes("chiken");
        check(containsRecipeId(search["results"], 5),
              "search 'chiken' finds Chicken Biryani");
        check(containsRecipeId(search["results"], 4),
              "search 'chiken' finds Chicken Tikka");
        check(!containsRecipeId(search["results"], 6),
              "search 'chiken' does not match unrelated 'thick' steps");

        search = service->searchRecipes("karai");
        check(containsRecipeId(search["results"], 3),
              "search 'karai' finds Peshawari Karahi");

        search = service->searchRecipes("peshawri");
        check(containsRecipeId(search["results"], 3),
              "search 'peshawri' finds Peshawari Karahi");

        search = service->searchRecipes("chiken biryani");
        check(!search["results"].empty() && search["results"][0].value("id", -1) == 5,
              "multi-word typo search ranks Chicken Biryani first");

        search = service->searchRecipes("biryani recipe");
        check(containsRecipeId(search["results"], 5),
              "search ignores the filler word 'recipe'");

        search = service->searchRecipes("how to make biryani");
        check(containsRecipeId(search["results"], 5),
              "search ignores common question filler words");

        search = service->searchRecipes("ticka");
        check(containsRecipeId(search["results"], 4),
              "search 'ticka' finds the tikka recipes");

        search = service->searchRecipes("tomato");
        check(containsRecipeId(search["results"], 3),
              "search 'tomato' finds the karahi recipes");

        search = service->searchRecipes("frys");
        check(containsRecipeId(search["results"], 1),
              "search 'frys' finds the fries recipes");

        search = service->searchRecipes("bif nihari");
        check(containsRecipeId(search["results"], 6),
              "short typo 'bif' finds Beef Nihari");

        search = service->searchRecipes("potatos");
        check(containsRecipeId(search["results"], 1),
              "plural typo 'potatos' finds Crispy Fries");

        search = service->searchRecipes("xyz");
        check(search["results"].empty(), "search 'xyz' returns no results");

        search = service->searchRecipes("");
        check(search["results"].empty(), "empty search returns no results");

        // BackendService (HTTP) and the test use the free searchRecipes()
        // function in Search.h.
        RecipeDatabase consoleDb(testDir);
        check(consoleDb.load(), "console search database loads");
        SearchResult consoleHits = searchRecipes(consoleDb, "chiken");
        bool consoleFinds5 = false;
        for(RecipeRef &ref : consoleHits.best){
            if(consoleDb.getDishes()[ref.dishIndex]
                   .getVariants()[ref.variantIndex].getId() == 5){
                consoleFinds5 = true;
            }
        }
        check(consoleFinds5, "console search uses the same fuzzy matcher");

        // ----------------------------------------------------
        // 4. Natural-language recipe extraction (AI draft flow)
        // ----------------------------------------------------
        json parsed = service->parseRecipeText(
            "I made chicken biryani with rice, chicken, yogurt, onions and spices. "
            "I marinated the chicken, fried onions, layered it with rice and cooked "
            "it slowly on low heat.");
        check(parsed["recipe"].value("title", "") == "Chicken Biryani",
              "parse returns the extracted recipe title");
        check(parsed["recipe"].value("mainIngredient", "") == "rice",
              "parse returns the main ingredient");
        check(parsed["recipe"]["ingredients"].size() == 5,
              "parse returns the ingredient list");
        check(parsed["recipe"]["steps"].size() == 4,
              "parse returns the cooking steps");
        check(parsed.value("source", "") == "fake",
              "parse reports which extractor was used");
        check(parsed["inferredFields"].is_array()
                  && !parsed["inferredFields"].empty(),
              "parse marks fields the AI had to infer");
        check(service->listRecipes().size() == 18,
              "parse does not save the draft automatically");

        expectApiError(400, "empty AI description returns 400", [&]{
            service->parseRecipeText("  ");
        });
        expectApiError(502, "AI failure is translated to an API error", [&]{
            service->parseRecipeText("please make this explode");
        });

        // ----------------------------------------------------
        // 5. Rating with a proof image, per user
        // ----------------------------------------------------
        // Recipe 5 belongs to junaid, so rating it is a self-rating.
        expectApiError(403, "an author cannot rate their own recipe", [&]{
            service->rateRecipe(5, 5, string("/uploads/proof-biryani.jpg"),
                                junaid);
        });

        // He rates a recipe he does not own instead: Yakhni Pulao (guest's).
        json rating = service->rateRecipe(
            9, 5, string("/uploads/proof-biryani.jpg"), junaid);
        check(rating.value("myRating", 0) == 5,
              "rating response includes myRating");
        check(rating.value("myRatingProofImageRef", "")
                  == "/uploads/proof-biryani.jpg",
              "rating response includes the proof image");

        detail = service->getRecipe(9, junaid);
        check(detail.value("myRatingProofImageRef", "")
                  == "/uploads/proof-biryani.jpg",
              "proof image is visible in recipe detail");

        // Guest rates junaid's recipe 5 - a cross-rating, allowed.
        json guestRating = service->rateRecipe(5, 3, nullopt, guest);
        check(guestRating.value("myRating", 0) == 3,
              "guest has a separate rating on recipe 5");
        check(service->getRecipe(5, junaid).value("myRating", 0) == 0,
              "the owner still has no rating on his own recipe");

        string rawText = readWholeFile(testDir + "/recipes.json");
        check(rawText.find("/uploads/proof-biryani.jpg") != string::npos,
              "saving a rating writes the proof image to JSON");
        check(rawText.find("https://upload.wikimedia.org/") != string::npos,
              "seed recipes keep their photo urls when a rating is saved");

        expectApiError(400, "rating below 1 returns 400", [&]{
            service->rateRecipe(5, 0, nullopt, junaid);
        });
        expectApiError(400, "rating above 5 returns 400", [&]{
            service->rateRecipe(5, 6, nullopt, junaid);
        });
        expectApiError(401, "rating without login returns 401", [&]{
            service->rateRecipe(5, 5, nullopt, "");
        });
        expectApiError(404, "rating an unknown recipe returns 404", [&]{
            service->rateRecipe(999999, 5, nullopt, junaid);
        });

        // ----------------------------------------------------
        // 6. Add, update and owner-only access
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
            {"imageRef", "/uploads/test-biryani.png"},
            {"youtubeUrl", "https://www.youtube.com/watch?v=test-biryani"}
        };

        expectApiError(401, "creating a recipe without login returns 401", [&]{
            service->addRecipe(body, "");
        });

        json added = service->addRecipe(body, junaid);
        int newId = added.value("id", -1);
        check(newId > 0, "adding a recipe returns a new id");
        check(added.value("ownerId", 0) == 1,
              "junaid owns the recipe he added");
        check(added.value("ownerName", "") == "junaid",
              "added recipe returns the owner name");
        check(added.value("imageRef", "") == "/uploads/test-biryani.png",
              "added recipe keeps its uploaded image path");
        check(added.value("youtubeUrl", "")
                  == "https://www.youtube.com/watch?v=test-biryani",
              "added recipe keeps its youtubeUrl");

        string newDishName = "Test Dishes " + suffix;
        json guestRecipe = service->addRecipe(json{
            {"dish", newDishName},
            {"title", "Guest Dish Recipe " + suffix},
            {"ingredients", {"test ingredient"}},
            {"steps", {"test step"}},
            {"cookingTime", 1}
        }, guest);
        int guestRecipeId = guestRecipe.value("id", -1);
        check(guestRecipe.value("ownerId", 0) == 2,
              "guest owns the recipe he added");

        expectApiError(409, "duplicate title in the same dish returns 409", [&]{
            service->addRecipe(json{
                {"dish", "Biryani"},
                {"title", "Chicken Biryani"},
                {"ingredients", {"rice"}},
                {"steps", {"cook"}}
            }, junaid);
        });
        expectApiError(400, "missing title returns 400", [&]{
            service->addRecipe(json{
                {"dish", "Biryani"},
                {"ingredients", {"rice"}},
                {"steps", {"cook"}}
            }, junaid);
        });
        expectApiError(400, "wrong title type returns 400", [&]{
            service->addRecipe(json{
                {"dish", "Biryani"},
                {"title", 12345},
                {"ingredients", {"rice"}},
                {"steps", {"cook"}}
            }, junaid);
        });

        expectApiError(403, "a non-owner cannot edit a recipe", [&]{
            service->updateRecipe(5, json{{"title", "Hijacked"}}, guest);
        });
        expectApiError(403, "a non-owner cannot delete a recipe", [&]{
            service->deleteRecipe(5, guest);
        });

        json updateBody = {
            {"title", "Updated Test Biryani " + suffix},
            {"mainIngredient", "basmati rice"},
            {"ingredients", {"rice", "chicken", "saffron"}},
            {"steps", {"marinate", "layer", "cook"}},
            {"cookingTime", 50},
            {"imageRef", "/uploads/updated-biryani.png"},
            {"youtubeUrl", "https://youtu.be/updated-biryani"}
        };
        json updated = service->updateRecipe(newId, updateBody, junaid);
        check(updated.value("title", "") == "Updated Test Biryani " + suffix,
              "the owner can update the title");
        check(updated.value("cookingTime", 0) == 50,
              "the owner can update the cooking time");
        check(updated.value("imageRef", "") == "/uploads/updated-biryani.png",
              "the owner can update the imageRef");
        check(!updated["updatedAt"].is_null(),
              "update sets updatedAt");

        expectApiError(400, "changing the dish returns 400", [&]{
            service->updateRecipe(newId, json{{"dish", "Another Dish"}}, junaid);
        });
        expectApiError(400, "empty update ingredients returns 400", [&]{
            service->updateRecipe(newId, json{{"ingredients", json::array()}},
                                  junaid);
        });

        // A rejected update must not partially change the recipe in memory.
        string titleBefore = service->getRecipe(newId).value("title", "");
        expectApiError(400, "invalid update does not partially apply", [&]{
            service->updateRecipe(newId, json{
                {"title", "Rejected Title " + suffix},
                {"ingredients", json::array()}
            }, junaid);
        });
        check(service->getRecipe(newId).value("title", "") == titleBefore,
              "rejected update leaves the recipe unchanged in memory");

        json ratingsDetail = service->getRecipe(newId, guest);
        check(ratingsDetail.value("ratingCount", -1) == 0,
              "the new recipe starts unrated");

        rating = service->rateRecipe(newId, 4,
                                     string("/uploads/guest-proof.png"), guest);
        check(rating.value("ratingCount", 0) == 1,
              "guest can rate the new recipe");
        check(service->getRecipe(newId, guest).value("myRating", 0) == 4,
              "guest sees the new rating");
        check(service->getRecipe(newId, junaid).value("myRating", 0) == 0,
              "junaid still has no rating on the new recipe");

        // ----------------------------------------------------
        // 7. Per-dish ranking
        // ----------------------------------------------------
        json biryaniBoard = service->leaderboard("Biryani", junaid);
        check(biryaniBoard.value("dish", "") == "Biryani",
              "dish leaderboard echoes the filter");
        // Guest lowered Chicken Biryani to 3 stars above, so Beef Biryani
        // (4.5 from 2) leads. Chicken Biryani and the new 4-star recipe both
        // average 4.0; the seeded recipe has more ratings, so it comes next.
        check(leaderboardRank(biryaniBoard, 15) == 1,
              "Beef Biryani is #1 after the guest rating change");
        check(leaderboardRank(biryaniBoard, 5) == 2,
              "Chicken Biryani is #2 in Biryani");
        check(leaderboardRank(biryaniBoard, newId) == 3,
              "the newest one-rating recipe breaks the tie first");
        check(leaderboardRank(biryaniBoard, 16) == 4,
              "Vegetable Biryani is #4 in Biryani");

        json karahiBoard = service->leaderboard("Karahi", junaid);
        check(leaderboardRank(karahiBoard, 3) == 1,
              "Peshawari Karahi is #1 in Karahi");
        check(leaderboardRank(karahiBoard, 11) == 2,
              "Chicken Karahi is #2 in Karahi");
        json unratedKarahi = findLeaderboardEntry(karahiBoard, 12);
        check(unratedKarahi.value("rank", -1) == 0,
              "an unrated recipe has rank 0");
        check(unratedKarahi.value("isNew", false),
              "an unrated recipe is marked as new");
        check(karahiBoard["leaderboard"].back()["recipe"].value("id", -1) == 12,
              "unrated recipes come after rated recipes");

        // Mutton Karahi is junaid's recipe, so the rating comes from guest.
        service->rateRecipe(12, 5, nullopt, guest);
        karahiBoard = service->leaderboard("Karahi", junaid);
        check(leaderboardRank(karahiBoard, 12) == 1,
              "a new 5-star rating moves Mutton Karahi to #1");

        json globalBoard = service->leaderboard("", junaid);
        check(globalBoard["leaderboard"].size() >= 15,
              "global leaderboard still includes rated recipes");
        bool globalHasNew = false;
        for(const json& entry : globalBoard["leaderboard"]){
            if(entry.value("isNew", false)) globalHasNew = true;
        }
        check(!globalHasNew, "global leaderboard omits unrated recipes");

        // ----------------------------------------------------
        // 8. Persistence across a restart
        // ----------------------------------------------------
        service.reset();
        service = make_unique<BackendService>(testDir, recipeSeed,
                                              make_shared<FakeRecipeExtractor>(),
                                              userSeed);

        health = service->health();
        check(health.value("recipes", 0) == 20,
              "reloaded database has the two added recipes");
        check(service->me(junaid)["user"].value("id", 0) == 1,
              "the session token survives a server restart");

        detail = service->getRecipe(newId, junaid);
        check(detail.value("title", "") == "Updated Test Biryani " + suffix,
              "updated title survives reload");
        check(detail.value("imageRef", "") == "/uploads/updated-biryani.png",
              "updated imageRef survives reload");
        detail = service->getRecipe(9, junaid);
        check(detail.value("myRatingProofImageRef", "")
                  == "/uploads/proof-biryani.jpg",
              "seed recipe proof image survives reload");
        check(detail["ratings"].size() == 2,
              "rating changes survive reload");
        check(detail.value("myRating", 0) == 5,
              "junaid's rating survives reload");
        check(service->getRecipe(5, guest).value("myRating", 0) == 3,
              "guest's separate rating survives reload");

        search = service->searchRecipes(newDishName, junaid);
        check(containsRecipeId(search["results"], guestRecipeId),
              "the guest recipe survives reload");

        // ----------------------------------------------------
        // 9. Delete and cleanup behavior
        // ----------------------------------------------------
        expectApiError(403, "junaid cannot delete the guest recipe", [&]{
            service->deleteRecipe(guestRecipeId, junaid);
        });

        json deleted = service->deleteRecipe(guestRecipeId, guest);
        check(deleted.value("deleted", false) == true,
              "the owner can delete their recipe");

        deleted = service->deleteRecipe(newId, junaid);
        check(deleted.value("deleted", false) == true,
              "delete confirms the recipe was removed");
        expectApiError(404, "deleted recipe returns 404", [&]{
            service->getRecipe(newId);
        });

        list = service->listRecipes();
        check(list.size() == 18, "list is back to the 18 seed recipes");

        search = service->searchRecipes(newDishName);
        check(search["results"].empty(),
              "empty dish is removed and no longer searchable");

        check(!std::filesystem::exists(testDir + "/recipes.json.tmp"),
              "no temporary save file is left behind");

        // ----------------------------------------------------
        // 10. Shut down and remove test data
        // ----------------------------------------------------
        service.reset();
        std::filesystem::remove_all(testDir);

        if(failureCount == 0){
            cout << "\nALL BACKEND CHECKS PASSED\n";
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
