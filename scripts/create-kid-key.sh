#!/usr/bin/env bash
# Create a LiteLLM virtual key for one kid, with a monthly budget.
# Usage: ./scripts/create-kid-key.sh <kid-name> <birthdate YYYY-MM-DD> [monthly-budget-usd] [models]
# Example: ./scripts/create-kid-key.sh alex 2016-04-02 5 claude-kids,claude-kids-plus
#
# The name and birthdate go in the key's metadata; litellm/age_prompt.py uses
# them to pick and fill the system prompt for the kid's age on every request.
#
# Runs inside the litellm container (which has python3 but no curl) and reads
# the master key from the container's own environment, so .env isn't parsed
# here and the key never shows up in the host's process list.
set -euo pipefail
cd "$(dirname "$0")/.."

KID="${1:?kid name required}"
BIRTHDATE="${2:?birthdate required (YYYY-MM-DD)}"
BUDGET="${3:-5}"
MODELS="${4:-claude-kids}"

docker compose exec -T -e KID="$KID" -e BIRTHDATE="$BIRTHDATE" -e BUDGET="$BUDGET" -e MODELS="$MODELS" litellm python3 - <<'PY'
import datetime, json, os, urllib.request

kid = os.environ["KID"]
body = {
    "key_alias": kid,
    "metadata": {
        "kid_name": kid[:1].upper() + kid[1:],
        "birthdate": datetime.date.fromisoformat(os.environ["BIRTHDATE"]).isoformat(),
    },
    "max_budget": float(os.environ["BUDGET"]),
    "budget_duration": "30d",
    "models": [m.strip() for m in os.environ["MODELS"].split(",") if m.strip()],
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
echo "Add the returned \"key\" to the connection lists in .env with prefix ${KID} (docs/setup.md step 4)."
