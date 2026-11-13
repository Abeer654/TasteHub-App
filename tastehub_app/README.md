# TasteHub Flutter app

The Android/Linux client for the TasteHub C++ server. It uses the JSON API in
[`../API.md`](../API.md).

## Features

- Real login and signup with saved bearer tokens; expired sessions return to the
  login screen
- Home screen grouped by dish, with **All dishes** and **My recipes** filters
- Recipes ranked **inside each dish**: average rating, rating count, newest
  first; unrated recipes are marked **New** and the best rated is **Top pick**
- Recipe detail with ingredients, steps, per-user ratings, proof photos and
  YouTube links
- Add and edit recipes, including AI drafts you review before saving
- Photo upload from the device gallery/file picker, or an image URL
- Owner-only edit and delete; any logged-in user can rate
- System / Light / Dark theme, persisted with `shared_preferences`
- Typo-tolerant search, grouped by dish

Seed recipes have no photo on purpose; the app shows a warm gradient
placeholder until a user uploads one or adds a URL.

## Demo accounts

| Username | Password | User id |
|---|---|---|
| `junaid` | `tastehub` | `1` |
| `guest` | `guest` | `2` |

Each account has one active session, so logging in on another device replaces
the previous token.

## Run on Linux desktop

Start the server from the repository root first:

```bash
make run
```

Then, from this folder:

```bash
flutter run -d linux --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

The default URL is already `http://127.0.0.1:8080`, so `flutter run -d linux`
works too.

The first screen is the login screen. Use a demo button or create an account,
then pick a dish to see its ranked recipes.

## Build for Android

The server must bind to an address the phone can reach:

```bash
make demo
```

Build a debug APK with the laptop's LAN or Tailscale IP:

```bash
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://100.x.y.z:8080
```

Debug builds allow cleartext HTTP for the demo. Release builds would need an
HTTPS endpoint or an explicit cleartext policy.

## Checks

```bash
flutter analyze
flutter test
dart run tool/api_smoke.dart http://127.0.0.1:8080
```

`flutter test` covers auth/session restore, dish grouping and ranking, API
uploads, theme persistence and the main widget flows. `api_smoke.dart` checks
the app's models against a live server, including login, dish grouping and the
per-dish top recipe.

## Where things live

- `lib/services/api_client.dart` — the only HTTP code; bearer token and
  multipart upload
- `lib/services/session_controller.dart` — login, signup, logout, token restore
- `lib/services/theme_controller.dart` — System/Light/Dark persistence
- `lib/utils/ranking.dart` — dish grouping and the shared ranking rules
- `lib/screens/home_screen.dart` — dish grid, filters and search
- `lib/screens/dish_screen.dart` — ranked recipes inside one dish
- `lib/screens/recipe_form_screen.dart` — device photo upload and image URL
- `lib/screens/recipe_detail_screen.dart` — owner actions, rating and proof
- `lib/theme.dart` — `TasteHubColors` light/dark theme extension
