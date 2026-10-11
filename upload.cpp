#include <iostream>
#include <cstdlib>
#include "RecipeCore.h"
using namespace std;

// Reads one line from the keyboard. If input is closed (Ctrl+D / end of input),
// we stop safely and save nothing.
string readLine(){
    string line;
    if(!getline(cin, line)){
        cout << "\nInput ended. Nothing was saved.\n";
        exit(0);
    }
    return line;
}

// Keeps asking until the user types something (empty answer is not accepted)
string askRequired(string question){
    while(true){
        cout << question;
        string answer = tidyName(readLine());
        if(!answer.empty()) return answer;
        cout << "This cannot be empty. Please try again.\n";
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
            if(items.empty()){
                cout << "Please add at least one " << itemName << " before typing 'done'.\n";
                continue;
            }
            break;
        }
        if(line.empty()) continue;      // ignore accidental empty Enter
        items.push_back(line);
    }
    return items;
}

// Asks until the user types a valid number of minutes
int askCookingTime(){
    while(true){
        cout << "Cooking time in minutes (number only, e.g. 45): ";
        string text = trimSpaces(readLine());

        try{
            size_t used = 0;
            int minutes = stoi(text, &used);
            if(used == text.size() && minutes > 0 && minutes <= 10000) return minutes;
        }
        catch(...){
            // not a number -> falls through to the message below
        }
        cout << "Please enter a valid number of minutes (1 to 10000).\n";
    }
}

int main(){
    RecipeDatabase db;
    if(!db.load()){
        cout << "Stopped, so your saved recipes are not overwritten.\n";
        return 1;
    }

    // ---------- STEP 1: DISH name ----------
    string dishName = askRequired("Enter DISH name (e.g. Biryani, Pulao, Fries): ");

    int dishIndex = db.findDishIndex(dishName);

    if(dishIndex == -1){
        // brand new dish
        Dish newDish;
        newDish.setName(dishName);
        newDish.setId(db.nextDishId());      // id comes from the counter saved in the file
        newDish.autoSetDate();
        dishIndex = db.addDish(newDish);
        cout << "New dish created: " << dishName << "\n";
    }
    else{
        // dish already exists -> we only add a new variant under it
        Dish &existing = db.getDishes()[dishIndex];
        cout << "Dish '" << existing.getName() << "' already exists. Its variants:\n";
        for(auto &v : existing.getVariants()){
            cout << " - " << v.getName() << "\n";
        }
        cout << "Your recipe will be added as a new variant.\n";
    }

    Dish &dish = db.getDishes()[dishIndex];

    // ---------- STEP 2: VARIANT name ----------
    string variantName;
    while(true){
        variantName = askRequired("Enter VARIANT name (e.g. Bombay Biryani): ");

        if(dish.hasVariant(variantName)){
            cout << "This variant already exists under " << dish.getName()
                 << ". Please enter a different name.\n";
        }
        else{
            break;
        }
    }

    Variant variant;
    variant.setName(variantName);
    variant.setId(db.nextVariantId());
    variant.autoSetDate();

    // ---------- STEP 3: RECIPE ----------
    Recipe &recipe = variant.getRecipe();

    recipe.setMainIngredient(askRequired("What is the MAIN ingredient? (e.g. rice for biryani): "));

    vector<string> ingredients = askList("Enter ingredients one by one. Type 'done' when finished.", "ingredient", false);
    for(auto &ing : ingredients){
        recipe.addIngredient(ing);
    }

    vector<string> steps = askList("Enter steps one by one. Type 'done' when finished.", "step", true);
    for(auto &s : steps){
        recipe.addStep(s);
    }

    recipe.setCookingTime(askCookingTime());

    // ---------- SAVE ----------
    dish.addVariant(variant);

    if(db.save()){
        cout << "\nRecipe saved successfully!\n";
        variant.show(dish.getName());
    }
    else{
        cout << "\nSomething went wrong, recipe was NOT saved.\n";
        return 1;
    }

    return 0;
}