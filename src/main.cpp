#include <iostream>
#include <filesystem>
#include "cli/Console.h"
#include "cli/UploadMenu.h"
#include "cli/SearchMenu.h"
#include "cli/ReviewMenu.h"
using namespace std;

// ============================================================
//  main.cpp - the single console program
//
//  Loads the databases and logs the user in once, then offers the
//  three recipe menus plus account settings.
// ============================================================

// A fresh checkout has no data/ files yet. Copy the tracked demo data so the
// console and the server start from the same 18 recipes and two accounts.
void copySeedIfMissing(const string& target, const string& seed){
    if(std::filesystem::exists(target)) return;
    if(!std::filesystem::exists(seed)) return;
    std::filesystem::copy_file(seed, target,
                               std::filesystem::copy_options::overwrite_existing);
}

int main(){
    // All runtime state (recipes, accounts, saved login) lives in data/.
    std::filesystem::create_directories("data");
    copySeedIfMissing("data/recipes.json", "seed/recipes.json");
    copySeedIfMissing("data/users.json", "seed/users.json");

    RecipeDatabase db("data");
    UserDatabase users("data");

    bool exitApp = false;

    while(!exitApp){
        int userId = loginGate(users);          // nobody gets in without an account
        if(userId == 0) break;

        string username = users.nameOf(userId);
        bool sessionActive = true;

        while(sessionActive && !exitApp){
            cout << "\n===== TasteHub - logged in as: " << username << " =====\n";
            cout << " 1. Upload / edit / delete recipes\n";
            cout << " 2. Search recipes\n";
            cout << " 3. Rate / react / comment\n";
            cout << " 4. Account settings\n";
            cout << " 0. Exit\n";
            int choice = askChoice("Choice: ", 0, 4);

            if(choice == 0){
                exitApp = true;
            }
            else if(choice == 1){
                runUploadMenu(db, users, userId);
            }
            else if(choice == 2){
                runSearchMenu(db, users, userId);
            }
            else if(choice == 3){
                runReviewMenu(db, users, userId);
            }
            else if(choice == 4){
                cout << "\n===== Account settings =====\n";
                cout << " 1. Change password\n";
                cout << " 2. Delete my account\n";
                cout << " 3. Log out\n";
                cout << " 0. Back\n";
                int accountChoice = askChoice("Choice: ", 0, 3);

                if(accountChoice == 1){
                    changePassword(users, userId);
                }
                else if(accountChoice == 2){
                    if(deleteAccount(db, users, userId)) sessionActive = false;
                }
                else if(accountChoice == 3){
                    logOut(users, userId);
                    sessionActive = false;
                }
            }
        }
    }

    cout << "Bye!\n";
    return 0;
}
