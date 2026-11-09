#ifndef SEARCH_H
#define SEARCH_H

// ============================================================
//  Search.h - typo-tolerant recipe matching
//
//    - exact words and simple plurals match best
//    - prefixes match next ("chick" -> "chicken")
//    - one or two edit-distance typos are accepted for longer words
//    - every typed word must match somewhere, so multi-word searches stay precise
//    - dish/title/main-ingredient matches count more than ingredient/step matches
//
//  BackendService (HTTP) and the console menus all use this matcher.
// ============================================================

#include <algorithm>
#include <string>
#include <vector>
#include "Storage.h"

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
