#ifndef WEB_PAGE_H
#define WEB_PAGE_H

// ============================================================
//  WebPage.h - a tiny browser page for the Stage 2 API
//
//  The page is embedded as a raw string so the server always has it,
//  no matter which folder it is started from. It is plain HTML, CSS
//  and JavaScript and calls the existing JSON routes.
//
//  The page is read-only. It groups recipes by dish and ranks the
//  recipes inside each dish, which is the same story the Flutter app
//  tells. Keep this file presentational only: recipe rules belong in
//  BackendService, not here.
// ============================================================

inline constexpr const char* kIndexHtml = R"HTML(<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>TasteHub</title>
  <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Ctext y='50' font-size='50'%3E%F0%9F%8D%B2%3C/text%3E%3C/svg%3E">
  <style>
    :root {
      --bg: #faf6f0;
      --card: #fffdfa;
      --ink: #2d241c;
      --muted: #7d6e60;
      --line: #e9ded0;
      --accent: #bb4d2a;
      --gold: #d98a2b;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      min-height: 100vh;
      color: var(--ink);
      background:
        radial-gradient(circle at top left, #f6e7d6 0, transparent 34rem),
        var(--bg);
      font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
    }

    header, main {
      width: min(1120px, 100% - 40px);
      margin-inline: auto;
    }

    header { padding: 52px 0 24px; }

    .brand h1 {
      margin: 0;
      font-size: clamp(2.3rem, 6vw, 3.6rem);
      letter-spacing: -0.05em;
      line-height: 1;
    }

    .brand h1 span { color: var(--accent); }

    .brand p {
      margin: 8px 0 0;
      color: var(--muted);
      font-size: 1.02rem;
    }

    .controls {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
      margin-top: 28px;
    }

    #search {
      flex: 1 1 260px;
      min-width: 0;
      padding: 13px 18px;
      color: var(--ink);
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 999px;
      font: inherit;
      outline: none;
    }

    #search:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 3px #bb4d2a1f;
    }

    main { padding-bottom: 64px; }

    .status {
      min-height: 1.5em;
      margin: 18px 2px 14px;
      color: var(--muted);
      font-size: 0.94rem;
    }

    .status.error { color: #a32c1d; font-weight: 600; }

    .dish-section { margin: 0 0 34px; }

    .dish-head {
      display: flex;
      flex-wrap: wrap;
      gap: 6px 16px;
      align-items: baseline;
      margin: 0 2px 12px;
      padding-bottom: 10px;
      border-bottom: 1px solid var(--line);
    }

    .dish-head h2 {
      margin: 0;
      font-size: 1.45rem;
      letter-spacing: -0.03em;
    }

    .dish-head .meta { margin-left: auto; }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(235px, 1fr));
      gap: 16px;
    }

    .card {
      display: flex;
      flex-direction: column;
      gap: 9px;
      padding: 0 0 16px;
      text-align: left;
      color: inherit;
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 18px;
      font: inherit;
      cursor: pointer;
      overflow: hidden;
      transition: transform 160ms ease, box-shadow 160ms ease;
    }

    .card:hover {
      transform: translateY(-3px);
      box-shadow: 0 14px 30px #2d241c14;
    }

    .card:focus-visible {
      outline: 3px solid #bb4d2a66;
      outline-offset: 2px;
    }

    .photo {
      position: relative;
      display: block;
      width: 100%;
      aspect-ratio: 16 / 10;
      object-fit: cover;
      background: #f1e7db;
    }

    .placeholder {
      display: grid;
      place-items: center;
      width: 100%;
      aspect-ratio: 16 / 10;
      color: #fffdfa;
      font-size: 2.1rem;
      font-weight: 760;
    }

    .card-body {
      display: flex;
      flex-direction: column;
      gap: 8px;
      padding: 0 18px;
      flex: 1;
    }

    .dish {
      color: var(--accent);
      font-size: 0.7rem;
      font-weight: 750;
      letter-spacing: 0.13em;
      text-transform: uppercase;
    }

    .card-title {
      font-size: 1.18rem;
      font-weight: 720;
      line-height: 1.28;
    }

    .meta {
      color: var(--muted);
      font-size: 0.88rem;
      line-height: 1.4;
    }

    .rating {
      display: flex;
      gap: 8px;
      align-items: baseline;
      margin-top: auto;
      font-size: 0.86rem;
    }

    .stars { color: var(--gold); letter-spacing: 0.08em; }

    .badge-row {
      display: flex;
      gap: 8px;
      align-items: center;
      padding: 14px 18px 0;
    }

    .rank {
      padding: 3px 9px;
      color: var(--accent);
      background: #f9e7db;
      border-radius: 999px;
      font-size: 0.75rem;
      font-weight: 750;
    }

    .rank.top {
      color: #7a4a00;
      background: #f7e2b8;
    }

    .new-tag {
      padding: 3px 9px;
      color: #4d6b3f;
      background: #e7efdf;
      border-radius: 999px;
      font-size: 0.75rem;
      font-weight: 750;
    }

    .empty {
      padding: 36px 20px;
      color: var(--muted);
      text-align: center;
      background: #fffdfab8;
      border: 1px dashed var(--line);
      border-radius: 18px;
    }

    dialog {
      width: min(680px, calc(100vw - 32px));
      max-height: 86vh;
      padding: 0 30px 30px;
      color: var(--ink);
      background: var(--card);
      border: 0;
      border-radius: 22px;
      box-shadow: 0 30px 90px #2d241c40;
      overflow: auto;
    }

    dialog::backdrop { background: #2d241c66; }

    .detail-photo {
      width: calc(100% + 60px);
      max-height: 300px;
      margin: 0 -30px 22px;
      object-fit: cover;
      border-radius: 22px 22px 0 0;
    }

    .detail-placeholder {
      width: calc(100% + 60px);
      height: 190px;
      margin: 0 -30px 22px;
      border-radius: 22px 22px 0 0;
      font-size: 3rem;
    }

    .close {
      position: sticky;
      top: 10px;
      float: right;
      width: 36px;
      height: 36px;
      color: var(--muted);
      background: #f1e7db;
      border: 0;
      border-radius: 50%;
      font-size: 1.25rem;
      line-height: 1;
      cursor: pointer;
      z-index: 2;
    }

    dialog h2 {
      margin: 6px 0 10px;
      padding-right: 42px;
      font-size: 1.9rem;
      letter-spacing: -0.03em;
      line-height: 1.15;
    }

    dialog h3 {
      margin: 26px 0 10px;
      font-size: 0.78rem;
      letter-spacing: 0.12em;
      text-transform: uppercase;
    }

    dialog ul, dialog ol {
      margin: 0;
      padding-left: 22px;
      line-height: 1.7;
    }

    dialog a {
      display: inline-block;
      margin-top: 22px;
      color: var(--accent);
      font-weight: 650;
    }

    .detail-meta {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 18px;
      color: var(--muted);
      font-size: 0.92rem;
      margin-bottom: 8px;
    }

    .rating-row {
      display: flex;
      flex-wrap: wrap;
      gap: 6px 12px;
      align-items: baseline;
      padding: 8px 0;
      border-bottom: 1px solid var(--line);
      font-size: 0.9rem;
    }

    .rating-row .meta { margin-left: auto; }
    .rating-row img {
      width: 34px;
      height: 34px;
      object-fit: cover;
      border-radius: 8px;
    }

    @media (max-width: 560px) {
      header { padding-top: 34px; }
      dialog { padding: 0 22px 22px; }
      .detail-photo, .detail-placeholder {
        width: calc(100% + 44px);
        margin-inline: -22px;
      }
    }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <h1>Taste<span>Hub</span></h1>
      <p>Home cooking, shared. Every dish ranks its own recipes.</p>
    </div>

    <div class="controls">
      <input id="search" type="search" placeholder="Search recipes, dishes or ingredients..."
             autocomplete="off" aria-label="Search recipes">
    </div>
  </header>

  <main>
    <p id="status" class="status" aria-live="polite">Loading recipes...</p>
    <section id="dishes" aria-live="polite"></section>
    <noscript>
      <p class="empty">This page needs JavaScript. The same data is available
      as JSON at <code>/api/recipes</code>.</p>
    </noscript>
  </main>

  <dialog id="detail" aria-label="Recipe details">
    <button id="close-detail" class="close" aria-label="Close">×</button>
    <div id="detail-body"></div>
  </dialog>

  <script>
    const state = {
      recipes: [],
      query: "",
    };

    const palettes = [
      ["#b65a36", "#e0a15a"],
      ["#5b7b4b", "#a9be7a"],
      ["#8b4a5e", "#d5909a"],
      ["#3f6a72", "#7fb0b3"],
      ["#9a6b2f", "#d8b36a"],
      ["#6b4e7a", "#ad8fbc"],
    ];

    let requestNumber = 0;
    let searchTimer = null;

    const dishesRoot = document.getElementById("dishes");
    const statusLine = document.getElementById("status");
    const searchInput = document.getElementById("search");
    const detailDialog = document.getElementById("detail");
    const detailBody = document.getElementById("detail-body");

    async function api(path) {
      const response = await fetch(path, { headers: { Accept: "application/json" } });
      const body = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(body.error || "Request failed (" + response.status + ")");
      }
      return body;
    }

    function escapeHtml(value) {
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
    }

    function stars(value) {
      const filled = Math.max(0, Math.min(5, Math.round(Number(value) || 0)));
      return "★".repeat(filled) + "☆".repeat(5 - filled);
    }

    function setStatus(message, isError = false) {
      statusLine.textContent = message;
      statusLine.classList.toggle("error", isError);
    }

    // Only user URLs and files uploaded through /api/images are shown.
    // Seed recipes have an empty imageRef and keep the gradient placeholder.
    function imageUrl(ref) {
      if (typeof ref !== "string") return "";
      if (ref.startsWith("/uploads/")) return ref;
      if (/^https?:\/\//i.test(ref)) return ref;
      return "";
    }

    function hashText(text) {
      let hash = 0;
      for (const char of String(text || "?")) {
        hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
      }
      return hash;
    }

    function gradient(text) {
      const palette = palettes[hashText(text) % palettes.length];
      return "linear-gradient(135deg, " + palette[0] + ", " + palette[1] + ")";
    }

    function placeholder(text, extraClass = "placeholder") {
      const letter = escapeHtml(String(text || "?").trim().charAt(0) || "?");
      return '<div class="' + extraClass + '" style="background: ' +
             gradient(text) + '">' + letter.toUpperCase() + "</div>";
    }

    function photoHtml(recipe, extraClass = "photo") {
      const url = imageUrl(recipe.imageRef);
      if (!url) return placeholder(recipe.title, extraClass.replace("photo", "placeholder"));
      return '<img class="' + extraClass + '" src="' + escapeHtml(url) +
             '" alt="' + escapeHtml(recipe.title) + '" loading="lazy">';
    }

    // Same order as the backend: average desc, rating count desc, newest
    // first. Recipes without ratings follow, newest first, marked "New".
    function rankRecipes(recipes) {
      const rated = recipes.filter((recipe) => Number(recipe.ratingCount) > 0);
      const unrated = recipes.filter((recipe) => Number(recipe.ratingCount) === 0);

      rated.sort((a, b) => {
        if (Number(b.averageRating) !== Number(a.averageRating)) {
          return Number(b.averageRating) - Number(a.averageRating);
        }
        if (Number(b.ratingCount) !== Number(a.ratingCount)) {
          return Number(b.ratingCount) - Number(a.ratingCount);
        }
        return String(b.createdAt || "").localeCompare(String(a.createdAt || ""));
      });
      unrated.sort((a, b) =>
        String(b.createdAt || "").localeCompare(String(a.createdAt || "")));

      return rated.concat(unrated);
    }

    function groupByDish(recipes) {
      const groups = new Map();

      for (const recipe of recipes) {
        const name = recipe.dish || "Recipes";
        const key = name.toLowerCase();
        if (!groups.has(key)) groups.set(key, { name, recipes: [] });
        groups.get(key).recipes.push(recipe);
      }

      return [...groups.values()].sort((a, b) =>
        a.name.localeCompare(b.name));
    }

    function ratingLine(recipe) {
      const rated = Number(recipe.ratingCount) > 0;
      return '<span class="rating">' +
        '<span class="stars">' + (rated ? stars(recipe.averageRating) : "☆☆☆☆☆") + "</span>" +
        '<span class="meta">' + (rated
          ? Number(recipe.averageRating).toFixed(1) + " (" + recipe.ratingCount + ")"
          : "New · not rated yet") + "</span></span>";
    }

    function recipeCard(recipe, rank) {
      const time = recipe.cookingTime ? recipe.cookingTime + " min" : "No time set";
      const ingredient = recipe.mainIngredient || "Ingredient not set";
      const owner = recipe.ownerName ? "by " + recipe.ownerName : "owner unknown";

      return `
        <button class="card" data-id="${recipe.id}">
          <div class="badge-row">
            ${rank > 0
              ? `<span class="rank${rank === 1 ? " top" : ""}">#${rank}${rank === 1 ? " · Top pick" : ""}</span>`
              : '<span class="new-tag">New</span>'}
          </div>
          ${photoHtml(recipe)}
          <span class="card-body">
            <span class="dish">${escapeHtml(recipe.dish || "Recipe")}</span>
            <span class="card-title">${escapeHtml(recipe.title)}</span>
            <span class="meta">${escapeHtml(owner)} · ${escapeHtml(time)} · ${escapeHtml(ingredient)}</span>
            ${ratingLine(recipe)}
          </span>
        </button>`;
    }

    function dishSection(group, matchCount) {
      const ranked = rankRecipes(group.recipes);
      const top = ranked.find((recipe) => Number(recipe.ratingCount) > 0);
      const count = group.recipes.length;
      const summary = matchCount !== undefined
        ? matchCount + " matching recipe" + (matchCount === 1 ? "" : "s")
        : count + " recipe" + (count === 1 ? "" : "s") +
          (top ? " · Top: " + top.title + " (" +
            Number(top.averageRating).toFixed(1) + ")" : " · No ratings yet");

      return `
        <section class="dish-section">
          <div class="dish-head">
            <h2>${escapeHtml(group.name)}</h2>
            <span class="meta">${escapeHtml(summary)}</span>
          </div>
          <div class="grid">
            ${ranked.map((recipe, index) => recipeCard(recipe, index + 1)).join("")}
          </div>
        </section>`;
    }

    function render() {
      const groups = groupByDish(state.recipes);
      const recipeCount = state.recipes.length;

      setStatus(state.query
        ? recipeCount + " result" + (recipeCount === 1 ? "" : "s") +
          ' for "' + state.query + '" · grouped by dish'
        : groups.length + " dish" + (groups.length === 1 ? "" : "es") + " · " +
          recipeCount + " recipe" + (recipeCount === 1 ? "" : "s") + " saved");

      dishesRoot.innerHTML = groups.length
        ? groups.map((group) => dishSection(
            group,
            state.query ? group.recipes.length : undefined)).join("")
        : '<p class="empty">No recipes found. Add one through the API or console app.</p>';
    }

    async function loadRecipes() {
      const current = ++requestNumber;
      state.query = "";
      setStatus("Loading recipes...");

      try {
        const recipes = await api("/api/recipes");
        if (current !== requestNumber) return;
        state.recipes = recipes;
        render();
      } catch (error) {
        if (current !== requestNumber) return;
        setStatus(error.message, true);
        dishesRoot.innerHTML = "";
      }
    }

    async function runSearch(query) {
      const current = ++requestNumber;
      const text = query.trim();
      state.query = text;

      if (!text) {
        loadRecipes();
        return;
      }

      setStatus('Searching for "' + text + '"...');

      try {
        const data = await api("/api/search?q=" + encodeURIComponent(text));
        if (current !== requestNumber) return;
        state.recipes = data.results || [];
        render();
      } catch (error) {
        if (current !== requestNumber) return;
        setStatus(error.message, true);
        dishesRoot.innerHTML = "";
      }
    }

    function ratingRows(recipe) {
      const ratings = recipe.ratings || [];
      if (!ratings.length) return '<p class="meta">No ratings yet.</p>';

      return ratings.map((rating) => {
        const proof = imageUrl(rating.proofImageRef);
        return '<div class="rating-row">' +
          '<span class="stars">' + stars(rating.stars) + "</span>" +
          '<span>' + escapeHtml(rating.userName || ("user " + rating.userId)) + "</span>" +
          (proof ? '<img src="' + escapeHtml(proof) + '" alt="Proof photo">' : "") +
          '<span class="meta">' + rating.stars + "/5</span>" +
          "</div>";
      }).join("");
    }

    function detailHtml(recipe) {
      const ingredients = (recipe.ingredients || [])
        .map((item) => "<li>" + escapeHtml(item) + "</li>").join("");
      const steps = (recipe.steps || [])
        .map((item) => "<li>" + escapeHtml(item) + "</li>").join("");
      const rated = Number(recipe.ratingCount) > 0;
      const time = recipe.cookingTime ? recipe.cookingTime + " min" : "No time set";
      const owner = recipe.ownerName ? "by " + recipe.ownerName : "";

      let youtube = "";
      try {
        const url = new URL(recipe.youtubeUrl || "");
        if (url.protocol === "http:" || url.protocol === "https:") {
          youtube = '<a href="' + escapeHtml(url.href) +
                    '" target="_blank" rel="noreferrer">Find it on YouTube</a>';
        }
      } catch (_) {
        // An empty or invalid link is simply not shown.
      }

      const photo = imageUrl(recipe.imageRef);

      return `
        ${photo
          ? '<img class="detail-photo" src="' + escapeHtml(photo) +
            '" alt="' + escapeHtml(recipe.title) + '">'
          : placeholder(recipe.title, "placeholder detail-placeholder")}
        <span class="dish">${escapeHtml(recipe.dish || "Recipe")}</span>
        <h2>${escapeHtml(recipe.title)}</h2>
        <div class="detail-meta">
          <span>${escapeHtml(owner)}</span>
          <span>${escapeHtml(time)}</span>
          <span>${escapeHtml(recipe.mainIngredient || "Ingredient not set")}</span>
          <span><span class="stars">${rated ? stars(recipe.averageRating) : "☆☆☆☆☆"}</span>
            ${rated ? Number(recipe.averageRating).toFixed(1) +
              " from " + recipe.ratingCount + " rating" +
              (recipe.ratingCount === 1 ? "" : "s") : "Not rated yet"}</span>
        </div>
        <h3>Ingredients</h3>
        <ul>${ingredients || "<li>No ingredients listed.</li>"}</ul>
        <h3>Steps</h3>
        <ol>${steps || "<li>No steps listed.</li>"}</ol>
        <h3>Ratings</h3>
        ${ratingRows(recipe)}
        ${youtube}`;
    }

    async function openDetail(id) {
      detailBody.innerHTML = '<p class="status">Loading recipe...</p>';
      detailDialog.showModal();

      try {
        const recipe = await api("/api/recipes/" + id);
        detailBody.innerHTML = detailHtml(recipe);
      } catch (error) {
        detailBody.innerHTML = '<p class="status error">' +
          escapeHtml(error.message) + "</p>";
      }
    }

    dishesRoot.addEventListener("click", (event) => {
      const card = event.target.closest(".card");
      if (card) openDetail(card.dataset.id);
    });

    searchInput.addEventListener("input", () => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => runSearch(searchInput.value), 250);
    });

    document.getElementById("close-detail")
      .addEventListener("click", () => detailDialog.close());

    detailDialog.addEventListener("click", (event) => {
      if (event.target !== detailDialog) return;

      // The dialog element also covers its own padding, so only close when the
      // click lands outside the visible box (the backdrop).
      const box = detailDialog.getBoundingClientRect();
      const inside = event.clientX >= box.left && event.clientX <= box.right &&
                     event.clientY >= box.top && event.clientY <= box.bottom;
      if (!inside) detailDialog.close();
    });

    loadRecipes();
  </script>
</body>
</html>
)HTML";

#endif
