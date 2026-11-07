#ifndef RECIPECORE_H
#define RECIPECORE_H

// ============================================================
//  RecipeCore.h  -  shared domain model + JSON storage
//
//  Used by upload.cpp, search.cpp, rating.cpp, backend_test.cpp and (through
//  BackendService.h) the Stage 2 HTTP server.
//
//  What is inside (read it from top to bottom):
//    PART A  small helper functions (text, dates, files)
//    PART B  password security  (a "black box": you only call it)
//    PART C  BaseEntity   <- the parent class (id + date)
//    PART D  Vote, Reactions, Rating, Ratings, Comment
//    PART E  Recipe, Variant, Dish   (Variant and Dish inherit BaseEntity)
//    PART F  User                    (inherits BaseEntity)
//    PART G  RecipeDatabase  (reads / writes recipes.json)
//    PART H  UserDatabase    (reads / writes users.json)
//    PART I  showing a recipe page
//    PART J  searching
// ============================================================

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <ctime>
#include <cstdio>
#include <algorithm>
#include <random>
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
        for(json &j : list){
            Vote v;
            v.userId = j.value("userId", 0);
            v.value = j.value("value", 0);
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
        for(json &j : array){
            Rating r;
            r.userId = j.value("userId", 0);
            r.stars = j.value("stars", 0);
            r.proofImageRef = j.value("proofImageRef", string(""));
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
        id = j.value("id", 0);
        userId = j.value("userId", 0);
        text = j.value("text", string(""));
        createdAt = j.value("createdAt", string(""));
        hidden = j.value("hidden", false);
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
        mainIngredient = j.value("mainIngredient", string(""));
        ingredients = j.value("ingredients", vector<string>());
        steps = j.value("steps", vector<string>());
        cookingTime = j.value("cookingTime", 0);
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
        id = j.value("id", 0);
        name = j.value("name", string(""));
        createdAt = j.value("createdAt", string(""));
        ownerId = j.value("ownerId", 0);               // old recipes have no owner -> 0
        updatedAt = j.value("updatedAt", string(""));
        imageRef = j.value("imageRef", string(""));
        youtubeUrl = j.value("youtubeUrl", string(""));
        if(j.contains("recipe")) recipe.fromJson(j["recipe"]);

        // Old recipes may not have every array. Guard each one so a partial
        // or hand-edited JSON file cannot crash the backend at startup.
        if(j.contains("ratings") && j["ratings"].is_array()) ratings.fromJson(j["ratings"]);
        if(j.contains("votes") && j["votes"].is_array()) reactions.fromJson(j["votes"]);
        comments.clear();
        if(j.contains("comments") && j["comments"].is_array()){
            for(json &cj : j["comments"]){
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
        id = j.value("id", 0);
        name = j.value("name", string(""));
        createdAt = j.value("createdAt", string(""));
        variants.clear();
        if(j.contains("variants") && j["variants"].is_array()){
            for(json &vj : j["variants"]){
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
        id = j.value("id", 0);
        username = j.value("username", string(""));
        createdAt = j.value("createdAt", string(""));
        salt = j.value("salt", string(""));
        passwordHash = j.value("passwordHash", string(""));
        recoverySalt = j.value("recoverySalt", string(""));
        recoveryHash = j.value("recoveryHash", string(""));
        sessionHash = j.value("sessionHash", string(""));
    }
};

// ------------------------------------------------------------
//  PART G: RecipeDatabase - loads/saves everything in recipes.json
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
//  PART H: UserDatabase - loads/saves all accounts in users.json
// ------------------------------------------------------------
class UserDatabase {
protected:
    int lastUserId = 0;
    vector<User> users;
    string fileName = "users.json";
    string backupName = "users.backup.json";

public:
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

// ------------------------------------------------------------
//  PART I: showing a recipe page (rating, likes, comments)
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

// text for a vote - in the Flutter app this decides the colour of the like/dislike buttons
string voteText(int vote){
    if(vote > 0) return "[LIKED]";
    if(vote < 0) return "[DISLIKED]";
    return "no vote";
}

// Shows the recipe, the viewer's own rating/vote, and the comments.
// maxComments = how many of the LATEST comments to show (0 = show all)
void showRecipePage(Dish &dish, Variant &variant, UserDatabase &users, int viewerId, int maxComments){
    variant.show(dish.getName(), users.nameOf(variant.getOwnerId()));

    int myRating = variant.getRatings().getRating(viewerId);
    string myRatingText = "not rated yet";
    if(myRating > 0) myRatingText = to_string(myRating) + "/5";
    cout << "Your rating: " << myRatingText
         << "   Your vote: " << voteText(variant.getReactions().getVote(viewerId)) << "\n";

    vector<int> visible = visibleCommentIndexes(variant, viewerId);
    int hiddenFromViewer = (int)variant.getComments().size() - (int)visible.size();

    cout << "COMMENTS (" << visible.size() << "):\n";

    int first = 0;
    if(maxComments > 0 && (int)visible.size() > maxComments){
        first = (int)visible.size() - maxComments;
        cout << " ... " << first << " older comment(s) not shown\n";
    }

    for(int i = first; i < (int)visible.size(); i++){
        Comment &c = variant.getComments()[visible[i]];

        cout << " " << i + 1 << ". " << users.nameOf(c.getUserId());
        if(isOwnerOf(variant, c.getUserId())) cout << " (Owner)";
        cout << "  " << readableDate(c.getCreatedAt());
        if(c.isHidden()) cout << "  [HIDDEN by the owner]";
        cout << "\n    " << c.getText() << "\n";
        cout << "    Likes: " << c.getReactions().likes()
             << "  Dislikes: " << c.getReactions().dislikes()
             << "  Your vote: " << voteText(c.getReactions().getVote(viewerId)) << "\n";
    }

    if(hiddenFromViewer > 0){
        cout << " (" << hiddenFromViewer << " comment(s) hidden by the owner)\n";
    }
}

// ------------------------------------------------------------
//  PART J: searching
//
//  The matcher is intentionally small but typo-tolerant:
//    - exact words and simple plurals match best
//    - prefixes match next ("chick" -> "chicken")
//    - one or two edit-distance typos are accepted for longer words
//    - every typed word must match somewhere, so multi-word searches stay precise
//    - dish/title/main-ingredient matches count more than ingredient/step matches
//
//  BackendService (HTTP) and the console programs all use this same matcher.
// ------------------------------------------------------------

// Common search filler. Users type "chicken recipe" or "how to make biryani";
// those extra words should not hide the real query words.
vector<string> removeStopWords(vector<string> words){
    static const vector<string> stopWords = {
        "a", "an", "and", "are", "best", "cook", "cooked", "cooking",
        "dish", "dishes", "easy", "find", "food", "for", "give", "homemade",
        "how", "i", "is", "make", "making", "me", "my", "of", "or",
        "please", "recipe", "recipes", "search", "show", "simple", "some",
        "style", "the", "to", "want", "what", "which", "with"
    };

    vector<string> result;
    for(const string &word : words){
        bool isStopWord = false;
        for(const string &stopWord : stopWords){
            if(word == stopWord){
                isStopWord = true;
                break;
            }
        }
        if(!isStopWord) result.push_back(word);
    }
    return result;
}

// The words that really count in what the user typed.
vector<string> searchWords(string keyword){
    return removeStopWords(splitWords(keyword));
}

// Small English plural normalizer for food searches:
// fries -> fry, tomatoes -> tomato, onions -> onion, dishes -> dish.
// It is deliberately simple; the edit-distance matcher handles real typos.
string stemWord(string word){
    word = toLowerCase(word);

    if(word.size() > 4 && word.compare(word.size() - 3, 3, "ies") == 0){
        return word.substr(0, word.size() - 3) + "y";
    }
    if(word.size() > 4 && word.compare(word.size() - 3, 3, "oes") == 0){
        return word.substr(0, word.size() - 2);
    }
    if(word.size() > 4 && word.compare(word.size() - 2, 2, "es") == 0){
        char before = word[word.size() - 3];
        bool needsFullEs = before == 's' || before == 'x' || before == 'z'
                        || word.substr(word.size() - 4, 2) == "ch"
                        || word.substr(word.size() - 4, 2) == "sh";
        if(needsFullEs) return word.substr(0, word.size() - 2);
        return word.substr(0, word.size() - 1);
    }
    if(word.size() > 3 && word.back() == 's' && word[word.size() - 2] != 's'){
        return word.substr(0, word.size() - 1);
    }
    return word;
}

// Damerau-Levenshtein distance (optimal string alignment).
// Unlike plain Levenshtein, swapping two neighbouring letters costs 1, so
// "briyani" is one typo away from "biryani", not two.
int damerauLevenshtein(const string &a, const string &b){
    int n = (int)a.size();
    int m = (int)b.size();
    vector<vector<int>> distance(n + 1, vector<int>(m + 1, 0));

    for(int i = 0; i <= n; i++) distance[i][0] = i;
    for(int j = 0; j <= m; j++) distance[0][j] = j;

    for(int i = 1; i <= n; i++){
        for(int j = 1; j <= m; j++){
            int cost = (a[i - 1] == b[j - 1]) ? 0 : 1;
            distance[i][j] = min({distance[i - 1][j] + 1,
                                  distance[i][j - 1] + 1,
                                  distance[i - 1][j - 1] + cost});

            if(i > 1 && j > 1
               && a[i - 1] == b[j - 2]
               && a[i - 2] == b[j - 1]){
                distance[i][j] = min(distance[i][j], distance[i - 2][j - 2] + 1);
            }
        }
    }
    return distance[n][m];
}

// Scores ONE query word against ONE word from the recipe.
// "strict" is used for cooking steps: steps are long prose, so loose fuzzy
// matches there create noise ("fries" matching every recipe that says "fry").
int wordMatchScore(const string &query, const string &word, bool strict){
    if(query.empty() || word.empty()) return 0;

    if(query == word) return 100;

    // Plural / singular forms: onions vs onion, fries vs fry, tomatoes vs tomato.
    if(stemWord(query) == stemWord(word)){
        if(!strict || (query.size() >= 4 && word.size() >= 4)) return 95;
    }

    // Prefixes need at least two letters. One letter is too broad.
    if(query.size() >= 2 && word.rfind(query, 0) == 0){
        if(!strict || word.size() >= 4) return 85;
    }
    if(query.size() >= 2 && query.rfind(word, 0) == 0 && word.size() >= 3){
        if(!strict || (query.size() >= 4 && word.size() >= 4)) return 75;
    }

    // Fuzzy matching needs words long enough to be meaningful.
    if(query.size() < 3 || word.size() < 3) return 0;

    // A word inside another word is not a typo: "oil" should not match "boil".
    if(word.find(query) != string::npos || query.find(word) != string::npos){
        return 0;
    }

    int distance = damerauLevenshtein(query, word);
    if(distance == 1){
        // Steps are long prose. A one-letter typo is fine there only when both
        // words are meaningful length and start with the same letter, so
        // "fries" cannot drift into the common step word "fry".
        if(strict && (query.size() < 4 || word.size() < 4 || query[0] != word[0])){
            return 0;
        }
        return 60;
    }

    if(distance == 2 && !strict){
        int longest = max((int)query.size(), (int)word.size());
        double similarity = 1.0 - (double)distance / (double)longest;
        bool sameStart = query[0] == word[0];

        // Accept two edits only when the words still clearly look related.
        // This keeps "chikn" -> "chicken" and "frys" -> "fries", but rejects
        // "tomato" -> "potato" and "chiken" -> "thick".
        if(sameStart && (longest <= 5 || similarity >= 0.65)) return 40;
    }

    return 0;
}

// Best score of one query word against any word in a piece of text.
int textMatchScore(const string &query, const string &text, bool strict){
    int best = 0;
    for(const string &word : splitWords(text)){
        best = max(best, wordMatchScore(query, word, strict));
        if(best == 100) break;
    }
    return best;
}

// Small bonus when a multi-word query matches a whole title/dish name.
// This makes "chiken biryani" rank Chicken Biryani above recipes that only
// happen to contain both words in separate places.
int phraseMatchBonus(const string &queryPhrase, const string &text){
    string target = toLowerCase(tidyName(text));
    if(target.empty()) return 0;

    if(target.find(queryPhrase) != string::npos) return 150;

    int longest = max((int)queryPhrase.size(), (int)target.size());
    if(longest == 0) return 0;

    int distance = damerauLevenshtein(queryPhrase, target);
    double similarity = 1.0 - (double)distance / (double)longest;
    if(similarity >= 0.75) return 100;
    return 0;
}

// One ranked result. "primary" means the match was in the recipe title, dish
// name or main ingredient (the console prints those as "Best matches").
class RecipeSearchHit {
public:
    RecipeRef ref;
    int score = 0;
    bool primary = false;
    double averageRating = 0;
    int ratingCount = 0;
    int id = 0;
};

// Returns false when any query word is missing from the recipe.
bool scoreRecipeSearch(RecipeRef ref, Dish &dish, Variant &variant,
                       const vector<string> &words, const string &phrase,
                       RecipeSearchHit &hit){
    Recipe &recipe = variant.getRecipe();
    int total = 0;
    bool primary = false;

    for(const string &word : words){
        int best = 0;
        bool matchedPrimary = false;

        int score = textMatchScore(word, variant.getName(), false);
        if(score > 0){ best = max(best, score * 3); matchedPrimary = true; }

        score = textMatchScore(word, dish.getName(), false);
        if(score > 0){ best = max(best, score * 2); matchedPrimary = true; }

        score = textMatchScore(word, recipe.getMainIngredient(), false);
        if(score > 0){ best = max(best, score * 2); matchedPrimary = true; }

        for(const string &ingredient : recipe.getIngredients()){
            score = textMatchScore(word, ingredient, false);
            if(score > 0) best = max(best, score);
        }
        for(const string &step : recipe.getSteps()){
            score = textMatchScore(word, step, true);
            if(score > 0) best = max(best, score);
        }

        // AND search: every word must appear somewhere, otherwise the recipe
        // is not a match for this query.
        if(best == 0) return false;

        total += best;
        if(matchedPrimary) primary = true;
    }

    if(words.size() > 1){
        total += phraseMatchBonus(phrase, variant.getName());
        total += phraseMatchBonus(phrase, dish.getName()) / 2;
    }

    hit.ref = ref;
    hit.score = total;
    hit.primary = primary;
    hit.averageRating = variant.getRatings().average();
    hit.ratingCount = variant.getRatings().count();
    hit.id = variant.getId();
    return true;
}

// Higher text score first; ties go to the better-rated recipe, then the
// smaller id so output is stable.
bool betterSearchHit(const RecipeSearchHit &a, const RecipeSearchHit &b){
    if(a.score != b.score) return a.score > b.score;
    if(a.averageRating != b.averageRating) return a.averageRating > b.averageRating;
    if(a.ratingCount != b.ratingCount) return a.ratingCount > b.ratingCount;
    return a.id < b.id;
}

// The shared search entry point. BackendService turns these hits into JSON;
// the console programs turn them into recipe pages.
vector<RecipeSearchHit> findRecipeMatches(RecipeDatabase &db, const string &keyword){
    vector<RecipeSearchHit> hits;

    vector<string> words = searchWords(keyword);
    if(words.empty()) return hits;

    string phrase;
    for(int i = 0; i < (int)words.size(); i++){
        if(i > 0) phrase += " ";
        phrase += words[i];
    }

    for(int d = 0; d < (int)db.getDishes().size(); d++){
        Dish &dish = db.getDishes()[d];
        for(int v = 0; v < (int)dish.getVariants().size(); v++){
            Variant &variant = dish.getVariants()[v];
            RecipeSearchHit hit;
            if(scoreRecipeSearch(makeRef(d, v), dish, variant, words, phrase, hit)){
                hits.push_back(hit);
            }
        }
    }

    sort(hits.begin(), hits.end(), betterSearchHit);
    return hits;
}

class SearchResult {
public:
    vector<RecipeRef> best;
    vector<RecipeRef> others;
};

// Console-friendly wrapper: same matcher, split into "best" (title/dish/main
// ingredient match) and "others" (ingredient or step match).
SearchResult searchRecipes(RecipeDatabase &db, string keyword){
    SearchResult result;
    for(RecipeSearchHit &hit : findRecipeMatches(db, keyword)){
        if(hit.primary) result.best.push_back(hit.ref);
        else result.others.push_back(hit.ref);
    }
    return result;
}

#endif