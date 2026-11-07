# TasteHub Tech Stack

## Architecture

```
Flutter APK (phone) → Tailscale → C++ HTTP server (laptop) → JSON files
```

## Core choices

| Area | Choice | Why |
|---|---|---|
| Backend | C++17 | Project requirement|
| OOP model | Existing `BaseEntity`, `Recipe`, `Variant`, `Dish`, `User`, `RecipeDatabase`, `UserDatabase` | Keeps inheritance, encapsulation, composition, and abstraction; add a virtual `toJson()` for polymorphism |
| HTTP server | `cpp-httplib` | Single-header, simple, no heavy framework |
| JSON | `nlohmann/json` (`json.hpp`) | Already vendored; easy serialization |
| Storage | JSON files | Simple for a demo; no database setup; easy to inspect and reset |
| Concurrency | `std::mutex` + atomic save | Prevents file corruption from concurrent requests |
| Server host | Laptop | Avoids Android NDK/FFI; easiest C++ integration |
| Connectivity | Tailscale | Works across Wi-Fi/cellular; stable private IP; encrypted; no port forwarding |
| Fallback | Same Wi-Fi / `adb reverse` / phone hotspot | Keeps the demo reliable if Tailscale fails |
| Frontend | Flutter (Android APK) | UI demo; existing Flutter toolchain |
| HTTP client | Flutter `http` package | Standard and simple |
| AI | Google Gemini free tier, called from Flutter | Avoids C++ HTTPS/OpenSSL; key via `--dart-define` or settings; local fallback |
| Search | C++ fuzzy search (Levenshtein/trigram) | Typo tolerance; demonstrates C++ logic |
| Leaderboard | C++ rating/ranking | Average + count; optional Bayesian average |
| Rating proof | Optional `proofImageRef` on each rating | User can attach a photo proving they cooked the recipe; path/URL only |
| Images | Local files on phone; path/URL stored in JSON | No upload/static server needed for a single-phone demo |
| YouTube | URL stored in JSON | Simple; Flutter opens or embeds it |
| Auth | None for demo (fixed user/profile) | Not needed for demo; keeps scope small; `User` class stays for OOP evidence |
| Build | CMake + g++/clang | Portable; no Android NDK |
| API | REST JSON | Simple contract for Flutter |
| Testing | curl/Python smoke test | Quick pre-demo verification |
| Docs | README, `API.md`, Tailscale setup | Clear handoff and demo setup |

## OOP evidence

- **Classes/objects:** `Recipe`, `Variant`, `Dish`, `User`, `Comment`, `Rating`, `Reactions`
- **Inheritance:** `BaseEntity` → `Comment`, `Variant`, `Dish`, `User`
- **Encapsulation:** `protected` fields with getters/setters
- **Composition:** `Dish` owns `Variant`s; `Variant` owns a `Recipe`, comments, ratings, reactions
- **Abstraction:** `RecipeDatabase`, `UserDatabase`, and a new `BackendService` facade
- **Polymorphism:** add `virtual json toJson() = 0;` to `BaseEntity` and call it through a `BaseEntity&`

## API sketch

- `GET /api/health`
- `GET /api/recipes`
- `GET /api/recipes/:id`
- `POST /api/recipes`
- `PUT /api/recipes/:id`
- `DELETE /api/recipes/:id`
- `GET /api/search?q=`
- `PUT /api/recipes/:id/rating` (stars + optional proof image)
- `GET /api/leaderboard`

## Data

- `data/recipes.json`
- `seed/` for demo data
- `--data-dir` flag
- ISO-8601 timestamps
- Atomic writes (temp file + rename)
- Rating proof images stored as `proofImageRef` (URL or phone path)

## Not using

| Option | Why not |
|---|---|
| Android NDK / FFI | Too much work for a demo; the laptop server is simpler |
| Embedded HTTP server in APK | More moving parts; no demo benefit |
| SQLite | JSON is enough for a demo; less setup |
| C++ HTTPS for Gemini | Flutter can call Gemini directly; avoids OpenSSL |
| Full auth/comments/like-dislike reactions | Out of demo scope; keep the classes for OOP evidence. Star ratings with proof images are in scope. |
| Image upload server | Local files are enough for a single-phone demo |

## Demo flow

1. Start the C++ server on the laptop.
2. Connect the phone and laptop through Tailscale.
3. Build the APK with `--dart-define=API_BASE_URL=http://<tailscale-ip>:8080`.
4. Add a recipe → format with AI → save to JSON.
5. Search with typos.
6. Rate recipes with an optional proof image → leaderboard updates.

## Notes

- Android debug builds need cleartext HTTP enabled, or use Tailscale Serve for HTTPS.
- Keep the laptop awake during the demo.
- Test the fallback connection before the demo.
