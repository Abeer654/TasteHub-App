# Stage 2 — HTTP Server

**Goal:** expose the Stage 1 backend as a local HTTP JSON API. The server is a
thin waiter: it parses requests, calls `BackendService`, and returns JSON. It
must not contain recipe logic.

**Done when:** every endpoint in `API.md` works with `curl`, data persists
across restarts, and the server can be reached from another device.

---

## 1. Prerequisites

- Stage 1 checkpoint passed.
- `BackendService.h`, `RecipeCore.h`, `backend_test.cpp` compile.
- You are in the repository root:

```bash
cd ~/development/TasteHub-App
```

---

## 2. Vendor `httplib.h`

Download the pinned release next to `json.hpp`:

```bash
curl -L -o httplib.h \
  https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.65.0/httplib.h
```

Check it:

```bash
ls -lh httplib.h
head -5 httplib.h
```

`cpp-httplib` is a single header. It is MIT-licensed. Do not edit it.

---

## 3. Create `CMakeLists.txt`

Create `CMakeLists.txt` in the repository root:

```cmake
cmake_minimum_required(VERSION 3.16)
project(TasteHub LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)

# HTTP server
add_executable(tastehub-server server.cpp)
target_link_libraries(tastehub-server PRIVATE Threads::Threads)
target_compile_options(tastehub-server PRIVATE -Wall -Wextra)

# Backend test program
add_executable(backend_test backend_test.cpp)
target_link_libraries(backend_test PRIVATE Threads::Threads)
target_compile_options(backend_test PRIVATE -Wall -Wextra)
```

If your compiler is old and `std::filesystem` fails to link, add this line:

```cmake
target_link_libraries(tastehub-server PRIVATE stdc++fs)
target_link_libraries(backend_test PRIVATE stdc++fs)
```

---

## 4. Create `server.cpp`

Create `server.cpp` in the repository root:

```cpp
#include <iostream>
#include <string>
#include "httplib.h"
#include "BackendService.h"

using namespace std;

static void sendJson(httplib::Response& res, const json& body, int status = 200){
    res.status = status;
    res.set_content(body.dump(), "application/json");
}

template <typename F>
static void handle(httplib::Response& res, F fn, int successStatus = 200){
    try {
        sendJson(res, fn(), successStatus);
    }
    catch(const ApiException& e){
        sendJson(res, json{{"error", e.what()}}, e.status);
    }
    catch(const json::exception& e){
        sendJson(res, json{{"error", e.what()}}, 400);
    }
    catch(const std::exception& e){
        sendJson(res, json{{"error", e.what()}}, 500);
    }
}

int main(int argc, char** argv){
    string host = "0.0.0.0";
    int port = 8080;
    string dataDir = "data";

    for(int i = 1; i < argc; i++){
        string arg = argv[i];
        if(arg == "--host" && i + 1 < argc){
            host = argv[++i];
        }
        else if(arg == "--port" && i + 1 < argc){
            port = stoi(argv[++i]);
        }
        else if(arg == "--data-dir" && i + 1 < argc){
            dataDir = argv[++i];
        }
        else {
            cerr << "Unknown argument: " << arg << "\n";
            cerr << "Usage: tastehub-server [--host 0.0.0.0] [--port 8080] [--data-dir data]\n";
            return 1;
        }
    }

    try {
        BackendService service(dataDir);
        httplib::Server svr;

        svr.set_logger([](const httplib::Request& req, const httplib::Response& res){
            cout << req.method << " " << req.path << " -> " << res.status << "\n";
        });

        svr.set_post_routing_handler([](const httplib::Request&, httplib::Response& res){
            res.set_header("Access-Control-Allow-Origin", "*");
            res.set_header("Access-Control-Allow-Headers", "Content-Type");
            res.set_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        });

        svr.Options(R"(.*)", [](const httplib::Request&, httplib::Response& res){
            res.status = 204;
        });

        svr.set_error_handler([](const httplib::Request&, httplib::Response& res){
            json body;
            body["error"] = "HTTP " + to_string(res.status);
            res.set_content(body.dump(), "application/json");
        });

        svr.Get("/api/health", [&](const httplib::Request&, httplib::Response& res){
            handle(res, [&]{ return service.health(); });
        });

        svr.Get("/api/recipes", [&](const httplib::Request&, httplib::Response& res){
            handle(res, [&]{ return service.listRecipes(); });
        });

        svr.Get(R"(/api/recipes/(\d+))", [&](const httplib::Request& req, httplib::Response& res){
            int id = stoi(req.matches[1].str());
            handle(res, [&]{ return service.getRecipe(id); });
        });

        svr.Post("/api/recipes", [&](const httplib::Request& req, httplib::Response& res){
            handle(res, [&]{
                json body = json::parse(req.body);
                return service.addRecipe(body);
            }, 201);
        });

        svr.Put(R"(/api/recipes/(\d+))", [&](const httplib::Request& req, httplib::Response& res){
            int id = stoi(req.matches[1].str());
            handle(res, [&]{
                json body = json::parse(req.body);
                return service.updateRecipe(id, body);
            });
        });

        svr.Delete(R"(/api/recipes/(\d+))", [&](const httplib::Request& req, httplib::Response& res){
            int id = stoi(req.matches[1].str());
            handle(res, [&]{ return service.deleteRecipe(id); });
        });

        svr.Get("/api/search", [&](const httplib::Request& req, httplib::Response& res){
            string query = req.has_param("q") ? req.get_param_value("q") : "";
            handle(res, [&]{ return service.searchRecipes(query); });
        });

        svr.Put(R"(/api/recipes/(\d+)/rating)", [&](const httplib::Request& req, httplib::Response& res){
            int id = stoi(req.matches[1].str());
            handle(res, [&]{
                json body = json::parse(req.body);
                if(!body.contains("stars") || !body["stars"].is_number_integer()){
                    throw ApiException(400, "stars must be an integer");
                }
                return service.rateRecipe(id, body["stars"].get<int>());
            });
        });

        svr.Get("/api/leaderboard", [&](const httplib::Request&, httplib::Response& res){
            handle(res, [&]{ return service.leaderboard(); });
        });

        cout << "TasteHub server listening on http://" << host << ":" << port << "\n";
        cout << "Data dir: " << dataDir << "\n";
        cout << "Press Ctrl+C to stop.\n";

        if(!svr.listen(host, port)){
            cerr << "Could not listen on " << host << ":" << port << "\n";
            return 1;
        }
    }
    catch(const std::exception& e){
        cerr << "Startup error: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
```

### Why each route is thin

| Route | Backend call |
|---|---|
| `GET /api/health` | `service.health()` |
| `GET /api/recipes` | `service.listRecipes()` |
| `GET /api/recipes/:id` | `service.getRecipe(id)` |
| `POST /api/recipes` | `service.addRecipe(body)` |
| `PUT /api/recipes/:id` | `service.updateRecipe(id, body)` |
| `DELETE /api/recipes/:id` | `service.deleteRecipe(id)` |
| `GET /api/search?q=` | `service.searchRecipes(query)` |
| `PUT /api/recipes/:id/rating` | `service.rateRecipe(id, stars)` |
| `GET /api/leaderboard` | `service.leaderboard()` |

The server never touches `RecipeDatabase` directly.

---

## 5. Build

```bash
cmake -S . -B build
cmake --build build -j
```

Expected:

```text
[ 50%] Built target backend_test
[100%] Built target tastehub-server
```

If CMake is not installed:

```bash
sudo apt install cmake
```

---

## 6. Run the server

From the repository root:

```bash
./build/tastehub-server --host 0.0.0.0 --port 8080 --data-dir data
```

Expected:

```text
TasteHub server listening on http://0.0.0.0:8080
Data dir: data
Press Ctrl+C to stop.
```

Leave this terminal open. Use a second terminal for `curl`.

---

## 7. Test every endpoint with `curl`

### Health

```bash
curl -s http://localhost:8080/api/health | python3 -m json.tool
```

Expected:

```json
{
    "recipes": 6,
    "status": "ok"
}
```

### List

```bash
curl -s http://localhost:8080/api/recipes | python3 -m json.tool
```

You should see 6 recipe summaries.

### Detail

```bash
curl -s http://localhost:8080/api/recipes/5 | python3 -m json.tool
```

You should see Chicken Biryani with `ingredients` and `steps`.

### Typo search

```bash
curl -s "http://localhost:8080/api/search?q=biriyani" | python3 -m json.tool
curl -s "http://localhost:8080/api/search?q=chiken" | python3 -m json.tool
```

The first result should be Chicken Biryani / chicken recipes.

### Add

```bash
curl -s -X POST http://localhost:8080/api/recipes \
  -H "Content-Type: application/json" \
  -d '{
    "dish": "Test Dish",
    "title": "Curl Test Curry",
    "mainIngredient": "chicken",
    "ingredients": ["chicken", "spices", "yogurt"],
    "steps": ["mix", "cook", "serve"],
    "cookingTime": 30,
    "imageRef": "",
    "youtubeUrl": "https://www.youtube.com/results?search_query=chicken+curry+recipe"
  }' | python3 -m json.tool
```

Note the `id` in the response.

### Rate

Replace `ID` with the id from the add response:

```bash
curl -s -X PUT http://localhost:8080/api/recipes/ID/rating \
  -H "Content-Type: application/json" \
  -d '{"stars": 5}' | python3 -m json.tool
```

### Leaderboard

```bash
curl -s http://localhost:8080/api/leaderboard | python3 -m json.tool
```

The new recipe should appear with the rating.

### Edit

```bash
curl -s -X PUT http://localhost:8080/api/recipes/ID \
  -H "Content-Type: application/json" \
  -d '{"title": "Curl Test Curry Updated"}' | python3 -m json.tool
```

### Delete

```bash
curl -s -X DELETE http://localhost:8080/api/recipes/ID | python3 -m json.tool
```

### Error cases

```bash
# 404
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/recipes/9999

# 400: stars out of range
curl -s -o /dev/null -w "%{http_code}\n" \
  -X PUT http://localhost:8080/api/recipes/5/rating \
  -H "Content-Type: application/json" \
  -d '{"stars": 9}'

# 409: duplicate title in the same dish
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST http://localhost:8080/api/recipes \
  -H "Content-Type: application/json" \
  -d '{"dish":"Biryani","title":"Chicken Biryani","ingredients":["rice"],"steps":["cook"]}'
```

Expected: `404`, `400`, `409`.

### Persistence

1. Stop the server with `Ctrl+C`.
2. Start it again.
3. Run the list endpoint:

```bash
curl -s http://localhost:8080/api/recipes | python3 -m json.tool
```

The recipes you added and ratings you changed should still be there.

Reset the demo data when you are done testing:

```bash
./scripts/reset-demo.sh
```

---

## 8. API contract

The frozen contract is in [`../API.md`](../API.md). Read it once before
starting Flutter. Do not change field names after Flutter starts consuming them.

Quick reference:

```text
GET    /api/health
GET    /api/recipes
GET    /api/recipes/:id
POST   /api/recipes
PUT    /api/recipes/:id
DELETE /api/recipes/:id
GET    /api/search?q=...
PUT    /api/recipes/:id/rating
GET    /api/leaderboard
```

Error shape:

```json
{ "error": "Recipe not found" }
```

---

## 9. Checkpoint

- [ ] `cmake` configures and builds without errors.
- [ ] `./build/tastehub-server ...` starts and prints the data dir.
- [ ] `/api/health` returns `"status": "ok"` and `"recipes": 6`.
- [ ] `/api/recipes` returns 6 summaries.
- [ ] `/api/recipes/5` returns Chicken Biryani with ingredients and steps.
- [ ] `?q=biriyani` finds Chicken Biryani.
- [ ] `?q=chiken` finds chicken recipes.
- [ ] `POST /api/recipes` returns `201` and a new id.
- [ ] `PUT /api/recipes/ID/rating` changes the average.
- [ ] `/api/leaderboard` puts the highest average first.
- [ ] `PUT /api/recipes/ID` edits a recipe.
- [ ] `DELETE /api/recipes/ID` removes it.
- [ ] `404`, `400`, and `409` are returned for bad requests.
- [ ] Data survives a server restart.
- [ ] `./scripts/reset-demo.sh` restores the 6 seed recipes.

---

## 10. Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `httplib.h: No such file` | Download failed or wrong folder | Run the `curl` command from the repo root |
| `Could not listen on 0.0.0.0:8080` | Port already in use | `sudo lsof -i :8080`, stop the old process, or use `--port 8081` |
| `Connection refused` from another device | Server bound to `127.0.0.1` or firewall blocks it | Use `--host 0.0.0.0` and open port 8080 |
| `undefined reference to pthread...` | Missing threads link | Keep `Threads::Threads` in CMake |
| `json::parse_error` | Request body is not valid JSON | Check quotes and commas in the `curl -d` body |
| `404` on a valid id | Wrong data dir or data was reset | Check `--data-dir data` and `data/recipes.json` |
| `409` on add | Same title already exists in that dish | Use a different title or delete the old recipe |
| CORS error in a browser | CORS headers missing | The server sets them; check you rebuilt after adding them |
| Server starts but list is empty | `data/recipes.json` is empty and seed missing | `./scripts/reset-demo.sh` |

---

## 11. Handoff to Stage 3

Stage 3 connects the phone to this server through Tailscale. Before you start:

- Keep the server running.
- Know your laptop's Tailscale IP.
- Make sure the server uses `--host 0.0.0.0`.

**Commit:**

```bash
git add -A
git commit -m "Stage 2: HTTP JSON API"
```
