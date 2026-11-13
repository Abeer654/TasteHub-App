// ============================================================
//  server.cpp - Stage 2 HTTP JSON API
//
//  This file is deliberately thin. It only:
//    - reads command-line options,
//    - turns HTTP requests into BackendService calls,
//    - turns BackendService results or ApiExceptions into JSON,
//    - serves one small browser page at "/".
//
//  All recipe validation, storage, search and AI logic stays in
//  BackendService and the core headers. The HTTP layer must never
//  include Console.h or any of the console menu headers.
//
//  Build:  make server
//  Run:    ./build/tastehub-server --host 127.0.0.1 --port 8080 --data-dir data
// ============================================================

#include <charconv>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <string>
#include <system_error>
#include "httplib.h"
#include "WebPage.h"
#include "core/BackendService.h"

using namespace std;

namespace {

// JSON request bodies stay small. Uploads use the same server but are checked
// against their own 10 MB file limit below.
constexpr size_t MAX_JSON_BODY = 1024 * 1024;
constexpr size_t MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

// ------------------------------------------------------------
//  Command-line options
// ------------------------------------------------------------

struct ServerOptions {
    string host = "127.0.0.1";
    int port = 8080;
    string dataDir = "data";
    string uploadsDir;          // empty means <data-dir>/uploads
};

enum class ParseResult {
    Ok,
    Help,
    Error
};

void printUsage(const string& program){
    cout << "Usage: " << program << " [options]\n"
         << "\n"
         << "Options:\n"
         << "  --host <address>   Interface to bind (default: 127.0.0.1)\n"
         << "  --port <number>    TCP port to listen on (default: 8080)\n"
         << "  --data-dir <path>  Folder holding recipes.json (default: data)\n"
         << "  --uploads-dir <path>  Folder for uploaded photos (default: <data-dir>/uploads)\n"
         << "  -h, --help         Show this help\n";
}

bool parsePort(const string& text, int& port){
    if(text.empty()) return false;

    int value = 0;
    const char* begin = text.data();
    const char* end = text.data() + text.size();
    auto result = from_chars(begin, end, value);

    if(result.ec != errc() || result.ptr != end) return false;
    if(value < 1 || value > 65535) return false;

    port = value;
    return true;
}

// Reads --host, --port and --data-dir. Unknown or malformed options are
// rejected instead of being silently ignored, which makes demo mistakes easy
// to spot.
ParseResult parseOptions(int argc, char** argv, ServerOptions& options){
    for(int i = 1; i < argc; i++){
        string argument = argv[i];

        if(argument == "-h" || argument == "--help"){
            return ParseResult::Help;
        }

        // Every supported option takes exactly one value.
        auto nextValue = [&](const string& name) -> optional<string> {
            if(i + 1 >= argc){
                cerr << "ERROR: " << name << " needs a value\n";
                return nullopt;
            }
            return string(argv[++i]);
        };

        if(argument == "--host"){
            optional<string> value = nextValue(argument);
            if(!value) return ParseResult::Error;

            options.host = trimSpaces(*value);
            if(options.host.empty()){
                cerr << "ERROR: --host cannot be empty\n";
                return ParseResult::Error;
            }
            continue;
        }

        if(argument == "--port"){
            optional<string> value = nextValue(argument);
            if(!value) return ParseResult::Error;

            if(!parsePort(*value, options.port)){
                cerr << "ERROR: --port must be a number from 1 to 65535\n";
                return ParseResult::Error;
            }
            continue;
        }

        if(argument == "--data-dir"){
            optional<string> value = nextValue(argument);
            if(!value) return ParseResult::Error;

            options.dataDir = trimSpaces(*value);
            if(options.dataDir.empty()){
                cerr << "ERROR: --data-dir cannot be empty\n";
                return ParseResult::Error;
            }
            continue;
        }

        if(argument == "--uploads-dir"){
            optional<string> value = nextValue(argument);
            if(!value) return ParseResult::Error;

            options.uploadsDir = trimSpaces(*value);
            if(options.uploadsDir.empty()){
                cerr << "ERROR: --uploads-dir cannot be empty\n";
                return ParseResult::Error;
            }
            continue;
        }

        cerr << "ERROR: unknown option: " << argument << "\n";
        return ParseResult::Error;
    }

    return ParseResult::Ok;
}

// ------------------------------------------------------------
//  JSON response helpers
// ------------------------------------------------------------

void sendJson(httplib::Response& response, int status, const json& body){
    response.status = status;
    response.set_header("Cache-Control", "no-store");
    response.set_content(
        body.dump(-1, ' ', false, json::error_handler_t::replace),
        "application/json");
}

void sendError(httplib::Response& response, int status, const string& message){
    sendJson(response, status, json{{"error", message}});
}

// The app sends "Authorization: Bearer <token>". Missing or malformed headers
// simply produce an empty token; BackendService decides whether auth is needed.
string bearerToken(const httplib::Request& request){
    string header = request.get_header_value("Authorization");
    string prefix = "Bearer ";
    if(header.size() <= prefix.size()) return "";

    string start = header.substr(0, prefix.size());
    if(toLowerCase(start) != "bearer ") return "";
    return trimSpaces(header.substr(prefix.size()));
}

// Detect the real image type from its first bytes, not from the filename or
// the browser-provided content type.
string imageExtension(const string& bytes){
    if(bytes.size() >= 3
       && (unsigned char)bytes[0] == 0xFF
       && (unsigned char)bytes[1] == 0xD8
       && (unsigned char)bytes[2] == 0xFF){
        return "jpg";
    }

    const string pngSignature = "\x89PNG\r\n\x1a\n";
    if(bytes.size() >= pngSignature.size()
       && bytes.compare(0, pngSignature.size(), pngSignature) == 0){
        return "png";
    }

    if(bytes.size() >= 12
       && bytes.compare(0, 4, "RIFF") == 0
       && bytes.compare(8, 4, "WEBP") == 0){
        return "webp";
    }

    return "";
}

// ------------------------------------------------------------
//  Request parsing helpers
// ------------------------------------------------------------

// POST and PUT bodies must be JSON objects. Returning false means the helper
// has already written a 400 response, so the route should simply return.
bool readJsonObject(const httplib::Request& request,
                    httplib::Response& response,
                    json& body){
    if(request.body.empty()){
        sendError(response, 400, "Request body must be a JSON object");
        return false;
    }
    if(request.body.size() > MAX_JSON_BODY){
        sendError(response, 413, "Request body is too large");
        return false;
    }

    body = json::parse(request.body, nullptr, false);
    if(body.is_discarded()){
        sendError(response, 400, "Request body must be valid JSON");
        return false;
    }
    if(!body.is_object()){
        sendError(response, 400, "Request body must be a JSON object");
        return false;
    }

    return true;
}

// The :id route parameter is a string from the URL. Convert it once here so
// every route handles bad ids the same way. Named path parameters are stored
// in path_params; regex routes would use matches instead.
bool readRecipeId(const httplib::Request& request,
                  httplib::Response& response,
                  int& recipeId){
    auto parameter = request.path_params.find("id");
    if(parameter == request.path_params.end()){
        sendError(response, 400, "Recipe id must be a positive integer");
        return false;
    }

    string text = parameter->second;
    int value = 0;
    const char* begin = text.data();
    const char* end = text.data() + text.size();
    auto result = from_chars(begin, end, value);

    if(result.ec != errc() || result.ptr != end || value <= 0){
        sendError(response, 400, "Recipe id must be a positive integer");
        return false;
    }

    recipeId = value;
    return true;
}

// Every API route goes through this small wrapper. The backend already attaches
// HTTP status codes to ApiException, so the server only forwards them.
template<typename Handler>
void handleRequest(httplib::Response& response, Handler handler){
    try {
        handler();
    }
    catch(const ApiException& error){
        sendError(response, error.status, error.what());
    }
    catch(const json::exception&){
        sendError(response, 400, "Invalid JSON request");
    }
    catch(const std::exception& error){
        cerr << "ERROR: " << error.what() << "\n";
        sendError(response, 500, "Internal server error");
    }
    catch(...){
        cerr << "ERROR: unknown exception while handling request\n";
        sendError(response, 500, "Internal server error");
    }
}

// ------------------------------------------------------------
//  Routes
// ------------------------------------------------------------

void registerRoutes(httplib::Server& server, BackendService& service,
                    const string& uploadsDir){
    // GET / - a small browser page. It is only HTML, CSS and JavaScript;
    // every piece of data still comes from the JSON API routes below.
    server.Get("/", [](const httplib::Request&, httplib::Response& response){
        response.status = 200;
        response.set_header("Cache-Control", "no-store");
        response.set_content(kIndexHtml, "text/html; charset=utf-8");
    });

    // GET /api/health - cheap readiness check, also used by the smoke test.
    server.Get("/api/health", [&service](const httplib::Request&,
                                         httplib::Response& response){
        handleRequest(response, [&]{
            sendJson(response, 200, service.health());
        });
    });

    // ------------------------------------------------------------
    //  Authentication
    // ------------------------------------------------------------

    server.Post("/api/auth/signup",
                [&service](const httplib::Request& request,
                           httplib::Response& response){
        handleRequest(response, [&]{
            json body;
            if(!readJsonObject(request, response, body)) return;
            sendJson(response, 201, service.signup(body));
        });
    });

    server.Post("/api/auth/login",
                [&service](const httplib::Request& request,
                           httplib::Response& response){
        handleRequest(response, [&]{
            json body;
            if(!readJsonObject(request, response, body)) return;
            sendJson(response, 200, service.login(body));
        });
    });

    server.Post("/api/auth/logout",
                [&service](const httplib::Request& request,
                           httplib::Response& response){
        handleRequest(response, [&]{
            sendJson(response, 200, service.logout(bearerToken(request)));
        });
    });

    server.Get("/api/auth/me",
               [&service](const httplib::Request& request,
                          httplib::Response& response){
        handleRequest(response, [&]{
            sendJson(response, 200, service.me(bearerToken(request)));
        });
    });

    // ------------------------------------------------------------
    //  Recipes
    // ------------------------------------------------------------

    // GET /api/recipes - all recipe summaries as a JSON array.
    server.Get("/api/recipes", [&service](const httplib::Request& request,
                                          httplib::Response& response){
        handleRequest(response, [&]{
            sendJson(response, 200, service.listRecipes(bearerToken(request)));
        });
    });

    // GET /api/leaderboard?dish=... - ranking inside one dish. Without a dish
    // filter it stays a global list of rated recipes.
    server.Get("/api/leaderboard", [&service](const httplib::Request& request,
                                              httplib::Response& response){
        handleRequest(response, [&]{
            string dish;
            if(request.has_param("dish")){
                dish = request.get_param_value("dish");
            }
            sendJson(response, 200,
                     service.leaderboard(dish, bearerToken(request)));
        });
    });

    // GET /api/search?q=... - typo-tolerant search.
    // A missing or blank query is treated as "no search yet" and returns an
    // empty result list, which is friendlier for the mobile search screen.
    server.Get("/api/search", [&service](const httplib::Request& request,
                                         httplib::Response& response){
        handleRequest(response, [&]{
            string query;
            if(request.has_param("q")){
                query = trimSpaces(request.get_param_value("q"));
            }

            if(query.empty()){
                sendJson(response, 200,
                         json{{"query", ""}, {"results", json::array()}});
                return;
            }

            sendJson(response, 200,
                     service.searchRecipes(query, bearerToken(request)));
        });
    });

    // POST /api/recipes/parse - AI draft only; nothing is saved here.
    server.Post("/api/recipes/parse", [&service](const httplib::Request& request,
                                                 httplib::Response& response){
        handleRequest(response, [&]{
            // Parsing is a logged-in feature; this also keeps the Gemini key
            // from being usable by anonymous clients.
            service.me(bearerToken(request));

            json body;
            if(!readJsonObject(request, response, body)) return;

            if(!body.contains("text") || body["text"].is_null()){
                sendError(response, 400,
                          "text is required and should describe the dish");
                return;
            }
            if(!body["text"].is_string()){
                sendError(response, 400, "text must be a string");
                return;
            }

            sendJson(response, 200,
                     service.parseRecipeText(body["text"].get<string>()));
        });
    });

    // POST /api/images - authenticated multipart photo upload.
    // The returned /uploads/... path is what a recipe or proof stores.
    server.Post("/api/images",
                [&service, uploadsDir](const httplib::Request& request,
                                       httplib::Response& response){
        handleRequest(response, [&]{
            // Calling me() here gives a clear 401 before any file is written.
            service.me(bearerToken(request));

            if(!request.is_multipart_form_data()
               || !request.form.has_file("file")){
                throw ApiException(400,
                    "Send a multipart form with a file field named 'file'");
            }

            httplib::FormData file = request.form.get_file("file");
            if(file.content.empty()){
                throw ApiException(400, "The uploaded file is empty");
            }
            if(file.content.size() > MAX_UPLOAD_BYTES){
                throw ApiException(413, "Image must be 10 MB or smaller");
            }

            string extension = imageExtension(file.content);
            if(extension.empty()){
                throw ApiException(400,
                    "Only JPEG, PNG and WebP images are supported");
            }

            std::filesystem::create_directories(uploadsDir);

            string imageName;
            std::filesystem::path imagePath;
            do {
                imageName = "img_" + randomHex(8) + "." + extension;
                imagePath = std::filesystem::path(uploadsDir) / imageName;
            } while(std::filesystem::exists(imagePath));

            std::ofstream output(imagePath, std::ios::binary);
            if(!output){
                throw ApiException(500, "Could not store the uploaded image");
            }
            output.write(file.content.data(),
                         (std::streamsize)file.content.size());
            output.close();
            if(!output){
                throw ApiException(500, "Could not store the uploaded image");
            }

            sendJson(response, 201,
                     json{{"imageRef", "/uploads/" + imageName}});
        });
    });

    // POST /api/recipes - create a recipe/variant. Login required.
    server.Post("/api/recipes", [&service](const httplib::Request& request,
                                           httplib::Response& response){
        handleRequest(response, [&]{
            json body;
            if(!readJsonObject(request, response, body)) return;

            sendJson(response, 201,
                     service.addRecipe(body, bearerToken(request)));
        });
    });

    // PUT /api/recipes/:id/rating - rate 1-5, optionally replacing the proof.
    server.Put("/api/recipes/:id/rating",
               [&service](const httplib::Request& request,
                          httplib::Response& response){
        handleRequest(response, [&]{
            int recipeId = 0;
            if(!readRecipeId(request, response, recipeId)) return;

            json body;
            if(!readJsonObject(request, response, body)) return;

            if(!body.contains("stars") || body["stars"].is_null()){
                sendError(response, 400, "stars is required");
                return;
            }
            if(!body["stars"].is_number_integer()){
                sendError(response, 400, "stars must be an integer");
                return;
            }

            // Omitted or null keeps the existing proof. An empty string clears
            // it, which matches the rating rules documented in API.md.
            optional<string> proofImageRef;
            if(body.contains("proofImageRef") && !body["proofImageRef"].is_null()){
                if(!body["proofImageRef"].is_string()){
                    sendError(response, 400,
                              "proofImageRef must be a string");
                    return;
                }
                proofImageRef = body["proofImageRef"].get<string>();
            }

            int stars = body["stars"].get<int>();
            sendJson(response, 200,
                     service.rateRecipe(recipeId, stars, proofImageRef,
                                        bearerToken(request)));
        });
    });

    // GET /api/recipes/:id - full detail, including all ratings and proofs.
    server.Get("/api/recipes/:id", [&service](const httplib::Request& request,
                                              httplib::Response& response){
        handleRequest(response, [&]{
            int recipeId = 0;
            if(!readRecipeId(request, response, recipeId)) return;

            sendJson(response, 200,
                     service.getRecipe(recipeId, bearerToken(request)));
        });
    });

    // PUT /api/recipes/:id - partial edit. Owner only.
    server.Put("/api/recipes/:id", [&service](const httplib::Request& request,
                                              httplib::Response& response){
        handleRequest(response, [&]{
            int recipeId = 0;
            if(!readRecipeId(request, response, recipeId)) return;

            json body;
            if(!readJsonObject(request, response, body)) return;

            sendJson(response, 200,
                     service.updateRecipe(recipeId, body,
                                          bearerToken(request)));
        });
    });

    // DELETE /api/recipes/:id - delete one recipe. Owner only.
    server.Delete("/api/recipes/:id", [&service](const httplib::Request& request,
                                                 httplib::Response& response){
        handleRequest(response, [&]{
            int recipeId = 0;
            if(!readRecipeId(request, response, recipeId)) return;

            sendJson(response, 200,
                     service.deleteRecipe(recipeId, bearerToken(request)));
        });
    });
}

// ------------------------------------------------------------
//  Server setup
// ------------------------------------------------------------

// cpp-httplib enables SO_REUSEPORT on Linux by default. That lets a second
// server bind the same port and silently split connections between them, which
// looks like random 404s or timeouts in the browser. SO_REUSEADDR still allows
// a quick restart, but rejects a second listener on the same address.
void setServerSocketOptions(socket_t socket){
#ifdef _WIN32
    (void)socket;
#else
    httplib::set_socket_opt(socket, SOL_SOCKET, SO_REUSEADDR, 1);
#endif
}

void configureServer(httplib::Server& server){
    server.set_socket_options(setServerSocketOptions);

    // Uploads can be up to 10 MB. JSON routes still enforce the smaller
    // MAX_JSON_BODY limit inside readJsonObject().
    server.set_payload_max_length(12 * 1024 * 1024);

    // AI parse requests can take up to 45 seconds while Gemini is called, so
    // keep the socket timeouts comfortably above the Gemini client timeout.
    server.set_read_timeout(60, 0);
    server.set_write_timeout(60, 0);

    // One concise line per request. Never log bodies, search text or API keys.
    server.set_logger([](const httplib::Request& request,
                         const httplib::Response& response){
        clog << request.method << ' ' << request.path
             << " -> " << response.status << "\n";
    });

    // cpp-httplib's default errors are HTML. Keep the API JSON-only for
    // unknown routes, wrong methods and oversized bodies. The error handler
    // runs for every response with status >= 400, so leave responses that an
    // API route already filled with JSON untouched.
    server.set_error_handler(
        [](const httplib::Request&,
           httplib::Response& response) -> httplib::Server::HandlerResponse {
            if(!response.body.empty()){
                return httplib::Server::HandlerResponse::Unhandled;
            }

            int status = response.status >= 400 ? response.status : 500;

            if(status == 404){
                sendError(response, status, "Not found");
            }
            else if(status == 413){
                sendError(response, status, "Request body is too large");
            }
            else {
                sendError(response, status, "Request failed");
            }

            return httplib::Server::HandlerResponse::Handled;
        });

    // Safety net: route handlers normally catch their own exceptions, but an
    // unexpected one should still produce JSON instead of an empty response.
    server.set_exception_handler(
        [](const httplib::Request&, httplib::Response& response,
           std::exception_ptr error){
            try {
                if(error) rethrow_exception(error);
            }
            catch(const ApiException& apiError){
                sendError(response, apiError.status, apiError.what());
                return;
            }
            catch(const json::exception&){
                sendError(response, 400, "Invalid JSON request");
                return;
            }
            catch(const std::exception& unexpected){
                cerr << "ERROR: " << unexpected.what() << "\n";
            }
            catch(...){
                cerr << "ERROR: unknown exception while handling request\n";
            }

            sendError(response, 500, "Internal server error");
        });
}

} // namespace

// ------------------------------------------------------------
//  Entry point
// ------------------------------------------------------------

int main(int argc, char** argv){
    ServerOptions options;
    ParseResult result = parseOptions(argc, argv, options);

    if(result == ParseResult::Help){
        printUsage(argv[0]);
        return 0;
    }
    if(result == ParseResult::Error){
        printUsage(argv[0]);
        return 2;
    }

    try {
        // One service instance owns the database and its mutex. cpp-httplib
        // may call the routes from several threads at once, and BackendService
        // is already responsible for serialising access.
        BackendService service(options.dataDir);

        string uploadsDir = options.uploadsDir;
        if(uploadsDir.empty()){
            uploadsDir = (std::filesystem::path(options.dataDir) / "uploads").string();
        }
        std::filesystem::create_directories(uploadsDir);

        httplib::Server server;
        configureServer(server);
        server.set_file_extension_and_mimetype_mapping("webp", "image/webp");

        // User photos are stored as ordinary files and served read-only.
        if(!server.set_mount_point("/uploads", uploadsDir)){
            cerr << "ERROR: could not serve uploads from " << uploadsDir << "\n";
            return 1;
        }

        registerRoutes(server, service, uploadsDir);

        // Bind before printing the banner. If the port is already in use, the
        // second server should fail immediately and clearly instead of looking
        // like it started successfully.
        if(!server.bind_to_port(options.host, options.port)){
            cerr << "ERROR: could not listen on "
                 << options.host << ":" << options.port << "\n";
            return 1;
        }

        json health = service.health();

        // 0.0.0.0 and :: are bind addresses, not useful browser addresses.
        string pageHost = options.host;
        if(pageHost == "0.0.0.0" || pageHost == "::") pageHost = "127.0.0.1";

        cout << "TasteHub HTTP server\n"
             << "  host:    " << options.host << "\n"
             << "  port:    " << options.port << "\n"
             << "  page:    http://" << pageHost << ":" << options.port << "/\n"
             << "  data:    " << options.dataDir << "\n"
             << "  uploads: " << uploadsDir << "\n"
             << "  recipes: " << health.value("recipes", 0) << "\n";
        cout.flush();

        if(!server.listen_after_bind()){
            cerr << "ERROR: server stopped unexpectedly\n";
            return 1;
        }
    }
    catch(const ApiException& error){
        cerr << "ERROR: " << error.what() << "\n";
        return 1;
    }
    catch(const std::exception& error){
        cerr << "ERROR: " << error.what() << "\n";
        return 1;
    }

    return 0;
}
