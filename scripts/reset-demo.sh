#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p data
cp seed/recipes.json data/recipes.json
rm -f data/recipes.backup.json data/recipes.json.tmp

echo "Reset data/recipes.json from seed/recipes.json"
