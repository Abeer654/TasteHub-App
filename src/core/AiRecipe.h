#ifndef AIRECIPE_H
#define AIRECIPE_H

// ============================================================
//  AiRecipe.h - natural-language recipe extraction
//
//  The user can describe a dish in plain language ("AI mode") and this
//  module turns it into the structured fields the backend needs:
//
//      dish, title, main ingredient, ingredients, steps, cooking time
//
//  Gemini is called over HTTPS with libcurl. The API key is read from
//  GEMINI_API_KEY (or GOOGLE_API_KEY). If the environment does not have
//  the key, a local .env file is loaded automatically.
//
//  Tests never need the network: BackendService accepts a RecipeExtractor,
//  and backend_test injects a fake one.
// ============================================================

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include "Models.h"

#if !defined(TASTEHUB_NO_GEMINI)
#include <curl/curl.h>
#endif

using namespace std;
using json = nlohmann::json;

// A recipe draft is exactly the data the AI-assisted flow needs before the
// user confirms it. The recipe part maps 1:1 to POST /api/recipes.
struct RecipeDraft {
    string dish;
    string title;
    string mainIngredient;
    vector<string> ingredients;
    vector<string> steps;
    int cookingTime = 0;
    string imageRef;
    string youtubeUrl;

    // Conversational extras for the UI.
    string message;
    vector<string> inferredFields;
    vector<string> followUpQuestions;
    string source;                 // "gemini", "fake", etc.
};

// AI/network failures carry the HTTP status the API should return.
class AiServiceError : public std::runtime_error {
public:
    int status;

    AiServiceError(int statusCode, const string& message)
        : std::runtime_error(message), status(statusCode) {}
};

// BackendService depends on this interface, not on libcurl. Tests inject a
// fake implementation; production uses GeminiRecipeExtractor.
class RecipeExtractor {
public:
    virtual ~RecipeExtractor() = default;
    virtual RecipeDraft extract(const string& userText) = 0;
};

// ------------------------------------------------------------
//  Environment / .env loading
// ------------------------------------------------------------

inline string aiEnvValue(const string& name){
    const char* value = std::getenv(name.c_str());
    return value == nullptr ? string("") : trimSpaces(string(value));
}

inline void aiSetEnvValue(const string& name, const string& value){
#if defined(_WIN32)
    _putenv_s(name.c_str(), value.c_str());
#else
    setenv(name.c_str(), value.c_str(), 0);   // 0 = never overwrite a real env var
#endif
}

inline string aiUnquote(string value){
    value = trimSpaces(value);
    if(value.size() >= 2){
        char first = value.front();
        char last = value.back();
        if((first == '"' && last == '"') || (first == '\'' && last == '\'')){
            value = value.substr(1, value.size() - 2);
        }
    }
    return value;
}

// Reads a simple KEY=VALUE file. Missing files are ignored on purpose:
// production can use real environment variables instead of .env.
inline void aiLoadDotEnv(const string& path){
    ifstream file(path);
    if(!file) return;

    string line;
    while(getline(file, line)){
        line = trimSpaces(line);
        if(line.empty() || line[0] == '#') continue;

        if(line.rfind("export ", 0) == 0){
            line = trimSpaces(line.substr(7));
        }

        size_t equals = line.find('=');
        if(equals == string::npos) continue;

        string key = trimSpaces(line.substr(0, equals));
        string value = aiUnquote(line.substr(equals + 1));
        if(key.empty()) continue;
        if(!aiEnvValue(key).empty()) continue;
        aiSetEnvValue(key, value);
    }
}

inline string aiApiKey(){
    string key = aiEnvValue("GEMINI_API_KEY");
    if(key.empty()) key = aiEnvValue("GOOGLE_API_KEY");
    if(!key.empty()) return aiUnquote(key);

    // Running from the repository root is the normal case. The parent
    // fallback lets a server started from a subfolder still find the key.
    aiLoadDotEnv(".env");
    aiLoadDotEnv("../.env");

    key = aiEnvValue("GEMINI_API_KEY");
    if(key.empty()) key = aiEnvValue("GOOGLE_API_KEY");
    return aiUnquote(key);
}

inline string aiModelName(){
    string model = aiEnvValue("GEMINI_MODEL");
    if(model.empty()){
        aiLoadDotEnv(".env");
        aiLoadDotEnv("../.env");
        model = aiEnvValue("GEMINI_MODEL");
    }
    if(model.empty()) model = "gemini-3.5-flash";
    model = aiUnquote(model);
    if(model.rfind("models/", 0) == 0) model = model.substr(7);
    return model;
}

// Keeps secrets out of error messages, just in case a service echoes them.
inline string aiRedactSecret(string text, const string& secret){
    if(secret.empty()) return text;
    size_t position = 0;
    while((position = text.find(secret, position)) != string::npos){
        text.replace(position, secret.size(), "[redacted]");
        position += 10;
    }
    return text;
}

// ------------------------------------------------------------
//  Parsing / normalization
// ------------------------------------------------------------

inline vector<string> aiStringArray(const json& value, const string& key){
    vector<string> result;
    if(!value.contains(key) || !value[key].is_array()) return result;

    for(const json& item : value[key]){
        if(!item.is_string()) continue;
        string text = key == "steps" ? trimSpaces(item.get<string>())
                                     : tidyName(item.get<string>());
        if(!text.empty()) result.push_back(text);
    }
    return result;
}

inline string aiStripCodeFences(string text){
    text = trimSpaces(text);

    // Gemini normally returns pure JSON because responseMimeType is set,
    // but stripping fences makes the parser tolerant of older models.
    if(text.rfind("```", 0) == 0){
        size_t firstNewline = text.find('\n');
        if(firstNewline != string::npos) text = text.substr(firstNewline + 1);
    }
    if(text.size() >= 3 && text.compare(text.size() - 3, 3, "```") == 0){
        text = text.substr(0, text.size() - 3);
    }
    text = trimSpaces(text);

    size_t firstBrace = text.find('{');
    size_t lastBrace = text.rfind('}');
    if(firstBrace != string::npos && lastBrace != string::npos && lastBrace > firstBrace){
        text = text.substr(firstBrace, lastBrace - firstBrace + 1);
    }
    return text;
}

// Fills sensible defaults and rejects a draft that still has no real content.
// This is deliberately separate from Gemini so tests can exercise it offline.
inline RecipeDraft aiNormalizeDraft(RecipeDraft draft, const string& source){
    draft.dish = tidyName(draft.dish);
    draft.title = tidyName(draft.title);
    draft.mainIngredient = tidyName(draft.mainIngredient);
    draft.imageRef = trimSpaces(draft.imageRef);
    draft.youtubeUrl = trimSpaces(draft.youtubeUrl);
    draft.message = trimSpaces(draft.message);

    vector<string> ingredients;
    for(const string& item : draft.ingredients){
        string clean = tidyName(item);
        if(!clean.empty()) ingredients.push_back(clean);
    }
    draft.ingredients = ingredients;

    vector<string> steps;
    for(const string& item : draft.steps){
        string clean = trimSpaces(item);
        if(!clean.empty()) steps.push_back(clean);
    }
    draft.steps = steps;

    vector<string> inferred;
    for(const string& item : draft.inferredFields){
        string clean = tidyName(item);
        if(!clean.empty()) inferred.push_back(clean);
    }
    draft.inferredFields = inferred;

    vector<string> questions;
    for(const string& item : draft.followUpQuestions){
        string clean = trimSpaces(item);
        if(!clean.empty()) questions.push_back(clean);
    }
    draft.followUpQuestions = questions;

    if(draft.mainIngredient.empty() && !draft.ingredients.empty()){
        draft.mainIngredient = draft.ingredients[0];
    }
    if(draft.title.empty()) draft.title = draft.dish;
    if(draft.dish.empty()) draft.dish = draft.mainIngredient.empty() ? "My Recipes"
                                                                    : draft.mainIngredient;
    if(draft.title.empty()) draft.title = "My Recipe";

    if(draft.cookingTime < 0) draft.cookingTime = 0;
    if(draft.cookingTime > 10000) draft.cookingTime = 10000;
    if(draft.source.empty()) draft.source = source;

    if(draft.ingredients.empty()){
        throw AiServiceError(422,
            "I could not identify any ingredients. Add a few ingredients and try again.");
    }
    if(draft.steps.empty()){
        throw AiServiceError(422,
            "I could not identify the cooking steps. Describe how you make it and try again.");
    }
    return draft;
}

inline RecipeDraft aiParseDraftJson(const string& rawText, const string& source){
    string text = aiStripCodeFences(rawText);
    json value = json::parse(text, nullptr, false);
    if(value.is_discarded()){
        throw AiServiceError(502, "Gemini returned invalid JSON");
    }
    if(!value.is_object()){
        throw AiServiceError(502, "Gemini returned an unexpected JSON shape");
    }

    RecipeDraft draft;
    if(value.contains("dish") && value["dish"].is_string()){
        draft.dish = value["dish"].get<string>();
    }
    if(value.contains("title") && value["title"].is_string()){
        draft.title = value["title"].get<string>();
    }
    if(value.contains("mainIngredient") && value["mainIngredient"].is_string()){
        draft.mainIngredient = value["mainIngredient"].get<string>();
    }
    if(value.contains("imageRef") && value["imageRef"].is_string()){
        draft.imageRef = value["imageRef"].get<string>();
    }
    if(value.contains("youtubeUrl") && value["youtubeUrl"].is_string()){
        draft.youtubeUrl = value["youtubeUrl"].get<string>();
    }
    if(value.contains("message") && value["message"].is_string()){
        draft.message = value["message"].get<string>();
    }

    if(value.contains("cookingTime")){
        if(value["cookingTime"].is_number_integer()){
            draft.cookingTime = value["cookingTime"].get<int>();
        }
        else if(value["cookingTime"].is_number_float()){
            draft.cookingTime = (int)value["cookingTime"].get<double>();
        }
        else if(value["cookingTime"].is_string()){
            string minutes = trimSpaces(value["cookingTime"].get<string>());
            try {
                if(!minutes.empty()) draft.cookingTime = stoi(minutes);
            }
            catch(...) {
                draft.cookingTime = 0;
            }
        }
    }

    draft.ingredients = aiStringArray(value, "ingredients");
    draft.steps = aiStringArray(value, "steps");
    draft.inferredFields = aiStringArray(value, "inferredFields");
    draft.followUpQuestions = aiStringArray(value, "followUpQuestions");

    return aiNormalizeDraft(draft, source);
}

// ------------------------------------------------------------
//  Gemini request / response
// ------------------------------------------------------------

inline json aiRecipeSchema(){
    json properties = json::object();
    properties["dish"] = {{"type", "STRING"}};
    properties["title"] = {{"type", "STRING"}};
    properties["mainIngredient"] = {{"type", "STRING"}};
    properties["ingredients"] = {{"type", "ARRAY"}, {"items", {{"type", "STRING"}}}};
    properties["steps"] = {{"type", "ARRAY"}, {"items", {{"type", "STRING"}}}};
    properties["cookingTime"] = {{"type", "INTEGER"}};
    properties["imageRef"] = {{"type", "STRING"}};
    properties["youtubeUrl"] = {{"type", "STRING"}};
    properties["message"] = {{"type", "STRING"}};
    properties["inferredFields"] = {{"type", "ARRAY"}, {"items", {{"type", "STRING"}}}};
    properties["followUpQuestions"] = {{"type", "ARRAY"}, {"items", {{"type", "STRING"}}}};

    json schema;
    schema["type"] = "OBJECT";
    schema["properties"] = properties;
    schema["required"] = json::array({"dish", "title", "mainIngredient",
                                      "ingredients", "steps"});
    return schema;
}

inline string aiSystemPrompt(){
    return
        "You extract exactly one recipe from a casual user description. "
        "The user may ramble, make typos, or mix English with Roman Urdu. "
        "Return JSON only, following the provided schema. "
        "dish is the broad dish family (for example Biryani, Karahi, Fries). "
        "title is the specific recipe name (for example Chicken Biryani). "
        "mainIngredient is the ONE base ingredient that defines the dish, lowercase: "
        "rice for biryani or pulao, potato for fries, mutton for karahi, beef for nihari. "
        "ingredients is a short list of ingredient names, with the main ingredient first; "
        "include quantities only if the user gave them. "
        "steps is an ordered list of short imperative cooking steps. "
        "cookingTime is the total time in minutes as an integer; use 0 only if truly unknown. "
        "If the user omitted an important detail, infer a standard value for that dish instead of refusing, "
        "and list the field name in inferredFields (for example steps or cookingTime). "
        "ingredients and steps must never be empty. "
        "message is one short, friendly sentence replying to the user and mentioning the main ingredient. "
        "followUpQuestions has at most 3 short questions, only for genuinely important missing details.";
}

inline string aiBuildRequestJson(const string& userText){
    json systemPart = {{"text", aiSystemPrompt()}};
    json systemInstruction;
    systemInstruction["parts"] = json::array({systemPart});

    json userPart = {{"text", userText}};
    json content;
    content["role"] = "user";
    content["parts"] = json::array({userPart});

    json generationConfig;
    generationConfig["temperature"] = 0.2;
    generationConfig["responseMimeType"] = "application/json";
    generationConfig["responseSchema"] = aiRecipeSchema();

    json request;
    request["systemInstruction"] = systemInstruction;
    request["contents"] = json::array({content});
    request["generationConfig"] = generationConfig;
    return request.dump();
}

inline RecipeDraft aiParseGeminiResponse(const string& responseBody,
                                        const string& apiKey = ""){
    json value = json::parse(responseBody, nullptr, false);
    if(value.is_discarded()){
        throw AiServiceError(502, "Gemini returned an unreadable response");
    }

    if(value.contains("error")){
        string message = "Gemini request failed";
        if(value["error"].is_object()){
            message = value["error"].value("message", message);
        }
        throw AiServiceError(502, aiRedactSecret(message, apiKey));
    }

    if(!value.contains("candidates") || !value["candidates"].is_array()
       || value["candidates"].empty()){
        throw AiServiceError(502, "Gemini returned no recipe");
    }

    const json& candidate = value["candidates"][0];
    string finishReason = candidate.value("finishReason", string(""));
    if(finishReason == "SAFETY" || finishReason == "BLOCKLIST"
       || finishReason == "PROHIBITED_CONTENT"){
        throw AiServiceError(422,
            "Gemini could not answer that description. Please rephrase it.");
    }

    string text;
    if(candidate.contains("content") && candidate["content"].is_object()
       && candidate["content"].contains("parts")
       && candidate["content"]["parts"].is_array()){
        for(const json& part : candidate["content"]["parts"]){
            if(part.contains("text") && part["text"].is_string()){
                text += part["text"].get<string>();
            }
        }
    }

    if(trimSpaces(text).empty()){
        throw AiServiceError(502, "Gemini returned an empty answer");
    }
    return aiParseDraftJson(text, "gemini");
}

#if !defined(TASTEHUB_NO_GEMINI)
inline size_t aiCurlWrite(char* data, size_t size, size_t count, void* userData){
    size_t total = size * count;
    static_cast<string*>(userData)->append(data, total);
    return total;
}

struct AiCurlGlobal {
    AiCurlGlobal(){ curl_global_init(CURL_GLOBAL_DEFAULT); }
    ~AiCurlGlobal(){ curl_global_cleanup(); }
};

inline AiCurlGlobal& aiCurlGlobal(){
    static AiCurlGlobal instance;
    return instance;
}
#endif

inline string aiHttpPost(const string& url, const string& apiKey, const string& body){
#if defined(TASTEHUB_NO_GEMINI)
    (void)url;
    (void)apiKey;
    (void)body;
    throw AiServiceError(503,
        "Gemini support was not compiled in. Rebuild without -DTASTEHUB_NO_GEMINI and link -lcurl.");
#else
    (void)aiCurlGlobal();

    CURL* curl = curl_easy_init();
    if(curl == nullptr){
        throw AiServiceError(500, "Could not initialize the HTTP client");
    }

    string response;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    string keyHeader = "x-goog-api-key: " + apiKey;
    headers = curl_slist_append(headers, keyHeader.c_str());

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)body.size());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, aiCurlWrite);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 45L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "TasteHub-CPP/1.0");

    CURLcode result = curl_easy_perform(curl);
    long status = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if(result != CURLE_OK){
        throw AiServiceError(502,
            "Could not reach Gemini: " + string(curl_easy_strerror(result)));
    }

    if(status < 200 || status >= 300){
        string message = "Gemini request failed";
        json errorBody = json::parse(response, nullptr, false);
        if(!errorBody.is_discarded() && errorBody.contains("error")
           && errorBody["error"].is_object()){
            message = errorBody["error"].value("message", message);
        }
        message = aiRedactSecret(message, apiKey);

        if(status == 401 || status == 403){
            throw AiServiceError(502,
                "Gemini rejected the API key. Check GEMINI_API_KEY in .env.");
        }
        if(status == 429){
            throw AiServiceError(503,
                "Gemini rate limit reached. Please try again shortly.");
        }
        if(status == 404){
            throw AiServiceError(502, message);
        }
        if(status == 503){
            throw AiServiceError(503, "Gemini is busy right now. Please try again.");
        }
        throw AiServiceError(502, message);
    }

    return response;
#endif
}

// Tries the configured model first, then a couple of fallbacks. Model names
// change over time, so a retired or overloaded model should not break the app.
inline vector<string> aiModelCandidates(const string& configuredModel){
    vector<string> models;

    auto add = [&](string name){
        name = trimSpaces(name);
        if(name.rfind("models/", 0) == 0) name = name.substr(7);
        if(name.empty()) return;
        if(std::find(models.begin(), models.end(), name) != models.end()) return;
        models.push_back(name);
    };

    add(configuredModel);
    add(aiModelName());
    add("gemini-3.5-flash");
    add("gemini-3.5-flash-lite");
    return models;
}

class GeminiRecipeExtractor : public RecipeExtractor {
public:
    explicit GeminiRecipeExtractor(string model = "") : configuredModel(std::move(model)) {}

    RecipeDraft extract(const string& userText) override {
        string text = trimSpaces(userText);
        if(text.size() < 10){
            throw AiServiceError(400,
                "Tell me a little more about the dish and how you make it.");
        }

        string apiKey = aiApiKey();
        if(apiKey.empty()){
            throw AiServiceError(503,
                "GEMINI_API_KEY is not set. Add it to .env or the environment.");
        }

        vector<string> models = aiModelCandidates(configuredModel);
        AiServiceError lastError(502, "Gemini request failed");

        for(size_t i = 0; i < models.size(); i++){
            string url = "https://generativelanguage.googleapis.com/v1beta/models/"
                       + models[i] + ":generateContent";
            try {
                string response = aiHttpPost(url, apiKey, aiBuildRequestJson(text));
                return aiParseGeminiResponse(response, apiKey);
            }
            catch(const AiServiceError& error){
                lastError = error;

                // Retry a fallback only when the model itself is unavailable.
                // Bad input, a rejected key, or a safety refusal should stop here.
                string reason = error.what();
                bool modelProblem = error.status == 503
                    || reason.find("no longer available") != string::npos
                    || reason.find("NOT_FOUND") != string::npos
                    || reason.find("Could not reach Gemini: Timeout") != string::npos;
                if(!modelProblem || i + 1 == models.size()) throw;
            }
        }

        throw lastError;
    }

private:
    string configuredModel;
};

#endif
