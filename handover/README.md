# TasteHub Handover

This folder is the step-by-step build guide for the TasteHub demo.
Work through the stages in order. Each stage ends with a **checkpoint**.
Do not start the next stage until the checkpoint passes.

## The big picture

```text
Flutter APK (phone)
        |
        |  Tailscale private network
        v
C++ HTTP server (laptop)
        |
        v
JSON files (seed/ and data/)
```

- **C++ backend** = the kitchen: recipes, ratings, search, leaderboard.
- **HTTP server** = the waiter: turns API requests into backend calls.
- **Flutter app** = the customer: displays and edits recipes.
- **Tailscale** = the private road between the phone and the laptop.

## Stage index

| Stage | Guide | Goal | Done when |
|---|---|---|---|
| 1 | [`01-backend-brain.md`](01-backend-brain.md) | Turn the console code into a reusable backend | `./backend_test` prints correct JSON and typo search works |
| 2 | [`02-http-server.md`](02-http-server.md) | Expose the backend as an HTTP JSON API | Every endpoint works with `curl` |
| 3 | [`03-connectivity.md`](03-connectivity.md) | Connect the phone to the laptop | Phone browser shows `/api/health` via Tailscale |
| 4 | [`04-flutter.md`](04-flutter.md) | Build the Flutter app | App lists, opens, adds, searches, and rates recipes |
| 5 | [`05-demo-polish.md`](05-demo-polish.md) | Add AI formatting, images, YouTube, and demo checks | Full demo runs twice without surprises |

Supporting files:

- [`../API.md`](../API.md) — frozen API contract; Flutter must follow it.
- [`../techstack.md`](../techstack.md) — why each technology was chosen.
- `../seed/recipes.json` — clean demo data (6 recipes).
- `../scripts/clean_seed.py` — rebuilds the seed from the original data.
- `../scripts/reset-demo.sh` — resets `data/recipes.json` from the seed.
- `../tests/smoke_test.py` — API smoke test.

## How to use this without burning tokens

1. Open only the stage file you are working on.
2. Copy commands exactly. Run them from the repository root:
   ```bash
   cd ~/development/TasteHub-App
   ```
3. When something fails, collect:
   - the exact command you ran
   - the full error text
   - the file and function name
   Then ask for help with only that. Do not paste the whole project.
4. Commit after every checkpoint:
   ```bash
   git add -A
   git commit -m "Stage 1: backend brain complete"
   ```
5. Never skip a checkpoint to "fix it later". The stages depend on each other.

## Current state (before Stage 1)

- The backend is three console programs: `upload.cpp`, `search.cpp`, `rating.cpp`.
- They share `RecipeCore.h` and `ConsoleTools.h`.
- The code compiles, but:
  - data paths depend on the current folder
  - dates are mixed formats
  - saves are not atomic
  - search is not typo-tolerant
  - there is no HTTP server
  - there is no Flutter app
- `seed/recipes.json` is ready with 6 recipes, images, YouTube URLs, and ISO dates.
- `data/recipes.json` is a runtime copy (gitignored).
- Flutter is installed. Android SDK/JDK/NDK are **not** installed yet.
- Tailscale is **not** configured yet.

## Ground rules

- Keep the C++ OOP design. Do not rewrite from scratch.
- Keep each executable as **one `.cpp` file** for now. Header-defined functions
  can cause duplicate-symbol errors if you split into multiple translation units.
- The server must not include `ConsoleTools.h`.
- Do not add login, sessions, comments, votes, account deletion, image upload,
  SQLite, FFI, or Android NDK for this demo.
- Keep AI in Flutter, not C++.
- The demo user is always id `1`.
- Run the server from the repository root so `seed/` and `data/` resolve.

## Target file map

```text
TasteHub-App/
  API.md                  API contract
  techstack.md            technology choices
  RecipeCore.h            domain model + JSON storage
  BackendService.h        backend facade (new)
  backend_test.cpp        backend test program (new)
  server.cpp              HTTP server (new)
  CMakeLists.txt          build file (new)
  httplib.h               vendored HTTP library (new)
  seed/recipes.json       demo data (tracked)
  data/recipes.json       runtime data (gitignored)
  scripts/
    clean_seed.py
    reset-demo.sh
  tests/
    smoke_test.py
  handover/
    01-backend-brain.md
    02-http-server.md
    03-connectivity.md
    04-flutter.md
    05-demo-polish.md
  tastehub_app/           Flutter app (created in Stage 4)
```

## Commit plan

```bash
# after Stage 1
git add -A
git commit -m "Stage 1: backend brain and clean seed"

# after Stage 2
git add -A
git commit -m "Stage 2: HTTP JSON API"

# after Stage 3 (documentation only)
git add -A
git commit -m "Stage 3: Tailscale connectivity notes"

# after Stage 4
git add -A
git commit -m "Stage 4: Flutter app"

# after Stage 5
git add -A
git commit -m "Stage 5: AI formatting, images, demo polish"
```

If a stage breaks, you can always return to the last commit:

```bash
git log --oneline
git restore .
```

## Definition of done

The demo is ready when:

- `./build/tastehub-server --host 0.0.0.0 --port 8080 --data-dir data` starts.
- `curl http://localhost:8080/api/health` returns `{"status":"ok","recipes":6}`.
- The phone opens `http://<tailscale-ip>:8080/api/health` in its browser.
- The APK lists recipes, opens one, adds one, searches with a typo, rates one,
  and shows the leaderboard.
- Restarting the server keeps the data.
- The full demo has been run twice without errors.
