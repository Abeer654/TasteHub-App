# Running TasteHub

Run all commands from the repository root.

## Requirements

- `g++` with C++17 support
- `make`
- `libcurl` development files (Debian/Ubuntu: `libcurl4-openssl-dev`)

## Build

```bash
make
```

This creates:

- `build/tastehub` — the console app
- `build/backend_test` — the Stage 1 acceptance test

## Run the tests

```bash
make test
```

The test is offline and uses a fake AI extractor. A successful run ends with:

```text
ALL STAGE 1 CHECKS PASSED
```

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
