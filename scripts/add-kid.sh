#!/usr/bin/env bash
# Add a kid on the LiteLLM side, end to end: create their key, add their
# connection to .env, restart, check it, then print the Open WebUI steps
# (user, group, preset) with the exact values to use.
# Usage: ./scripts/add-kid.sh [name] [birthdate YYYY-MM-DD] [monthly-usd] [models]
# Asks for anything missing. Example: ./scripts/add-kid.sh alex 2016-04-02 5 claude-kids
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

die() { echo "$*" >&2; exit 1; }

KID="${1:-}"
BIRTHDATE="${2:-}"
BUDGET="${3:-}"
MODELS="${4:-}"

[[ -f .env ]] || die "No .env yet. Start with docs/setup.md step 1."
docker compose exec -T litellm true 2>/dev/null || die "LiteLLM isn't running. Start the stack first: make up"

ask KID "Kid's name, lowercase (key alias and model prefix, e.g. alex)"
KID=$(printf '%s' "$KID" | tr '[:upper:]' '[:lower:]')
[[ "$KID" =~ ^[a-z][a-z0-9-]*$ ]] || die "Name must be lowercase letters, digits, or dashes: $KID"
grep -q "\"prefix_id\":\"$KID\"" .env && die "$KID already has a connection in .env."
EXISTS=$(docker compose exec -T postgres psql -U litellm -d litellm -Atc \
  "SELECT count(*) FROM \"LiteLLM_VerificationToken\" WHERE key_alias = '$KID'")
[[ "$EXISTS" == 0 ]] || die "A LiteLLM key named $KID already exists. Pick another name, or delete it in the LiteLLM admin UI."

ask BIRTHDATE "Birthdate (YYYY-MM-DD)"
[[ "$BIRTHDATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "Birthdate must be YYYY-MM-DD: $BIRTHDATE"
ask BUDGET "Monthly budget in USD" 5
ask MODELS "Models, comma-separated" claude-kids

echo "Creating key $KID..."
OUT=$(./scripts/create-kid-key.sh "$KID" "$BIRTHDATE" "$BUDGET" "$MODELS")
KEY=$(printf '%s' "$OUT" | sed -n 's/.*"key":"\(sk-[^"]*\)".*/\1/p')
[[ -n "$KEY" ]] || die "Key creation didn't return a key: $OUT"

mkdir -p backups
BAK="backups/.env.bak-$(date +%Y%m%d-%H%M%S)"
cp -p .env "$BAK"

# Append the connection to the three OPENAI_API_* lists. The key and .env go
# in on stdin, so the key never appears on a command line.
read -r -d '' EDIT_ENV <<'PY' || true
import json, os, sys
key, env = sys.stdin.read().split("\n", 1)
lines = env.split("\n")
idx = {l.split("=", 1)[0]: i for i, l in enumerate(lines) if "=" in l and not l.startswith("#")}
def value(name):
    if name not in idx:
        sys.exit(f"{name} is missing from .env")
    return lines[idx[name]].split("=", 1)[1].strip().strip("'\"")
urls = [u for u in value("OPENAI_API_BASE_URLS").split(";") if u]
keys = [k for k in value("OPENAI_API_KEYS").split(";") if k]
configs = json.loads(value("OPENAI_API_CONFIGS") or "{}")
if not (len(urls) == len(keys) == len(configs)):
    sys.exit(f"The connection lists in .env have different lengths ({len(urls)} URLs, {len(keys)} keys, {len(configs)} configs). Fix them first (make doctor).")
configs[str(len(keys))] = {"prefix_id": os.environ["KID"]}
urls.append("http://litellm:4000/v1")
keys.append(key)
lines[idx["OPENAI_API_BASE_URLS"]] = "OPENAI_API_BASE_URLS=" + ";".join(urls)
lines[idx["OPENAI_API_KEYS"]] = "OPENAI_API_KEYS=" + ";".join(keys)
lines[idx["OPENAI_API_CONFIGS"]] = "OPENAI_API_CONFIGS='" + json.dumps(configs, separators=(",", ":")) + "'"
sys.stdout.write("\n".join(lines))
PY

if ! { printf '%s\n' "$KEY"; cat .env; } | docker compose exec -T -e KID="$KID" litellm python3 -c "$EDIT_ENV" > .env.new; then
  rm -f .env.new
  die "Couldn't update .env (unchanged). The key $KID was created but isn't connected: delete it in the LiteLLM admin UI (Virtual Keys), fix .env, and run this again."
fi
mv .env.new .env
echo "Added connection $KID to .env (backup: $BAK)."

echo "Restarting..."
docker compose up -d --wait >/dev/null 2>&1 || die "Restart failed. Check: make logs"

docker compose exec -T -e KID="$KID" openwebui python3 - <<'PY' || die "The new connection doesn't work. Run: make doctor"
import json, os, urllib.request
key = os.environ["OPENAI_API_KEYS"].split(";")[-1]
auth = {"Authorization": "Bearer " + key}
info = json.loads(urllib.request.urlopen(urllib.request.Request("http://litellm:4000/key/info", headers=auth)).read())["info"]
models = json.loads(urllib.request.urlopen(urllib.request.Request("http://litellm:4000/v1/models", headers=auth)).read())["data"]
assert info["key_alias"] == os.environ["KID"], info["key_alias"]
print(f"Checked: Open WebUI reaches LiteLLM as {info['key_alias']}, models: {', '.join(m['id'] for m in models)}")
PY

NAME="$(printf '%s' "${KID:0:1}" | tr '[:lower:]' '[:upper:]')${KID:1}"
FIRST_MODEL="${MODELS%%,*}"
cat <<EOF

Done in LiteLLM and .env. Now in Open WebUI, as an admin (make open):

  1. Admin Panel > Users > +
       Name: $NAME    Email: anything unique, e.g. $KID@family.local    Role: user
  2. Admin Panel > Users > Groups > +
       Name: $NAME    Members: $NAME
  3. Workspace > Models > +
       Name:          $NAME's AI Helper
       Base model:    $KID.$FIRST_MODEL
       System prompt: leave empty (the age prompt comes from LiteLLM)
       Suggestions:   from openwebui/presets.md
       Access:        group $NAME only, never public
  4. Admin Panel > Settings > Models > $KID.$FIRST_MODEL
       Access:        group $NAME only, never public (the preset needs it)
       Menu:          Hide Model (tidies $NAME's list)
  5. Admin Panel > Users > Groups > $NAME > Default Model: $NAME's AI Helper
  6. make doctor, then log in as $NAME in a private window (docs/setup.md step 7).
EOF
