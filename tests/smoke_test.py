#!/usr/bin/env python3
"""HTTP smoke test for TasteHub Stage 2.

By default this script starts its own temporary server, so it never touches the
real data/ folder:

    make http-test

To run read-only checks against a server that is already running:

    python3 tests/smoke_test.py --base-url http://127.0.0.1:8080

The read-only mode does not create, update or delete recipes.
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
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SERVER_BINARY = REPO_ROOT / "build" / "tastehub-server"
SEED_FILE = REPO_ROOT / "seed" / "recipes.json"


# ------------------------------------------------------------
#  Small HTTP and assertion helpers
# ------------------------------------------------------------

def request(base_url, method, path, body=None, raw_body=None):
    """Return (status, parsed_json_or_none, content_type)."""
    data = None
    if raw_body is not None:
        data = raw_body.encode()
    elif body is not None:
        data = json.dumps(body).encode()

    http_request = urllib.request.Request(base_url + path, data=data,
                                          method=method)
    http_request.add_header("Accept", "application/json")
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


def request_text(base_url, path):
    """Return (status, body_text, content_type) for non-JSON routes."""
    http_request = urllib.request.Request(base_url + path, method="GET")

    try:
        with urllib.request.urlopen(http_request, timeout=10) as response:
            return (response.status,
                    response.read().decode(),
                    response.headers.get_content_type())
    except urllib.error.HTTPError as error:
        return (error.code,
                error.read().decode(),
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
         "--data-dir", "../data"],
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
         "--data-dir", "../data"],
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
    status, page, content_type = request_text(base_url, "/")
    check_status(status, 200, "home page returns 200")
    check(content_type == "text/html", "home page is served as HTML")
    check("TasteHub" in page and "/api/recipes" in page,
          "home page contains the browser app and API calls")

    status, health, content_type = request(base_url, "GET", "/api/health")
    check_status(status, 200, "health returns 200")
    check(content_type == "application/json",
          "health response is application/json")
    check(health.get("status") == "ok", "health status is ok")
    check(health.get("recipes", 0) >= 6, "health reports at least 6 recipes")

    status, recipes, _ = request(base_url, "GET", "/api/recipes")
    check_status(status, 200, "recipe list returns 200")
    check(isinstance(recipes, list) and len(recipes) >= 6,
          "recipe list has at least 6 entries")

    status, detail, _ = request(base_url, "GET", "/api/recipes/5")
    check_status(status, 200, "recipe detail returns 200")
    check(detail.get("title") == "Chicken Biryani",
          "recipe 5 is Chicken Biryani")
    check(isinstance(detail.get("ingredients"), list),
          "detail has ingredients")
    check(isinstance(detail.get("steps"), list), "detail has steps")
    check(isinstance(detail.get("ratings"), list), "detail has ratings")

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

    status, leaderboard, _ = request(base_url, "GET", "/api/leaderboard")
    check_status(status, 200, "leaderboard returns 200")
    check(find_leaderboard_entry(leaderboard.get("leaderboard", []), 5) is not None,
          "seed leaderboard contains Chicken Biryani")

    status, body, _ = request(base_url, "GET", "/api/recipes/999999")
    check_error(status, body, 404, "missing recipe")

    status, body, _ = request(base_url, "GET", "/api/recipes/not-a-number")
    check_error(status, body, 400, "malformed recipe id")

    status, body, _ = request(base_url, "GET", "/api/does-not-exist")
    check_error(status, body, 404, "unknown route")


# ------------------------------------------------------------
#  Mutating checks for the self-contained test
# ------------------------------------------------------------

def run_mutation_checks(base_url):
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

    status, created, content_type = request(
        base_url, "POST", "/api/recipes", body=new_recipe)
    check_status(status, 201, "create returns 201")
    check(content_type == "application/json",
          "create response is application/json")
    check(created.get("title") == "Smoke Test Curry",
          "created recipe has the right title")
    recipe_id = created["id"]

    status, body, _ = request(
        base_url, "POST", "/api/recipes", body=new_recipe)
    check_error(status, body, 409, "duplicate title")

    status, body, _ = request(
        base_url, "POST", "/api/recipes", raw_body="{not valid json")
    check_error(status, body, 400, "malformed create body")

    status, body, _ = request(
        base_url, "POST", "/api/recipes",
        body={"dish": "Smoke Test", "ingredients": ["x"], "steps": ["y"]})
    check_error(status, body, 400, "missing create title")

    proof_url = "https://example.com/proofs/smoke-curry.jpg"
    status, rating, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 5, "proofImageRef": proof_url})
    check_status(status, 200, "rating with proof returns 200")
    check(rating.get("myRating") == 5, "rating value is saved")
    check(rating.get("myRatingProofImageRef") == proof_url,
          "proof image is saved")

    # Omitting the proof keeps it; sending an empty string clears it.
    status, rating, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 4})
    check_status(status, 200, "rating without proof returns 200")
    check(rating.get("myRatingProofImageRef") == proof_url,
          "omitted proof keeps the existing image")

    status, rating, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 3, "proofImageRef": ""})
    check_status(status, 200, "rating with empty proof returns 200")
    check(rating.get("myRatingProofImageRef") == "",
          "empty proof clears the image")

    # Put the good proof back for the detail/list/search/leaderboard checks.
    status, rating, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 5, "proofImageRef": proof_url})
    check_status(status, 200, "rating can restore the proof image")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 0})
    check_error(status, body, 400, "rating below 1 is rejected")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": "five"})
    check_error(status, body, 400, "non-integer rating is rejected")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}/rating",
        body={"stars": 5, "proofImageRef": 123})
    check_error(status, body, 400, "non-string proof is rejected")

    status, detail, _ = request(
        base_url, "GET", f"/api/recipes/{recipe_id}")
    check_status(status, 200, "created recipe detail returns 200")
    check(detail.get("myRatingProofImageRef") == proof_url,
          "detail includes the demo user's proof")
    check(any(item.get("proofImageRef") == proof_url
              for item in detail.get("ratings", [])),
          "detail ratings include the proof image")

    status, recipes, _ = request(base_url, "GET", "/api/recipes")
    summary = find_recipe(recipes, recipe_id)
    check(summary is not None, "created recipe appears in the list")
    check(summary.get("myRatingProofImageRef") == proof_url,
          "list summary includes the proof image")

    status, search, _ = request(base_url, "GET", "/api/search?q=smoke")
    check_status(status, 200, "searching the new recipe returns 200")
    check(find_recipe(search.get("results", []), recipe_id) is not None,
          "search finds the new recipe")

    status, leaderboard, _ = request(base_url, "GET", "/api/leaderboard")
    entry = find_leaderboard_entry(leaderboard.get("leaderboard", []), recipe_id)
    check(entry is not None, "new recipe appears on the leaderboard")
    check(entry.get("averageRating") == 5.0,
          "new recipe has the expected average rating")

    status, updated, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}",
        body={"title": "Smoke Test Curry Updated"})
    check_status(status, 200, "update returns 200")
    check(updated.get("title") == "Smoke Test Curry Updated",
          "title was updated")
    check(updated.get("updatedAt") is not None,
          "update sets updatedAt")

    status, body, _ = request(
        base_url, "PUT", f"/api/recipes/{recipe_id}",
        body={"dish": "Another Dish"})
    check_error(status, body, 400, "changing dish is rejected")

    status, body, _ = request(
        base_url, "POST", "/api/recipes/parse",
        body={"text": "short"})
    check_error(status, body, 400, "short AI description is rejected")

    status, body, _ = request(
        base_url, "POST", "/api/recipes/parse",
        body={"text": "I made chicken biryani with rice, chicken and spices."})
    check_error(status, body, 503, "AI parse without a key is unavailable")

    _, health_after_parse, _ = request(base_url, "GET", "/api/health")
    check(health_after_parse["recipes"] == recipe_count_before + 1,
          "AI parse did not save a recipe")

    return recipe_id, recipe_count_before


def run_persistence_and_delete_checks(base_url, data_dir, recipe_id,
                                      recipe_count_before):
    status, detail, _ = request(
        base_url, "GET", f"/api/recipes/{recipe_id}")
    check_status(status, 200, "created recipe survives a server restart")
    check(detail.get("title") == "Smoke Test Curry Updated",
          "updated title survives a server restart")
    check(detail.get("myRatingProofImageRef") ==
          "https://example.com/proofs/smoke-curry.jpg",
          "rating proof survives a server restart")

    status, deleted, _ = request(
        base_url, "DELETE", f"/api/recipes/{recipe_id}")
    check_status(status, 200, "delete returns 200")
    check(deleted.get("deleted") is True, "delete response is correct")

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
    data_dir = work_dir / "data"

    process = None
    log_file = None
    last_log = work_dir / "server.log"

    try:
        process, log_file, base_url = start_server(work_dir, last_log)
        run_read_only_checks(base_url)
        check_duplicate_port_rejected(
            base_url, work_dir, work_dir / "server-duplicate.log")
        recipe_id, recipe_count_before = run_mutation_checks(base_url)

        stop_server(process, log_file)
        process, log_file = None, None

        # Restart against the same data directory to prove persistence.
        last_log = work_dir / "server-restart.log"
        process, log_file, base_url = start_server(work_dir, last_log)
        run_persistence_and_delete_checks(
            base_url, data_dir, recipe_id, recipe_count_before)

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
