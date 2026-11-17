#!/usr/bin/env python3
"""HTTP smoke test for TasteHub Stage 2.

By default this script starts its own temporary server, so it never touches the
real data/ folder:

    make http-test

To run read-only checks against a server that is already running:

    python3 tests/smoke_test.py --base-url http://127.0.0.1:8080

The read-only mode logs in with the demo accounts but does not create, update,
delete or rate anything.
"""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SERVER_BINARY = REPO_ROOT / "build" / "tastehub-server"
SEED_FILE = REPO_ROOT / "seed" / "recipes.json"
USERS_SEED_FILE = REPO_ROOT / "seed" / "users.json"

# A real 1x1 transparent PNG. The server checks magic bytes, not names.
TINY_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000d4944415478da63f8cf00000301010018dd8db00000000049454e44"
    "ae426082"
)


# ------------------------------------------------------------
#  Small HTTP and assertion helpers
# ------------------------------------------------------------

def request(base_url, method, path, body=None, raw_body=None, token=None):
    """Return (status, parsed_json_or_none, content_type)."""
    data = None
    if raw_body is not None:
        data = raw_body.encode()
    elif body is not None:
        data = json.dumps(body).encode()

    http_request = urllib.request.Request(base_url + path, data=data,
                                          method=method)
    http_request.add_header("Accept", "application/json")
    if token:
        http_request.add_header("Authorization", "Bearer " + token)
    if data is not None:
        http_request.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(http_request, timeout=10) as response:
            text = response.read().decode()
            return (response.status,
                    json.loads(text) if text else None,
                    response.headers.get_content_type())
    except urllib.error.HTTPError as error:
        text = error.read().decode()
        return (error.code,
                json.loads(text) if text else None,
                error.headers.get_content_type())


def request_bytes(base_url, path):
    """Return (status, body_bytes, content_type) for binary files."""
    http_request = urllib.request.Request(base_url + path, method="GET")

    try:
        with urllib.request.urlopen(http_request, timeout=10) as response:
            return (response.status,
                    response.read(),
                    response.headers.get_content_type())
    except urllib.error.HTTPError as error:
        return (error.code, error.read(), error.headers.get_content_type())


def upload_image(base_url, token, content, filename="photo.png",
                 content_type="image/png"):
    """POST a multipart form to /api/images and return (status, body, type)."""
    boundary = "----TasteHub" + uuid.uuid4().hex
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: {content_type}\r\n"
        "\r\n"
    ).encode() + content + f"\r\n--{boundary}--\r\n".encode()

    http_request = urllib.request.Request(
        base_url + "/api/images", data=body, method="POST")
    http_request.add_header("Accept", "application/json")
    http_request.add_header("Content-Type",
                            "multipart/form-data; boundary=" + boundary)
    if token:
        http_request.add_header("Authorization", "Bearer " + token)

    try:
        with urllib.request.urlopen(http_request, timeout=10) as response:
            text = response.read().decode()
            return (response.status,
                    json.loads(text) if text else None,
                    response.headers.get_content_type())
    except urllib.error.HTTPError as error:
        text = error.read().decode()
        return (error.code,
                json.loads(text) if text else None,
                error.headers.get_content_type())


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"PASS: {message}")


def check_status(status, expected, message):
    check(status == expected, f"{message} (got {status}, expected {expected})")


def check_error(status, body, expected_status, message):
    check_status(status, expected_status, message)
    check(isinstance(body, dict) and "error" in body,
          f"{message}: response is a JSON error")


def find_recipe(recipes, recipe_id):
    for recipe in recipes:
        if recipe.get("id") == recipe_id:
            return recipe
    return None


def find_leaderboard_entry(leaderboard, recipe_id):
    for entry in leaderboard:
        if entry.get("recipe", {}).get("id") == recipe_id:
            return entry
    return None


def login(base_url, username, password):
    status, body, _ = request(
        base_url, "POST", "/api/auth/login",
        body={"username": username, "password": password})
    check_status(status, 200, f"{username} can log in")
    token = body.get("token", "")
    check(len(token) > 20, f"{username} receives a session token")
    return token


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


# ------------------------------------------------------------
#  Server lifecycle for the self-contained test
# ------------------------------------------------------------

def start_server(work_dir, log_path):
    """Start the server from work_dir/run and wait until health responds."""
    log_file = open(log_path, "w", buffering=1)
    port = free_port()

    environment = os.environ.copy()
    # The temporary cwd has no .env, so these must be absent for the
    # "Gemini is not configured" check to be deterministic.
    environment.pop("GEMINI_API_KEY", None)
    environment.pop("GOOGLE_API_KEY", None)

    process = subprocess.Popen(
        [str(SERVER_BINARY),
         "--host", "127.0.0.1",
         "--port", str(port),
         "--data-dir", "../data",
         "--uploads-dir", "../data/uploads"],
        cwd=str(work_dir / "run"),
        env=environment,
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )

    base_url = f"http://127.0.0.1:{port}"
    deadline = time.time() + 10

    while time.time() < deadline:
        if process.poll() is not None:
            log_file.flush()
            log_file.close()
            raise RuntimeError(
                f"server exited during startup:\n{Path(log_path).read_text()}")

        try:
            status, _, _ = request(base_url, "GET", "/api/health")
            if status == 200:
                return process, log_file, base_url
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            pass

        time.sleep(0.1)

    process.terminate()
    process.wait(timeout=5)
    log_file.close()
    raise RuntimeError(f"server did not become ready:\n{Path(log_path).read_text()}")


def stop_server(process, log_file):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    if log_file is not None:
        log_file.close()


def check_duplicate_port_rejected(base_url, work_dir, log_path):
    """A second server on the same port must fail instead of sharing requests."""
    port = int(base_url.rsplit(":", 1)[1])
    log_file = open(log_path, "w", buffering=1)

    environment = os.environ.copy()
    environment.pop("GEMINI_API_KEY", None)
    environment.pop("GOOGLE_API_KEY", None)

    process = subprocess.Popen(
        [str(SERVER_BINARY),
         "--host", "127.0.0.1",
         "--port", str(port),
         "--data-dir", "../data",
         "--uploads-dir", "../data/uploads"],
        cwd=str(work_dir / "run"),
        env=environment,
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )

    try:
        return_code = process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
        log_file.close()
        raise AssertionError("a second server bound the same port") from None

    log_file.close()
    output = Path(log_path).read_text()

    check(return_code != 0, "second server on the same port exits with an error")
    check("could not listen" in output,
          "second server reports the port conflict")


# ------------------------------------------------------------
#  Read-only checks (also used by --base-url mode)
# ------------------------------------------------------------

def run_read_only_checks(base_url):
    status, health, content_type = request(base_url, "GET", "/api/health")
    check_status(status, 200, "health returns 200")
    check(content_type == "application/json",
          "health response is application/json")
    check(health.get("status") == "ok", "health status is ok")
    check(health.get("recipes", 0) >= 18,
          "health reports the seeded recipes")
    check(health.get("users", 0) >= 3,
          "health reports the three demo accounts")

    # ---- authentication ----
    junaid = login(base_url, "junaid", "tastehub")
    guest = login(base_url, "guest", "guest")

    status, me, _ = request(base_url, "GET", "/api/auth/me", token=junaid)
    check_status(status, 200, "me returns 200 with a token")
    check(me.get("user", {}).get("id") == 1, "junaid is user 1")
    check(me.get("user", {}).get("username") == "junaid",
          "me includes the username")
    check("passwordHash" not in json.dumps(me),
          "me never exposes password hashes")

    status, body, _ = request(base_url, "GET", "/api/auth/me")
    check_error(status, body, 401, "me without a token is rejected")

    status, body, _ = request(
        base_url, "POST", "/api/auth/login",
        body={"username": "junaid", "password": "wrong"})
    check_error(status, body, 401, "wrong password is rejected")

    # Logging in again replaces the previous session, so re-login after the
    # deliberate wrong-password attempt only changed nothing. Keep the tokens.

    # ---- public recipe reads ----
    status, recipes, _ = request(base_url, "GET", "/api/recipes")
    check_status(status, 200, "recipe list returns 200")
    check(isinstance(recipes, list) and len(recipes) >= 18,
          "recipe list has the seeded recipes")
    check(all("ownerName" in item for item in recipes),
          "recipe summaries include ownerName")
    check(all(item.get("myRating") == 0 for item in recipes),
          "anonymous list has myRating 0")

    status, mine, _ = request(base_url, "GET", "/api/recipes", token=junaid)
    # Self-ratings are banned: junaid owns recipe 5, so his visible
    # rating is the cross-rating on guest's Yakhni Pulao (recipe 9).
    summary = find_recipe(mine, 5)
    check(summary is not None and summary.get("myRating") == 0,
          "an author has no self-rating on their own recipe")
    summary = find_recipe(mine, 9)
    check(summary is not None and summary.get("myRating") == 5,
          "a logged-in user sees their cross-rating")

    status, detail, _ = request(base_url, "GET", "/api/recipes/5")
    check_status(status, 200, "recipe detail returns 200")
    check(detail.get("title") == "Chicken Biryani",
          "recipe 5 is Chicken Biryani")
    check(isinstance(detail.get("ingredients"), list),
          "detail has ingredients")
    check(isinstance(detail.get("steps"), list), "detail has steps")
    check(isinstance(detail.get("ratings"), list), "detail has ratings")
    check(all("userName" in rating for rating in detail.get("ratings", [])),
          "detail ratings include usernames")

    status, search, _ = request(base_url, "GET", "/api/search?q=briyani")
    check_status(status, 200, "typo search returns 200")
    check(any(item.get("id") == 5 for item in search.get("results", [])),
          "typo search finds Chicken Biryani")

    status, search, _ = request(base_url, "GET", "/api/search?q=chiken")
    check_status(status, 200, "chicken typo search returns 200")
    check(len(search.get("results", [])) > 0,
          "chicken typo search returns results")

    status, search, _ = request(base_url, "GET", "/api/search?q=")
    check_status(status, 200, "blank search returns 200")
    check(search.get("results") == [],
          "blank search returns an empty result list")

    # ---- per-dish ranking ----
    status, biryani, _ = request(
        base_url, "GET", "/api/leaderboard?dish=Biryani")
    check_status(status, 200, "dish leaderboard returns 200")
    check(biryani.get("dish") == "Biryani", "dish leaderboard echoes the filter")
    entries = biryani.get("leaderboard", [])
    chicken = find_leaderboard_entry(entries, 5)
    check(chicken is not None, "Biryani leaderboard contains Chicken Biryani")
    check(chicken.get("rank") == 1, "Chicken Biryani is #1 in Biryani")
    check([entry.get("rank") for entry in entries] == [1, 2, 3],
          "Biryani ranks are 1, 2 and 3")

    status, karahi, _ = request(
        base_url, "GET", "/api/leaderboard?dish=Karahi")
    check_status(status, 200, "Karahi leaderboard returns 200")
    entries = karahi.get("leaderboard", [])
    mutton = find_leaderboard_entry(entries, 12)
    check(mutton is not None and mutton.get("rank") == 0,
          "the unrated Mutton Karahi has rank 0")
    check(mutton.get("isNew") is True, "the unrated recipe is marked as new")
    check(entries[-1].get("recipe", {}).get("id") == 12,
          "unrated recipes come after rated recipes")

    status, leaderboard, _ = request(base_url, "GET", "/api/leaderboard")
    check_status(status, 200, "global leaderboard returns 200")
    check(find_leaderboard_entry(leaderboard.get("leaderboard", []), 5)
          is not None, "global leaderboard contains Chicken Biryani")

    # ---- error handling ----
    status, body, _ = request(base_url, "GET", "/api/recipes/999999")
    check_error(status, body, 404, "missing recipe")

    status, body, _ = request(base_url, "GET", "/api/recipes/not-a-number")
    check_error(status, body, 400, "malformed recipe id")

    status, body, _ = request(base_url, "GET", "/api/does-not-exist")
    check_error(status, body, 404, "unknown route")

    return junaid, guest


# ------------------------------------------------------------
#  Mutating checks for the self-contained test
# ------------------------------------------------------------

def run_mutation_checks(base_url, junaid, guest):
    _, health, _ = request(base_url, "GET", "/api/health")
    recipe_count_before = health["recipes"]

    new_recipe = {
        "dish": "Smoke Test",
        "title": "Smoke Test Curry",
        "mainIngredient": "chicken",
        "ingredients": ["chicken", "spices"],
        "steps": ["mix the ingredients", "cook until ready"],
        "cookingTime": 20,
        "imageRef": "",
        "youtubeUrl": "",
    }

    # ---- login is required for writes ----
    status, body, _ = request(
        base_url, "POST", "/api/recipes", body=new_recipe)
    check_error(status, body, 401, "creating a recipe without login is rejected")

    status, body, _ = request(
        base_url, "PUT", "/api/recipes/5/rating", body={"stars": 5})
    check_error(status, body, 401, "rating without login is rejected")

    status, body, _ = request(
        base_url, "DELETE", "/api/recipes/5", token="")
    check_error(status, body, 401, "deleting without login is rejected")

    # ---- image uploads ----
    status, uploaded, content_type = upload_image(base_url, junaid, TINY_PNG)
    check_status(status, 201, "PNG upload returns 201")
    check(content_type == "application/json",
          "upload response is application/json")
    image_ref = uploaded.get("imageRef", "")
    check(image_ref.startswith("/uploads/"),
          "upload returns an /uploads/ image path")

    status, image_bytes, image_type = request_bytes(base_url, image_ref)
    check_status(status, 200, "uploaded image can be downloaded")
    check(image_bytes == TINY_PNG, "uploaded image bytes are intact")
    check(image_type == "image/png", "uploaded image is served as image/png")

    status, body, _ = upload_image(
        base_url, junaid, b"hello", filename="notes.txt",
        content_type="text/plain")
    check_error(status, body, 400, "non-image upload is rejected")

    status, body, _ = upload_image(base_url, None, TINY_PNG)
    check_error(status, body, 401, "upload without login is rejected")

    # ---- create and ownership ----
    status, created, content_type = request(
        base_url, "POST", "/api/recipes", body={**new_recipe,
                                                "imageRef": image_ref},
        token=junaid)
    check_status(status, 201, "create returns 201")
    check(content_type == "application/json",
          "create response is application/json")
    check(created.get("title") == "Smoke Test Curry",
          "created recipe has the right title")
    check(created.get("ownerId") == 1, "created recipe belongs to junaid")
    check(created.get("imageRef") == image_ref,
          "created recipe keeps the uploaded image")
    recipe_id = created["id"]

    status, body, _ = request(
        base_url, "POST", "/api/recipes", body=new_recipe, token=junaid)
    check_error(status, body, 409, "duplicate title")

    status, body, _ = request(
        base_url, "POST", "/api/recipes", raw_body="{not valid json",
        token=junaid)
    check_error(status, body, 400, "malformed create body")

    status, body, _ = request(
        base_url, "POST", "/api/recipes",
        body={"dish": "Smoke Test", "ingredients": ["x"], "steps": ["y"]},
        token=junaid)
    check_error(status, body, 400, "missing create title")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}",
        body={"title": "Guest Hijack"}, token=guest)
    check_error(status, body, 403, "a non-owner cannot edit the recipe")

    status, body, _ = request(
        base_url, "DELETE", f"/api/recipes/{recipe_id}", token=guest)
    check_error(status, body, 403, "a non-owner cannot delete the recipe")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}",
        body={"title": "Anonymous Hijack"})
    check_error(status, body, 401, "an anonymous edit is rejected")

    # ---- per-user ratings ----
    status, rating, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 4, "proofImageRef": "https://example.com/guest.jpg"},
        token=guest)
    check_status(status, 200, "guest can rate the new recipe")
    check(rating.get("myRating") == 4, "guest's rating value is saved")

    status, detail, _ = request(
        base_url, "GET", f"/api/recipes/{recipe_id}", token=guest)
    check(detail.get("myRating") == 4, "guest sees their own rating")
    check(detail.get("myRatingProofImageRef") ==
          "https://example.com/guest.jpg",
          "guest proof image is saved")

    status, detail, _ = request(
        base_url, "GET", f"/api/recipes/{recipe_id}", token=junaid)
    check(detail.get("myRating") == 0,
          "junaid's rating stays separate from guest's")
    check(any(item.get("userName") == "guest"
              and item.get("stars") == 4
              for item in detail.get("ratings", [])),
          "detail ratings include the guest's name and stars")

    # Authors cannot rate their own recipes: recipe 5 belongs to junaid.
    status, body, _ = request(
        base_url, "PUT", "/api/recipes/5/rating",
        body={"stars": 5}, token=junaid)
    check_error(status, body, 403, "an author cannot rate their own recipe")

    # Rating an existing seed recipe he does not own replaces only his
    # own rating.
    status, rating, _ = request(
        base_url, "PUT", "/api/recipes/9/rating",
        body={"stars": 5, "proofImageRef": image_ref}, token=junaid)
    check_status(status, 200, "junaid can rate a recipe he does not own")
    check(rating.get("myRatingProofImageRef") == image_ref,
          "an uploaded image can be used as the rating proof")

    # Omitting the proof keeps it; sending an empty string clears it.
    status, rating, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 3}, token=guest)
    check_status(status, 200, "rating without proof returns 200")
    check(rating.get("myRatingProofImageRef") ==
          "https://example.com/guest.jpg",
          "omitted proof keeps the existing image")

    status, rating, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 4, "proofImageRef": ""}, token=guest)
    check_status(status, 200, "rating with empty proof returns 200")
    check(rating.get("myRatingProofImageRef") == "",
          "empty proof clears the image")

    # Put a good proof back for the detail/list/leaderboard checks.
    status, rating, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 5,
              "proofImageRef": "https://example.com/proofs/smoke-curry.jpg"},
        token=guest)
    check_status(status, 200, "rating can restore the proof image")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 0}, token=guest)
    check_error(status, body, 400, "rating below 1 is rejected")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": "five"}, token=guest)
    check_error(status, body, 400, "non-integer rating is rejected")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 5, "proofImageRef": 123}, token=guest)
    check_error(status, body, 400, "non-string proof is rejected")

    # ---- reads after the writes ----
    status, detail, _ = request(
        base_url, "GET", f"/api/recipes/{recipe_id}", token=guest)
    check_status(status, 200, "created recipe detail returns 200")
    check(detail.get("myRatingProofImageRef") ==
          "https://example.com/proofs/smoke-curry.jpg",
          "detail includes the viewer's proof")
    check(any(item.get("proofImageRef") ==
              "https://example.com/proofs/smoke-curry.jpg"
              for item in detail.get("ratings", [])),
          "detail ratings include the proof image")

    status, recipes, _ = request(
        base_url, "GET", "/api/recipes", token=guest)
    summary = find_recipe(recipes, recipe_id)
    check(summary is not None, "created recipe appears in the list")
    check(summary.get("myRatingProofImageRef") ==
          "https://example.com/proofs/smoke-curry.jpg",
          "list summary includes the viewer's proof")

    status, search, _ = request(base_url, "GET", "/api/search?q=smoke")
    check_status(status, 200, "searching the new recipe returns 200")
    check(find_recipe(search.get("results", []), recipe_id) is not None,
          "search finds the new recipe")

    status, board, _ = request(
        base_url, "GET", "/api/leaderboard?dish=Smoke%20Test")
    check_status(status, 200, "new dish leaderboard returns 200")
    entry = find_leaderboard_entry(board.get("leaderboard", []), recipe_id)
    check(entry is not None, "new recipe appears in its dish ranking")
    check(entry.get("rank") == 1, "the only recipe in the dish is #1")
    check(entry.get("averageRating") == 5.0,
          "new recipe has the expected average rating")

    # ---- owner edit ----
    status, updated, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}",
        body={"title": "Smoke Test Curry Updated"}, token=junaid)
    check_status(status, 200, "the owner can update the recipe")
    check(updated.get("title") == "Smoke Test Curry Updated",
          "title was updated")
    check(updated.get("updatedAt") is not None,
          "update sets updatedAt")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}",
        body={"dish": "Another Dish"}, token=junaid)
    check_error(status, body, 400, "changing dish is rejected")

    status, body, _ = request(
        base_url, "POST", "/api/recipes/parse",
        body={"text": "I made chicken biryani with rice, chicken and spices."})
    check_error(status, body, 401, "AI parse requires login")

    status, body, _ = request(
        base_url, "POST", "/api/recipes/parse",
        body={"text": "short"}, token=junaid)
    check_error(status, body, 400, "short AI description is rejected")

    status, body, _ = request(
        base_url, "POST", "/api/recipes/parse",
        body={"text": "I made chicken biryani with rice, chicken and spices."},
        token=junaid)
    check_error(status, body, 503, "AI parse without a key is unavailable")

    _, health_after_parse, _ = request(base_url, "GET", "/api/health")
    check(health_after_parse["recipes"] == recipe_count_before + 1,
          "AI parse did not save a recipe")

    return recipe_id, recipe_count_before, image_ref


def run_persistence_and_delete_checks(base_url, data_dir, recipe_id,
                                      recipe_count_before, image_ref,
                                      junaid):
    status, detail, _ = request(
        base_url, "GET", f"/api/recipes/{recipe_id}", token=junaid)
    check_status(status, 200, "created recipe survives a server restart")
    check(detail.get("title") == "Smoke Test Curry Updated",
          "updated title survives a server restart")
    check(detail.get("imageRef") == image_ref,
          "the uploaded recipe image survives a server restart")
    check(any(item.get("proofImageRef") ==
              "https://example.com/proofs/smoke-curry.jpg"
              for item in detail.get("ratings", [])),
          "rating proof survives a server restart")

    status, _, image_type = request_bytes(base_url, image_ref)
    check_status(status, 200, "the uploaded image survives a server restart")
    check(image_type == "image/png", "the image still has the right type")

    status, body, _ = request(
        base_url, "DELETE", f"/api/recipes/{recipe_id}", token=junaid)
    check_status(status, 200, "the owner can delete the recipe")
    check(body.get("deleted") is True, "delete response is correct")

    status, body, _ = request(base_url, "GET", f"/api/recipes/{recipe_id}")
    check_error(status, body, 404, "deleted recipe is gone")

    status, health, _ = request(base_url, "GET", "/api/health")
    check_status(status, 200, "health returns 200 after delete")
    check(health.get("recipes") == recipe_count_before,
          "delete restores the original recipe count")

    data_file = data_dir / "recipes.json"
    check(data_file.exists(), "server wrote recipes.json")
    check(not (data_dir / "recipes.json.tmp").exists(),
          "server left no .tmp save file")

    saved = json.loads(data_file.read_text())
    check(all(dish.get("variants") for dish in saved.get("dishes", [])),
          "empty dish was removed after deleting its last recipe")


# ------------------------------------------------------------
#  Entry point
# ------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="TasteHub HTTP smoke test")
    parser.add_argument("--base-url",
                        help="Run read-only checks against a running server")
    args = parser.parse_args()

    if args.base_url:
        try:
            run_read_only_checks(args.base_url.rstrip("/"))
        except Exception as error:
            print(f"FAIL: {error}")
            return 1
        print("\nAll read-only smoke tests passed.")
        return 0

    if not SERVER_BINARY.exists():
        print("FAIL: build/tastehub-server is missing; run `make server` first")
        return 1

    temp_parent = Path("/tmp/opencode")
    if not temp_parent.is_dir():
        temp_parent = Path(tempfile.gettempdir())

    work_dir = Path(tempfile.mkdtemp(prefix="tastehub-http-", dir=str(temp_parent)))
    (work_dir / "run").mkdir()
    (work_dir / "seed").mkdir()
    shutil.copyfile(SEED_FILE, work_dir / "seed" / "recipes.json")
    shutil.copyfile(USERS_SEED_FILE, work_dir / "seed" / "users.json")
    data_dir = work_dir / "data"

    process = None
    log_file = None
    last_log = work_dir / "server.log"

    try:
        process, log_file, base_url = start_server(work_dir, last_log)
        junaid, guest = run_read_only_checks(base_url)
        check_duplicate_port_rejected(
            base_url, work_dir, work_dir / "server-duplicate.log")
        recipe_id, recipe_count_before, image_ref = run_mutation_checks(
            base_url, junaid, guest)

        stop_server(process, log_file)
        process, log_file = None, None

        # Restart against the same data directory to prove persistence.
        last_log = work_dir / "server-restart.log"
        process, log_file, base_url = start_server(work_dir, last_log)
        run_persistence_and_delete_checks(
            base_url, data_dir, recipe_id, recipe_count_before, image_ref,
            junaid)

        stop_server(process, log_file)
        process, log_file = None, None

        server_output = ""
        for log_path in (work_dir / "server.log",
                         work_dir / "server-restart.log"):
            if log_path.exists():
                server_output += log_path.read_text()

        check("Choice:" not in server_output,
              "server never prints a console prompt")

        print("\nAll HTTP smoke tests passed.")
        return 0
    except Exception as error:
        print(f"FAIL: {error}")
        if last_log.exists():
            print("\n--- server log ---")
            print("\n".join(last_log.read_text().splitlines()[-25:]))
        return 1
    finally:
        stop_server(process, log_file)
        shutil.rmtree(work_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
