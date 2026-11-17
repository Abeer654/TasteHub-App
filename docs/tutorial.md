# Running TasteHub

Run all commands from the repository root.

## Requirements

- `g++` with C++17 support
- `make`
- `libcurl` development files (Debian/Ubuntu: `libcurl4-openssl-dev`)
- `python3` for the HTTP smoke test
- Flutter 3.47+ for the desktop/mobile app (optional for the server only)

## Build

```bash
make
```

This creates:

- `build/backend_test` — the backend acceptance test
- `build/tastehub-server` — the HTTP server

To build only the HTTP server:

```bash
make server
```

## Run the tests

```bash
make test
```

The backend test is offline and uses a fake AI extractor. A successful run ends
with:

```text
ALL BACKEND CHECKS PASSED
```

The HTTP server has its own smoke test:

```bash
make http-test
```

It starts a temporary server with a temporary data and uploads folder, checks
authentication, ownership, per-user ratings, dish rankings, image uploads and
persistence across a restart, then deletes the temporary data. It does not touch
the real `data/` folder.

The Flutter app has its own checks:

```bash
make app-test
```

This runs `flutter analyze` and the model, ranking, session, theme and widget
tests. HTTP is mocked, so no server is needed.

To rebuild from scratch:

```bash
make clean
make
```

## Demo accounts

| Username | Password | User id |
|---|---|---|
| `junaid` | `tastehub` | `1` |
| `guest` | `guest` | `2` |
| `critic` | `critic` | `3` |

Each account has one active session. Logging in on another device replaces the
previous token, which is useful for showing that recipes and ratings stay
separate. Nobody can rate a recipe they authored - the `critic` account exists
so the demo data still has recipes with ratings from several different users.

## Run the HTTP server

The easiest way is `make run`:

```bash
make run
```

This builds the server if needed, then starts it on `127.0.0.1:8080` using the
normal `data/` and `data/uploads/` folders. Stop it with `Ctrl+C`.

A normal startup looks like this:

```text
TasteHub HTTP server
  host:    127.0.0.1
  port:    8080
  data:    data
  uploads: data/uploads
  recipes: 18
```

For a demo where a phone or another device must reach the server:

```bash
make demo
```

`make demo` is the same as `make run`, but binds to `0.0.0.0` so other devices on
the network can connect. Point the Flutter app at `http://<this-computer-ip>:8080`.

Change the port, data folder or uploads folder when needed:

```bash
make run PORT=9000
make run DATA_DIR=my-data
make run UPLOADS_DIR=my-data/photos
make demo PORT=9000
```

The equivalent long command, if you prefer to run the binary directly:

```bash
./build/tastehub-server --host 127.0.0.1 --port 8080 \
  --data-dir data --uploads-dir data/uploads
```

The server reads and writes `recipes.json` and `users.json` in the data folder.
It prints one line per request and never asks for console input.
Stop it with `Ctrl+C`.

Run only one server process against a data folder at a time. Two processes keep
separate in-memory copies, so editing from both at once can overwrite
changes.

Options:

```text
--host <address>      Interface to bind (default: 127.0.0.1)
--port <number>       TCP port to listen on (default: 8080)
--data-dir <path>     Folder holding recipes.json and users.json (default: data)
--uploads-dir <path>  Folder for uploaded photos (default: <data-dir>/uploads)
-h, --help            Show help
```

Use `--host 0.0.0.0` when another device needs to reach the server. Keep
`127.0.0.1` for normal local development.

Only one server can use a port at a time. If the port is already busy, startup
fails with:

```text
ERROR: could not listen on 127.0.0.1:8080
```

Stop the other server or choose another port with `make run PORT=8081`.

### Quick API checks

With the server running in another terminal, public reads need no token:

```bash
curl http://127.0.0.1:8080/api/health
curl http://127.0.0.1:8080/api/recipes
curl http://127.0.0.1:8080/api/recipes/5
curl "http://127.0.0.1:8080/api/search?q=briyani"
curl "http://127.0.0.1:8080/api/leaderboard?dish=Biryani"
```

Log in and keep the token for the write examples:

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"junaid","password":"tastehub"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')

curl http://127.0.0.1:8080/api/auth/me \
  -H "Authorization: Bearer $TOKEN"
```

Create a recipe:

```bash
curl -X POST http://127.0.0.1:8080/api/recipes \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "dish": "Biryani",
    "title": "Test Biryani",
    "mainIngredient": "rice",
    "ingredients": ["rice", "chicken", "spices"],
    "steps": ["mix everything", "cook until ready"],
    "cookingTime": 45
  }'
```

Upload a real photo and use the returned `/uploads/...` path on a recipe or a
rating proof:

```bash
curl -X POST http://127.0.0.1:8080/api/images \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@/path/to/my-biryani.jpg"
```

Rate it with an optional proof image (recipe 7 belongs to `guest`, so
`junaid`'s token is allowed; rating a recipe you authored yourself answers
`403`):

```bash
curl -X PUT http://127.0.0.1:8080/api/recipes/7/rating \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"stars": 5, "proofImageRef": "/uploads/img_example.jpg"}'
```

Delete it (only the owner can edit or delete):

```bash
curl -X DELETE http://127.0.0.1:8080/api/recipes/7 \
  -H "Authorization: Bearer $TOKEN"
```

Ask the AI for a draft (requires a Gemini key; this does not save anything):

```bash
curl -X POST http://127.0.0.1:8080/api/recipes/parse \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"text":"I made chicken biryani with rice, chicken, yogurt and spices."}'
```

The full request and response contract is in `API.md`.

## Run the Flutter app

The client lives in `tastehub_app/`. It talks to the same JSON API.

### Linux desktop

Start the server in one terminal:

```bash
make run
```

Start the app in a second terminal:

```bash
make app-run
```

The app opens on a login screen. Use one of the demo buttons or create an
account. After login:

- Home groups recipes into dishes, with **All dishes** and **My recipes** filters.
- Tapping a dish opens its recipes ranked #1, #2, #3. The best rated recipe is
  highlighted as **Top pick**; unrated recipes are marked **New** and come last.
- Any logged-in user can rate a recipe and attach a proof photo.
- Only the recipe owner sees **Edit** and **Delete**.
- Add recipe offers manual entry or an AI draft. Photos can be uploaded from the
  device (JPEG/PNG/WebP, up to 10 MB) or added as an image URL.
- The brightness menu switches between **System**, **Light** and **Dark**; the
  choice is saved between launches.

The old global leaderboard tab is gone. Rankings are always inside a dish.

Use a different server URL if needed:

```bash
make app-run APP_API_URL=http://127.0.0.1:9000
```

Build a release binary without starting it:

```bash
make app-build
./tastehub_app/build/linux/x64/release/bundle/tastehub_app
```

### Android

The phone must reach the server over the network. Start demo mode:

```bash
make demo
```

Build a debug APK with the laptop's LAN or Tailscale IP:

```bash
make app-apk APP_API_URL=http://100.x.y.z:8080
```

Install it with
`adb install -r tastehub_app/build/app/outputs/flutter-apk/app-debug.apk`.
This requires the Android SDK and `adb`, which `flutter doctor` checks.

Debug builds allow plain HTTP for the demo. A release build would need HTTPS or
an explicit cleartext policy.

### App checks

```bash
make app-test       # flutter analyze + tests, no server needed
make app-api-check  # hit a running server with the app's API client
```

`make app-api-check` logs in as `junaid`, reads the real server, groups recipes
by dish and logs out. A successful run looks like:

```text
health:     ok (18 recipes)
login:      junaid (user 1)
recipes:    18
detail:     Crispy Fries (4 ingredients, 4 steps)
search:     3 result(s) for "briyani" - first: Chicken Biryani
dishes:     6
  Biryani: 3 recipe(s), top Chicken Biryani 5.0
  ...
```

## Optional: real Gemini check

AI mode needs a Gemini API key. Create `.env` from the example and fill it in:

```bash
cp .env.example .env
```

Then set `GEMINI_API_KEY` in `.env`. The model can be changed with `GEMINI_MODEL`.

To make one real network call:

```bash
make gemini-smoke
```
