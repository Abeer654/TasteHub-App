#ifndef STORAGE_H
#define STORAGE_H

// ============================================================
//  Storage.h - JSON persistence for recipes and accounts
//
//  RecipeDatabase owns the Dish/Variant tree and writes recipes.json.
//  UserDatabase owns the accounts and writes users.json.
// ============================================================

#include "Models.h"

// ------------------------------------------------------------
//  RecipeDatabase - loads/saves everything in recipes.json
//  The "last used id" numbers are stored INSIDE the file, so ids keep
//  increasing (1, 2, 3...) even after the program is closed and reopened.
//  (ids of deleted recipes / comments are never used again)
// ------------------------------------------------------------

// points to one recipe: which dish, and which variant inside that dish
class RecipeRef {
public:
    int dishIndex;
    int variantIndex;
};

RecipeRef makeRef(int dishIndex, int variantIndex){
    RecipeRef ref;
    ref.dishIndex = dishIndex;
    ref.variantIndex = variantIndex;
    return ref;
}

// what will happen to the recipes of an account that is being deleted
class DeletionPlan {
public:
    vector<RecipeRef> keep;       // good record -> stays as "Deleted user"
    vector<RecipeRef> remove;     // deleted
};

// Owns the in-memory Dish/Variant tree and serializes it to one JSON file.
// The console programs use the default folder; BackendService passes "data".
class RecipeDatabase {
protected:
    int lastDishId = 0;
    int lastVariantId = 0;
    int lastCommentId = 0;
    vector<Dish> dishes;
    string fileName = "recipes.json";
    string backupName = "recipes.backup.json";

public:
    // The default "." keeps the old console programs working unchanged.
    // The HTTP layer later passes a folder such as "data" or a --data-dir value.
    explicit RecipeDatabase(string dataFolder = "."){
        if(dataFolder.empty()) dataFolder = ".";
        fileName = dataFolder + "/recipes.json";
        backupName = dataFolder + "/recipes.backup.json";
    }

    // Returns false only if the file exists but is damaged/unreadable
    bool load(){
        dishes.clear();
        lastDishId = 0;
        lastVariantId = 0;
        lastCommentId = 0;

        string text = readWholeFile(fileName);
        if(text.size() == 0) return true;               // no file yet (or empty file) = empty database

        // "false" = do not crash on a damaged file, give a "discarded" marker instead
        json j = json::parse(text, nullptr, false);
        if(j.is_discarded() || !j.contains("dishes") || !j["dishes"].is_array()){
            cout << "ERROR: could not read " << fileName << " (the file is damaged)\n";
            return false;
        }

        lastDishId = j.value("lastDishId", 0);
        lastVariantId = j.value("lastVariantId", 0);
        lastCommentId = j.value("lastCommentId", 0);

        for(json &dj : j["dishes"]){
            Dish d;
            d.fromJson(dj);
            dishes.push_back(d);
        }

        // safety: if the counters in the file are behind (e.g. file edited by hand),
        // move them ahead of the biggest id that really exists, so ids never repeat
        for(Dish &d : dishes){
            if(d.getId() > lastDishId) lastDishId = d.getId();
            for(Variant &v : d.getVariants()){
                if(v.getId() > lastVariantId) lastVariantId = v.getId();
                for(Comment &c : v.getComments()){
                    if(c.getId() > lastCommentId) lastCommentId = c.getId();
                }
            }
        }

        return true;
    }

    bool save(){
        json j;
        j["lastDishId"] = lastDishId;
        j["lastVariantId"] = lastVariantId;
        j["lastCommentId"] = lastCommentId;
        j["dishes"] = json::array();
        for(Dish &d : dishes){
            // Call through the base class on purpose. This is the runtime
            // polymorphism demonstration: BaseEntity::toJson() dispatches to
            // Dish::toJson(), and each Dish serializes its own Variants.
            BaseEntity &entity = d;
            j["dishes"].push_back(entity.toJson());
        }

        string text = jsonToText(j);      // make the text FIRST, so a problem can never empty the file
        makeBackupOf(fileName, backupName);

        // Atomic save: write the complete new file to a temporary name, then
        // rename it over the real file. If the process dies mid-write, the old
        // recipes.json stays intact.
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
    }

    // Ids are monotonic and never reused, even after a recipe is deleted.
    int nextDishId(){
        lastDishId++;
        return lastDishId;
    }

    int nextVariantId(){
        lastVariantId++;
        return lastVariantId;
    }

    int nextCommentId(){
        lastCommentId++;
        return lastCommentId;
    }

    // position of the dish in the list, or -1 if not found
    int findDishIndex(string dishName){
        for(int i = 0; i < (int)dishes.size(); i++){
            if(toLowerCase(dishes[i].getName()) == toLowerCase(dishName)) return i;
        }
        return -1;
    }

    // adds a dish and returns its position in the list
    int addDish(Dish d){
        dishes.push_back(d);
        return (int)dishes.size() - 1;
    }

    vector<Dish>& getDishes(){
        return dishes;
    }

    // finds a recipe by its id; dishIndex = -1 if it does not exist (any more)
    RecipeRef findVariantById(int variantId){
        for(int d = 0; d < (int)dishes.size(); d++){
            vector<Variant> &vars = dishes[d].getVariants();
            for(int v = 0; v < (int)vars.size(); v++){
                if(vars[v].getId() == variantId) return makeRef(d, v);
            }
        }
        return makeRef(-1, -1);
    }

    // all recipes uploaded by one user
    vector<RecipeRef> findByOwner(int ownerId){
        vector<RecipeRef> result;
        for(int d = 0; d < (int)dishes.size(); d++){
            vector<Variant> &vars = dishes[d].getVariants();
            for(int v = 0; v < (int)vars.size(); v++){
                if(vars[v].getOwnerId() == ownerId){
                    result.push_back(makeRef(d, v));
                }
            }
        }
        return result;
    }

    // deletes one recipe; if its dish has no recipes left, the empty dish is removed too
    void removeVariant(int dishIndex, int variantIndex){
        vector<Variant> &vars = dishes[dishIndex].getVariants();
        vars.erase(vars.begin() + variantIndex);
        if(vars.size() == 0){
            dishes.erase(dishes.begin() + dishIndex);
        }
    }

    // which recipes of this user would stay and which would be deleted
    DeletionPlan planAccountDeletion(int userId){
        DeletionPlan plan;
        vector<RecipeRef> mine = findByOwner(userId);
        for(RecipeRef &ref : mine){
            Variant &v = dishes[ref.dishIndex].getVariants()[ref.variantIndex];
            if(isGoodRecipe(v)) plan.keep.push_back(ref);
            else plan.remove.push_back(ref);
        }
        return plan;
    }

    // removes every rating, vote and comment that this user ever made
    void removeUserActivity(int userId){
        for(Dish &d : dishes){
            for(Variant &v : d.getVariants()){
                v.getRatings().removeUser(userId);
                v.getReactions().removeUser(userId);

                vector<Comment> &list = v.getComments();
                for(int i = (int)list.size() - 1; i >= 0; i--){
                    if(list[i].getUserId() == userId){
                        list.erase(list.begin() + i);
                    }
                }
                for(Comment &c : list){
                    c.getReactions().removeUser(userId);
                }
            }
        }
    }

    // Everything for deleting an account: the user's comments, ratings and likes go;
    // recipes with a GOOD RECORD stay (owner becomes "Deleted user"), the others are deleted.
    void deleteAccountData(int userId){
        removeUserActivity(userId);

        for(int d = (int)dishes.size() - 1; d >= 0; d--){
            vector<Variant> &vars = dishes[d].getVariants();
            for(int v = (int)vars.size() - 1; v >= 0; v--){
                if(vars[v].getOwnerId() != userId) continue;

                if(isGoodRecipe(vars[v])) vars[v].setOwnerId(DELETED_OWNER);
                else vars.erase(vars.begin() + v);
            }
            if(vars.size() == 0){
                dishes.erase(dishes.begin() + d);
            }
        }
    }
};

// ------------------------------------------------------------
//  UserDatabase - loads/saves all accounts in users.json
// ------------------------------------------------------------
class UserDatabase {
protected:
    int lastUserId = 0;
    vector<User> users;
    string fileName = "users.json";
    string backupName = "users.backup.json";

public:
    // The default "." keeps existing callers working. The console passes
    // "data" so accounts and the login session live next to recipes.json.
    explicit UserDatabase(string dataFolder = "."){
        if(dataFolder.empty()) dataFolder = ".";
        fileName = dataFolder + "/users.json";
        backupName = dataFolder + "/users.backup.json";
    }

    bool load(){
        users.clear();
        lastUserId = 0;

        string text = readWholeFile(fileName);
        if(text.size() == 0) return true;               // no file yet (or empty file) = no users

        json j = json::parse(text, nullptr, false);
        if(j.is_discarded() || !j.contains("users") || !j["users"].is_array()){
            cout << "ERROR: could not read " << fileName << " (the file is damaged)\n";
            return false;
        }

        lastUserId = j.value("lastUserId", 0);

        for(json &uj : j["users"]){
            User u;
            u.fromJson(uj);
            users.push_back(u);
        }

        for(User &u : users){
            if(u.getId() > lastUserId) lastUserId = u.getId();
        }

        return true;
    }

    bool save(){
        json j;
        j["lastUserId"] = lastUserId;
        j["users"] = json::array();
        for(User &u : users){
            j["users"].push_back(u.toJson());
        }

        string text = jsonToText(j);
        makeBackupOf(fileName, backupName);

        ofstream outFile(fileName);
        if(!outFile){
            cout << "ERROR: could not write to " << fileName << "\n";
            return false;
        }
        outFile << text;
        outFile.close();
        return !outFile.fail();
    }

    int nextUserId(){
        lastUserId++;
        return lastUserId;
    }

    // position in the list, or -1. Capital/small letters don't matter: "Abeer" = "abeer"
    int findIndexByUsername(string username){
        for(int i = 0; i < (int)users.size(); i++){
            if(toLowerCase(users[i].getUsername()) == toLowerCase(username)) return i;
        }
        return -1;
    }

    int findIndexById(int id){
        for(int i = 0; i < (int)users.size(); i++){
            if(users[i].getId() == id) return i;
        }
        return -1;
    }

    int addUser(User u){
        users.push_back(u);
        return (int)users.size() - 1;
    }

    void removeUser(int index){
        users.erase(users.begin() + index);
    }

    vector<User>& getUsers(){
        return users;
    }

    // username for an id. "Deleted user" for recipes that stayed after their
    // account was deleted, "unknown" for old recipes that have no owner.
    string nameOf(int id){
        if(id == DELETED_OWNER) return "Deleted user";
        int index = findIndexById(id);
        if(index == -1) return "unknown";
        return users[index].getUsername();
    }
};

#endif
