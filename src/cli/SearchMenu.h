#ifndef SEARCHMENU_H
#define SEARCHMENU_H

// ============================================================
//  SearchMenu.h - search recipes
//
//  Best matches come first; every recipe shows its rating, likes and
//  the latest comments. Use the review menu to rate, like or comment.
// ============================================================

#include "Console.h"
#include "core/Search.h"

void showResults(RecipeDatabase &db, UserDatabase &users, int userId, string keyword){
    vector<string> words = searchWords(keyword);

    if(words.size() == 0){
        cout << "Please type a dish or ingredient name.\n";
        return;
    }

    SearchResult result = searchRecipes(db, keyword);

    if(result.best.size() == 0 && result.others.size() == 0){
        cout << "No matching recipes found.\n";
        return;
    }

    if(result.best.size() > 0){
        cout << "\nBest matches:\n";
        for(RecipeRef &ref : result.best){
            Dish &dish = db.getDishes()[ref.dishIndex];
            showRecipePage(dish, dish.getVariants()[ref.variantIndex], users, userId, 2);
        }
    }

    if(result.others.size() > 0){
        cout << "\nOther recipes that also contain this:\n";
        for(RecipeRef &ref : result.others){
            Dish &dish = db.getDishes()[ref.dishIndex];
            showRecipePage(dish, dish.getVariants()[ref.variantIndex], users, userId, 2);
        }
    }
}

// ============================================================
//  The search screen
// ============================================================

void runSearchMenu(RecipeDatabase &db, UserDatabase &users, int userId){
    while(true){
        cout << "\nEnter a word to search (type 'back' to return): ";
        string keyword;
        if(!getline(cin, keyword)) return;
        keyword = trimSpaces(keyword);

        if(toLowerCase(keyword) == "back" || toLowerCase(keyword) == "exit") return;

        if(keyword.size() == 0){
            cout << "Please type something to search.\n";
            continue;
        }

        // reload the files every time, so changes made meanwhile also show up
        if(!db.load()) continue;
        users.load();

        showResults(db, users, userId, keyword);
    }
}

#endif
