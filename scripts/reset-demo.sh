#!/usr/bin/env bash
# Reset the demo to the tracked seed data.
#
# Before replacing anything, the current recipes, users and uploaded photos are
# copied to data/backups/<timestamp>/. That means a live demo can be restarted
# without losing the recipes or accounts created during it.
set -euo pipefail

cd "$(dirname "$0")/.."

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="data/backups/$stamp"

mkdir -p data "$backup_dir"

for item in recipes.json users.json uploads; do
    if [ -e "data/$item" ]; then
        cp -R "data/$item" "$backup_dir/"
    fi
done

cp seed/recipes.json data/recipes.json
cp seed/users.json data/users.json

rm -f data/recipes.backup.json data/users.backup.json \
      data/recipes.json.tmp data/users.json.tmp data/session.txt

# Start every demo with placeholders and no orphaned photos.
rm -rf data/uploads
mkdir -p data/uploads

echo "Demo data reset from seed/."
echo "Previous data (if any) was backed up to $backup_dir"
echo
echo "Demo accounts:"
echo "  junaid / tastehub"
echo "  guest  / guest"
echo
echo "Next: make run        (server)"
echo "      make app-run    (Flutter client)"
