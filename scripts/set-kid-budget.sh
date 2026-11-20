#!/usr/bin/env bash
# Change an existing kid's monthly budget (USD). Spend so far this period is
# kept; the budget still resets every 30 days.
# Usage: ./scripts/set-kid-budget.sh <kid-name> <monthly-budget-usd>
# Example: ./scripts/set-kid-budget.sh alex 10
# Asks for anything missing.
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/lib.sh
KID="${1:-}"
BUDGET="${2:-}"
ask KID "Kid (key alias)"
ask BUDGET "Monthly budget in USD"

docker compose exec -T -e KID="$KID" -e BUDGET="$BUDGET" litellm python3 - <<'PY'
import json, os, urllib.request

body = {
    "key_alias": os.environ["KID"],
    "max_budget": float(os.environ["BUDGET"]),
}
req = urllib.request.Request(
    "http://localhost:4000/key/update",
    data=json.dumps(body).encode(),
    headers={
        "Authorization": f"Bearer {os.environ['LITELLM_MASTER_KEY']}",
        "Content-Type": "application/json",
    },
)
resp = json.load(urllib.request.urlopen(req))
print(f"{resp.get('key_alias')}: ${resp.get('max_budget')} per {resp.get('budget_duration')}, spent ${resp.get('spend') or 0:.4f}")
PY
