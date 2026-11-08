// ============================================================
//  tests/gemini_smoke.cpp - optional real-network check
//
//  This is NOT part of make test. It calls the real Gemini API using
//  GEMINI_API_KEY from the environment or from .env, so it needs network
//  access and a valid key.
//
//  Build and run from the repository root:
//      make gemini-smoke
//
//  Or pass your own description:
//      /tmp/opencode/tastehub-gemini-smoke "I made ..."
// ============================================================

#include <iostream>
#include "AiRecipe.h"

using namespace std;

int main(int argc, char** argv){
    string text;
    for(int i = 1; i < argc; i++){
        if(i > 1) text += " ";
        text += argv[i];
    }
    if(text.empty()){
        text =
            "I made chicken biryani last night with rice, chicken, yogurt, "
            "onions and spices. I marinated the chicken, fried the onions, "
            "layered everything with rice and cooked it on low heat for an hour.";
    }

    try {
        GeminiRecipeExtractor extractor;
        RecipeDraft draft = extractor.extract(text);

        cout << "SOURCE: " << draft.source << "\n";
        cout << "DISH: " << draft.dish << "\n";
        cout << "TITLE: " << draft.title << "\n";
        cout << "MAIN: " << draft.mainIngredient << "\n";
        cout << "TIME: " << draft.cookingTime << " minutes\n";

        cout << "INGREDIENTS:\n";
        for(const string& item : draft.ingredients) cout << " - " << item << "\n";

        cout << "STEPS:\n";
        for(int i = 0; i < (int)draft.steps.size(); i++){
            cout << " " << i + 1 << ". " << draft.steps[i] << "\n";
        }

        cout << "MESSAGE: " << draft.message << "\n";

        cout << "INFERRED:";
        for(const string& item : draft.inferredFields) cout << " " << item;
        cout << "\n";

        cout << "QUESTIONS:";
        for(const string& item : draft.followUpQuestions) cout << " " << item;
        cout << "\n";
    }
    catch(const AiServiceError& error){
        cout << "AI_ERROR(" << error.status << "): " << error.what() << "\n";
        return 1;
    }

    return 0;
}
