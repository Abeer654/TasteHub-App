# Running TasteHub

Run all commands from the repository root.

## Requirements

- `g++` with C++17 support
- `make`
- `libcurl` development files (Debian/Ubuntu: `libcurl4-openssl-dev`)
- `python3` for the HTTP smoke test

## Build

```bash
make
```

This creates:

- `build/tastehub` — the console app
- `build/backend_test` — the Stage 1 acceptance test
- `build/tastehub-server` — the Stage 2 HTTP server

To build only the HTTP server:

```bash
make server
```

## Run the tests

```bash
make test
```

The test is offline and uses a fake AI extractor. A successful run ends with:

```text
ALL STAGE 1 CHECKS PASSED
```

The HTTP server has its own smoke test:

```bash
make http-test
```

This starts a temporary server with a temporary data folder, checks every API
route, restarts the server to prove persistence, and deletes the temporary data.
It does not touch `data/recipes.json`.

To rebuild from scratch:

```bash
make clean
make
```

## Run the CLI

```bash
./build/tastehub
```

The first screen lets you log in or create an account. The main menu then offers:

1. Upload / edit / delete recipes
2. Search recipes
3. Rate / react / comment
4. Account settings
0. Exit

Runtime data is stored in `data/`. To reset the demo recipes from the clean seed:

```bash
./scripts/reset-demo.sh
```

## Run the HTTP server

The easiest way is `make run`:

```bash
make run
```

This builds the server if needed, then starts it on `127.0.0.1:8080` using the
normal `data/` folder. Stop it with `Ctrl+C`.

A normal startup looks like this:

```text
TasteHub HTTP server
  host:    127.0.0.1
  port:    8080
  data:    data
  recipes: 6
```

Open http://127.0.0.1:8080 in Chrome. The built-in page lists recipes, searches
them, shows the leaderboard and opens a recipe's ingredients and steps. It is
plain HTML and JavaScript and uses the JSON API below.

For a demo where a phone or another device must reach the server:

```bash
make demo
```

`make demo` is the same as `make run`, but binds to `0.0.0.0` so other devices on
the network can connect. On the other device, open `http://<this-computer-ip>:8080`
in its browser.

Change the port or data folder when needed:

```bash
make run PORT=9000
make run DATA_DIR=my-data
make demo PORT=9000
```

The equivalent long command, if you prefer to run the binary directly:

```bash
./build/tastehub-server --host 127.0.0.1 --port 8080 --data-dir data
```

The server reads and writes the same `data/recipes.json` as the console app. It
prints one line per request and never asks for console input. Stop it with
`Ctrl+C`.

Run only one process against a data folder at a time. The console app and the
server keep separate in-memory copies, so editing from both at once can overwrite
changes.

Options:

```text
--host <address>   Interface to bind (default: 127.0.0.1)
--port <number>    TCP port to listen on (default: 8080)
--data-dir <path>  Folder holding recipes.json (default: data)
-h, --help         Show help
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

With the server running in another terminal:

```bash
curl http://127.0.0.1:8080/api/health
curl http://127.0.0.1:8080/api/recipes
curl http://127.0.0.1:8080/api/recipes/5
curl "http://127.0.0.1:8080/api/search?q=briyani"
curl http://127.0.0.1:8080/api/leaderboard
```

Create a recipe:

```bash
curl -X POST http://127.0.0.1:8080/api/recipes \
  -H "Content-Type: application/json" \
  -d '{
    "dish": "Biryani",
    "title": "Test Biryani",
    "mainIngredient": "rice",
    "ingredients": ["rice", "chicken", "spices"],
    "steps": ["mix everything", "cook until ready"],
    "cookingTime": 45
  }'
```

Rate it with an optional proof image:

```bash
curl -X PUT http://127.0.0.1:8080/api/recipes/7/rating \
  -H "Content-Type: application/json" \
  -d '{"stars": 5, "proofImageRef": "https://example.com/my-biryani.jpg"}'
```

Delete it:

```bash
curl -X DELETE http://127.0.0.1:8080/api/recipes/7
```

Ask the AI for a draft (requires a Gemini key; this does not save anything):

```bash
curl -X POST http://127.0.0.1:8080/api/recipes/parse \
  -H "Content-Type: application/json" \
  -d '{"text":"I made chicken biryani with rice, chicken, yogurt and spices."}'
```

The full request and response contract is in `API.md`.

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
