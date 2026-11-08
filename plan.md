# TasteHub Plan

Last updated: 2026-11-08
Status: Stage 1 complete. Next: Phase 0 refactor, then Stage 2.

This is the single plan for the project. Work through it top to bottom and do
not start a phase until its checkpoint passes.

Supporting documents:

- `plan.md` — the single project plan (tracked).
- `API.md` — detailed HTTP request/response contract (tracked).
- `devlog.md` — local-only implementation history (gitignored).
- `seed/recipes.json` — clean demo data (tracked).
- `.env` — local Gemini key (gitignored).

---

## 1. Goal

Build a small but complete recipe demo:

- A C++ backend with recipes, variants, ratings, proof images, comments
  (OOP evidence), fuzzy search and a leaderboard.
- A single console program for all normal actions.
- A C++ HTTP JSON API.
- A Flutter Android app connected over Tailscale.
- Natural-language recipe input through Gemini: the user describes a dish, the
  backend returns a structured draft, and the user confirms it before saving.

The demo must be repeatable without editing code between runs.

---

## 2. Architecture and tech stack

```text
Flutter APK (phone)
        |
        |  Tailscale private network
        v
C++ HTTP server (laptop)
        |
        +--> JSON files (seed/ and data/)
        |
        +--> Gemini API (AI recipe drafts)
```

| Area | Choice | Why |
|---|---|---|
| Backend | C++17 | Project requirement |
| OOP model | `BaseEntity`, `Recipe`, `Variant`, `Dish`, `User`, `Comment`, `Rating`, `Reactions`, `RecipeDatabase`, `UserDatabase` | Inheritance, encapsulation, composition, abstraction and polymorphism evidence |
| HTTP server | `cpp-httplib` | Single-header, simple, no heavy framework |
| JSON | `nlohmann/json` (`json.hpp`) | Already vendored and easy to inspect |
| Storage | JSON files | Enough for a demo; no database setup |
| Concurrency | `std::mutex` + atomic save | Prevents file corruption from concurrent requests |
| AI | Gemini via libcurl | One prompt/schema in the backend; testable offline with a fake extractor |
| Search | C++ fuzzy search | Plural, prefix and Damerau-Levenshtein matching |
| Ratings | 1–5 stars + optional image path/URL | Proof image is part of the rating |
| Frontend | Flutter Android APK | UI demo |
| HTTP client | Flutter `http` package | Standard and simple |
| Connectivity | Tailscale | Works across Wi-Fi/cellular without port forwarding |
| Fallback connections | Same Wi-Fi, `adb reverse`, phone hotspot | Keeps the demo reliable |
| Auth | Demo user id `1` | Keeps the demo small; `User` stays for OOP evidence |
| Build | CMake or Makefile + g++/clang | Portable; no Android NDK |

### OOP evidence to keep

- **Classes/objects:** `Recipe`, `Variant`, `Dish`, `User`, `Comment`, `Rating`, `Reactions`
- **Inheritance:** `BaseEntity` → `Comment`, `Variant`, `Dish`, `User`
- **Encapsulation:** `protected` fields with getters/setters
- **Composition:** `Dish` owns `Variant`s; `Variant` owns a `Recipe`, ratings, comments and reactions
- **Abstraction:** `RecipeDatabase`, `UserDatabase`, `BackendService`
- **Polymorphism:** `BaseEntity::toJson()` called through a `BaseEntity&`

Do not remove the polymorphic `toJson()` just to satisfy a refactor.

---

## 3. Current state

Stage 1 is complete and verified.

What works:

- Load the 6 demo recipes from `seed/recipes.json`.
- List recipes and get one recipe with ingredients, steps and ratings.
- Add a recipe to an existing dish or a new dish.
- Store `imageRef` and `youtubeUrl`.
- Edit and delete recipes; empty dishes are removed automatically.
- Typo-tolerant search over dish names, titles, ingredients and steps.
- Rate 1–5 with an optional proof image.
- Update an existing rating without creating a duplicate.
- Rank rated recipes on the leaderboard.
- Persist to JSON with atomic saves and a backup.
- Describe a dish naturally and receive a Gemini recipe draft.
- Review the draft before saving; drafts are never saved automatically.
- Console rating flow supports proof images.

Verification:

- `make test` → 127 PASS, 0 FAIL.
- ASan/UBSan clean.
- Real Gemini call verified.
- CLI upload, edit, delete, search, ratings and proof images verified.
- `data/recipes.json` matches `seed/recipes.json` after tests.

Current limitations:

- There is no HTTP server yet.
- There is no Flutter app yet.
- The console is split into three programs: `upload`, `search`, `rating`.
- Everything is header-only and each executable must stay one translation unit.
- The API uses demo user `1`; there is no real authentication.
- Comments and like/dislike reactions remain for OOP evidence but are not part of
  the Stage 1 HTTP contract.
- Only one server process is assumed; JSON access is not locked across processes.
- AI needs network access and a valid `GEMINI_API_KEY`.

---

## 4. Phase 0 — Refactor before Stage 2 (do this first)

### 4.1 Why this comes first

`RecipeCore.h` is about 1,800 lines and contains the model, JSON storage, fuzzy
search, password code, date/string helpers and console display. `ConsoleTools.h`
adds input, login and sessions. The console is three separate programs because
`upload.cpp`, `search.cpp` and `rating.cpp` each have their own `main()`.

Adding the HTTP server in this shape will make the coupling worse and can cause
duplicate-symbol errors as soon as a second `.cpp` is added to an executable.

The goal is:

- One console binary: `./tastehub`.
- A small number of headers organized by responsibility.
- One `main.cpp` for the console.
- `backend_test.cpp` and the future `server.cpp` remain separate executables.
- All existing behavior and all 127 tests stay green.

### 4.2 Target file layout

```text
TasteHub-App/
  plan.md
  API.md
  devlog.md

  Utils.h              small text/date/hash/JSON helpers
  Models.h             domain classes
  Storage.h            RecipeDatabase + UserDatabase
  Search.h             fuzzy search and ranking
  AiRecipe.h           Gemini client + recipe draft
  BackendService.h     API facade used by the test and server
  Console.h            input, passwords, session, login, recipe display

  UploadMenu.h         upload/edit/delete + AI yap flow
  SearchMenu.h         search screen
  ReviewMenu.h         rate / react / comment screen

  main.cpp             top-level menu + main()
  backend_test.cpp     acceptance test (separate executable)
  server.cpp           Stage 2 HTTP server (separate executable)

  seed/recipes.json
  data/recipes.json
```

This is a header-only core with one console `.cpp`. That is deliberate: only one
translation unit includes the implementation headers, so there are no duplicate
definitions.

### 4.3 What each header owns

| File | Responsibility |
|---|---|
| `Utils.h` | `trimSpaces`, `toLowerCase`, `tidyName`, dates, JSON file helpers, hashing, random codes |
| `Models.h` | `BaseEntity`, `Vote`, `Reactions`, `Rating`, `Ratings`, `Comment`, `Recipe`, `Variant`, `Dish`, `User` |
| `Storage.h` | `RecipeDatabase`, `UserDatabase`, load/save, atomic write, backups, ID counters |
| `Search.h` | stemming, Damerau-Levenshtein, matching scores, `searchRecipes` |
| `AiRecipe.h` | `RecipeDraft`, `RecipeExtractor`, Gemini request/response, prompt, parsing, `.env` loading |
| `BackendService.h` | validation, mutex, JSON shapes for the API and tests |
| `Console.h` | keyboard input, password input, session file, `loginGate`, `showRecipePage` |
| `UploadMenu.h` | upload, edit, delete, AI draft preview and save |
| `SearchMenu.h` | search loop and result display |
| `ReviewMenu.h` | rate, like/dislike, comment actions |
| `main.cpp` | top-level menu, one login, calls the three menu functions |

### 4.4 Refactor steps

1. **Freeze behavior**
   - Run `make test` and record 127 PASS.
   - Confirm `data/recipes.json` matches `seed/recipes.json`.

2. **Split the headers mechanically**
   - Move model classes into `Models.h`.
   - Move database classes into `Storage.h`.
   - Move fuzzy search into `Search.h`.
   - Move input/login/session/display into `Console.h`.
   - Move shared helpers into `Utils.h`.
   - Keep `AiRecipe.h` and `BackendService.h` as modules.
   - Do not change behavior while moving code.

3. **Convert the three console programs into menu functions**
   - `upload.cpp` → `runUploadMenu(...)`
   - `search.cpp` → `runSearchMenu(...)`
   - `rating.cpp` → `runReviewMenu(...)`
   - Each function receives the shared database, user database and `userId`.
   - Remove the per-program `main()` functions.

4. **Create `main.cpp`**
   - Load `RecipeDatabase` and `UserDatabase` once.
   - Log in once through `loginGate`.
   - Show the top-level menu:
     ```text
     1. Upload / edit / delete recipes
     2. Search recipes
     3. Rate / react / comment
     0. Exit
     ```
   - Call the matching menu function.

5. **Build one binary**
   ```bash
   g++ -std=c++17 -O2 -Wall -Wextra -pthread main.cpp -o tastehub -lcurl
   ./tastehub
   ```

6. **Keep the test separate**
   ```bash
   g++ -std=c++17 -O2 -Wall -Wextra -pthread backend_test.cpp -o backend_test -lcurl
   ./backend_test
   ```

7. **Update the build file**
   - `make` builds `tastehub` and `backend_test`.
   - `make test` runs `backend_test`.
   - Remove the old `upload`, `search` and `rating` targets.
   - Keep the build file local for now; decide later whether to track it.

8. **Update the docs**
   - Add the new file map to this plan.
   - Record the refactor in `devlog.md`.

### 4.5 Rules

- One console `.cpp` only: `main.cpp`.
- Headers may contain implementation because only one translation unit includes
  them.
- Never put `main()` in a header.
- Keep dependencies one-way:
  `Utils → Models → Storage → Search/AiRecipe → Console → Menus → main`.
- Domain, storage, search and AI headers must not include menu headers.
- Do not create one `.cpp` per model class. One `Models.h` is enough.
- Do not add a second `.cpp` to the console executable unless the core is first
  moved into a proper library.
- Keep `BackendService.h` free of console code.
- Keep `server.cpp` separate from the console.

### 4.6 Checkpoint

The refactor is done when:

```bash
make
make test
./tastehub
./backend_test
```

- `make test` still reports **127 PASS, 0 FAIL**.
- `./tastehub` offers upload, search and review from one menu.
- Login happens once per session.
- Searching with `briyani` still finds Chicken Biryani.
- AI yap upload still previews and saves.
- Rating with a proof image still works.
- `data/recipes.json` still matches `seed/recipes.json` after tests.
- No duplicate-symbol linker errors.

### 4.7 If the project grows later

Only then consider a core library:

```text
tastehub_core: Utils.cpp Models.cpp Storage.cpp Search.cpp Console.cpp AiRecipe.cpp
tastehub:      main.cpp + tastehub_core
tastehub-server: server.cpp + tastehub_core
```

Do not do this during Phase 0. The one-header-per-responsibility + one
`main.cpp` layout is enough for the demo.

---

## 5. Stage 2 — HTTP server

### Goal

Expose the backend as a JSON API without moving recipe logic into the HTTP
layer.

### Files

- `httplib.h` — vendored `cpp-httplib`.
- `server.cpp` — routes, request parsing, HTTP status mapping, startup flags.
- `BackendService.h` — already contains the backend operations.
- Build target `tastehub-server` — separate from the console.

`server.cpp` must not include `Console.h`, `UploadMenu.h`, `SearchMenu.h` or
`ReviewMenu.h`.

### Routes

| Method | Path | Action |
|---|---|---|
| `GET` | `/api/health` | Status + recipe count |
| `GET` | `/api/recipes` | List recipe summaries |
| `GET` | `/api/recipes/:id` | Recipe detail |
| `POST` | `/api/recipes` | Add a recipe/variant |
| `POST` | `/api/recipes/parse` | Gemini draft from free-form text; does not save |
| `PUT` | `/api/recipes/:id` | Edit a recipe |
| `DELETE` | `/api/recipes/:id` | Delete a recipe; remove an empty dish |
| `PUT` | `/api/recipes/:id/rating` | Rate 1–5 with optional proof image |
| `GET` | `/api/search?q=` | Fuzzy search |
| `GET` | `/api/leaderboard` | Rated recipes ranked by average |

### Error mapping

| Status | Meaning |
|---|---|
| `200` | OK |
| `201` | Recipe created |
| `400` | Invalid input |
| `404` | Recipe not found |
| `409` | Duplicate title in the same dish |
| `422` | AI could not extract ingredients or steps |
| `500` | Server or file error |
| `502` | Gemini request failed |
| `503` | Gemini missing, rate-limited or busy |

### Server behavior

- Run from the repository root so `seed/` and `data/` resolve.
- Use `--host 0.0.0.0 --port 8080 --data-dir data`.
- Use `std::mutex` for database access.
- Do not hold the mutex during the Gemini network call.
- Return JSON copies, never references to in-memory recipes.
- Keep the API on demo user `1`.
- `POST /api/recipes/parse` calls `BackendService::parseRecipeText`.
- A parsed draft is never saved by the parse endpoint.

### Build and run

```bash
g++ -std=c++17 -O2 -Wall -Wextra -pthread server.cpp -o tastehub-server -lcurl
./tastehub-server --host 0.0.0.0 --port 8080 --data-dir data
```

### Curl checks

```bash
curl http://localhost:8080/api/health
curl http://localhost:8080/api/recipes
curl http://localhost:8080/api/recipes/5
curl "http://localhost:8080/api/search?q=briyani"
curl http://localhost:8080/api/leaderboard
```

Also test add, parse, edit, rate with proof, delete and the error statuses.

### Checkpoint

- Every route works with `curl`.
- Typo search still finds the right recipe.
- AI parse returns a draft and does not save it.
- Rating with a proof image appears in list/detail/search/leaderboard data.
- Restarting the server preserves data.
- `./tastehub` and `./backend_test` still work.
- The server does not print console menus or prompt for input.

---

## 6. Stage 3 — Connectivity

### Goal

Open the API from the phone over a private network.

### Steps

1. Install Tailscale on the laptop and sign in.
2. Install Tailscale on the phone and sign in to the same tailnet.
3. Start the server:
   ```bash
   ./tastehub-server --host 0.0.0.0 --port 8080 --data-dir data
   ```
4. Allow port `8080` in the firewall if needed.
5. Open the phone browser and visit:
   ```text
   http://<laptop-tailscale-ip>:8080/api/health
   ```
6. If Android blocks cleartext HTTP, either:
   - allow cleartext for the debug build, or
   - use Tailscale Serve for HTTPS.

### Fallbacks

- Same Wi-Fi: use the laptop's LAN IP.
- USB: `adb reverse tcp:8080 tcp:8080`, then use `http://127.0.0.1:8080`.
- Phone hotspot: connect the laptop to the phone's hotspot and use the laptop's
  hotspot IP.

### Checkpoint

- The phone browser shows `{"status":"ok","recipes":6}` through Tailscale.
- At least one fallback connection has been tested.
- The laptop is set not to sleep during the demo.

---

## 7. Stage 4 — Flutter app

### Goal

Build the Android client.

### Steps

1. Install Flutter and Android tooling.
2. Create the project:
   ```bash
   flutter create tastehub_app
   ```
3. Add the `http` package.
4. Configure the API URL with `--dart-define=API_BASE_URL=...`.
5. Create the recipe model and API client.
6. Add widgets:
   - recipe image
   - rating stars
   - error view
   - recipe card
7. Add screens:
   - recipe list
   - recipe detail
   - add/edit recipe form
   - search
   - leaderboard
8. Add the AI flow:
   - user describes the dish
   - call `POST /api/recipes/parse`
   - show the draft
   - let the user edit/confirm
   - call `POST /api/recipes`
9. Add assets and YouTube handling.
10. Configure Android internet permission and cleartext HTTP for debug.
11. Test on the Linux desktop first, then build the debug APK.

### Checkpoint

- The app lists recipes.
- It opens recipe detail with ingredients, steps, ratings and proof images.
- It adds and edits a recipe.
- Search finds `briyani` → Chicken Biryani.
- Rating updates the leaderboard.
- AI draft preview works; cancelling does not save.
- The APK runs on the phone over Tailscale.

---

## 8. Stage 5 — Demo polish

### Steps

1. Verify the AI flow end to end:
   - natural-language input
   - structured draft
   - confirmation
   - saved recipe
   - fallback to the manual form when Gemini is unavailable
2. Add real images and YouTube links.
3. Add/verify the reset script:
   ```bash
   ./scripts/reset-demo.sh
   ```
4. Run the API smoke test.
5. Run the full demo script twice.
6. Final checklist:
   - server starts from the repo root
   - phone connects
   - list/detail/add/edit/search/rate/leaderboard work
   - AI draft works or fails with a clear message
   - restart preserves data
   - seed reset works
   - no secret is committed

### Checkpoint

The full demo runs twice in a row without code changes or manual file edits.

---

## 9. Data, ratings and configuration reference

### Data files

| Path | Purpose |
|---|---|
| `seed/recipes.json` | Clean tracked demo data (6 recipes) |
| `data/recipes.json` | Runtime data; reset from the seed |
| `users.json` | CLI accounts; user `1` is the demo user |
| `session.txt` | CLI session |
| `.env` | Local `GEMINI_API_KEY` and `GEMINI_MODEL`; git-ignored |

### Rating rules

- One rating per demo user per recipe.
- Stars are `1`–`5`.
- `proofImageRef` is optional.
- Omitting the proof keeps the existing proof.
- Sending an empty proof clears it.
- Ratings appear in list, detail, search and leaderboard data.

### AI configuration

```text
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-3.5-flash
```

- The key may also come from `GOOGLE_API_KEY`.
- `.env` is loaded from the current folder or its parent.
- The key is sent in the `x-goog-api-key` header.
- Errors redact the key.
- Model fallbacks are tried when a model is retired or busy.

### API details

The full request/response contract is in `API.md`. Keep that file updated when a
route changes.

---

## 10. Git and GitHub workflow

### 10.1 What belongs on GitHub

Tracked on GitHub:

- C++ source and headers
- `json.hpp`
- `Makefile`
- `seed/recipes.json`
- `scripts/`
- `tests/`
- `plan.md`
- `API.md`
- `.env.example`
- `.gitignore`

Local only (gitignored, never pushed):

- `devlog.md`
- `.env`
- `data/`
- `users.json`, `users.backup.json`, `session.txt`
- compiled binaries and temporary files

`techstack.md` and `handover/*.md` were folded into `plan.md` and removed from
GitHub. They remain recoverable from Git history if needed.

### 10.2 Removing a tracked file from GitHub but keeping it locally

Use `git rm --cached` and add the path to `.gitignore`:

```bash
git rm --cached devlog.md
# add devlog.md to .gitignore
git add .gitignore
git commit -m "docs: keep devlog local only"
git push origin main
```

Deleting a file from GitHub does not delete the local copy when `--cached` is
used. The old content also remains in Git history.

### 10.3 Commit the Phase 0 refactor

Use a branch so the refactor can be reviewed separately:

```bash
git switch -c refactor/header-split

# make the refactor
make test

git add Utils.h Models.h Storage.h Search.h AiRecipe.h Console.h \
        BackendService.h UploadMenu.h SearchMenu.h ReviewMenu.h main.cpp
git status
git diff --cached --stat
git commit -m "refactor: split headers and add single tastehub CLI"

git push -u origin refactor/header-split
```

Open a pull request or merge the branch into `main` after the checkpoint passes.

If you work directly on `main` instead:

```bash
git switch main
git pull --rebase origin main
# make changes, test, then:
git add <explicit files>
git commit -m "refactor: split headers and add single tastehub CLI"
git push origin main
```

### 10.4 General rules

- Stage explicit files. Do not use `git add -A` unless you just inspected
  `git status`.
- Never commit `.env`, `data/`, compiled binaries or generated APKs.
- Run `make test` before every commit that touches code.
- Keep docs and code in separate commits.
- Keep commits small and named after one change.
- Use normal `git push` for new commits.
- Use `git push --force-with-lease` only when intentionally rewriting a commit
  that was already pushed.
- If a commit includes the wrong file:
  ```bash
  git restore --staged <file>
  # or, if it was already committed:
  git reset --soft HEAD~1
  # fix the staging area, then commit again
  ```

---

## 11. Definition of done

The project is done when:

- `./tastehub-server --host 0.0.0.0 --port 8080 --data-dir data` starts.
- `curl http://localhost:8080/api/health` returns the recipe count.
- The phone opens the health endpoint over Tailscale.
- The APK lists, opens, adds, edits, searches and rates recipes.
- A typo search still finds the intended recipe.
- AI input produces a reviewable draft and saves only after confirmation.
- Ratings and proof images appear everywhere they should.
- Restarting the server preserves data.
- `./scripts/reset-demo.sh` restores the seed.
- The full demo has been run twice without errors.
- `make test` still passes.

---

## 12. Risks and notes

- Gemini model names change. Keep the fallback list and a friendly error path.
- Never commit the API key.
- Tailscale can fail; test a fallback connection before the demo.
- Keep the laptop awake during the demo.
- JSON files are safe for one server process only; do not run two servers on the
  same data folder.
- The demo uses user `1`; do not add real authentication for this scope.
- The build file is currently local/ignored. Decide later whether to track a
  Makefile or `CMakeLists.txt` for a reproducible clone.
- Do not split the model into one `.cpp` per class. One `Models.h` is enough.
- Do not add a second `.cpp` to the console executable until the core is moved
  into a library.
