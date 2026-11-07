#!/usr/bin/env python3
"""Smoke test for the TasteHub HTTP API.

Run while the C++ server is running:
    python3 tests/smoke_test.py

The test adds and deletes a recipe. Reset the demo data afterward:
    ./scripts/reset-demo.sh
"""

import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8080"


def request(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            text = response.read().decode()
            return response.status, json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        text = error.read().decode()
        return error.code, json.loads(text) if text else None


def check(condition, message):
    if condition:
        print(f"PASS: {message}")
    else:
        print(f"FAIL: {message}")
        sys.exit(1)


status, health = request("GET", "/api/health")
check(status == 200, "health returns 200")
check(health["status"] == "ok", "health status is ok")
check(health["recipes"] >= 6, "health reports at least 6 recipes")

status, recipes = request("GET", "/api/recipes")
check(status == 200, "list returns 200")
check(isinstance(recipes, list) and len(recipes) >= 6, "list has at least 6 recipes")

status, detail = request("GET", "/api/recipes/5")
check(status == 200, "detail returns 200")
check(detail["title"] == "Chicken Biryani", "recipe 5 is Chicken Biryani")
check(isinstance(detail.get("ingredients"), list), "detail has ingredients")
check(isinstance(detail.get("steps"), list), "detail has steps")

status, search = request("GET", "/api/search?q=biriyani")
check(status == 200, "typo search returns 200")
check(
    any(item["title"] == "Chicken Biryani" for item in search["results"]),
    "typo search finds Biryani",
)

status, search = request("GET", "/api/search?q=chiken")
check(status == 200, "chicken typo search returns 200")
check(len(search["results"]) > 0, "chicken typo search returns results")

body = {
    "dish": "Smoke Test",
    "title": "Smoke Test Curry",
    "mainIngredient": "chicken",
    "ingredients": ["chicken", "spices"],
    "steps": ["mix", "cook"],
    "cookingTime": 20,
    "imageRef": "",
    "youtubeUrl": "",
}
status, created = request("POST", "/api/recipes", body)
check(status == 201, "create returns 201")
recipe_id = created["id"]
check(created["title"] == "Smoke Test Curry", "created recipe has the right title")

status, rating = request("PUT", f"/api/recipes/{recipe_id}/rating", {"stars": 5})
check(status == 200, "rating returns 200")
check(rating["myRating"] == 5, "rating is saved")

status, leaderboard = request("GET", "/api/leaderboard")
check(status == 200, "leaderboard returns 200")
check(
    any(
        item["recipe"]["id"] == recipe_id
        for item in leaderboard["leaderboard"]
    ),
    "new recipe is on the leaderboard",
)

status, updated = request(
    "PUT", f"/api/recipes/{recipe_id}", {"title": "Smoke Test Curry Updated"}
)
check(status == 200, "update returns 200")
check(updated["title"] == "Smoke Test Curry Updated", "title was updated")

status, deleted = request("DELETE", f"/api/recipes/{recipe_id}")
check(status == 200, "delete returns 200")
check(deleted["deleted"] is True, "delete response is correct")

status, missing = request("GET", f"/api/recipes/{recipe_id}")
check(status == 404, "deleted recipe returns 404")

print("\nAll smoke tests passed.")
