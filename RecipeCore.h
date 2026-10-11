#ifndef RECIPE_CORE_H
#define RECIPE_CORE_H

// =====================================================================
//  RecipeCore.h  -  shared code for the whole cooking app
//  Every file (upload, search, rating, ai format, main) includes THIS,
//  so Dish / Variant / Recipe / RecipeDatabase exist only in one place.
//
//  Data layout:   Dish  ->  Variants  ->  Recipe
//  Example:       Biryani -> Bombay Biryani -> (ingredients, steps, time)
//  Saved in:      recipes.json
// =====================================================================

#include <iostream>
#include <string>
#include <vector>
#include <fstream>
#include <algorithm>
#include <cctype>
#include <ctime>
#include "json.hpp"

using namespace std;
using json = nlohmann::json;

const string RECIPES_FILE = "recipes.json";

// ---------------------------------------------------------------------
//  Small helper functions
// ---------------------------------------------------------------------

// "Rice", "RICE", "rice"  ->  "rice"
inline string toLowerCase(string s){
    transform(s.begin(), s.end(), s.begin(),
              [](unsigned char c){ return (char)tolower(c); });
    return s;
}

// removes spaces / tabs / newlines from both ends
inline string trimSpaces(const string &s){
    size_t start = s.find_first_not_of(" \t\r\n");
    if(start == string::npos) return "";
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

// Splits text into lowercase words. Anything that is not a letter/digit
// (space, comma, dash...) is a separator.  "Chicken, Rice" -> ["chicken","rice"]
inline vector<string> splitWords(const string &text){
    vector<string> words;
    string word = "";
    for(char ch : text){
        unsigned char c = (unsigned char)ch;
        if(isalnum(c) || c > 127){
            word += (char)tolower(c);
        } else if(!word.empty()){
            words.push_back(word);
            word = "";
        }
    }
    if(!word.empty()) words.push_back(word);
    return words;
}

// "  bombay    biryani " -> "Bombay Biryani"  (trim + single spaces + capital letters)
inline string tidyName(const string &text){
    string result = "";
    string word = "";
    auto flush = [&](){
        if(word.empty()) return;
        word[0] = (char)toupper((unsigned char)word[0]);
        if(!result.empty()) result += " ";
        result += word;
        word = "";
    };
    for(char c : text){
        if(c == ' ' || c == '\t' || c == '\r' || c == '\n') flush();
        else word += c;
    }
    flush();
    return result;
}

// true if the text contains the word EXACTLY (whole word, case-insensitive)
inline bool textHasWord(const string &text, const string &word){
    string w = toLowerCase(trimSpaces(word));
    for(auto &t : splitWords(text)){
        if(t == w) return true;
    }
    return false;
}

// true if any word in the text STARTS with the typed word
// ("potato" matches "potatoes", "chick" matches "chicken")
inline bool textHasWordStart(const string &text, const string &word){
    string w = toLowerCase(trimSpaces(word));
    if(w.empty()) return false;
    for(auto &t : splitWords(text)){
        if(t.compare(0, w.size(), w) == 0) return true;
    }
    return false;
}

// ---------------------------------------------------------------------
//  BaseEntity : id + date, shared by Dish and Variant
// ---------------------------------------------------------------------
class BaseEntity {
protected:
    int id = 0;
    string createdAt;

public:
    void setId(int newId){ id = newId; }
    int getId() const { return id; }

    void autoSetDate(){
        time_t now = time(0);
        char buffer[64];
        strftime(buffer, sizeof(buffer), "%d-%m-%Y %H:%M", localtime(&now));
        createdAt = buffer;
    }

    void setCreatedAt(const string &d){ createdAt = d; }
    string getCreatedAt() const { return createdAt; }
};

// ---------------------------------------------------------------------
//  Recipe : the actual cooking details
// ---------------------------------------------------------------------
class Recipe {
private:
    string mainIngredient;
    vector<string> ingredients;
    vector<string> steps;
    int cookingTime = 0;

public:
    void setMainIngredient(const string &m){ mainIngredient = m; }
    string getMainIngredient() const { return mainIngredient; }

    void addIngredient(const string &i){ ingredients.push_back(i); }
    void addStep(const string &s){ steps.push_back(s); }
    void setCookingTime(int t){ cookingTime = t; }

    const vector<string>& getIngredients() const { return ingredients; }
    const vector<string>& getSteps() const { return steps; }
    int getCookingTime() const { return cookingTime; }

    // does the main ingredient, any ingredient or any step contain this word?
    bool hasWord(const string &word) const {
        if(textHasWordStart(mainIngredient, word)) return true;
        for(auto &i : ingredients) if(textHasWordStart(i, word)) return true;
        for(auto &s : steps) if(textHasWordStart(s, word)) return true;
        return false;
    }

    json toJson() const {
        json j;
        j["mainIngredient"] = mainIngredient;
        j["ingredients"] = ingredients;
        j["steps"] = steps;
        j["cookingTime"] = cookingTime;
        return j;
    }

    void fromJson(const json &j){
        mainIngredient = j.value("mainIngredient", "");
        ingredients = j.value("ingredients", vector<string>());
        steps = j.value("steps", vector<string>());
        cookingTime = j.value("cookingTime", 0);
    }
};

// ---------------------------------------------------------------------
//  Variant : one version of a dish (e.g. "Bombay Biryani")
// ---------------------------------------------------------------------
class Variant : public BaseEntity {
private:
    string name;
    Recipe recipe;

public:
    void setName(const string &n){ name = n; }
    string getName() const { return name; }
    Recipe& getRecipe(){ return recipe; }
    const Recipe& getRecipe() const { return recipe; }

    void show(const string &dishName) const {
        cout << "\n----------------------------\n";
        cout << "DISH: " << dishName << "\n";
        cout << "VARIANT: " << name << "\n";
        cout << "MAIN INGREDIENT: " << recipe.getMainIngredient() << "\n";
        cout << "INGREDIENTS:\n";
        for(auto &ing : recipe.getIngredients()){
            cout << " - " << ing << "\n";
        }
        cout << "STEPS:\n";
        int stepNum = 1;
        for(auto &s : recipe.getSteps()){
            cout << " " << stepNum << ". " << s << "\n";
            stepNum++;
        }
        cout << "Cooking Time: " << recipe.getCookingTime() << " minutes\n";
        cout << "Posted on: " << getCreatedAt() << "\n";
        cout << "----------------------------\n";
    }

    json toJson() const {
        json j;
        j["id"] = id;
        j["name"] = name;
        j["createdAt"] = createdAt;
        j["recipe"] = recipe.toJson();
        return j;
    }

    void fromJson(const json &j){
        id = j.value("id", 0);
        name = j.value("name", "");
        createdAt = j.value("createdAt", "");
        if(j.contains("recipe")) recipe.fromJson(j["recipe"]);
    }
};

// ---------------------------------------------------------------------
//  Dish : a dish name that holds many variants
// ---------------------------------------------------------------------
class Dish : public BaseEntity {
private:
    string name;
    vector<Variant> variants;

public:
    void setName(const string &n){ name = n; }
    string getName() const { return name; }

    vector<Variant>& getVariants(){ return variants; }
    const vector<Variant>& getVariants() const { return variants; }

    void addVariant(const Variant &v){ variants.push_back(v); }

    // same variant name (ignoring capital/small letters) already under this dish?
    bool hasVariant(const string &variantName) const {
        string target = toLowerCase(trimSpaces(variantName));
        for(auto &v : variants){
            if(toLowerCase(trimSpaces(v.getName())) == target) return true;
        }
        return false;
    }

    json toJson() const {
        json j;
        j["id"] = id;
        j["name"] = name;
        j["createdAt"] = createdAt;
        j["variants"] = json::array();
        for(auto &v : variants) j["variants"].push_back(v.toJson());
        return j;
    }

    void fromJson(const json &j){
        id = j.value("id", 0);
        name = j.value("name", "");
        createdAt = j.value("createdAt", "");
        variants.clear();
        if(j.contains("variants")){
            for(auto &vj : j["variants"]){
                Variant v;
                v.fromJson(vj);
                variants.push_back(v);
            }
        }
    }
};

// ---------------------------------------------------------------------
//  RecipeDatabase : loads / saves everything from recipes.json
// ---------------------------------------------------------------------
class RecipeDatabase {
private:
    vector<Dish> dishes;
    int lastDishId = 0;       // saved in the file, so IDs never repeat
    int lastVariantId = 0;

public:
    vector<Dish>& getDishes(){ return dishes; }

    int nextDishId(){ return ++lastDishId; }
    int nextVariantId(){ return ++lastVariantId; }

    // returns the position of the dish in the list, or -1 if not found
    int findDishIndex(const string &dishName) const {
        string target = toLowerCase(trimSpaces(dishName));
        for(size_t i = 0; i < dishes.size(); i++){
            if(toLowerCase(trimSpaces(dishes[i].getName())) == target) return (int)i;
        }
        return -1;
    }

    int addDish(const Dish &d){
        dishes.push_back(d);
        return (int)dishes.size() - 1;
    }

    // Returns true if loading worked (a missing file = first run = also fine).
    // Returns false if the file exists but is broken, so we never overwrite it.
    bool load(){
        dishes.clear();
        lastDishId = 0;
        lastVariantId = 0;

        ifstream inFile(RECIPES_FILE);
        if(!inFile) return true;                       // no file yet -> empty database

        // completely empty file -> treat as empty database
        if(inFile.peek() == ifstream::traits_type::eof()) return true;

        try{
            json j = json::parse(inFile);

            lastDishId = j.value("lastDishId", 0);
            lastVariantId = j.value("lastVariantId", 0);

            if(j.contains("dishes")){
                for(auto &dj : j["dishes"]){
                    Dish d;
                    d.fromJson(dj);
                    dishes.push_back(d);
                }
            }
        }
        catch(const json::exception &e){
            cout << "ERROR: " << RECIPES_FILE << " could not be read.\n";
            cout << "Reason: " << e.what() << "\n";
            dishes.clear();
            return false;
        }

        // safety: make sure counters are never smaller than an existing id
        for(auto &d : dishes){
            lastDishId = max(lastDishId, d.getId());
            for(auto &v : d.getVariants()){
                lastVariantId = max(lastVariantId, v.getId());
            }
        }
        return true;
    }

    bool save() const {
        json j;
        j["lastDishId"] = lastDishId;
        j["lastVariantId"] = lastVariantId;
        j["dishes"] = json::array();
        for(auto &d : dishes) j["dishes"].push_back(d.toJson());

        ofstream outFile(RECIPES_FILE);
        if(!outFile) return false;
        outFile << j.dump(2) << "\n";
        outFile.close();
        return !outFile.fail();
    }
};

#endif
