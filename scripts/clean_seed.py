#!/usr/bin/env python3
"""Create a clean demo seed from the original output/recipes.json.

What it does:
- converts old dates like 10-10-2026 20:06 to 2026-10-10T20:06:00Z
- adds imageRef and youtubeUrl to every recipe
- makes every recipe belong to demo user 1
- removes comments and votes (not part of the demo)
- adds two extra recipes so search/leaderboard demos have data
- writes seed/recipes.json and a fresh data/recipes.json

Run from the repository root:
    python3 scripts/clean_seed.py
"""

import json
import re
from pathlib import Path
from urllib.parse import quote_plus

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "output" / "recipes.json"
SEED = ROOT / "seed" / "recipes.json"
DATA = ROOT / "data" / "recipes.json"

# A fresh clone has no output/ (it is runtime data). Fall back to the
# cleaned seed so the script can still be re-run safely.
if not SOURCE.exists():
    SOURCE = SEED

MEDIA = {
    "crispy fries": (
        "asset:assets/images/fries.jpg",
        "https://www.youtube.com/results?search_query=crispy+fries+recipe",
    ),
    "hydrabadi pulao": (
        "asset:assets/images/pulao.jpg",
        "https://www.youtube.com/results?search_query=hyderabadi+pulao+recipe",
    ),
    "peshawari karahi": (
        "asset:assets/images/karahi.jpg",
        "https://www.youtube.com/results?search_query=peshawari+karahi+recipe",
    ),
    "spicy chicken tikka": (
        "asset:assets/images/chicken-tikka.jpg",
        "https://www.youtube.com/results?search_query=chicken+tikka+recipe",
    ),
    "chicken biryani": (
        "asset:assets/images/biryani.jpg",
        "https://www.youtube.com/results?search_query=chicken+biryani+recipe",
    ),
    "beef nihari": (
        "asset:assets/images/nihari.jpg",
        "https://www.youtube.com/results?search_query=beef+nihari+recipe",
    ),
}


def normalize_date(value):
    """Return an ISO-8601 UTC date, or the original value if unknown."""
    if not isinstance(value, str) or not value.strip():
        return value
    value = value.strip()

    # 10-10-2026 20:06  or  10-10-2026 20:06:30
    match = re.match(
        r"^(\d{1,2})-(\d{1,2})-(\d{4})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?$", value
    )
    if match:
        day, month, year, hour, minute, second = match.groups()
        return (
            f"{year}-{int(month):02d}-{int(day):02d}"
            f"T{int(hour):02d}:{minute}:{int(second or 0):02d}Z"
        )

    # 2026-10-18T23:54:46  ->  2026-10-18T23:54:46Z
    match = re.match(
        r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?Z?$", value
    )
    if match:
        year, month, day, hour, minute, second = match.groups()
        return f"{year}-{month}-{day}T{hour}:{minute}:{int(second or 0):02d}Z"

    return value


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def media_for(name):
    key = name.strip().lower()
    if key in MEDIA:
        return MEDIA[key]
    return (
        f"asset:assets/images/{slug(name)}.jpg",
        f"https://www.youtube.com/results?search_query={quote_plus(name + ' recipe')}",
    )


def new_variant(variant_id, name, main_ingredient, ingredients, steps, cooking_time,
                rating, created_at):
    image_ref, youtube_url = media_for(name)
    return {
        "id": variant_id,
        "name": name,
        "ownerId": 1,
        "createdAt": created_at,
        "updatedAt": "",
        "recipe": {
            "mainIngredient": main_ingredient,
            "ingredients": ingredients,
            "steps": steps,
            "cookingTime": cooking_time,
        },
        "ratings": [{"userId": 1, "stars": rating}],
        "imageRef": image_ref,
        "youtubeUrl": youtube_url,
    }


def add_extra_recipes(data):
    """Add Biryani and Nihari so the demo has searchable, ratable recipes."""
    dishes = data.setdefault("dishes", [])
    existing = {dish.get("name", "").lower() for dish in dishes}

    if "biryani" not in existing:
        biryani = new_variant(
            5,
            "Chicken Biryani",
            "rice",
            ["rice", "chicken", "yogurt", "spices", "onion"],
            [
                "marinate the chicken",
                "fry the onions",
                "layer rice and chicken",
                "cook on low heat",
            ],
            60,
            5,
            "2026-10-20T18:00:00Z",
        )
        # A second rating makes the leaderboard average more interesting.
        biryani["ratings"].append({"userId": 2, "stars": 4})
        dishes.append(
            {
                "id": 5,
                "name": "Biryani",
                "createdAt": "2026-10-20T18:00:00Z",
                "variants": [biryani],
            }
        )

    if "nihari" not in existing:
        dishes.append(
            {
                "id": 6,
                "name": "Nihari",
                "createdAt": "2026-10-22T09:30:00Z",
                "variants": [
                    new_variant(
                        6,
                        "Beef Nihari",
                        "beef",
                        ["beef", "flour", "spices", "ginger"],
                        [
                            "cook the beef slowly",
                            "add the flour slurry",
                            "simmer until thick",
                            "garnish with ginger",
                        ],
                        180,
                        4,
                        "2026-10-22T09:30:00Z",
                    )
                ],
            }
        )

    data["lastDishId"] = max(data.get("lastDishId", 0), 6)
    data["lastVariantId"] = max(data.get("lastVariantId", 0), 6)
    data["lastCommentId"] = 0


def clean(data):
    for dish in data.get("dishes", []):
        dish["createdAt"] = normalize_date(dish.get("createdAt", ""))
        for variant in dish.get("variants", []):
            variant["createdAt"] = normalize_date(variant.get("createdAt", ""))
            variant["updatedAt"] = normalize_date(variant.get("updatedAt", ""))
            variant["ownerId"] = 1
            variant.pop("comments", None)
            variant.pop("votes", None)
            variant.setdefault("ratings", [])
            image_ref, youtube_url = media_for(variant.get("name", "recipe"))
            variant["imageRef"] = image_ref
            variant["youtubeUrl"] = youtube_url


def main():
    if not SOURCE.exists():
        raise SystemExit(f"Missing source file: {SOURCE}")

    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    clean(data)
    add_extra_recipes(data)

    SEED.parent.mkdir(parents=True, exist_ok=True)
    DATA.parent.mkdir(parents=True, exist_ok=True)

    text = json.dumps(data, indent=4, ensure_ascii=False) + "\n"
    SEED.write_text(text, encoding="utf-8")
    DATA.write_text(text, encoding="utf-8")

    recipes = sum(len(dish.get("variants", [])) for dish in data.get("dishes", []))
    dish_count = len(data.get("dishes", []))
    print(f"Wrote {SEED}")
    print(f"Wrote {DATA}")
    print(f"Recipes: {recipes} in {dish_count} dishes")


if __name__ == "__main__":
    main()
