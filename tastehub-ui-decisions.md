# TasteHub UI Spec — Decisions

Date: 2026-11-16
Input: `tastehub-ui-spec.md` (spec IDs like `H-01` refer to that file)
Status: decisions only — except **D-04 (§2) and Phases 1 + 2 (§5), which are
now implemented**: D-04 fully (server 403, UI hidden, seed re-homed, docs
amended) and both UI phases shipped on 2026-11-17 (`flutter analyze` clean,
65 app tests green). Deferred (§3), rejected (§4) and Phase 3+ (§5) remain
decisions only.

Every spec item is classified below. Reference these IDs when implementing:
**ADOPT** = implement as written · **MODIFY** = implement with the noted change ·
**DEFER** = correct, but needs backend/API work or its own stage ·
**REJECT** = conflicts with project rules or fakes a feature ·
**DONE** = already implemented; verify only.

---

## 1. Items already implemented (verify, do not rebuild)

| ID | Why it's already done |
|---|---|
| R-01 | `recipe_detail_screen.dart` renders **one template** for every recipe: `RecipeHero` → `RecipeOverview` → ingredients → steps → rating → community → YouTube. The spec's "variant A has no hero/chips" observation is outdated. |
| R-06 (owner-only edit) | App bar actions are already inside `if (_isOwner)`; non-authors never see pencil or overflow. |
| H-07 (clear button) | Search field already shows a trailing × when text is present. |
| E-06 (dirty guard) | Recipe form already has the unsaved-changes dialog and sticky save bar (see `tastehub_app/README.md`). |
| G-06 (partial) | Error, empty and loading views already exist via `status_views.dart`; only skeletons and AI-cancel polish are missing. |

---

## 2. Conflicts with project rules — MODIFIED or REJECTED

### D-05 + H-01 · Top pick threshold — **MODIFY**
- Spec rule `v ≥ 3 AND R ≥ 4.5` → **no dish in the sample data qualifies**
  (highest rating count is 2), so every badge would vanish.
- `docs/plan.md` checkpoint requires *"Top pick and New labels where
  appropriate"* — strict spec compliance breaks the demo acceptance criteria.
- **Decision:**
  - Adopt the Bayesian smoothing formula for **"Best: …" ordering** as
    written (it is a genuine improvement over raw average).
  - Badge threshold becomes **`v ≥ 2 AND R ≥ 4.5`**: strong dishes keep the
    badge, weak ones lose it → still satisfies design principle 1
    ("a badge must mean something") without emptying the UI.
- Accept (adjusted): Biryani's best (5.0, 2 ratings) **keeps** the badge; a
  4.0-from-1 recipe's dish shows none.

### D-04 · Author cannot rate own recipe — **ADOPTED (full ban, implemented 2026-11-16)**

Originally rejected here to protect `docs/plan.md` §9 and the CLI demo flow;
on discussion the project chose to **do the ban properly instead**:

- **Server:** `BackendService::rateRecipe` throws `403 "You cannot rate your
  own recipe"`; `API.md` documents it; both test suites assert it
  (`backend_test.cpp`, `smoke_test.py`).
- **UI:** the detail screen hides the star picker and rating-photo controls
  for authors — the "Your rating" card becomes a read-only **Community
  rating** card (`canRate: !_isOwner` in `recipe_rating_section.dart`).
- **CLI:** `ReviewMenu.h` prints "You wrote this recipe, so you cannot rate
  it" before the star prompt (the CLI writes the DB directly, so it mirrors
  the rule itself).
- **Data:** all 15 seed + 1 demo self-ratings were **re-homed** to a new
  third account `critic / critic` (id 3) — every count and average stays
  identical (`5.0 (2)` remains `5.0 (2)`), so the `v ≥ 2` badge threshold
  and the spec's sample data still hold. Health check is now
  `21 recipes and 3 users`.
- **Docs:** `plan.md` §9 + definition of done, `API.md`, `tutorial.md`,
  app `README.md`, `devlog.md` amended.

### H-02 · FAB — **MODIFY**
- Adopt: list bottom content padding **96dp** (current code uses 156dp, sized
  for the old extended FAB; an icon-only FAB needs 56 + 16 + margin ≈ 96).
- Reject: converting back to an extended/collapsing FAB — the icon-only
  circular FAB was an explicit choice on 2026-11-15 (see `issuewithapk.md`
  #2d) after the extended FAB was judged too intrusive.

---

## 3. Items needing the C++ backend — DEFER (separate stage)

These are correct but cannot be done client-side; they change `Models.h`,
`Storage.h`, `BackendService.h`, `API.md`, the server routes and both test
suites. Schedule as a **Stage 6 backend + API** effort before the dependent UI:

| ID | Depends on | Blocked UI |
|---|---|---|
| D-01 structured ingredients | schema + JSON migration + API contract | E-04 editor, R-02 quantity column |
| D-02 servings | `Recipe.servings` field + API | R-02 servings stepper & scaling |
| D-03 step timers | `Step.timerSeconds` + API | R-05 timer chips, R-07 timers |

---

## 4. REJECT

| ID | Reason |
|---|---|
| S-02 (YouTube import row) | Spec itself says omit when the AI pipeline cannot ingest links — it cannot. |
| R-06 (Share / Report) | No backend endpoints and no per-recipe URLs exist to share. Faking them violates design principle 1. Owner Edit/Delete already works; leave the rest. |

(D-04 was originally rejected here; it has since been **adopted and
implemented** — see §2.)

---

## 5. ADOPT — implement as written

### Phase 1 · quick wins (half a day) — **implemented 2026-11-17**
| ID | Note |
|---|---|
| G-01 | Lighten `muted` to `#C4BAAE`; add `accentOnDark #F0A27F` for accent text < 18sp. |
| G-02 | Body `letterSpacing: 0` in `theme.dart`; uppercase labels may keep +0.8. |
| G-05 + M-03 | No empty star rows: cards show `★ 4.5 (2)` compact, unrated shows the outlined **New** chip. (`rating_stars.dart` currently always draws five stars; `recipe_list_card.dart` uses `notRatedText: 'New - not rated'`.) |
| H-07 (text) | Placeholder → "Search recipes or ingredients"; clear button already exists. Recent-searches list = optional add-on. |
| S-01 | Remove "Gemini" from user-facing text — 3 places: `home_screen.dart` add sheet, `ai_recipe_screen.dart` ×2. |
| R-03 (cleanup) | Delete "No recipe photo yet - add one above" and the duplicate corner "Add photo" pill in `recipe_hero.dart`; keep exactly one add-photo control. |
| E-01 | Dish field rendered locked: 60% opacity, lock icon, no focus, helper "Locked after creation." |
| H-02 (padding) | See §2 — 96dp bottom padding only. |

### Phase 2 · trust and consistency (1–2 days) — **implemented 2026-11-17**
| ID | Note |
|---|---|
| D-05 + H-01 | Per §2 modified rule; smoothing in `utils/ranking.dart` so dish cards and dish page share it. |
| H-06 + M-05 | Dish-name → food-icon lookup with generic fallback; letter placeholder replaced (32dp in list thumbnails, 48dp in hero/cards). |
| H-04 | Counts move into chips ("All dishes · 8"); remove the separate count line. |
| H-05 + M-02 | Fixed 112dp dish card / 88dp recipe card layouts as specced, incl. cooking-time range line and ⋮ overflow menu (Edit / Add photo / Delete with dialog) replacing the chevron. |
| M-01 | Sticky dish section headers in My recipes + `Grouped | Flat | Recent` segmented control. |
| M-04 | Dynamic subtitle `14 recipes · N need photos`, tappable filter. |
| E-02 | Strict YouTube URL validation (watch/youtu.be/shorts/m.youtube only), paste button, 16:9 preview; existing `/results?` URL must fail. |
| E-03 | Numeric-only time field with 15/30/45/60 quick chips. |
| G-06 | Skeleton cards for loading; keep existing error/empty views; AI progress bar + Cancel. |
| H-03 | Collapsing header: expanded wordmark+tagline → 56dp bar after 56dp scroll, sticky 48dp search, theme toggle moves into avatar menu. Biggest item in this phase. |
| R-04 | Rating distribution bottom sheet + instant feedback. Authors see the distribution but no rating control (D-04, §2). |

### Phase 3+ · adopt later (client-only)
| ID | Note |
|---|---|
| R-08 | YouTube thumbnail card — small, can be pulled forward. |
| S-03 | AI draft opens the Edit form prefilled with the review banner (replaces current preview flow in `ai_recipe_screen.dart`). |
| G-03 + G-04 | 48dp touch-target and accessibility-label pass. |
| R-07 | Cook mode — build last. |

---

## 6. Recommended order (replaces the spec's §9 checklist)

1. **Phase 1** above (quick wins) — build, install, eyeball on phone.
2. **Phase 2**: badge/ranking logic → placeholders → counts → cards →
   My-recipes grouping → form validations → states → collapsing header.
3. **Stage 6 (backend)**: D-01/D-02/D-03 through `API.md`, server, tests.
4. **Phase 3**: E-04, R-02 quantities/servings, R-05 timers, then R-07/S-03/R-08.
5. Re-run `make test`, `make http-test`, `make app-test`, rebuild
   `app-release.apk`, reinstall on the phone.

## 7. Open questions for the spec author

- H-02 extended/collapsing FAB was rejected in favour of the icon-only FAB —
  confirm if this matters.
- ~~D-04's author-rating ban needs a plan/API amendment decision~~ — resolved:
  adopted and implemented on 2026-11-16 (§2).
- R-02's servings stepper and quantity scaling are unimplementable until
  D-01/D-02 land — the ingredients card should stay name-only until then.
