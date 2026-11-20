#!/usr/bin/env bash
# Create a LiteLLM virtual key for a parent: all models, no age prompt.
# Usage: ./scripts/create-parent-key.sh [name] [monthly-budget-usd]
# Example: ./scripts/create-parent-key.sh parent 10
#
# Use this for your own Open WebUI connection rather than the master key, so
# an Open WebUI admin login doesn't also hand over control of LiteLLM.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:-parent}"
BUDGET="${2:-10}"

docker compose exec -T -e NAME="$NAME" -e BUDGET="$BUDGET" litellm python3 - <<'PY'
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
echo
echo "Add the returned \"key\" as the first entry of OPENAI_API_KEYS in .env (docs/setup.md step 2)."
