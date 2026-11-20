#!/usr/bin/env bash
# Create a LiteLLM virtual key for a parent: all models, no age prompt.
# Usage: ./scripts/create-parent-key.sh [name] [monthly-budget-usd]
# Example: ./scripts/create-parent-key.sh parent 10
#
# Use this for your own Open WebUI connection rather than the master key, so
# an Open WebUI admin login doesn't also hand over control of LiteLLM.
#
# On a fresh .env (OPENAI_API_KEYS empty), puts the key there as the first
# connection and restarts. Otherwise prints the key to add yourself.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077  # .env and its backups hold every key

die() { echo "$*" >&2; exit 1; }

NAME="${1:-parent}"
BUDGET="${2:-10}"

[[ -f .env ]] || die "No .env yet. Start with docs/setup.md step 1."

OUT=$(docker compose exec -T -e NAME="$NAME" -e BUDGET="$BUDGET" litellm python3 - <<'PY'
import json, os, urllib.request

# No "models" (all models) and no birthdate (age_prompt.py passes it through).
body = {
    "key_alias": os.environ["NAME"],
    "max_budget": float(os.environ["BUDGET"]),
    "budget_duration": "30d",
}
req = urllib.request.Request(
    "http://localhost:4000/key/generate",
    data=json.dumps(body).encode(),
    headers={
        "Authorization": f"Bearer {os.environ['LITELLM_MASTER_KEY']}",
        "Content-Type": "application/json",
    },
)
print(urllib.request.urlopen(req).read().decode())
PY
)
KEY=$(printf '%s' "$OUT" | sed -n 's/.*"key":"\(sk-[^"]*\)".*/\1/p')
[[ -n "$KEY" ]] || die "Key creation didn't return a key: $OUT"
echo "Created key $NAME (\$$BUDGET per 30 days, every model)."

if ! grep -qE "^OPENAI_API_KEYS=[\"']*$" .env; then
  echo
  echo "OPENAI_API_KEYS in .env already has keys, so it's left alone. The new key:"
  echo "  $KEY"
  echo "Add it to .env yourself (docs/setup.md step 2), then: docker compose up -d --wait"
  exit 0
fi

mkdir -p backups
BAK="backups/.env.bak-$(date +%Y%m%d-%H%M%S)"
cp -p .env "$BAK"
# The key goes in through the environment, not the command line. Copy over
# rather than mv, so .env keeps its permissions.
KEY="$KEY" awk '/^OPENAI_API_KEYS=/ { print "OPENAI_API_KEYS=" ENVIRON["KEY"]; next } { print }' .env > .env.new
cat .env.new > .env
rm -f .env.new
echo "Added it to .env as the first connection (backup: $BAK)."

echo "Restarting..."
docker compose up -d --wait >/dev/null 2>&1 || die "Restart failed. Check: docker compose logs"
echo "Done. Open WebUI now lists the models as parent.<model> (docs/setup.md step 2)."
