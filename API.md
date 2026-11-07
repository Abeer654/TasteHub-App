# TasteHub API Contract

This file is the agreement between the C++ server and the Flutter app.
Do not change field names without updating both sides.

## Base URL

```text
http://<laptop-tailscale-ip>:8080
```

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
| `500` | Server or file error |

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/health` | Health check |
| `GET` | `/api/recipes` | List recipe summaries |
| `GET` | `/api/recipes/:id` | One recipe with ingredients, steps and ratings |
| `POST` | `/api/recipes` | Add a recipe |
| `PUT` | `/api/recipes/:id` | Edit a recipe |
| `DELETE` | `/api/recipes/:id` | Delete a recipe |
| `GET` | `/api/search?q=...` | Typo-tolerant search |
| `PUT` | `/api/recipes/:id/rating` | Rate a recipe (1-5) with optional proof image |
| `GET` | `/api/leaderboard` | Top-rated recipes |

## Recipe summary

Returned by `GET /api/recipes` and inside search/leaderboard results.

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
