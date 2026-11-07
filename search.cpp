#include <iostream>
#include "ConsoleTools.h"
using namespace std;

// ============================================================
//  search.cpp  -  search recipes (log in first).
//  Best rated recipes come first; every recipe shows its rating,
//  likes and the latest comments.  To rate / like / comment use rating.cpp
// ============================================================

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

int main(){
    // Use the same runtime folder as the Stage 2 server, so recipes uploaded
    // in the console are visible through the API and vice versa.
    RecipeDatabase db("data");
    UserDatabase users;

    while(true){
        int userId = loginGate(users);          // goes straight in if you are already logged in
        if(userId == 0) break;

        bool loggedIn = true;
        while(loggedIn){
            string keyword;
            cout << "\nEnter a word to search (type 'exit' to quit, 'logout' to log out): ";
            if(!getline(cin, keyword)) return 0;
            keyword = trimSpaces(keyword);

            if(toLowerCase(keyword) == "exit") return 0;

            if(toLowerCase(keyword) == "logout"){
                logOut(users, userId);
                loggedIn = false;
                continue;
            }

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

    return 0;
}
