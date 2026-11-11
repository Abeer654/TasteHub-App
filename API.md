# TasteHub API Contract

This file is the agreement between the C++ server and the Flutter app.
Do not change field names without updating both sides.

## Base URL

```text
http://<laptop-tailscale-ip>:8080
```

Opening the base URL in a browser serves a small demo page that uses the JSON
endpoints below. It is a convenience for demos, not part of the mobile API
contract.

All requests and responses use JSON:

```text
Content-Type: application/json
```

The demo has no login. Every request acts as demo user `1`.

## Errors

Every error has the same shape:

```json
{ "error": "Recipe not found" }
```

| Status | Meaning |
|---|---|
| `200` | OK |
| `201` | Recipe created |
| `400` | Invalid input |
| `404` | Recipe not found |
| `409` | Duplicate title in the same dish |
| `422` | AI could not extract ingredients or steps |
| `500` | Server or file error |
| `502` | Gemini request failed |
| `503` | Gemini is not configured, rate-limited, or busy |

Request bodies must be valid JSON objects. Malformed JSON, wrong field types and
non-positive recipe ids return `400`. Unknown API routes return a JSON `404`.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/health` | Health check |
| `GET` | `/api/recipes` | List recipe summaries |
| `GET` | `/api/recipes/:id` | One recipe with ingredients, steps and ratings |
| `POST` | `/api/recipes` | Add a recipe |
| `POST` | `/api/recipes/parse` | Turn a free-form description into an AI recipe draft |
| `PUT` | `/api/recipes/:id` | Edit a recipe |
| `DELETE` | `/api/recipes/:id` | Delete a recipe |
| `GET` | `/api/search?q=...` | Typo-tolerant search |
| `PUT` | `/api/recipes/:id/rating` | Rate a recipe (1-5) with optional proof image |
| `GET` | `/api/leaderboard` | Top-rated recipes |

## Recipe summary

Returned by `GET /api/recipes` (as a JSON array) and inside search/leaderboard
results.

```json
{
  "id": 5,
  "title": "Chicken Biryani",
  "dish": "Biryani",
  "mainIngredient": "rice",
  "cookingTime": 60,
  "imageRef": "asset:assets/images/biryani.jpg",
  "youtubeUrl": "https://www.youtube.com/results?search_query=chicken+biryani+recipe",
  "averageRating": 4.5,
  "ratingCount": 2,
  "myRating": 5,
  "myRatingProofImageRef": "",
  "createdAt": "2026-10-20T18:00:00Z",
  "updatedAt": null
}
```

## Recipe detail

Returned by `GET /api/recipes/:id`, `POST /api/recipes`, and
`PUT /api/recipes/:id`. It is a summary plus:

```json
{
  "ingredients": ["rice", "chicken", "yogurt", "spices", "onion"],
  "steps": ["marinate the chicken", "fry the onions", "layer rice and chicken"],
  "ratings": [
    {
      "userId": 1,
      "stars": 5,
      "proofImageRef": "https://example.com/proofs/my-biryani.jpg"
    },
    {
      "userId": 2,
      "stars": 4,
      "proofImageRef": ""
    }
  ]
}
```

`ratings` is only included in the detail response. `proofImageRef` is the
optional photo a user attached as proof that they cooked the recipe.

## Create / edit request

`POST /api/recipes`:

```json
{
  "dish": "Biryani",
  "title": "Chicken Biryani",
  "mainIngredient": "rice",
  "ingredients": ["rice", "chicken", "yogurt", "spices", "onion"],
  "steps": ["marinate the chicken", "fry the onions", "layer rice and chicken"],
  "cookingTime": 60,
  "imageRef": "asset:assets/images/biryani.jpg",
  "youtubeUrl": "https://www.youtube.com/results?search_query=chicken+biryani+recipe"
}
```

Rules:

- `title`, `ingredients`, and `steps` are required.
- `dish` is optional; it defaults to `"My Recipes"`.
- `dish` cannot be changed after creation.
- `imageRef` and `youtubeUrl` are optional strings.
- `imageRef` may be:
  - an asset path: `asset:assets/images/biryani.jpg`
  - a web URL: `https://...`
  - a local phone path: `/data/user/0/.../recipe_123.jpg`
- Dates are ISO-8601 UTC, for example `2026-11-06T12:30:00Z`.

## AI recipe draft (natural-language input)

```text
POST /api/recipes/parse
```

The user describes a dish in their own words. Gemini extracts the fields a
recipe needs. This endpoint **does not save anything**: the client shows the
draft, then sends the `recipe` object to `POST /api/recipes` after the user
confirms or edits it.

Request:

```json
{
  "text": "I made chicken biryani last night with rice, chicken, yogurt, onions and spices. I marinated the chicken, fried the onions, layered it with rice and cooked it on low heat for an hour."
}
```

Response:

```json
{
  "message": "That sounds delicious! Rice makes this chicken biryani truly wonderful.",
  "recipe": {
    "dish": "Biryani",
    "title": "Chicken Biryani",
    "mainIngredient": "rice",
    "ingredients": ["rice", "chicken", "yogurt", "onions", "spices"],
    "steps": [
      "Marinate the chicken with yogurt and spices.",
      "Fry the onions until golden brown.",
      "Layer the chicken and rice.",
      "Cook on low heat for an hour."
    ],
    "cookingTime": 60,
    "imageRef": "",
    "youtubeUrl": ""
  },
  "inferredFields": ["cookingTime"],
  "followUpQuestions": ["How much rice did you use?"],
  "source": "gemini"
}
```

Rules:

- `text` is required and should contain at least a sentence.
- `recipe` uses exactly the `POST /api/recipes` fields, so it can be sent
  directly after the user reviews it.
- `mainIngredient` is the base that defines the dish (`rice` for biryani,
  `mutton` for karahi, `potato` for fries).
- `inferredFields` lists fields Gemini filled without the user saying them.
  The UI should highlight these for confirmation.
- `followUpQuestions` is optional and may be empty.
- `source` is `gemini` in normal use. Tests can inject a fake extractor.
- If Gemini cannot identify ingredients or steps, the endpoint returns `422`.
- If the key is missing, the model is busy, or the network fails, the endpoint
  returns `503` or `502`.

Configuration:

```text
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-3.5-flash
```

Put these in `.env` (git-ignored) or the server environment. `.env.example`
shows the names. The backend also tries a small fallback list of Gemini models.

## Delete

```text
DELETE /api/recipes/:id
```

Response:

```json
{
  "deleted": true,
  "id": 5
}
```

Deleting the last recipe in a dish also removes the now-empty dish. Deleting an
unknown recipe returns `404`.

## Rating

Request:

```json
{
  "stars": 4,
  "proofImageRef": "https://example.com/proofs/my-biryani.jpg"
}
```

Response:

```json
{
  "averageRating": 4.2,
  "ratingCount": 5,
  "myRating": 4,
  "myRatingProofImageRef": "https://example.com/proofs/my-biryani.jpg"
}
```

Rules:

- `stars` must be an integer from `1` to `5`.
- `proofImageRef` is optional. It can be an asset path, a web URL, or a local
  phone path, the same way `imageRef` works for recipes.
- One demo user has one rating per recipe. Sending a new rating updates the
  existing one instead of adding a second rating.
- If `proofImageRef` is omitted, the existing proof image is kept. Send an
  empty string to remove the proof image.
- The demo allows rating your own recipe because there is only one user.

## Search

```text
GET /api/search?q=biriyani
```

Search is case-insensitive and typo-tolerant. It looks at dish names, recipe
titles, main ingredients, ingredients and steps. Common filler words such as
`recipe`, `dish`, `how`, `to` and `make` are ignored, so `how to make biryani`
and `biryani recipe` both work. Every remaining query word must match somewhere.

A missing or blank `q` is treated as "no search yet" and returns `200` with an
empty `results` array.

Response:

```json
{
  "query": "biriyani",
  "results": [
    {
      "id": 5,
      "title": "Chicken Biryani",
      "dish": "Biryani",
      "mainIngredient": "rice",
      "cookingTime": 60,
      "imageRef": "asset:assets/images/biryani.jpg",
      "youtubeUrl": "https://www.youtube.com/results?search_query=chicken+biryani+recipe",
      "averageRating": 4.5,
      "ratingCount": 2,
      "myRating": 5,
      "myRatingProofImageRef": "",
      "createdAt": "2026-10-20T18:00:00Z",
      "updatedAt": null
    }
  ]
}
```

## Leaderboard

```json
{
  "leaderboard": [
    {
      "rank": 1,
      "recipe": {
        "id": 5,
        "title": "Chicken Biryani",
        "dish": "Biryani",
        "mainIngredient": "rice",
        "cookingTime": 60,
        "imageRef": "asset:assets/images/biryani.jpg",
        "youtubeUrl": "https://www.youtube.com/results?search_query=chicken+biryani+recipe",
        "averageRating": 4.5,
        "ratingCount": 2,
        "myRating": 5,
        "myRatingProofImageRef": "",
        "createdAt": "2026-10-20T18:00:00Z",
        "updatedAt": null
      },
      "averageRating": 4.5,
      "ratingCount": 2
    }
  ]
}
```

Only recipes with at least one rating appear. Sort order:

1. average rating, highest first
2. number of ratings, highest first
3. creation date, newest first

## Health

```json
{ "status": "ok", "recipes": 6 }
```
