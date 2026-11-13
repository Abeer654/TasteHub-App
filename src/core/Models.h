#ifndef MODELS_H
#define MODELS_H

// ============================================================
//  Models.h - domain model + shared text/date/file/hash helpers
//
//  Part A  small helper functions (text, dates, files)
//  Part B  password security (a "black box": you only call it)
//  Part C  BaseEntity - the parent class (id + date)
//  Part D  Vote, Reactions, Rating, Ratings, Comment
//  Part E  Recipe, Variant, Dish (Variant and Dish inherit BaseEntity)
//  Part F  User (inherits BaseEntity)
//  Part G  access rules for recipes and comments
//
//  Storage.h, Search.h, AiRecipe.h and Console.h build on this file.
// ============================================================

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <vector>
#include "json.hpp"
using namespace std;
using json = nlohmann::json;

// ------------------------------------------------------------
//  Settings (constants)
// ------------------------------------------------------------
const int DELETED_OWNER = -1;                 // ownerId of a recipe whose owner deleted the account
const double GOOD_RECIPE_MIN_AVERAGE = 4.0;   // a recipe has a GOOD RECORD if its average rating is at least this ...
const int GOOD_RECIPE_MIN_RATINGS = 2;        // ... from at least this many people
const int MAX_COMMENT_LENGTH = 500;
// ------------------------------------------------------------
//  PART A: small helper functions
// ------------------------------------------------------------

// Note: a "char" can be NEGATIVE for Urdu letters (they use 2-3 bytes each).
// That is why some helpers below convert the char to "unsigned char" first.

bool isSpaceChar(char c){
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

bool isLetterOrDigit(char c){
    unsigned char u = (unsigned char)c;
    return isalnum(u);
}

// true for the bytes of non-English letters (like Urdu)
bool isNonEnglishByte(char c){
    unsigned char u = (unsigned char)c;
    return u >= 128;
}

// Urdu letters use 2-3 bytes. Every byte except the first one is a "continuation byte".
bool isContinuationByte(char c){
    unsigned char u = (unsigned char)c;
    return u >= 128 && u < 192;
}

char lowerChar(char c){
    unsigned char u = (unsigned char)c;
    return (char)tolower(u);
}

// "Rice", "RICE", "rice" all become "rice"
string toLowerCase(string s){
    for(int i = 0; i < (int)s.size(); i++){
        s[i] = lowerChar(s[i]);
    }
    return s;
}

// removes extra spaces from start and end: "  Biryani " -> "Biryani"
string trimSpaces(string s){
    int start = 0;
    int end = (int)s.size() - 1;
    while(start <= end && isSpaceChar(s[start])) start++;
    while(end >= start && isSpaceChar(s[end])) end--;
    return s.substr(start, end - start + 1);
}

// also fixes spaces inside: "Chicken    Biryani " -> "Chicken Biryani"
string tidyName(string s){
    s = trimSpaces(s);
    string result = "";
    bool lastWasSpace = false;
    for(int i = 0; i < (int)s.size(); i++){
        char c = s[i];
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

// Account names are 3-20 characters: letters, numbers, dot, underscore or
// hyphen, starting with a letter or number. Shared by the console and server.
bool isValidUsername(string name){
    if(name.size() < 3 || name.size() > 20) return false;
    if(!isLetterOrDigit(name[0])) return false;
    for(int i = 0; i < (int)name.size(); i++){
        char c = name[i];
        if(!isLetterOrDigit(c) && c != '_' && c != '.' && c != '-') return false;
    }
    return true;
}

// 5 -> "05"
string twoDigits(int number){
    if(number < 10) return "0" + to_string(number);
    return to_string(number);
}

// Current UTC date and time in a format Flutter/Dart can read:
// 2026-10-10T18:30:05Z
string currentTimeText(){
    time_t now = time(0);
    tm t;

    // Always store timestamps in UTC with a trailing "Z".
    // Flutter/Dart can parse this directly, and it avoids timezone drift
    // when the laptop and the phone are in different time zones.
#ifdef _WIN32
    gmtime_s(&t, &now);
#else
    gmtime_r(&now, &t);
#endif

    char buffer[32];
    strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &t);
    return string(buffer);
}

// 2026-10-10T18:30:05 -> 2026-10-10 18:30:05
string readableDate(string iso){
    if(iso.size() > 10 && iso[10] == 'T') iso[10] = ' ';
    return iso;
}

// 4.5 -> "4.5"   4.0 -> "4.0"   (one digit after the point)
string oneDecimal(double value){
    int tenths = (int)(value * 10 + 0.5);
    return to_string(tenths / 10) + "." + to_string(tenths % 10);
}

// shortens long text to about maxBytes bytes, never cutting a letter in half
string cutText(string s, int maxBytes){
    if((int)s.size() <= maxBytes) return s;
    int cut = maxBytes;
    while(cut > 0 && isContinuationByte(s[cut])) cut--;
    return s.substr(0, cut) + "...";
}

// reads a whole file into one text ("" if the file does not exist)
string readWholeFile(string fileName){
    ifstream inFile(fileName);
    string text = "";
    string line;
    while(getline(inFile, line)){
        text += line + "\n";
    }
    return text;
}

// copies the current file to a backup file (done before every save)
void makeBackupOf(string fileName, string backupName){
    string oldText = readWholeFile(fileName);
    if(oldText.size() == 0) return;
    ofstream out(backupName);
    out << oldText;
}

// turns JSON into text. (The extra words keep it safe even if somebody typed a broken character.)
string jsonToText(json &j){
    return j.dump(4, ' ', false, json::error_handler_t::replace);
}

// Safe readers for hand-edited or partially written JSON. A missing field or a
// wrong type falls back to a default instead of throwing during startup.
string jsonStringValue(const json &j, const string &key, const string &fallback = ""){
    if(!j.is_object() || !j.contains(key) || !j[key].is_string()) return fallback;
    return j[key].get<string>();
}

int jsonIntValue(const json &j, const string &key, int fallback = 0){
    if(!j.is_object() || !j.contains(key) || !j[key].is_number_integer()) return fallback;
    return j[key].get<int>();
}

bool jsonBoolValue(const json &j, const string &key, bool fallback = false){
    if(!j.is_object() || !j.contains(key) || !j[key].is_boolean()) return fallback;
    return j[key].get<bool>();
}

vector<string> jsonStringList(const json &j, const string &key){
    vector<string> result;
    if(!j.is_object() || !j.contains(key) || !j[key].is_array()) return result;

    for(const json &item : j[key]){
        if(item.is_string()) result.push_back(item.get<string>());
    }
    return result;
}

// Splits text into lowercase WORDS. Letters/digits (and Urdu letters) stay together,
// spaces, commas, dots etc. separate words:  "Rice, 2 cups" -> ["rice", "2", "cups"]
vector<string> splitWords(string text){
    vector<string> words;
    string word = "";

    for(int i = 0; i < (int)text.size(); i++){
        char c = text[i];
        if(isLetterOrDigit(c) || isNonEnglishByte(c)){
            word += lowerChar(c);
        }
        else if(word.size() > 0){
            words.push_back(word);
            word = "";
        }
    }
    if(word.size() > 0) words.push_back(word);

    return words;
}

// same word, also treating simple plurals as same: egg/eggs, potato/potatoes
bool sameWord(string a, string b){
    return a == b
        || a + "s" == b || a + "es" == b
        || b + "s" == a || b + "es" == a;
}

// true if text has this WHOLE word (so "oil" does NOT match "boil")
bool textHasWord(string text, string word){
    word = toLowerCase(word);
    vector<string> words = splitWords(text);
    for(int i = 0; i < (int)words.size(); i++){
        if(sameWord(words[i], word)) return true;
    }
    return false;
}

// true if a word in text STARTS with the typed word ("biry" finds "biryani",
// but "oil" still does NOT match "boil")
bool textHasWordStart(string text, string word){
    word = toLowerCase(word);
    if(word.size() == 0) return false;

    vector<string> words = splitWords(text);
    for(int i = 0; i < (int)words.size(); i++){
        if(words[i].substr(0, word.size()) == word) return true;
        if(sameWord(words[i], word)) return true;
    }
    return false;
}
// ------------------------------------------------------------
//  PART B: PASSWORD SECURITY   (a "black box" - you do NOT need to
//  understand what is inside, just what it does)
//
//   - A password is NEVER saved as readable text. We save a scrambled
//     version of it, called a "hash". Nobody can turn a hash back into
//     the password.
//   - "salt" = a random text mixed into the password before scrambling,
//     so two people with the same password still get different hashes.
//   - sha256Hex() is a standard, ready-made scrambling recipe (SHA-256).
//     The bit tricks inside (<< >> & ^) belong to that recipe.
//
//  The only functions the rest of the program uses:
//     hashPassword(salt, password)   randomHex(bytes)
//     generateRecoveryCode()         normalizeRecoveryCode(code)
//  (A real startup would use a ready-made login service instead.)
// ------------------------------------------------------------

unsigned int rotateRight(unsigned int x, int n){
    return (x >> n) | (x << (32 - n));
}

// SHA-256: turns any text into a 64-character scrambled code
string sha256Hex(string input){
    const unsigned int k[64] = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    };

    unsigned int h[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
                         0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};

    // padding: add 0x80, then zeros, then the original length in bits
    string msg = input;
    unsigned long long bitLength = (unsigned long long)input.size() * 8;
    msg += (char)0x80;
    while(msg.size() % 64 != 56) msg += (char)0;
    for(int i = 7; i >= 0; i--){
        msg += (char)((bitLength >> (i * 8)) & 0xff);
    }

    for(int chunk = 0; chunk < (int)msg.size(); chunk += 64){
        unsigned int w[64];
        for(int i = 0; i < 16; i++){
            int p = chunk + i * 4;
            w[i] = ((unsigned int)(unsigned char)msg[p] << 24)
                 | ((unsigned int)(unsigned char)msg[p + 1] << 16)
                 | ((unsigned int)(unsigned char)msg[p + 2] << 8)
                 |  (unsigned int)(unsigned char)msg[p + 3];
        }
        for(int i = 16; i < 64; i++){
            unsigned int s0 = rotateRight(w[i-15], 7) ^ rotateRight(w[i-15], 18) ^ (w[i-15] >> 3);
            unsigned int s1 = rotateRight(w[i-2], 17) ^ rotateRight(w[i-2], 19) ^ (w[i-2] >> 10);
            w[i] = w[i-16] + s0 + w[i-7] + s1;
        }

        unsigned int a = h[0], b = h[1], c = h[2], d = h[3];
        unsigned int e = h[4], f = h[5], g = h[6], hh = h[7];

        for(int i = 0; i < 64; i++){
            unsigned int S1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
            unsigned int ch = (e & f) ^ (~e & g);
            unsigned int t1 = hh + S1 + ch + k[i] + w[i];
            unsigned int S0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
            unsigned int maj = (a & b) ^ (a & c) ^ (b & c);
            unsigned int t2 = S0 + maj;

            hh = g; g = f; f = e; e = d + t1;
            d = c; c = b; b = a; a = t1 + t2;
        }

        h[0] += a; h[1] += b; h[2] += c; h[3] += d;
        h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }

    string hexDigits = "0123456789abcdef";
    string result = "";
    for(int i = 0; i < 8; i++){
        for(int shift = 28; shift >= 0; shift -= 4){
            result += hexDigits[(h[i] >> shift) & 0xf];
        }
    }
    return result;
}

// password + salt -> hash, scrambled 10000 times (makes guessing passwords slow)
string hashPassword(string salt, string password){
    string h = sha256Hex(salt + password);
    for(int i = 0; i < 10000; i++){
        h = sha256Hex(h + salt + password);
    }
    return h;
}

random_device randomSource;       // the computer's own source of random numbers

// a random whole number from 0 to range-1
// (we only use 256 and 32, so every number is equally likely)
int randomNumber(int range){
    unsigned int value = randomSource() + (unsigned int)time(0);
    return (int)(value % (unsigned int)range);
}

// random text made of hex characters, e.g. a salt
string randomHex(int bytes){
    string hexDigits = "0123456789abcdef";
    string result = "";
    for(int i = 0; i < bytes; i++){
        int value = randomNumber(256);
        result += hexDigits[value / 16];
        result += hexDigits[value % 16];
    }
    return result;
}

// recovery code like K7QM-4XNP-9TWD (no confusing letters like O/0 or I/1)
string generateRecoveryCode(){
    string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    string code = "";
    for(int i = 0; i < 12; i++){
        if(i > 0 && i % 4 == 0) code += '-';
        code += alphabet[randomNumber(32)];
    }
    return code;
}

// "k7qm 4xnp-9twd" -> "K7QM4XNP9TWD" (so small/capital letters, spaces and dashes don't matter)
string normalizeRecoveryCode(string code){
    string result = "";
    for(int i = 0; i < (int)code.size(); i++){
        if(isLetterOrDigit(code[i])){
            unsigned char u = (unsigned char)code[i];
            result += (char)toupper(u);
        }
    }
    return result;
}
// ------------------------------------------------------------
//  PART C: BaseEntity - the PARENT class. Dish, Variant, Comment and User
//  all INHERIT from it, so each of them automatically has an id and a date.
// ------------------------------------------------------------
class BaseEntity {
protected:
    int id = 0;
    string createdAt;

public:
    // Stage 1 uses this base class to prove runtime polymorphism:
    // RecipeDatabase::save() calls toJson() through a BaseEntity&.
    virtual ~BaseEntity() = default;
    virtual json toJson() = 0;

    void setId(int newId){
        id = newId;
    }

    int getId(){
        return id;
    }

    // Date/time is generated automatically by the system
    void autoSetDate(){
        createdAt = currentTimeText();
    }

    void setCreatedAt(string date){
        createdAt = date;
    }

    string getCreatedAt(){
        return createdAt;
    }
};
// ------------------------------------------------------------
//  PART D: likes / dislikes, ratings and comments
// ------------------------------------------------------------

// one like (+1) or dislike (-1) of one user
class Vote {
public:
    int userId;
    int value;
};

// Reactions: all likes and dislikes of ONE thing (a recipe or a comment).
// One user has only ONE vote on one thing.
class Reactions {
protected:
    vector<Vote> votes;

public:
    // +1 (liked), -1 (disliked) or 0 (no vote yet)
    int getVote(int userId){
        for(Vote &v : votes){
            if(v.userId == userId) return v.value;
        }
        return 0;
    }

    // returns false if the user ALREADY has exactly this vote (nothing changes).
    // Liking after disliking (or the other way round) CHANGES the vote.
    bool setVote(int userId, int value){
        for(Vote &v : votes){
            if(v.userId == userId){
                if(v.value == value) return false;
                v.value = value;
                return true;
            }
        }
        Vote newVote;
        newVote.userId = userId;
        newVote.value = value;
        votes.push_back(newVote);
        return true;
    }

    int likes(){
        int count = 0;
        for(Vote &v : votes){
            if(v.value > 0) count++;
        }
        return count;
    }

    int dislikes(){
        int count = 0;
        for(Vote &v : votes){
            if(v.value < 0) count++;
        }
        return count;
    }

    void removeUser(int userId){
        for(int i = (int)votes.size() - 1; i >= 0; i--){
            if(votes[i].userId == userId) votes.erase(votes.begin() + i);
        }
    }

    json toJson(){
        json list = json::array();
        for(Vote &v : votes){
            json j;
            j["userId"] = v.userId;
            j["value"] = v.value;
            list.push_back(j);
        }
        return list;
    }

    void fromJson(json &list){
        votes.clear();
        if(!list.is_array()) return;

        for(json &j : list){
            if(!j.is_object()) continue;
            Vote v;
            v.userId = jsonIntValue(j, "userId", 0);
            v.value = jsonIntValue(j, "value", 0);
            votes.push_back(v);
        }
    }
};

// One 1-5 star rating from one user.
// proofImageRef is an optional photo that proves the user cooked the recipe.
class Rating {
public:
    int userId = 0;
    int stars = 0;
    string proofImageRef;
};

// Ratings: all star ratings of ONE recipe (one rating per user)
class Ratings {
protected:
    vector<Rating> list;

public:
    // 1-5, or 0 if this user has not rated yet
    int getRating(int userId){
        for(Rating &r : list){
            if(r.userId == userId) return r.stars;
        }
        return 0;
    }

    // The proof photo this user attached to their rating.
    // Returns "" when the user has not rated or did not attach a photo.
    string getProofImageRef(int userId){
        for(Rating &r : list){
            if(r.userId == userId) return r.proofImageRef;
        }
        return "";
    }

    // Updates the stars only. If the user already attached a proof photo,
    // it stays unchanged. Used by the old console rating program.
    // Returns false if the user already gave exactly this rating.
    bool setRating(int userId, int stars){
        for(Rating &r : list){
            if(r.userId == userId){
                if(r.stars == stars) return false;
                r.stars = stars;
                return true;
            }
        }
        Rating newRating;
        newRating.userId = userId;
        newRating.stars = stars;
        list.push_back(newRating);
        return true;
    }

    // Updates the stars and the proof photo together.
    // An empty proofImageRef clears the photo.
    bool setRatingWithProof(int userId, int stars, string proofImageRef){
        for(Rating &r : list){
            if(r.userId == userId){
                if(r.stars == stars && r.proofImageRef == proofImageRef) return false;
                r.stars = stars;
                r.proofImageRef = proofImageRef;
                return true;
            }
        }

        Rating newRating;
        newRating.userId = userId;
        newRating.stars = stars;
        newRating.proofImageRef = proofImageRef;
        list.push_back(newRating);
        return true;
    }

    int count(){
        return (int)list.size();
    }

    // Read-only access for the API, which adds usernames to each rating.
    vector<Rating>& getList(){
        return list;
    }

    double average(){
        if(list.size() == 0) return 0;
        int total = 0;
        for(Rating &r : list){
            total += r.stars;
        }
        return (double)total / (double)list.size();
    }

    void removeUser(int userId){
        for(int i = (int)list.size() - 1; i >= 0; i--){
            if(list[i].userId == userId) list.erase(list.begin() + i);
        }
    }

    json toJson(){
        json array = json::array();
        for(Rating &r : list){
            json j;
            j["userId"] = r.userId;
            j["stars"] = r.stars;
            j["proofImageRef"] = r.proofImageRef;
            array.push_back(j);
        }
        return array;
    }

    void fromJson(json &array){
        list.clear();
        if(!array.is_array()) return;

        for(json &j : array){
            if(!j.is_object()) continue;
            Rating r;
            r.userId = jsonIntValue(j, "userId", 0);
            r.stars = jsonIntValue(j, "stars", 0);
            r.proofImageRef = jsonStringValue(j, "proofImageRef", "");
            list.push_back(r);
        }
    }
};

// Comment: written by a user on a recipe (inherits id + date from BaseEntity).
// The owner of the recipe can HIDE it (it is not deleted).
class Comment : public BaseEntity {
protected:
    int userId = 0;
    string text;
    bool hidden = false;
    Reactions reactions;

public:
    void setUserId(int u){
        userId = u;
    }

    int getUserId(){
        return userId;
    }

    void setText(string t){
        text = t;
    }

    string getText(){
        return text;
    }

    void setHidden(bool h){
        hidden = h;
    }

    bool isHidden(){
        return hidden;
    }

    Reactions& getReactions(){
        return reactions;
    }

    json toJson() override {
        json j;
        j["id"] = id;
        j["userId"] = userId;
        j["text"] = text;
        j["createdAt"] = createdAt;
        j["hidden"] = hidden;
        j["votes"] = reactions.toJson();
        return j;
    }

    void fromJson(json &j){
        if(!j.is_object()) return;

        id = jsonIntValue(j, "id", 0);
        userId = jsonIntValue(j, "userId", 0);
        text = jsonStringValue(j, "text", "");
        createdAt = jsonStringValue(j, "createdAt", "");
        hidden = jsonBoolValue(j, "hidden", false);
        if(j.contains("votes") && j["votes"].is_array()) reactions.fromJson(j["votes"]);
    }
};
// ------------------------------------------------------------
//  PART E: Recipe, Variant, Dish
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

    void setIngredients(vector<string> list){
        ingredients = list;
    }

    void setSteps(vector<string> list){
        steps = list;
    }

    void setCookingTime(int t){
        cookingTime = t;
    }

    string getMainIngredient(){
        return mainIngredient;
    }

    // Returning references keeps the Stage 1 search and JSON code from copying
    // every ingredient/step list on every request.
    vector<string>& getIngredients(){
        return ingredients;
    }

    vector<string>& getSteps(){
        return steps;
    }

    int getCookingTime(){
        return cookingTime;
    }

    // true if a word starting with the typed word is in main ingredient, ingredients or steps
    bool hasWord(string word){
        if(textHasWordStart(mainIngredient, word)) return true;

        for(int i = 0; i < (int)ingredients.size(); i++){
            if(textHasWordStart(ingredients[i], word)) return true;
        }
        for(int i = 0; i < (int)steps.size(); i++){
            if(textHasWordStart(steps[i], word)) return true;
        }
        return false;
    }

    void showDetails(){
        cout << "MAIN INGREDIENT: " << mainIngredient << "\n";
        cout << "INGREDIENTS:\n";
        for(int i = 0; i < (int)ingredients.size(); i++){
            cout << " - " << ingredients[i] << "\n";
        }
        cout << "STEPS:\n";
        for(int i = 0; i < (int)steps.size(); i++){
            cout << " " << i + 1 << ". " << steps[i] << "\n";
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
        if(!j.is_object()) return;

        mainIngredient = jsonStringValue(j, "mainIngredient", "");
        ingredients = jsonStringList(j, "ingredients");
        steps = jsonStringList(j, "steps");
        cookingTime = jsonIntValue(j, "cookingTime", 0);
    }
};

// Variant: e.g. "Bombay Biryani" (inherits id + date from BaseEntity)
// ownerId = id of the user who uploaded it (0 = unknown / old recipe, -1 = account deleted)
class Variant : public BaseEntity {
protected:
    string name;
    Recipe recipe;
    int ownerId = 0;
    string updatedAt;            // empty until the recipe is edited
    Ratings ratings;
    Reactions reactions;         // likes / dislikes of the recipe
    vector<Comment> comments;
    string imageRef;             // asset path, web URL, or local phone path
    string youtubeUrl;           // YouTube link for the recipe

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

    void setOwnerId(int owner){
        ownerId = owner;
    }

    int getOwnerId(){
        return ownerId;
    }

    string getUpdatedAt(){
        return updatedAt;
    }

    void setImageRef(string value){
        imageRef = value;
    }

    string getImageRef(){
        return imageRef;
    }

    void setYoutubeUrl(string value){
        youtubeUrl = value;
    }

    string getYoutubeUrl(){
        return youtubeUrl;
    }

    Ratings& getRatings(){
        return ratings;
    }

    Reactions& getReactions(){
        return reactions;
    }

    vector<Comment>& getComments(){
        return comments;
    }

    // remembers the time of the last edit (automatic)
    void markEdited(){
        updatedAt = currentTimeText();
    }

    int visibleCommentCount(){
        int count = 0;
        for(Comment &c : comments){
            if(!c.isHidden()) count++;
        }
        return count;
    }

    // "Rating: 4.5/5 (2 ratings)   Likes: 5   Dislikes: 1   Comments: 3"
    string summaryLine(){
        string text;
        if(ratings.count() == 0){
            text = "Rating: not rated yet";
        }
        else{
            string ratingWord = " ratings)";
            if(ratings.count() == 1) ratingWord = " rating)";
            text = "Rating: " + oneDecimal(ratings.average()) + "/5 (" + to_string(ratings.count()) + ratingWord;
        }
        text += "   Likes: " + to_string(reactions.likes());
        text += "   Dislikes: " + to_string(reactions.dislikes());
        text += "   Comments: " + to_string(visibleCommentCount());
        return text;
    }

    void show(string dishName, string uploaderName){
        cout << "\n----------------------------\n";
        cout << "DISH: " << dishName << "\n";
        cout << "VARIANT: " << name << "\n";
        cout << "Uploaded by: " << uploaderName << "\n";
        recipe.showDetails();
        cout << "Posted on: " << readableDate(createdAt) << "\n";
        if(updatedAt.size() > 0){
            cout << "Edited on: " << readableDate(updatedAt) << "\n";
        }
        cout << summaryLine() << "\n";
        cout << "----------------------------\n";
    }

    json toJson() override {
        json j;
        j["id"] = id;
        j["name"] = name;
        j["ownerId"] = ownerId;
        j["createdAt"] = createdAt;
        j["updatedAt"] = updatedAt;
        j["recipe"] = recipe.toJson();
        j["ratings"] = ratings.toJson();
        j["votes"] = reactions.toJson();
        j["comments"] = json::array();
        for(Comment &c : comments){
            j["comments"].push_back(c.toJson());
        }
        j["imageRef"] = imageRef;
        j["youtubeUrl"] = youtubeUrl;
        return j;
    }

    void fromJson(json &j){
        if(!j.is_object()) return;

        id = jsonIntValue(j, "id", 0);
        name = jsonStringValue(j, "name", "");
        createdAt = jsonStringValue(j, "createdAt", "");
        ownerId = jsonIntValue(j, "ownerId", 0);        // old recipes have no owner -> 0
        updatedAt = jsonStringValue(j, "updatedAt", "");
        imageRef = jsonStringValue(j, "imageRef", "");
        youtubeUrl = jsonStringValue(j, "youtubeUrl", "");
        if(j.contains("recipe") && j["recipe"].is_object()) recipe.fromJson(j["recipe"]);

        // Old recipes may not have every array. Guard each one so a partial
        // or hand-edited JSON file cannot crash the backend at startup.
        if(j.contains("ratings") && j["ratings"].is_array()) ratings.fromJson(j["ratings"]);
        if(j.contains("votes") && j["votes"].is_array()) reactions.fromJson(j["votes"]);
        comments.clear();
        if(j.contains("comments") && j["comments"].is_array()){
            for(json &cj : j["comments"]){
                if(!cj.is_object()) continue;
                Comment c;
                c.fromJson(cj);
                comments.push_back(c);
            }
        }
    }
};
// position of a comment (by its id) inside a recipe, or -1
int findCommentIndexById(Variant &variant, int commentId){
    for(int i = 0; i < (int)variant.getComments().size(); i++){
        if(variant.getComments()[i].getId() == commentId) return i;
    }
    return -1;
}

// A recipe has a GOOD RECORD if people rated it well. When its owner deletes the
// account, such a recipe stays on the app (as "Deleted user"). The AI check
// planned for part 4 can later improve or replace this one rule.
bool isGoodRecipe(Variant &variant){
    return variant.getRatings().count() >= GOOD_RECIPE_MIN_RATINGS
        && variant.getRatings().average() >= GOOD_RECIPE_MIN_AVERAGE;
}
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
        for(Variant &v : variants){
            if(toLowerCase(v.getName()) == toLowerCase(variantName)) return true;
        }
        return false;
    }

    json toJson() override {
        json j;
        j["id"] = id;
        j["name"] = name;
        j["createdAt"] = createdAt;
        j["variants"] = json::array();
        for(Variant &v : variants){
            j["variants"].push_back(v.toJson());
        }
        return j;
    }

    void fromJson(json &j){
        if(!j.is_object()) return;

        id = jsonIntValue(j, "id", 0);
        name = jsonStringValue(j, "name", "");
        createdAt = jsonStringValue(j, "createdAt", "");
        variants.clear();
        if(j.contains("variants") && j["variants"].is_array()){
            for(json &vj : j["variants"]){
                if(!vj.is_object()) continue;
                Variant v;
                v.fromJson(vj);
                variants.push_back(v);
            }
        }
    }
};
// ------------------------------------------------------------
//  PART F: User (an account). Password and recovery code are saved
//  only as salt + hash, never as readable text.
// ------------------------------------------------------------
class User : public BaseEntity {
protected:
    string username;
    string salt;
    string passwordHash;
    string recoverySalt;
    string recoveryHash;
    string sessionHash;          // scrambled copy of the "stay logged in" token (empty = not logged in anywhere)

public:
    void setUsername(string u){
        username = u;
    }

    string getUsername(){
        return username;
    }

    void setPassword(string plainPassword){
        salt = randomHex(16);
        passwordHash = hashPassword(salt, plainPassword);
    }

    bool checkPassword(string plainPassword){
        if(passwordHash.size() == 0) return false;
        return hashPassword(salt, plainPassword) == passwordHash;
    }

    // Makes a NEW recovery code (the old one stops working).
    // Returns the readable code to show the user ONCE - only its hash is saved.
    string makeNewRecoveryCode(){
        string code = generateRecoveryCode();
        recoverySalt = randomHex(16);
        recoveryHash = hashPassword(recoverySalt, normalizeRecoveryCode(code));
        return code;
    }

    bool checkRecoveryCode(string code){
        if(recoveryHash.size() == 0) return false;
        return hashPassword(recoverySalt, normalizeRecoveryCode(code)) == recoveryHash;
    }

    // "Stay logged in": only a scrambled copy of the secret token is saved here
    void startSession(string token){
        sessionHash = sha256Hex(token);
    }

    bool checkSession(string token){
        if(sessionHash.size() == 0) return false;
        return sha256Hex(token) == sessionHash;
    }

    void endSession(){
        sessionHash = "";
    }

    json toJson() override {
        json j;
        j["id"] = id;
        j["username"] = username;
        j["createdAt"] = createdAt;
        j["salt"] = salt;
        j["passwordHash"] = passwordHash;
        j["recoverySalt"] = recoverySalt;
        j["recoveryHash"] = recoveryHash;
        j["sessionHash"] = sessionHash;
        return j;
    }

    void fromJson(json &j){
        if(!j.is_object()) return;

        id = jsonIntValue(j, "id", 0);
        username = jsonStringValue(j, "username", "");
        createdAt = jsonStringValue(j, "createdAt", "");
        salt = jsonStringValue(j, "salt", "");
        passwordHash = jsonStringValue(j, "passwordHash", "");
        recoverySalt = jsonStringValue(j, "recoverySalt", "");
        recoveryHash = jsonStringValue(j, "recoveryHash", "");
        sessionHash = jsonStringValue(j, "sessionHash", "");
    }
};
// ------------------------------------------------------------
//  PART G: access rules for recipes and comments
// ------------------------------------------------------------

bool isOwnerOf(Variant &variant, int userId){
    return userId > 0 && variant.getOwnerId() == userId;
}

// A hidden comment can only be seen by the recipe owner and by the person who wrote it
bool canSeeComment(Variant &variant, Comment &comment, int viewerId){
    if(!comment.isHidden()) return true;
    return isOwnerOf(variant, viewerId) || comment.getUserId() == viewerId;
}
// positions of the comments this viewer is allowed to see
vector<int> visibleCommentIndexes(Variant &variant, int viewerId){
    vector<int> result;
    for(int i = 0; i < (int)variant.getComments().size(); i++){
        if(canSeeComment(variant, variant.getComments()[i], viewerId)) result.push_back(i);
    }
    return result;
}

#endif
