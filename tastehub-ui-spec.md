# TasteHub — Self-Contained UI Change Spec

This document needs **no screenshots**. Every screen is described as it exists today, followed by the exact changes to make, with measurements and acceptance criteria. Hand this file to a developer or an AI coding assistant as the only input.

**How to read it**
- Each change has an ID (e.g. `H-01`). Reference IDs in commits and PRs.
- **Current** = what the screen does now. **Change** = what to build. **Accept** = how to verify it.
- Priority: **P0** = broken or misleading, do first. **P1** = clear improvement. **P2** = polish.
- Units are Android-style (`dp` for sizes, `sp` for text). If your framework differs (Flutter logical pixels, etc.), treat 1dp = 1 logical px.
- The framework is not stated in the source. Specs are framework-agnostic and assume **Material 3 conventions** (top app bar, FAB, bottom sheet, chips, snackbar).

---

## 0. App Overview

**TasteHub** is a mobile app (dark theme, orange accent) where users browse **dishes** (e.g. Biryani, Fries), each containing several **recipes**, and pick the best-rated one. Users can add their own recipes manually or have an AI draft one from a description (Google Gemini is used behind the scenes).

**Concepts**
- **Dish**: a category (Biryani, Chicken Tikka, Fried Fish, Fries, Pulao, ...). A recipe belongs to exactly one dish, permanently.
- **Recipe**: title, dish, main ingredient, cooking time (minutes), optional YouTube URL, optional photo, ingredients list, ordered steps, ratings, author (username).
- **Top pick / Best**: the highest-rated recipe within a dish.

**Sample data currently in the app** (use it for testing)
- 8 dishes, 21 recipes total. The current user (`junaid`) owns 14 recipes across 7 dishes.
- Dishes: Biryani (3 recipes, best "Chicken Biryani", 5.0 from 2 ratings), Chicken Tikka (3, best "Simple Chicken Tikka", 4.5 from 2), Fried Fish (1, best "Crispy Fried Fish", 4.5 from 2), Fries (4, best "Crispy Fries"), Pulao and others.
- Recipes: Crispy Fries (Fries, 20 min, 5.0 from 2), Loaded Cheese Fries (Fries, 30 min, 4.0 from 1), Cheese Fries (Fries, 30 min, unrated, has photo), Hydrabadi Pulao (Pulao, 45 min, 4.5 from 2), Chicken Biryani (5 ingredients, 4 steps, 5.0 from 2).

---

## 1. Design Tokens

Colors below are **approximate** (sampled by eye from the current dark theme). Keep the existing values if the codebase already defines them, and only add or adjust what this spec says.

| Token | Value | Use |
|---|---|---|
| `background` | `#121010` | Screen background |
| `surface` | `#201C18` | Cards, bottom sheet |
| `surfaceVariant` | `#2B2520` | Text fields, inner containers |
| `outline` | `#3A322B` | 1dp card/field borders |
| `onSurface` | `#F5EBE0` | Primary text (cream) |
| `onSurfaceVariant` | `#B8AEA3` → **lighten to `#C4BAAE`** | Secondary text (see G-01) |
| `accent` | `#E8845C` | Primary buttons, FAB, selected chip, small accent text |
| `accentOnDark` | `#F0A27F` | **New.** Accent for small text on dark surfaces (contrast) |
| `star` | `#F2B84B` | Rating stars |
| `success` | `#8FBF7F` | Positive states (currently the ingredient checkmarks) |
| `danger` | `#E57373` | Delete/destructive |

**Shape**
- Card radius: **20dp**. Chip radius: full (pill). Text field radius: **16dp**. Bottom sheet top radius: **28dp**. Image inside a card: radius = card radius − card padding (concentric).

**Spacing scale (use only these):** 4, 8, 12, 16, 24, 32 dp. Screen horizontal padding: **16dp**.

**Type scale (use only these)**

| Role | Size | Weight | Use |
|---|---|---|---|
| Display | 32sp | Bold | "TasteHub" wordmark (expanded header) |
| Title | 22sp | SemiBold | Detail screen recipe title, section titles |
| Card title | 20sp | SemiBold | Dish/recipe card titles |
| Subtitle | 16sp | Medium | Card section headers ("Ingredients") |
| Body | 14sp | Regular | Everything else; **letter-spacing 0** |
| Label | 12sp | Medium | Chips, badges, helper text; uppercase labels may use +0.8sp tracking |

Wordmark: "Taste" in `onSurface`, "Hub" in `accent`. Keep this.

---

## 2. Global / Cross-Screen Changes

### G-01 · Secondary text contrast · P2
**Current:** Grey secondary text (taglines, counts, subtitles, helper text) on near-black appears at or below 4:1 contrast. Small orange text ("3 recipes", "+ Add ingredient") is also borderline.
**Change:** Set `onSurfaceVariant` to `#C4BAAE`. Use `accentOnDark` for any accent text smaller than 18sp.
**Accept:** Every text/background pair measures ≥ 4.5:1 (body) or ≥ 3:1 (text ≥ 18sp) with a contrast checker.

### G-02 · Body letter-spacing · P2
**Current:** Body text (placeholders, subtitles, step text) shows loose tracking.
**Change:** Set letter-spacing to 0 for all Body text. Only Label-uppercase may have extra tracking.
**Accept:** No body style has positive letter-spacing in the theme file.

### G-03 · Touch targets · P1
**Change:** All tappable elements ≥ **48×48dp** (visual size may be smaller; pad the hit area). This includes the step delete "×", toolbar icons, chips, and the theme/user controls.

### G-04 · Content descriptions · P1
**Change:** Every icon-only control gets an accessibility label: theme toggle ("Toggle theme"), user chip ("Account menu"), edit pencil ("Edit recipe"), overflow ("More options"), FAB ("Add recipe"), step delete ("Delete step N").

### G-05 · Rating display rules · P0
Apply everywhere ratings appear:
- **No ratings** → no stars at all. Show a "New" chip instead (see `C-03`).
- **Compact rating** (cards): single star icon + number + count, e.g. `★ 4.5 (2)`.
- **Full rating** (detail screen only): five-star row + `4.5 from 2 ratings`.
- Never show five empty stars.

### G-06 · Required states · P1
Design and implement all of these (currently only the happy paths are visible):
1. **Home, empty** (no dishes): icon + "No dishes yet" + "Add a recipe" button.
2. **My recipes, empty:** icon + "You haven't added any recipes" + "Add your first recipe" button.
3. **Search, no results:** "No matches for '<query>'" + "Create this recipe" button that opens the Add sheet with the query prefilled as title.
4. **Loading:** skeleton cards matching the real card size (not a spinner).
5. **Error/offline:** message + "Retry" button, keeping any cached content visible.
6. **AI draft generating:** full-width progress indicator, "Cancel" button, and when done a persistent label "AI draft: check before saving".

---

## 3. Data Model Changes

Needed to support the UI changes. Adapt names to the existing schema.

### D-01 · Ingredient becomes structured · P0
**Current:** Ingredient = a single text string (e.g. `"rice"`).
**Change:** `Ingredient { name: string (required), quantity: number | null, unit: string | null }`. Units enum: `g, kg, ml, l, tsp, tbsp, cup, pcs, pinch, to taste`.
**Migration:** Existing string ingredients become `{ name: <old string>, quantity: null, unit: null }`. Display `name` only when quantity is null.

### D-02 · Recipe gets servings · P1
Add `servings: int` (default 4). Quantities are stored for this base serving count.

### D-03 · Step gets optional timer · P2
`Step { text: string (required), timerSeconds: int | null }`. Existing steps migrate with `timerSeconds = null`.

### D-04 · Ratings need author and de-duplication · P1
`Rating { recipeId, userId, value: 1..5 }` with a **unique constraint on (recipeId, userId)**. A recipe's author cannot rate their own recipe (reject server-side and hide the control client-side).

### D-05 · "Top pick" score · P0
Compute per dish, over its recipes:

```
m = 3                      // minimum votes before a rating is trusted
C = global average rating  // across all rated recipes
score(recipe) = (v / (v + m)) * R + (m / (v + m)) * C
// v = recipe rating count, R = recipe average
```

- **Best recipe of a dish** = highest `score` (used for the "Best: ..." line).
- **A dish earns the "Top pick" badge only if its best recipe has `v >= 3` AND `R >= 4.5`.**
- Ties: more ratings wins, then newest.

---

## 4. Screen: Home — "All dishes"

### Current layout (top to bottom)
1. Status bar.
2. Wordmark "TasteHub" (large, "Hub" in orange).
3. Tagline: "Pick a dish, then pick the best recipe."
4. A row with a half-filled-circle **theme toggle** icon, then a **user chip** (circle avatar "J", text "junaid", dropdown caret).
5. **Search field**, rounded, search icon, placeholder "Search dishes, recipes or ingredi…" (truncated).
6. Two **filter chips**: "All dishes" (selected, filled orange) and "My recipes" (outlined).
7. Count text: "8 dishes · 21 recipes".
8. Vertical list of **dish cards**. Each card: image on the left (about one third of card width, full card height, hard-edged), and on the right: dish name (large), "N recipes" in orange, "Best: <recipe title>" in grey, then a row of five stars + "5.0 (2)" at the bottom. A pill badge **"Top pick"** (trophy icon + text on a dark translucent background) sits at the top-left of the image on every card shown. Dishes without a photo show a flat gradient tile with a giant white initial letter (B, F).
9. Floating "+" button, bottom-right, 56dp, orange.

Everything above the first card (items 2–7) occupies about 40% of the screen height.

### H-01 · "Top pick" badge must be earned · P0
**Change:** Show the badge only when the rule in `D-05` is met. Otherwise render no badge.
**Badge style:** 12sp Label, trophy icon 14dp + "Top pick", background `#000000` at 65% opacity, 8dp horizontal / 4dp vertical padding, pill shape, positioned 8dp from the image's top-left corner.
**Accept:** With the sample data, Biryani (only 2 ratings) shows **no** badge. A dish whose best recipe has 3+ ratings and ≥ 4.5 average does.

### H-02 · FAB must not cover content · P0
**Change:** Set the list's bottom content padding to **96dp**. Convert the FAB to an **extended FAB** labelled "Add recipe" (icon + 14sp label), which collapses to icon-only while scrolling down and re-expands when scrolling up or at the top.
**Accept:** The last card scrolls fully above the FAB with at least 16dp gap. Nothing on any card is hidden by the FAB at rest.

### H-03 · Collapsing header · P1
**Change:** Replace the static header with a collapsing top app bar.
- **Expanded state (at top of list):** wordmark (Display 32sp) with the tagline below it (Body 14sp), and avatar button at the top-right of the wordmark row.
- **Collapsed state (after scrolling ≥ 56dp):** a single 56dp bar with the wordmark at 22sp on the left and the avatar on the right. The tagline disappears.
- The **search field** sits directly under the bar and becomes **sticky** (pins below the collapsed bar). Height 48dp.
- **Theme toggle moves into the avatar menu** as "Theme: Dark / Light / System". Remove the standalone icon.
- Show the tagline only until the user has added or opened a recipe once (persist a boolean flag); afterward show nothing under the wordmark.
**Accept:** At rest, the first card's top edge is at least 120dp higher than in the old layout. After scrolling, the collapsed bar and the pinned search field both remain visible.

### H-04 · Filter chips carry the counts · P2
**Change:** Chip labels become "All dishes · 8" and "My recipes · 14". **Remove** the separate "8 dishes · 21 recipes" line.
**Accept:** The count line no longer exists; counts update live as data changes.

### H-05 · Dish card layout · P1
**Change:**
- Fixed card height **112dp**. Image: 112dp wide square on the left, inset 8dp from the card edge, corner radius 12dp. (Replaces the full-bleed one-third-width image.)
- Text column, left-aligned, 12dp from the image: 
  1. Dish name, Card title 20sp, 1 line, ellipsis. 
  2. `N recipes · <min>–<max> min` (Body 14sp, `accentOnDark`; use a single value when min = max). 
  3. `Best: <recipe title>` (Body 14sp, `onSurfaceVariant`, 1 line, ellipsis). 
  4. Bottom row: compact rating per `G-05` (`★ 4.5 (2)`), or the "New" chip if none.
- Remove the vertical dead space between rows 3 and 4 by anchoring row 4 to the bottom with 12dp bottom padding and distributing rows 1–3 from the top.
**Accept:** All cards are exactly 112dp tall; no card shows five-star rows; cooking-time range appears on every card that has recipes with times.

### H-06 · Placeholder images · P1
**Current:** Giant white letter on a flat green/gold/teal gradient.
**Change:** Keep the dish-specific gradient hue. Replace the giant letter with a **48dp food icon** (rice bowl for Biryani, drumstick for Tikka/chicken, fish for Fried Fish, fries for Fries, bowl for Pulao, generic cutlery otherwise) in white at **40% opacity**, centred. Map dish names to icons with a lookup table and a generic fallback.
**Accept:** No placeholder shows a letter. A dish with an unknown name shows the generic cutlery icon.

### H-07 · Search field · P2
**Change:** Placeholder text becomes "Search recipes or ingredients" (fits without truncation at default font scale). Add a trailing clear (×) button when text is present. When focused with empty text, show up to 5 recent searches as a list under the field.
**Accept:** The placeholder is fully visible on a 360dp-wide screen.

---

## 5. Screen: Home — "My recipes" tab

### Current layout
Same header as Home. Tagline changes to "Every recipe you have added, in one list." The "My recipes" chip is selected. Below: "My recipes · 14 recipes", then "Grouped by dish · 7 dishes". Then recipe cards in a flat list (no visible group headers). Each card: square thumbnail on the left (about 86dp; photo or placeholder gradient with giant letter), recipe title, grey line "Fries · 20 min" (dish and cooking time), rating row (five stars + "5.0 (2)"), and a right-pointing chevron. A recipe with no ratings shows five **empty** outline stars and "New - not rated". The same FAB is shown.

### M-01 · Real grouping with section headers · P1
**Change:** Render a **sticky section header** per dish: `FRIES · 3 recipes` (Label 12sp, uppercase, +0.8sp tracking, `accentOnDark`, 16dp left padding, 8dp top / 4dp bottom padding, background = `background`). Recipe cards sit under their header. Sort groups by most recently added recipe; sort recipes within a group newest first.
Add a small segmented control above the list (right-aligned): **Grouped | Flat | Recent**. Default **Grouped**. Remove the "Grouped by dish · 7 dishes" and "My recipes · 14 recipes" lines (counts live in the chip per `H-04`).
**Accept:** With sample data, "FRIES · 3 recipes" appears once above Crispy Fries, Loaded Cheese Fries, and Cheese Fries.

### M-02 · Recipe card contents · P1
**Change:**
- Height **88dp**; thumbnail 72dp square, radius 12dp, 8dp inset.
- Line 1: recipe title (Card title 20sp → use 18sp here, 1 line, ellipsis).
- Line 2: `<cooking time> min · <main ingredient>` (Body 14sp, `onSurfaceVariant`). **Remove the dish name** (the section header now provides it, except in "Flat" and "Recent" modes where it is shown as `Dish · 20 min`).
- Line 3: compact rating per `G-05`.
- **Remove the chevron.** Replace it with a 48dp overflow icon button (⋮) with menu: Edit, Add photo, Delete (danger color, confirmation dialog).
**Accept:** No chevrons; overflow menu works; Delete asks "Delete '<title>'? This can't be undone." with Cancel/Delete.

### M-03 · "New" chip replaces empty stars · P0
**Change:** Recipes with zero ratings show a **"New"** chip: pill, 1dp `accentOnDark` outline, 12sp Label text `accentOnDark`, 8dp horizontal / 2dp vertical padding. No stars, no "not rated" text.
**Accept:** "Cheese Fries" displays the chip only.

### M-04 · Subtitle becomes useful · P2
**Change:** Replace "Every recipe you have added, in one list." with a dynamic line: `14 recipes · N need photos` (hide the second part if N = 0). Tapping "N need photos" filters the list to recipes without a photo.

### M-05 · Placeholder thumbnails · P1
Same rule as `H-06`: dish-specific icon at 32dp on the gradient, no letters. For the user's own photo-less recipes add a 20dp camera badge at the thumbnail's bottom-right corner (white circle, dark icon) that opens the photo picker.

---

## 6. Screen: Recipe Detail

Two variants exist today and **they must become one**.

### Current — variant A (e.g. "Chicken Biryani")
Top bar: back arrow, title "Chicken Biryani", pencil (edit) icon, overflow (⋮). Then a rating pill ("★★★★★ 5.0 from 2 ratings"). Then a card **"Ingredients · 5 items"** listing: rice, chicken, yogurt, spices, onion, each preceded by a **green check-in-circle** icon and separated by thin dividers. Then a card **"Cooking steps · 4 steps"** with numbered orange circles: 1 marinate the chicken, 2 fry the onions, 3 layer rice and chicken, 4 cook on low heat. Another card begins below (cut off). **No hero image, no author/time/main-ingredient chips.**

### Current — variant B (e.g. "Crispy Fries")
Top bar: back arrow, title "Crispy Fries", pencil, overflow. A **hero card** (~215dp tall, green gradient, giant letter "C", faint knife-and-spoon illustration at the bottom-right). Over it: a white pill button **"Add photo"** (camera icon) at the top-right; a small chip "FRIES" bottom-left; the title "Crispy Fries" in large text; an image-off icon with the text "No recipe photo yet - add one above". Below the hero: three outlined chips — author (person icon + "junaid"), time (clock + "20 min"), main ingredient (icon + "potato"). Then the rating pill "5.0 from 2 ratings". Then the Ingredients card (potato, oil, salt, chilli powder — 4 items, same green checks) and the Cooking steps card (4 steps: cut potatoes into even strips and soak in cold water; heat oil to medium-high and fry until pale; fry a second time until golden and crisp; toss with salt and chilli powder while hot).

### Target structure (all recipes) — P0

**R-01 · One template.** Top to bottom:
1. **Top app bar** (see R-06).
2. **Hero** (photo or placeholder, see R-03).
3. **Info chips row**: author · cooking time · main ingredient · servings. A chip is **hidden** (not blank) when its value is missing. Owners see a dashed "+ Add time" chip in place of a missing time.
4. **Rating block** (see R-04).
5. **Video card** if a YouTube URL exists (see R-08).
6. **Ingredients card** (see R-02).
7. **Cooking steps card** (see R-05).
8. Sticky bottom bar with a primary button **"Start cooking"** (opens Cook mode, see R-07).

**Accept:** Opening Chicken Biryani and Crispy Fries shows identical structure; only missing data differs.

### R-02 · Ingredients card · P0
**Change:**
- Header: "Ingredients" (Subtitle 16sp) with `N items` (Label, `onSurfaceVariant`) and, at the right, a **servings stepper** `[−] 4 [+]` (min 1, max 99). Changing servings scales all numeric quantities proportionally and re-formats (e.g. 0.5 cup, 1½ tsp; round to nearest ¼ for volume units, to nearest 5 g/ml for g/ml above 50).
- Row layout: **checkbox (24dp, outline circle, unchecked by default)**, then quantity + unit (right-aligned in a 72dp column, `accentOnDark`, e.g. `500 g`), then ingredient name (Body 14sp, left-aligned, 12dp gap).
- Tapping a row toggles the checkbox: checked state = filled `success` check, name strikethrough with 60% opacity. State is kept in memory for the screen session (reset on leaving), optionally persisted per recipe if easy.
- If quantity is null, leave the quantity column empty (name still aligned).
- **Remove the always-green check icons.**
**Accept:** Items start unchecked; tapping toggles with strikethrough; changing servings from 4 to 8 doubles all numeric quantities.

### R-03 · Hero · P1
**Change:**
- With photo: 16:9 image, radius 20dp, gradient scrim at the bottom (transparent → 60% black) for title legibility. Title (Title 22sp) and a dish chip (e.g. "FRIES", Label uppercase) overlaid at bottom-left with 16dp inset.
- **Without photo, for the owner:** a ~140dp-tall card, dish gradient background, the dish icon (48dp, 40% white) centred at the top and a large centred **"Add a photo"** filled-tonal button (camera icon + label, 48dp tall). **Remove** the text "No recipe photo yet - add one above" and the corner "Add photo" pill.
- **Without photo, for other users:** a compact 96dp banner with dish gradient and icon only, no button, no helper text.
- The title is shown in the hero only. The top bar shows the title **only after the hero scrolls out of view**.
**Accept:** No text says "add one above"; there is exactly one add-photo control on the screen; the title never appears twice at the same time.

### R-04 · Rating block · P1
**Change:** Below the chips row:
- Summary row: five-star row + `4.5 from 2 ratings` (tapping it opens a bottom sheet with the distribution: five rows 5★…1★ with horizontal bars and counts).
- If the viewer is **not the author** and has not rated: a prompt "Rate this recipe" with five tappable stars (each 40dp target, 8dp gap). Tapping submits immediately and shows a snackbar "Thanks! You rated 4★" with an **Undo** action.
- If already rated: show "Your rating" with the filled stars; tapping lets them change it.
- If the viewer is the author: no rating control (per `D-04`).
**Accept:** A non-author can rate once and change it; the author sees no rating control; the summary updates immediately.

### R-05 · Cooking steps card · P1
**Change:**
- Keep the numbered orange circles (28dp) and one-action-per-step text (Body 14sp, line-height 1.4).
- If a step has `timerSeconds`, show a chip under the text: clock icon + `10 min`. Tapping starts a countdown timer with a notification when done.
- Add 16dp vertical spacing between steps and a 1dp divider is not needed.

### R-06 · Top bar and actions · P1
**Change:**
- Left: back arrow. Center/left: title (appears on scroll, see R-03). Right: **Favourite** (heart outline/filled, 48dp), then **overflow (⋮)**.
- **Edit (pencil) is visible only to the recipe's author.** Move it into the overflow menu as the first item for authors; keep it as a visible pencil icon only if there is space. Non-authors never see Edit or Delete.
- Overflow menu: Edit (author), Share, Report (non-author), Delete (author, `danger` color, confirmation dialog).
**Accept:** Logged in as a non-author, the menu contains only Share and Report.

### R-07 · Cook mode · P2 (new feature, build last)
**Change:** Full-screen view, screen kept awake. Shows one step at a time at **24sp**, with a progress indicator "Step 2 of 4" at the top, a large timer chip when the step has a timer, and big **Previous / Next** buttons (56dp tall) at the bottom; swipe left/right also navigates. A "Ingredients" button at the top-right opens a bottom sheet of the ingredients (same checklist state). Exit with an X at the top-left (confirm if mid-recipe).

### R-08 · Video card · P2
**Change:** If the YouTube URL exists and is valid, show a card between rating and ingredients: 16:9 thumbnail (from `https://img.youtube.com/vi/<id>/hqdefault.jpg`), play icon overlay, caption "Watch video". Tapping opens the YouTube app/browser.

---

## 7. Screen: Edit Recipe

### Current layout
Top bar: back arrow + "Edit recipe". Scrollable content with cards:
1. **"Recipe details"** (icon of crossed fork/spoon; subtitle "Name the dish and add the basics."). Fields, each a rounded outlined field with a floating label:
   - "Recipe title *" — "Crispy Fries"
   - "Dish" — "Fries", with helper text underneath: "The dish cannot change after creation." (the field looks identical to editable fields)
   - "Main ingredient" — "potato"
   - "Cooking time (minutes)" — "20", with a clock icon at the left
   - "YouTube URL (optional)" — a play icon and the value `https://www.youtube.com/resul…` (this is a **YouTube search-results URL**, not a video URL)
2. **"Recipe photo"** (camera icon; subtitle "The main photo shown on the dish card."). When empty: a large dashed area with an add-image icon and "No recipe photo yet".
3. An **ingredients** card ending with a text button "+ Add ingredient".
4. **"Cooking steps"** (flame icon; subtitle "One action per step is easiest to follow."). Four numbered steps, each a multi-line rounded text box with a **×** to its right: (1) Cut the potatoes into even strips and soak them in cold water. (2) Heat the oil to medium-high and fry the potatoes until pale. (3) Fry a second time until golden and crisp. (4) Toss with salt and chilli powder while hot. Then a "+ Add step" text button.
5. A **sticky bottom bar** that stays visible while scrolling: a text button "Cancel" on the left and a wide filled orange button "✓ Save changes".

### E-01 · Locked Dish field · P1
**Change:** Render the Dish field as disabled: 60% opacity, no focus ring, trailing **lock icon (20dp)**, and no tap response. Change helper text to **"Locked after creation."** Long-press shows a tooltip: "A recipe can't move to another dish after it's created."
**Accept:** Tapping the field does nothing and visibly does not look editable.

### E-02 · YouTube URL validation · P1
**Change:**
- Accept only: `https://www.youtube.com/watch?v=<id>`, `https://youtu.be/<id>`, `https://www.youtube.com/shorts/<id>`, and `https://m.youtube.com/watch?v=<id>`. Reject search-result URLs (`/results?search_query=`), playlists, and channel URLs.
- Validate on blur and on save. Error text under the field: "Paste a link to a single YouTube video."
- Add a trailing **Paste** icon button (clipboard) that pastes and validates.
- When valid, show a 16:9 thumbnail preview (120dp wide) under the field.
**Accept:** The existing `…/results…` URL is flagged as invalid and blocks saving until fixed or cleared.

### E-03 · Cooking time field · P2
**Change:** Numeric keyboard, integer only (1–1440), suffix text "min" inside the field. Below the field show quick-pick chips: **15 · 30 · 45 · 60**; tapping one fills the field.

### E-04 · Ingredients editor · P0
**Change:** Each ingredient row has three inputs: **Quantity** (numeric, 72dp wide), **Unit** (dropdown, 96dp wide, options from `D-01`), **Name** (flex). A 48dp delete (×) button at the right removes the row with a snackbar **Undo**. Reorder with a drag handle (see E-05). "+ Add ingredient" adds a row and focuses the Quantity field.
**Accept:** An ingredient can be saved as `500 g chicken`; a row with only a name is also valid.

### E-05 · Steps editor · P1
**Change:**
- Add a **drag handle (⋮⋮, 24dp icon in a 48dp target)** at the left of each step; long-press-and-drag reorders steps and the step numbers update live. (Place the number circle to the right of the handle.)
- The × button gets a 48×48dp hit area. Tapping it removes the step and shows a snackbar "Step deleted" with **Undo** (5 s). **No confirmation dialog.**
- "+ Add step" appends a step and auto-focuses it. Pressing **Next/Enter** on the keyboard from the last step adds another step; pressing it on an empty step removes that empty step and closes the keyboard.
- Each step gets a small optional **"Add timer"** text button below the field that reveals a minutes input (sets `timerSeconds`).
**Accept:** Steps can be reordered by dragging; deleting a step can be undone.

### E-06 · Unsaved-changes safety · P1
**Change:**
- "Save changes" is **disabled** (50% opacity) until any field differs from the loaded values.
- Back arrow and "Cancel", when there are unsaved changes, show a dialog: title "Discard changes?", body "Your edits won't be saved.", buttons **Keep editing** (default) / **Discard**.
- Validate required fields inline on blur (e.g. empty title shows "Add a title" under the field), not only on save.
**Accept:** Making no edits leaves Save disabled; back with edits shows the dialog; back without edits exits silently.

### E-07 · Photo card · P2
**Change:** When empty: dashed area (140dp tall) with "Add a photo" and two buttons: **Camera** and **Gallery**. When filled: show a 16:9 preview with **Replace** and **Remove** buttons. Reject images smaller than 800px on the long side with the message "Choose a larger photo (at least 800 px)."

---

## 8. Screen: "Add a recipe" bottom sheet

### Current layout
Opened by the FAB; the page behind is dimmed. A sheet with a drag handle, title **"Add a recipe"**, subtitle **"Write it yourself, or let AI create a draft to review."** Two rows, each with a 56dp rounded icon tile on the left and text on the right:
1. **"Write it manually"** — "Choose an existing dish or create a new one."
2. **"Describe it with AI"** — "Explain the dish in your own words and review the draft Gemini writes."

### S-01 · Remove the model name · P2
**Change:** Subtitle of row 2 becomes: **"Describe it in your own words, then review the AI-written draft."**
**Accept:** The string "Gemini" appears nowhere in user-facing text.

### S-02 · Row styling and hierarchy · P2
**Change:**
- Make each row a full-width list item, 72dp min height, 16dp horizontal padding, `surfaceVariant` background, 16dp radius, 8dp gap between rows.
- Add a trailing chevron (20dp) to both rows.
- Add a small **"AI"** chip (Label 12sp, `accent` background at 20% opacity, `accentOnDark` text) next to the title of row 2.
- Add a third row: **"Import from a YouTube link"** — "Paste a video link and we'll draft the recipe." (Only build if the AI pipeline can ingest a link. Otherwise omit.)
- Add a visible **"Cancel"** text button at the bottom (in addition to the drag handle) for accessibility.
**Accept:** Both rows are clearly tappable list items; keyboard/TalkBack users can dismiss the sheet via Cancel.

### S-03 · AI draft review · P1
**Change:** After AI generates a draft, open the Edit Recipe screen prefilled, with a dismissible banner at the top: "AI draft — check quantities and steps before saving." Mark fields the model left empty with an "Add" hint rather than inventing values. The draft is **not saved** until the user taps Save.

---

## 9. Implementation Checklist (in order)

**Phase 1 — Quick fixes (about half a day)**
- [ ] `H-02` FAB bottom padding + extended FAB
- [ ] `H-07` Shorter search placeholder + clear button
- [ ] `M-03` "New" chip replaces empty stars; `G-05` compact rating rule
- [ ] `R-03` remove "add one above" text and duplicate photo control
- [ ] `S-01` remove "Gemini" copy
- [ ] `E-01` disabled Dish field with lock icon
- [ ] `G-01`, `G-02` contrast and letter-spacing tokens

**Phase 2 — Trust and consistency (1–2 days)**
- [ ] `D-05` + `H-01` earned Top pick and smoothed ranking
- [ ] `R-01` unified detail template; `R-06` owner-only edit/delete
- [ ] `R-02` ingredient checklist (functional or removed)
- [ ] `M-01` real section headers in My recipes
- [ ] `H-05`, `M-02` tightened card layouts; `H-06`, `M-05` icon placeholders
- [ ] `E-02` YouTube validation; `E-06` unsaved-changes guard

**Phase 3 — Core features (several days)**
- [ ] `D-01` structured ingredients + migration; `E-04` editor; `R-02` quantities + servings scaling (`D-02`)
- [ ] `D-04` + `R-04` interactive rating
- [ ] `E-05` step reorder and undo delete
- [ ] `H-03` collapsing header with sticky search; `H-04` counts in chips
- [ ] `G-06` all empty/loading/error states

**Phase 4 — Differentiators (later)**
- [ ] `R-07` Cook mode; `D-03` + `R-05` step timers
- [ ] `R-08` video card; `S-02` import-from-YouTube; `S-03` AI draft review banner
- [ ] `G-03`, `G-04` full accessibility pass

---

## 10. Design Principles (use these to settle any question this document doesn't answer)

1. A badge, star, or checkmark must **mean something** or be removed.
2. Screens of the same type have **the same structure**. Missing data hides or prompts; it never changes the layout.
3. Empty states are **calls to action**, not apologies.
4. A locked or destructive control must **look** locked or destructive.
5. Content first: **chrome shrinks as the user scrolls.**
6. Prefer **undo** over confirmation dialogs for small, reversible actions; use dialogs only for irreversible ones (deleting a whole recipe, discarding unsaved edits).
