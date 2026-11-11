#ifndef WEB_PAGE_H
#define WEB_PAGE_H

// ============================================================
//  WebPage.h - a tiny browser page for the Stage 2 API
//
//  The page is embedded as a raw string so the server always has it,
//  no matter which folder it is started from. It is plain HTML, CSS
//  and JavaScript and calls the existing JSON routes.
//
//  Keep this file presentational only. Recipe rules belong in
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
      width: min(1080px, 100% - 40px);
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

    .tabs {
      display: flex;
      gap: 4px;
      padding: 4px;
      background: #f1e7db;
      border-radius: 999px;
    }

    .tab {
      padding: 9px 16px;
      color: var(--muted);
      background: transparent;
      border: 0;
      border-radius: 999px;
      font: inherit;
      font-size: 0.92rem;
      font-weight: 650;
      cursor: pointer;
    }

    .tab.active {
      color: var(--ink);
      background: var(--card);
      box-shadow: 0 1px 4px #2d241c14;
    }

    main { padding-bottom: 64px; }

    .status {
      min-height: 1.5em;
      margin: 18px 2px 14px;
      color: var(--muted);
      font-size: 0.94rem;
    }

    .status.error { color: #a32c1d; font-weight: 600; }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(235px, 1fr));
      gap: 16px;
    }

    .card {
      display: flex;
      flex-direction: column;
      gap: 9px;
      min-height: 168px;
      padding: 20px;
      text-align: left;
      color: inherit;
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 18px;
      font: inherit;
      cursor: pointer;
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

    .dish {
      color: var(--accent);
      font-size: 0.7rem;
      font-weight: 750;
      letter-spacing: 0.13em;
      text-transform: uppercase;
    }

    .card-title {
      font-size: 1.22rem;
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

    .rank {
      align-self: flex-start;
      padding: 3px 9px;
      color: var(--accent);
      background: #f9e7db;
      border-radius: 999px;
      font-size: 0.75rem;
      font-weight: 750;
    }

    .empty {
      grid-column: 1 / -1;
      padding: 36px 20px;
      color: var(--muted);
      text-align: center;
      background: #fffdfab8;
      border: 1px dashed var(--line);
      border-radius: 18px;
    }

    dialog {
      width: min(640px, calc(100vw - 32px));
      max-height: 86vh;
      padding: 30px;
      color: var(--ink);
      background: var(--card);
      border: 0;
      border-radius: 22px;
      box-shadow: 0 30px 90px #2d241c40;
      overflow: auto;
    }

    dialog::backdrop { background: #2d241c66; }

    .close {
      position: sticky;
      top: 0;
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
    }

    @media (max-width: 560px) {
      header { padding-top: 34px; }
      .controls { align-items: stretch; }
      .tabs { justify-content: center; }
      .tab { flex: 1; }
      dialog { padding: 22px; }
    }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <h1>Taste<span>Hub</span></h1>
      <p>Home cooking, shared. Browse the recipes saved on this server.</p>
    </div>

    <div class="controls">
      <input id="search" type="search" placeholder="Search recipes, dishes or ingredients..."
             autocomplete="off" aria-label="Search recipes">
      <div class="tabs" role="tablist" aria-label="Recipe views">
        <button class="tab active" data-view="recipes" role="tab"
                aria-selected="true">All recipes</button>
        <button class="tab" data-view="leaderboard" role="tab"
                aria-selected="false">Leaderboard</button>
      </div>
    </div>
  </header>

  <main>
    <p id="status" class="status" aria-live="polite">Loading recipes...</p>
    <section id="grid" class="grid" aria-live="polite"></section>
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
      view: "recipes",
      recipes: [],
      leaderboard: [],
      query: "",
    };

    let requestNumber = 0;
    let searchTimer = null;

    const grid = document.getElementById("grid");
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

    function updateTabs() {
      document.querySelectorAll(".tab").forEach((tab) => {
        const active = tab.dataset.view === state.view;
        tab.classList.toggle("active", active);
        tab.setAttribute("aria-selected", String(active));
      });
    }

    function recipeCard(recipe, rank = 0) {
      const rated = Number(recipe.ratingCount) > 0;
      const time = recipe.cookingTime ? recipe.cookingTime + " min" : "No time set";
      const ingredient = recipe.mainIngredient || "Ingredient not set";

      return `
        <button class="card" data-id="${recipe.id}">
          ${rank ? `<span class="rank">#${rank}</span>` : ""}
          <span class="dish">${escapeHtml(recipe.dish || "Recipe")}</span>
          <span class="card-title">${escapeHtml(recipe.title)}</span>
          <span class="meta">${escapeHtml(time)} · ${escapeHtml(ingredient)}</span>
          <span class="rating">
            <span class="stars">${rated ? stars(recipe.averageRating) : "☆☆☆☆☆"}</span>
            <span class="meta">${rated
              ? Number(recipe.averageRating).toFixed(1) + " (" + recipe.ratingCount + ")"
              : "Not rated yet"}</span>
          </span>
        </button>`;
    }

    function render() {
      updateTabs();

      if (state.view === "leaderboard") {
        const entries = state.leaderboard;
        setStatus(entries.length
          ? entries.length + " rated recipe" + (entries.length === 1 ? "" : "s")
          : "No ratings yet. Rate a recipe through the API to make the leaderboard.");

        grid.innerHTML = entries.length
          ? entries.map((entry) => recipeCard(entry.recipe, entry.rank)).join("")
          : '<p class="empty">The leaderboard is empty for now.</p>';
        return;
      }

      const recipes = state.recipes;
      setStatus(state.query
        ? recipes.length + " result" + (recipes.length === 1 ? "" : "s") +
          ' for "' + state.query + '"'
        : recipes.length + " recipe" + (recipes.length === 1 ? "" : "s") + " saved");

      grid.innerHTML = recipes.length
        ? recipes.map((recipe) => recipeCard(recipe)).join("")
        : '<p class="empty">No recipes found. Add one through the API or console app.</p>';
    }

    async function loadRecipes() {
      const current = ++requestNumber;
      state.view = "recipes";
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
        grid.innerHTML = "";
      }
    }

    async function loadLeaderboard() {
      const current = ++requestNumber;
      state.view = "leaderboard";
      setStatus("Loading leaderboard...");

      try {
        const data = await api("/api/leaderboard");
        if (current !== requestNumber) return;
        state.leaderboard = data.leaderboard || [];
        render();
      } catch (error) {
        if (current !== requestNumber) return;
        setStatus(error.message, true);
        grid.innerHTML = "";
      }
    }

    async function runSearch(query) {
      const current = ++requestNumber;
      const text = query.trim();
      state.view = "recipes";
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
        grid.innerHTML = "";
      }
    }

    function detailHtml(recipe) {
      const ingredients = (recipe.ingredients || [])
        .map((item) => "<li>" + escapeHtml(item) + "</li>").join("");
      const steps = (recipe.steps || [])
        .map((item) => "<li>" + escapeHtml(item) + "</li>").join("");
      const rated = Number(recipe.ratingCount) > 0;
      const time = recipe.cookingTime ? recipe.cookingTime + " min" : "No time set";

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

      return `
        <span class="dish">${escapeHtml(recipe.dish || "Recipe")}</span>
        <h2>${escapeHtml(recipe.title)}</h2>
        <div class="detail-meta">
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

    grid.addEventListener("click", (event) => {
      const card = event.target.closest(".card");
      if (card) openDetail(card.dataset.id);
    });

    document.querySelectorAll(".tab").forEach((tab) => {
      tab.addEventListener("click", () => {
        clearTimeout(searchTimer);
        searchInput.value = "";
        if (tab.dataset.view === "leaderboard") {
          loadLeaderboard();
        } else {
          loadRecipes();
        }
      });
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
