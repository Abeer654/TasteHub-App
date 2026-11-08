#include <iostream>
#include "AiRecipe.h"
#include "ConsoleTools.h"
using namespace std;

// ============================================================
//  upload.cpp  -  upload, edit and delete YOUR OWN recipes
//  (log in first). Pattern used for every save:
//  ask everything -> load the newest file -> change -> save,
//  so changes made meanwhile by other programs are never lost.
//
//  "Yap mode" lets the user describe the dish naturally. Gemini turns
//  that paragraph into the same Recipe fields the step-by-step form uses.
// ============================================================

// Shows what Gemini understood before anything is saved.
void showAiDraft(const RecipeDraft &draft){
    cout << "\n===== AI RECIPE DRAFT =====\n";
    cout << "Dish: " << draft.dish << "\n";
    cout << "Title: " << draft.title << "\n";
    cout << "Main ingredient: " << draft.mainIngredient << "\n";
    cout << "Cooking time: " << draft.cookingTime << " minutes\n";

    cout << "Ingredients:\n";
    for(const string &item : draft.ingredients) cout << " - " << item << "\n";

    cout << "Steps:\n";
    for(int i = 0; i < (int)draft.steps.size(); i++){
        cout << " " << i + 1 << ". " << draft.steps[i] << "\n";
    }

    if(!draft.imageRef.empty()) cout << "Image: " << draft.imageRef << "\n";
    if(!draft.youtubeUrl.empty()) cout << "YouTube: " << draft.youtubeUrl << "\n";
    if(!draft.message.empty()) cout << "\nAI: " << draft.message << "\n";

    if(!draft.inferredFields.empty()){
        cout << "AI filled in: ";
        for(int i = 0; i < (int)draft.inferredFields.size(); i++){
            if(i > 0) cout << ", ";
            cout << draft.inferredFields[i];
        }
        cout << "\n";
    }

    if(!draft.followUpQuestions.empty()){
        cout << "AI would ask:\n";
        for(const string &question : draft.followUpQuestions){
            cout << " - " << question << "\n";
        }
    }
}

// Natural-language upload. The user writes freely, Gemini extracts the
// structured recipe, then the user confirms before we save anything.
void uploadRecipeFromText(RecipeDatabase &db, int userId, string username){
    if(!db.load()){
        cout << "Stopped, so your saved recipes are not overwritten.\n";
        return;
    }

    cout << "\nDescribe the dish in your own words. Mention the ingredients and how you make it.\n";
    cout << "You can ramble; typos and Roman Urdu are fine.\n";
    cout << "Type 'done' on its own line when you are finished.\n";

    string text;
    while(true){
        string line = readLine();
        if(toLowerCase(trimSpaces(line)) == "done") break;
        text += line + "\n";
    }

    if(trimSpaces(text).empty()){
        cout << "Nothing was written, so nothing was saved.\n";
        return;
    }

    RecipeDraft draft;
    try {
        GeminiRecipeExtractor extractor;
        draft = extractor.extract(text);
    }
    catch(const AiServiceError &error){
        cout << "\nAI could not build the recipe: " << error.what() << "\n";
        cout << "You can still use the step-by-step upload.\n";
        return;
    }

    showAiDraft(draft);
    cout << "\nSave this recipe? Type yes to save, anything else to cancel: ";
    if(toLowerCase(trimSpaces(readLine())) != "yes"){
        cout << "Cancelled. Nothing was saved.\n";
        return;
    }

    // Reload after the (slow) AI call so a recipe added by another program
    // meanwhile is not lost.
    if(!db.load()){
        cout << "Stopped, so your saved recipes are not overwritten.\n";
        return;
    }

    // A dish cannot contain two recipes with the same title.
    while(true){
        int existingDish = db.findDishIndex(draft.dish);
        if(existingDish < 0 || !db.getDishes()[existingDish].hasVariant(draft.title)){
            break;
        }
        cout << "A recipe named '" << draft.title << "' already exists in '"
             << draft.dish << "'.\n";
        cout << "Enter a different title (or leave empty to cancel): ";
        string newTitle = tidyName(readLine());
        if(newTitle.empty()){
            cout << "Cancelled. Nothing was saved.\n";
            return;
        }
        draft.title = newTitle;
    }

    int dishIndex = db.findDishIndex(draft.dish);
    if(dishIndex < 0){
        Dish newDish;
        newDish.setName(draft.dish);
        newDish.setId(db.nextDishId());
        newDish.autoSetDate();
        dishIndex = db.addDish(newDish);
    }

    Dish &dish = db.getDishes()[dishIndex];

    Variant variant;
    variant.setName(draft.title);
    variant.setId(db.nextVariantId());
    variant.setOwnerId(userId);
    variant.autoSetDate();
    variant.getRecipe().setMainIngredient(draft.mainIngredient);
    variant.getRecipe().setIngredients(draft.ingredients);
    variant.getRecipe().setSteps(draft.steps);
    variant.getRecipe().setCookingTime(draft.cookingTime);
    variant.setImageRef(draft.imageRef);
    variant.setYoutubeUrl(draft.youtubeUrl);

    dish.addVariant(variant);

    if(db.save()){
        cout << "\nRecipe saved successfully!\n";
        variant.show(dish.getName(), username);
    }
    else{
        cout << "\nSomething went wrong, recipe was NOT saved.\n";
    }
}

// Asks for items one by one until the user types 'done' (at least 1 item is required)
vector<string> askList(string intro, string itemName, bool isSteps){
    vector<string> items;
    cout << intro << "\n";

    while(true){
        if(isSteps) cout << "Step " << items.size() + 1 << "> ";
        else cout << "> ";

        string line = trimSpaces(readLine());

        if(toLowerCase(line) == "done"){
            if(items.size() == 0){
                cout << "Please add at least one " << itemName << " before typing 'done'.\n";
                continue;
            }
            break;
        }
        if(line.size() == 0) continue;      // ignore accidental empty Enter
        items.push_back(line);
    }
    return items;
}

// Asks until the user types a valid number of minutes
int askCookingTime(){
    while(true){
        cout << "Cooking time in minutes (number only, e.g. 45): ";
        string text = trimSpaces(readLine());

        if(isWholeNumber(text)){
            int minutes = stoi(text);
            if(minutes > 0 && minutes <= 10000) return minutes;
        }
        cout << "Please enter a valid number of minutes (1 to 10000).\n";
    }
}

void uploadRecipe(RecipeDatabase &db, int userId, string username){
    if(!db.load()){
        cout << "Stopped, so your saved recipes are not overwritten.\n";
        return;
    }

    // ---------- STEP 1: DISH name ----------
    string dishName = askRequired("Enter DISH name (e.g. Biryani, Pulao, Fries): ");

    int dishIndex = db.findDishIndex(dishName);

    if(dishIndex == -1){
        cout << "New dish: " << dishName << "\n";
    }
    else{
        // dish already exists -> we only add a new variant under it
        Dish &existing = db.getDishes()[dishIndex];
        cout << "Dish '" << existing.getName() << "' already exists. Its variants:\n";
        for(Variant &v : existing.getVariants()){
            cout << " - " << v.getName() << "\n";
        }
        cout << "Your recipe will be added as a new variant.\n";
    }

    // ---------- STEP 2: VARIANT name ----------
    string variantName;
    while(true){
        variantName = askRequired("Enter VARIANT name (e.g. Bombay Biryani): ");

        if(dishIndex != -1 && db.getDishes()[dishIndex].hasVariant(variantName)){
            cout << "This variant already exists under " << db.getDishes()[dishIndex].getName()
                 << ". Please enter a different name.\n";
        }
        else{
            break;
        }
    }

    // ---------- STEP 3: RECIPE ----------
    Recipe recipe;
    recipe.setMainIngredient(askRequired("What is the MAIN ingredient? (e.g. rice for biryani): "));
    recipe.setIngredients(askList("Enter ingredients one by one. Type 'done' when finished.", "ingredient", false));
    recipe.setSteps(askList("Enter steps one by one. Type 'done' when finished.", "step", true));
    recipe.setCookingTime(askCookingTime());

    // ---------- SAVE (load the newest file first) ----------
    if(!db.load()){
        cout << "Stopped, so your saved recipes are not overwritten.\n";
        return;
    }

    dishIndex = db.findDishIndex(dishName);
    if(dishIndex == -1){
        Dish newDish;
        newDish.setName(dishName);
        newDish.setId(db.nextDishId());      // id comes from the counter saved in the file
        newDish.autoSetDate();
        dishIndex = db.addDish(newDish);
    }

    Dish &dish = db.getDishes()[dishIndex];

    if(dish.hasVariant(variantName)){
        cout << "Somebody just added a variant with this name. Your recipe was NOT saved - please try again.\n";
        return;
    }

    Variant variant;
    variant.setName(variantName);
    variant.setId(db.nextVariantId());
    variant.setOwnerId(userId);              // remembers WHO uploaded it
    variant.autoSetDate();
    variant.getRecipe() = recipe;

    dish.addVariant(variant);

    if(db.save()){
        cout << "\nRecipe saved successfully!\n";
        variant.show(dish.getName(), username);
    }
    else{
        cout << "\nSomething went wrong, recipe was NOT saved.\n";
    }
}

// Shows the user's OWN recipes as a numbered list and lets them pick one.
// Returns the recipe's id, or 0 if there is nothing to pick or the user cancels.
int chooseMyRecipe(RecipeDatabase &db, int userId, string action){
    vector<RecipeRef> mine = db.findByOwner(userId);

    if(mine.size() == 0){
        cout << "You have not uploaded any recipe yet.\n";
        return 0;
    }

    cout << "\nYour recipes:\n";
    for(int i = 0; i < (int)mine.size(); i++){
        cout << " " << i + 1 << ". " << describeRecipe(db, mine[i]) << "\n";
    }

    int choice = askChoice("Enter the number of the recipe to " + action + " (0 to cancel): ", 0, (int)mine.size());
    if(choice == 0) return 0;

    RecipeRef ref = mine[choice - 1];
    return db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex].getId();
}

void editRecipe(RecipeDatabase &db, int userId, string username){
    if(!db.load()){
        cout << "Stopped, so your saved recipes are not overwritten.\n";
        return;
    }

    int variantId = chooseMyRecipe(db, userId, "edit");
    if(variantId == 0) return;

    RecipeRef ref = db.findVariantById(variantId);
    Dish &dish = db.getDishes()[ref.dishIndex];
    Variant edited = dish.getVariants()[ref.variantIndex];     // a working COPY - the original stays safe until you save
    Recipe &recipe = edited.getRecipe();

    while(true){
        edited.show(dish.getName(), username);
        cout << "\nWhat do you want to change?\n";
        cout << " 1. Variant name\n";
        cout << " 2. Main ingredient\n";
        cout << " 3. Ingredients (type the full list again)\n";
        cout << " 4. Steps (type the full list again)\n";
        cout << " 5. Cooking time\n";
        cout << " 6. SAVE changes and finish\n";
        cout << " 0. Cancel (throw away changes)\n";
        int choice = askChoice("Choice: ", 0, 6);

        if(choice == 0){
            cout << "Cancelled. Nothing was changed.\n";
            return;
        }
        else if(choice == 1){
            while(true){
                string newName = askRequired("New variant name: ");

                bool taken = false;
                for(int i = 0; i < (int)dish.getVariants().size(); i++){
                    if(i == ref.variantIndex) continue;      // the recipe itself doesn't count
                    if(toLowerCase(dish.getVariants()[i].getName()) == toLowerCase(newName)) taken = true;
                }
                if(taken){
                    cout << "This variant name already exists under " << dish.getName() << ". Try another.\n";
                    continue;
                }
                edited.setName(newName);
                break;
            }
        }
        else if(choice == 2){
            recipe.setMainIngredient(askRequired("New main ingredient: "));
        }
        else if(choice == 3){
            recipe.setIngredients(askList("Type ALL ingredients again, one by one. Type 'done' when finished.", "ingredient", false));
        }
        else if(choice == 4){
            recipe.setSteps(askList("Type ALL steps again, one by one. Type 'done' when finished.", "step", true));
        }
        else if(choice == 5){
            recipe.setCookingTime(askCookingTime());
        }
        else if(choice == 6){
            break;
        }
    }

    // ---------- SAVE: load the newest file and change ONLY name + recipe ----------
    // (ratings, likes and comments that others added while you were editing stay safe)
    if(!db.load()){
        cout << "Stopped, so your saved recipes are not overwritten.\n";
        return;
    }

    RecipeRef fresh = db.findVariantById(variantId);
    if(fresh.dishIndex == -1){
        cout << "This recipe no longer exists. Nothing was saved.\n";
        return;
    }

    Dish &freshDish = db.getDishes()[fresh.dishIndex];
    Variant &target = freshDish.getVariants()[fresh.variantIndex];

    if(target.getOwnerId() != userId){
        cout << "This recipe is not yours any more. Nothing was saved.\n";
        return;
    }

    for(int i = 0; i < (int)freshDish.getVariants().size(); i++){
        if(i == fresh.variantIndex) continue;
        if(toLowerCase(freshDish.getVariants()[i].getName()) == toLowerCase(edited.getName())){
            cout << "Somebody just used this variant name. Nothing was saved - please try again.\n";
            return;
        }
    }

    target.setName(edited.getName());
    target.getRecipe() = edited.getRecipe();
    target.markEdited();

    if(db.save()){
        cout << "\nRecipe updated successfully!\n";
        target.show(freshDish.getName(), username);
    }
    else{
        cout << "\nSomething went wrong, changes were NOT saved.\n";
    }
}

void deleteRecipe(RecipeDatabase &db, int userId, string username){
    if(!db.load()){
        cout << "Stopped, so your saved recipes are not overwritten.\n";
        return;
    }

    int variantId = chooseMyRecipe(db, userId, "delete");
    if(variantId == 0) return;

    RecipeRef ref = db.findVariantById(variantId);
    Dish &dish = db.getDishes()[ref.dishIndex];
    dish.getVariants()[ref.variantIndex].show(dish.getName(), username);

    cout << "\nThis recipe will be deleted permanently (with its ratings and comments). Type yes to confirm: ";
    if(toLowerCase(trimSpaces(readLine())) != "yes"){
        cout << "Cancelled. The recipe was not deleted.\n";
        return;
    }

    // load the newest file, then delete
    if(!db.load()){
        cout << "Stopped, so your saved recipes are not overwritten.\n";
        return;
    }

    ref = db.findVariantById(variantId);
    if(ref.dishIndex == -1){
        cout << "This recipe was already deleted.\n";
        return;
    }
    if(db.getDishes()[ref.dishIndex].getVariants()[ref.variantIndex].getOwnerId() != userId){
        cout << "This recipe is not yours. Nothing was deleted.\n";
        return;
    }

    db.removeVariant(ref.dishIndex, ref.variantIndex);     // (also removes the dish if it became empty)

    if(db.save()) cout << "Recipe deleted.\n";
    else cout << "Something went wrong, the recipe was NOT deleted.\n";
}

int main(){
    // Use the same runtime folder as the Stage 2 server.
    RecipeDatabase db("data");
    UserDatabase users;

    while(true){
        int userId = loginGate(users);          // nobody gets in without an account
        if(userId == 0) break;

        string username = users.nameOf(userId);
        bool loggedIn = true;

        while(loggedIn){
            cout << "\n===== Logged in as: " << username << " =====\n";
            cout << " 1. Upload a new recipe (describe it or fill a form)\n";
            cout << " 2. Edit my recipe\n";
            cout << " 3. Delete my recipe\n";
            cout << " 4. Change password\n";
            cout << " 5. Delete my account\n";
            cout << " 6. Log out\n";
            cout << " 0. Exit\n";
            int choice = askChoice("Choice: ", 0, 6);

            if(choice == 0){
                cout << "Bye!\n";
                return 0;
            }
            else if(choice == 1){
                cout << "\nHow do you want to add the recipe?\n";
                cout << " 1. Describe it in your own words (AI yap mode)\n";
                cout << " 2. Fill it in step by step\n";
                cout << " 0. Cancel\n";
                int how = askChoice("Choice: ", 0, 2);

                if(how == 1) uploadRecipeFromText(db, userId, username);
                else if(how == 2) uploadRecipe(db, userId, username);
            }
            else if(choice == 2) editRecipe(db, userId, username);
            else if(choice == 3) deleteRecipe(db, userId, username);
            else if(choice == 4) changePassword(users, userId);
            else if(choice == 5){
                if(deleteAccount(db, users, userId)) loggedIn = false;
            }
            else if(choice == 6){
                logOut(users, userId);
                loggedIn = false;
            }
        }
    }

    cout << "Bye!\n";
    return 0;
}
