# TasteHub API Contract

This file is the agreement between the C++ server and the Flutter app.
Do not change field names without updating both sides.

## Base URL

```text
http://<laptop-tailscale-ip>:8080
```

Opening the base URL in a browser returns `404`; the JSON endpoints below are
the client contract.

Reads are public. Writes require a bearer token from `/api/auth/login` or
`/api/auth/signup`.

All JSON requests and responses use:

```text
Content-Type: application/json
```

### Demo accounts

| Username | Password | User id |
|---|---|---|
| `junaid` | `tastehub` | `1` |
| `guest` | `guest` | `2` |

Each account has one active session. Logging in again replaces the previous
token, so the app on one device will get `401` after the same account logs in
somewhere else.

## Errors

Every error has the same shape:

```json
{ "error": "Recipe not found" }
```

| Status | Meaning |
|---|---|
| `200` | OK |
| `201` | Recipe created, account created, or photo uploaded |
| `400` | Invalid input, malformed JSON, or unsupported image |
| `401` | Login required, wrong password, or expired/replaced token |
| `403` | Logged in, but not the owner of this recipe |
| `404` | Recipe or route not found |
| `409` | Duplicate title in the same dish, or username already taken |
| `413` | JSON body over 1 MB, request over 12 MB, or image over 10 MB |
| `422` | AI could not extract ingredients or steps |
| `500` | Server or file error |
| `502` | Gemini request failed |
| `503` | Gemini is not configured, rate-limited, or busy |

Request bodies must be valid JSON objects. Wrong field types and non-positive
recipe ids return `400`. Unknown API routes return a JSON `404`.

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `GET` | `/api/health` | No | Health check |
| `POST` | `/api/auth/signup` | No | Create an account and log in |
| `POST` | `/api/auth/login` | No | Log in and receive a token |
| `POST` | `/api/auth/logout` | Yes | End this token's session |
| `GET` | `/api/auth/me` | Yes | Validate a token and return the account |
| `GET` | `/api/recipes` | Optional | List recipe summaries |
| `GET` | `/api/recipes/:id` | Optional | One recipe with ingredients, steps and ratings |
| `POST` | `/api/recipes` | Yes | Add a recipe owned by the logged-in user |
| `POST` | `/api/recipes/parse` | Yes | Turn a description into an AI recipe draft |
| `PUT` | `/api/recipes/:id` | Owner | Edit a recipe |
| `DELETE` | `/api/recipes/:id` | Owner | Delete a recipe |
| `PUT` | `/api/recipes/:id/rating` | Yes | Rate a recipe (1-5) with optional proof photo |
| `GET` | `/api/search?q=...` | Optional | Typo-tolerant search |
| `GET` | `/api/leaderboard?dish=...` | Optional | Rank recipes, optionally inside one dish |
| `POST` | `/api/images` | Yes | Upload a JPEG/PNG/WebP photo |

For all endpoints, send the token as:

```text
Authorization: Bearer <token>
```

If the token is omitted on a read, `myRating` is `0` and
`myRatingProofImageRef` is empty.

## Authentication

### Sign up

```text
POST /api/auth/signup
```

```json
{
  "username": "newcook",
  "password": "at-least-6-characters"
}
```

Rules: username is 3-20 characters and starts with a letter or number.
Passwords are 6-64 characters. A duplicate username returns `409`.

Response (`201`):

```json
{
  "token": "a-long-random-hex-token",
  "user": { "id": 3, "username": "newcook" }
}
```

### Log in

```text
POST /api/auth/login
```

Request and response are the same as signup, except login returns `200`.
A wrong username or password returns `401`.

### Current account

```text
GET /api/auth/me
Authorization: Bearer <token>
```

```json
{
  "user": { "id": 1, "username": "junaid" }
}
```

### Log out

```text
POST /api/auth/logout
Authorization: Bearer <token>
```

```json
{ "loggedOut": true }
```

Password hashes are never included in any response.

## Recipe summary

Returned by `GET /api/recipes` (as a JSON array) and inside search and
leaderboard results.

```json
{
  "id": 5,
  "title": "Chicken Biryani",
  "dish": "Biryani",
  "ownerId": 1,
  "ownerName": "junaid",
  "mainIngredient": "rice",
  "cookingTime": 60,
  "imageRef": "/uploads/img_1a2b3c4d.png",
  "youtubeUrl": "https://www.youtube.com/results?search_query=chicken+biryani+recipe",
  "averageRating": 4.5,
  "ratingCount": 2,
  "myRating": 5,
  "myRatingProofImageRef": "",
  "createdAt": "2026-10-20T18:00:00Z",
  "updatedAt": null
}
```

Seed recipes deliberately have `"imageRef": ""`. The clients show a warm
gradient placeholder until a user uploads a photo or adds an image URL.

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
      "userName": "junaid",
      "stars": 5,
      "proofImageRef": "/uploads/img_5e6f7a8b.jpg"
    },
    {
      "userId": 2,
      "userName": "guest",
      "stars": 4,
      "proofImageRef": ""
    }
  ]
}
```

`ratings` is only included in the detail response. `userName` lets the UI show
who rated instead of just a user id. `proofImageRef` is the optional photo a
user attached as proof that they cooked the recipe.

## Create / edit request

`POST /api/recipes` (login required):

```json
{
  "dish": "Biryani",
  "title": "Chicken Biryani",
  "mainIngredient": "rice",
  "ingredients": ["rice", "chicken", "yogurt", "spices", "onion"],
  "steps": ["marinate the chicken", "fry the onions", "layer rice and chicken"],
  "cookingTime": 60,
  "imageRef": "/uploads/img_1a2b3c4d.png",
  "youtubeUrl": "https://www.youtube.com/results?search_query=chicken+biryani+recipe"
}
```

`PUT /api/recipes/:id` accepts any of the same fields for a partial update.
Only the owner may edit or delete; another logged-in user gets `403`.
Changing `dish` after creation returns `400`.

Rules:

- `title`, `ingredients`, and `steps` are required on create.
- `dish` is optional; it defaults to `"My Recipes"`.
- `imageRef` and `youtubeUrl` are optional strings.
- `imageRef` and `proofImageRef` may be:
  - a path returned by `POST /api/images`, for example `/uploads/img_1a2b3c4d.png`
  - a web URL: `https://...`
- The app uploads real photos from the device gallery/file picker. It does not
  generate images or use stock photos.
- Dates are ISO-8601 UTC, for example `2026-11-06T12:30:00Z`.

## Photo upload

```text
POST /api/images
Authorization: Bearer <token>
Content-Type: multipart/form-data
```

Send one file field named `file`. The server checks the file's magic bytes, not
its filename:

- JPEG (`.jpg`, `.jpeg`)
- PNG (`.png`)
- WebP (`.webp`)
- maximum 10 MB

Response (`201`):

```json
{ "imageRef": "/uploads/img_1a2b3c4d.png" }
```

The file is stored under the server's uploads folder and served read-only at:

```text
GET /uploads/<filename>
```

Uploading without a valid token returns `401`. A non-image or empty file
returns `400`. A file over 10 MB returns `413`.

The Flutter app resolves `/uploads/...` against the server base
URL. Absolute `http(s)` URLs are used as-is.

## AI recipe draft (natural-language input)

```text
POST /api/recipes/parse
Authorization: Bearer <token>
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
Authorization: Bearer <token>
```

Response:

```json
{
  "deleted": true,
  "id": 5
}
```

Only the owner may delete. Deleting the last recipe in a dish also removes the
now-empty dish. Deleting an unknown recipe returns `404`.

## Rating

```text
PUT /api/recipes/:id/rating
Authorization: Bearer <token>
```

Request:

```json
{
  "stars": 4,
  "proofImageRef": "/uploads/img_9f8e7d6c.jpg"
}
```

Response:

```json
{
  "averageRating": 4.2,
  "ratingCount": 5,
  "myRating": 4,
  "myRatingProofImageRef": "/uploads/img_9f8e7d6c.jpg"
}
```

Rules:

- `stars` must be an integer from `1` to `5`.
- Any logged-in user may rate any recipe **except one they authored**. A
  self-rating attempt returns `403` (`"You cannot rate your own recipe"`), and
  clients hide the rating control on own recipes.
- Each user has one rating per recipe. Sending a new rating updates that user's
  existing rating instead of adding a second one.
- `proofImageRef` is optional. It accepts the same uploaded path or web URL as
  a recipe photo.
- If `proofImageRef` is omitted, the existing proof image is kept. Send an
  empty string to remove the proof image.
- `myRating` and `myRatingProofImageRef` are per-user values; other users'
  ratings appear in the detail `ratings` array with their usernames.
- Rating without login returns `401`. A malformed rating returns `400`.
  Rating a recipe you own returns `403`; rating an unknown recipe `404`.

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
      "ownerId": 1,
      "ownerName": "junaid",
      "mainIngredient": "rice",
      "cookingTime": 60,
      "imageRef": "",
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

## Ranking

```text
GET /api/leaderboard?dish=Biryani
```

The app ranks recipes **inside each dish**. The old global dish leaderboard is
gone. With `dish`, only that dish's recipes are returned; without it, every
individual recipe is ranked together for compatibility.

```json
{
  "dish": "Biryani",
  "leaderboard": [
    {
      "rank": 1,
      "recipe": {
        "id": 5,
        "title": "Chicken Biryani",
        "dish": "Biryani",
        "ownerId": 1,
        "ownerName": "junaid",
        "mainIngredient": "rice",
        "cookingTime": 60,
        "imageRef": "",
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

Sort order:

1. average rating, highest first
2. number of ratings, highest first
3. creation date, newest first

Unrated recipes come after rated recipes, newest first. They have `"rank": 0`
and `"isNew": true`, which the clients show as a **New** badge. The top recipe
in a dish with at least one rating is highlighted as **Top pick**.

The Flutter home screen groups `GET /api/recipes` client-side because a dish
page needs the unrated recipes too.

## Health

```json
{ "status": "ok", "recipes": 18, "users": 3 }
```

`recipes` counts individual recipes, not dishes. The seed data contains six
dishes with three recipes each and three demo accounts: `junaid`, `guest` and
`critic` (the critic re-homed the legacy self-ratings so no author rates their
own recipe).
