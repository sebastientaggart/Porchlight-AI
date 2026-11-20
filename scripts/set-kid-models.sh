#!/usr/bin/env bash
# Replace the list of models an existing kid's LiteLLM key can use.
# Usage: ./scripts/set-kid-models.sh <kid-name> <models>
# Example: ./scripts/set-kid-models.sh alex claude-kids,claude-kids-plus
#
# The new model then appears under that kid's connection in Open WebUI
# (e.g. alex.claude-kids-plus); add it to their preset or create one.
# Asks for anything missing.
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/lib.sh
KID="${1:-}"
MODELS="${2:-}"
ask KID "Kid (key alias)"
ask MODELS "Models, comma-separated" "claude-kids"

docker compose exec -T -e KID="$KID" -e MODELS="$MODELS" litellm python3 - <<'PY'
import json, os, urllib.request

body = {
    "key_alias": os.environ["KID"],
    "models": [m.strip() for m in os.environ["MODELS"].split(",") if m.strip()],
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
print(f"{resp.get('key_alias')}: {resp.get('models')}")
PY
