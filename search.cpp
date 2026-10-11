#include <iostream>
#include "RecipeCore.h"
using namespace std;

// removes filler words like "and", "the", "with" (they are not real ingredients)
vector<string> removeStopWords(vector<string> words){
    vector<string> stopWords = {"and", "the", "a", "an", "with", "or", "of"};
    vector<string> result;

    for(auto &w : words){
        bool isStopWord = false;
        for(auto &sw : stopWords){
            if(w == sw){
                isStopWord = true;
                break;
            }
        }
        if(!isStopWord) result.push_back(w);
    }

    return result;
}

// Every typed word must be found somewhere (dish name, variant name, ingredients, steps)
bool matchesAllWords(Dish &dish, Variant &variant, vector<string> &words){
    for(auto &w : words){
        bool found = textHasWordStart(dish.getName(), w)
                  || textHasWordStart(variant.getName(), w)
                  || variant.getRecipe().hasWord(w);
        if(!found) return false;
    }
    return true;
}

// "Best match" = a typed word is exactly in the dish name, variant name or MAIN ingredient
bool isBestMatch(Dish &dish, Variant &variant, vector<string> &words){
    for(auto &w : words){
        if(textHasWord(dish.getName(), w)
           || textHasWord(variant.getName(), w)
           || textHasWord(variant.getRecipe().getMainIngredient(), w)){
            return true;
        }
    }
    return false;
}

void searchRecipes(RecipeDatabase &db, string keyword){
    vector<string> words = removeStopWords(splitWords(keyword));

    if(words.empty()){
        cout << "Please type a dish or ingredient name.\n";
        return;
    }

    bool found = false;

    // Pass 1: best matches first
    bool headingShown = false;
    for(auto &dish : db.getDishes()){
        for(auto &variant : dish.getVariants()){
            if(matchesAllWords(dish, variant, words) && isBestMatch(dish, variant, words)){
                if(!headingShown){
                    cout << "\nBest matches:\n";
                    headingShown = true;
                }
                variant.show(dish.getName());
                found = true;
            }
        }
    }

    // Pass 2: other recipes that only contain it somewhere
    headingShown = false;
    for(auto &dish : db.getDishes()){
        for(auto &variant : dish.getVariants()){
            if(matchesAllWords(dish, variant, words) && !isBestMatch(dish, variant, words)){
                if(!headingShown){
                    cout << "\nOther recipes that also contain this:\n";
                    headingShown = true;
                }
                variant.show(dish.getName());
                found = true;
            }
        }
    }

    if(!found){
        cout << "No matching recipes found.\n";
    }
}

int main(){
    RecipeDatabase db;

    while(true){
        string keyword;
        cout << "\nEnter a word to search (or type 'exit' to quit): ";
        if(!getline(cin, keyword)) break;
        keyword = trimSpaces(keyword);

        if(toLowerCase(keyword) == "exit") break;

        if(keyword.empty()){
            cout << "Please type something to search.\n";
            continue;
        }

        // reload the file every time, so recipes uploaded meanwhile also show up
        if(!db.load()) continue;

        searchRecipes(db, keyword);
    }

    return 0;
}