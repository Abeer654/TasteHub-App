# TasteHub Flutter app

The Android/Linux client for the TasteHub C++ server. It uses the JSON API in
[`../API.md`](../API.md).

## Features

- Real login and signup with saved bearer tokens; expired sessions return to the
  login screen
- Home screen grouped by dish, with **All dishes** and **My recipes** filters
- Recipes ranked **inside each dish**: average rating, rating count, newest
  first; unrated recipes are marked **New** and the best rated is **Top pick**
- Recipe detail with ingredients, steps, per-user ratings, rating photos and
  YouTube links
- Add and edit recipes, including AI drafts you review before saving
- Photo upload from the device gallery/file picker, or an image URL
- Owner-only edit and delete; any logged-in user can rate
- Unsaved-changes guard and a sticky save bar on the recipe form
- System / Light / Dark theme, persisted with `shared_preferences`
- Typo-tolerant search, grouped by dish

Seed recipes have no photo on purpose; the app shows a warm gradient
placeholder until a user uploads one or adds a URL.

### Recipe photo vs rating photo

These are deliberately separate and should stay that way:

| | Recipe photo | Rating photo |
|---|---|---|
| Field | `imageRef` | `proofImageRef` / `myRatingProofImageRef` |
| Where | dish card and detail hero | your rating card and other ratings |
| Edited with | `RecipePhotoField` on the form | `RatingPhotoDialog` on the detail screen |
| Shown once? | one main photo | your photo only in **Your rating**, never in **Other ratings** |

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
- `lib/theme.dart` — `TasteHubColors`, spacing/radii tokens, shared theme
- `lib/widgets/` — shared pieces used by more than one screen:
  `section_card.dart`, `proof_thumbnail.dart`, `recipe_photo_field.dart`,
  `recipe_thumbnail.dart`, `rating_stars.dart`, `status_views.dart`,
  `dish_card.dart`

## Screen sections (small hand-off units)

Each screen is an orchestrator plus small section files. A section can be
changed without reading the whole app; each file header states what it owns.

### Home and dish

| File | Owns |
|---|---|
| `lib/screens/home_screen.dart` | title bar, search, filters, add-recipe sheet, empty states |
| `lib/widgets/dish_card.dart` | one dish card; top-pick/new badges and search matches |
| `lib/screens/dish_screen.dart` | dish hero, “Best rated first” explainer, ranked rows |

### Recipe detail

`recipe_detail_screen.dart` loads the recipe and owns actions (rate, edit,
delete). The visual pieces are independent:

| File | Owns |
|---|---|
| `lib/screens/recipe_detail/recipe_hero.dart` | main photo, title overlay, add-photo shortcut |
| `lib/screens/recipe_detail/recipe_overview.dart` | owner/time/ingredient/rating chips |
| `lib/screens/recipe_detail/ingredients_card.dart` | ingredient checklist |
| `lib/screens/recipe_detail/steps_card.dart` | numbered cooking steps |
| `lib/screens/recipe_detail/recipe_rating_section.dart` | your stars, your rating photo |
| `lib/screens/recipe_detail/community_ratings.dart` | other people’s ratings |
| `lib/screens/recipe_detail/rating_photo_dialog.dart` | rate + attach a rating photo |

### Recipe form

`recipe_form_screen.dart` owns controllers, upload, save and the dirty-form
guard. The sections are independent:

| File | Owns |
|---|---|
| `lib/screens/recipe_form/basics_fields.dart` | title, dish, ingredient, time, YouTube |
| `lib/screens/recipe_form/ingredient_editor.dart` | ingredient rows |
| `lib/screens/recipe_form/step_editor.dart` | numbered step rows |
| `lib/screens/recipe_form/ai_draft_banner.dart` | review note for AI drafts |
| `lib/screens/recipe_form/save_bar.dart` | sticky Save / unsaved-changes bar |

To hand a section to another model, share that file, `lib/theme.dart` (tokens),
and the shared widgets it imports — most sections use only `section_card.dart`
and one of `rating_stars.dart` or `proof_thumbnail.dart`. The file headers
describe the inputs and ownership.
