#ifndef RECIPECORE_H
#define RECIPECORE_H

// ============================================================
//  RecipeCore.h  -  the ONE shared file used by BOTH
//  uploading_part.cpp and search_part.cpp  (this is what links them).
//  Contains: helper functions, BaseEntity, Recipe, Variant, Dish,
//            RecipeDatabase (reads/writes recipes.json)
// ============================================================

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <algorithm>
#include <ctime>
#include "json.hpp"
using namespace std;
using json = nlohmann::json;

// ------------------------------------------------------------
//  PART A: small helper functions
// ------------------------------------------------------------

// "Rice", "RICE", "rice" all become "rice"
inline string toLowerCase(string s){
    transform(s.begin(), s.end(), s.begin(),
              [](unsigned char c){ return tolower(c); });
    return s;
}

// removes extra spaces from start and end: "  Biryani " -> "Biryani"
inline string trimSpaces(string s){
    size_t start = s.find_first_not_of(" \t\r\n");
    if(start == string::npos) return "";
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

// also fixes spaces inside: "Chicken    Biryani " -> "Chicken Biryani"
inline string tidyName(string s){
    s = trimSpaces(s);
    string result;
    bool lastWasSpace = false;
    for(char c : s){
        if(c == ' ' || c == '\t'){
            if(!lastWasSpace) result += ' ';
            lastWasSpace = true;
        }
        else{
            result += c;
            lastWasSpace = false;
        }
    }
    return result;
}

// Splits text into lowercase WORDS. Letters/digits (and Urdu letters) stay together,
// spaces, commas, dots etc. separate words:  "Rice, 2 cups" -> ["rice", "2", "cups"]
inline vector<string> splitWords(string text){
    vector<string> words;
    string word;

    for(char ch : text){
        unsigned char c = (unsigned char)ch;
        bool isWordChar = (c >= 128) || isalnum(c);   // c >= 128 means non-English letters (Urdu etc.)

        if(isWordChar){
            word += (char)tolower(c);
        }
        else if(!word.empty()){
            words.push_back(word);
            word.clear();
        }
    }
    if(!word.empty()) words.push_back(word);

    return words;
}

// same word, also treating simple plurals as same: egg/eggs, potato/potatoes
inline bool sameWord(string a, string b){
    return a == b
        || a + "s" == b || a + "es" == b
        || b + "s" == a || b + "es" == a;
}

// true if text has this WHOLE word (so "oil" does NOT match "boil")
inline bool textHasWord(string text, string word){
    word = toLowerCase(word);
    for(auto &w : splitWords(text)){
        if(sameWord(w, word)) return true;
    }
    return false;
}

// true if a word in text STARTS with the typed word ("biry" finds "biryani",
// but "oil" still does NOT match "boil")
inline bool textHasWordStart(string text, string word){
    word = toLowerCase(word);
    if(word.empty()) return false;

    for(auto &w : splitWords(text)){
        if(w.compare(0, word.size(), word) == 0) return true;
        if(sameWord(w, word)) return true;
    }
    return false;
}

// ------------------------------------------------------------
//  PART B: BaseEntity (id + date shared by Dish and Variant)
// ------------------------------------------------------------
class BaseEntity {
protected:
    int id = 0;
    string createdAt;

public:
    void setId(int newId){
        id = newId;
    }

    int getId(){
        return id;
    }

    // Date/time is generated automatically, in a format Flutter/Dart can read:
    // 2026-10-10T18:30:05
    void autoSetDate(){
        time_t now = time(0);
        tm *localTime = localtime(&now);
        char buffer[32];
        strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%S", localTime);
        createdAt = buffer;
    }

    void setCreatedAt(string date){
        createdAt = date;
    }

    string getCreatedAt(){
        return createdAt;
    }
};

// ------------------------------------------------------------
//  PART C: Recipe, Variant, Dish
// ------------------------------------------------------------

// Recipe: main ingredient + ingredients + steps + time
class Recipe {
protected:
    string mainIngredient;
    vector<string> ingredients;
    vector<string> steps;
    int cookingTime = 0;

public:
    void setMainIngredient(string m){
        mainIngredient = m;
    }

    void addIngredient(string ing){
        ingredients.push_back(ing);
    }

    void addStep(string s){
        steps.push_back(s);
    }

    void setCookingTime(int t){
        cookingTime = t;
    }

    string getMainIngredient(){
        return mainIngredient;
    }

    // true if a word starting with the typed word is in main ingredient, ingredients or steps
    bool hasWord(string word){
        if(textHasWordStart(mainIngredient, word)) return true;

        for(auto &ing : ingredients){
            if(textHasWordStart(ing, word)) return true;
        }
        for(auto &s : steps){
            if(textHasWordStart(s, word)) return true;
        }
        return false;
    }

    void showDetails(){
        cout << "MAIN INGREDIENT: " << mainIngredient << "\n";
        cout << "INGREDIENTS:\n";
        for(auto &ing : ingredients){
            cout << " - " << ing << "\n";
        }
        cout << "STEPS:\n";
        int stepNum = 1;
        for(auto &s : steps){
            cout << " " << stepNum << ". " << s << "\n";
            stepNum++;
        }
        cout << "Cooking Time: " << cookingTime << " minutes\n";
    }

    json toJson(){
        json j;
        j["mainIngredient"] = mainIngredient;
        j["ingredients"] = ingredients;
        j["steps"] = steps;
        j["cookingTime"] = cookingTime;
        return j;
    }

    void fromJson(json &j){
        mainIngredient = j.at("mainIngredient").get<string>();
        ingredients = j.at("ingredients").get<vector<string>>();
        steps = j.at("steps").get<vector<string>>();
        cookingTime = j.at("cookingTime").get<int>();
    }
};

// Variant: e.g. "Bombay Biryani" (inherits id + date from BaseEntity)
class Variant : public BaseEntity {
protected:
    string name;
    Recipe recipe;

public:
    void setName(string n){
        name = n;
    }

    string getName(){
        return name;
    }

    Recipe& getRecipe(){
        return recipe;
    }

    void show(string dishName){
        string shownDate = createdAt;
        if(shownDate.size() > 10 && shownDate[10] == 'T') shownDate[10] = ' ';   // "2026-10-10 18:30:05"

        cout << "\n----------------------------\n";
        cout << "DISH: " << dishName << "\n";
        cout << "VARIANT: " << name << "\n";
        recipe.showDetails();
        cout << "Posted on: " << shownDate << "\n";
        cout << "----------------------------\n";
    }

    json toJson(){
        json j;
        j["id"] = id;
        j["name"] = name;
        j["createdAt"] = createdAt;
        j["recipe"] = recipe.toJson();
        return j;
    }

    void fromJson(json &j){
        id = j.at("id").get<int>();
        name = j.at("name").get<string>();
        createdAt = j.at("createdAt").get<string>();
        recipe.fromJson(j.at("recipe"));
    }
};

// Dish: e.g. "Biryani" (inherits id + date, owns many variants)
class Dish : public BaseEntity {
protected:
    string name;
    vector<Variant> variants;

public:
    void setName(string n){
        name = n;
    }

    string getName(){
        return name;
    }

    vector<Variant>& getVariants(){
        return variants;
    }

    void addVariant(Variant v){
        variants.push_back(v);
    }

    bool hasVariant(string variantName){
        for(auto &v : variants){
            if(toLowerCase(v.getName()) == toLowerCase(variantName)) return true;
        }
        return false;
    }

    json toJson(){
        json j;
        j["id"] = id;
        j["name"] = name;
        j["createdAt"] = createdAt;
        j["variants"] = json::array();
        for(auto &v : variants){
            j["variants"].push_back(v.toJson());
        }
        return j;
    }

    void fromJson(json &j){
        id = j.at("id").get<int>();
        name = j.at("name").get<string>();
        createdAt = j.at("createdAt").get<string>();
        variants.clear();
        for(auto &vj : j.at("variants")){
            Variant v;
            v.fromJson(vj);
            variants.push_back(v);
        }
    }
};

// ------------------------------------------------------------
//  PART D: RecipeDatabase - loads/saves everything in recipes.json
//  The "last used id" numbers are stored INSIDE the file, so ids keep
//  increasing (1, 2, 3...) even after the program is closed and reopened.
// ------------------------------------------------------------
class RecipeDatabase {
protected:
    int lastDishId = 0;
    int lastVariantId = 0;
    vector<Dish> dishes;
    string fileName = "recipes.json";
    string backupName = "recipes.backup.json";

    // copies the current file to recipes.backup.json before every save
    void makeBackup(){
        ifstream in(fileName, ios::binary);
        if(!in) return;
        ofstream out(backupName, ios::binary);
        out << in.rdbuf();
    }

public:
    // Returns false only if the file exists but is damaged/unreadable
    bool load(){
        dishes.clear();
        lastDishId = 0;
        lastVariantId = 0;

        ifstream inFile(fileName);
        if(!inFile) return true;                                        // no file yet = empty database
        if(inFile.peek() == ifstream::traits_type::eof()) return true;  // empty file = empty database

        try{
            json j;
            inFile >> j;
            lastDishId = j.value("lastDishId", 0);
            lastVariantId = j.value("lastVariantId", 0);

            for(auto &dj : j.at("dishes")){
                Dish d;
                d.fromJson(dj);
                dishes.push_back(d);
            }
        }
        catch(exception &e){
            cout << "ERROR: could not read " << fileName << " (" << e.what() << ")\n";
            return false;
        }

        // safety: if the counters in the file are behind (e.g. file edited by hand),
        // move them ahead of the biggest id that really exists, so ids never repeat
        for(auto &d : dishes){
            if(d.getId() > lastDishId) lastDishId = d.getId();
            for(auto &v : d.getVariants()){
                if(v.getId() > lastVariantId) lastVariantId = v.getId();
            }
        }

        return true;
    }

    bool save(){
        json j;
        j["lastDishId"] = lastDishId;
        j["lastVariantId"] = lastVariantId;
        j["dishes"] = json::array();
        for(auto &d : dishes){
            j["dishes"].push_back(d.toJson());
        }

        makeBackup();

        ofstream outFile(fileName);
        if(!outFile){
            cout << "ERROR: could not write to " << fileName << "\n";
            return false;
        }
        outFile << j.dump(4, ' ', false, json::error_handler_t::replace);
        outFile.close();
        return !outFile.fail();
    }

    int nextDishId(){
        lastDishId++;
        return lastDishId;
    }

    int nextVariantId(){
        lastVariantId++;
        return lastVariantId;
    }

    // position of the dish in the list, or -1 if not found
    int findDishIndex(string dishName){
        for(size_t i = 0; i < dishes.size(); i++){
            if(toLowerCase(dishes[i].getName()) == toLowerCase(dishName)) return (int)i;
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
};

#endif