#!/usr/bin/env bash
# Check the whole setup, read-only, and say what's wrong and where to fix it.
# Checks the running stack: after editing .env or the compose file, run
# `make up` first. Exits 1 if anything failed (warnings don't count).
# Usage: ./scripts/doctor.sh
set -uo pipefail
cd "$(dirname "$0")/.."

FAILS=0
WARNS=0

# Reads "level|message" lines: section, ok, warn, fail, info.
report() {
  local level msg
  while IFS='|' read -r level msg; do
    case "$level" in
      section) printf '\n%s\n' "$msg" ;;
      ok)      printf '  ✓ %s\n' "$msg" ;;
      warn)    printf '  ! %s\n' "$msg"; WARNS=$((WARNS + 1)) ;;
      fail)    printf '  ✗ %s\n' "$msg"; FAILS=$((FAILS + 1)) ;;
      info)    printf '    %s\n' "$msg" ;;
      *)       [[ -n "$level" ]] && printf '    %s\n' "$level${msg:+|$msg}" ;;
    esac
  done
}

# A .env value without sourcing the file (it holds JSON and secrets).
envval() { sed -n "s/^$1=//p" .env 2>/dev/null | tail -1 | sed -e "s/^['\"]//" -e "s/['\"]\$//"; }

finish() {
  echo
  if (( FAILS > 0 )); then
    echo "$FAILS problem(s), $WARNS warning(s)."
    exit 1
  fi
  echo "No problems. $WARNS warning(s)."
  exit 0
}

# --- Host -------------------------------------------------------------------
report <<< "section|Host"
docker info >/dev/null 2>&1 || { report <<< "fail|Docker isn't running."; finish; }
[[ -f .env ]] || { report <<< "fail|No .env. Start with docs/setup.md step 1."; finish; }

missing=""
for v in WEBUI_SECRET_KEY LITELLM_MASTER_KEY POSTGRES_PASSWORD ADMIN_UI_USERNAME ADMIN_UI_PASSWORD ANTHROPIC_API_KEY OPENAI_API_KEYS; do
  [[ -n "$(envval "$v")" ]] || missing="$missing $v"
done
if [[ -n "$missing" ]]; then
  report <<< "fail|Empty in .env:$missing"
else
  report <<< "ok|.env has the required values"
fi
[[ "$(envval LITELLM_MASTER_KEY)" == sk-* ]] || report <<< "fail|LITELLM_MASTER_KEY must start with sk- (.env)"
docker compose config -q 2>/dev/null || report <<< "fail|docker compose config fails: run it to see why"

PROFILES=",$(envval COMPOSE_PROFILES),"
SEARCH_ON=$(envval ENABLE_WEB_SEARCH)
if [[ "$SEARCH_ON" == true && "$PROFILES" != *,search,* ]]; then
  report <<< "fail|ENABLE_WEB_SEARCH=true but \"search\" isn't in COMPOSE_PROFILES (.env)"
elif [[ "$PROFILES" == *,search,* && "$SEARCH_ON" != true ]]; then
  report <<< "warn|SearXNG runs (profile \"search\") but ENABLE_WEB_SEARCH isn't true, so nothing uses it (.env)"
fi
if [[ "$PROFILES" == *,search,* && -z "$(envval SEARXNG_SECRET)" ]]; then
  report <<< "fail|SEARXNG_SECRET is empty (.env): openssl rand -hex 32"
fi

# --- Containers ---------------------------------------------------------------
report <<< "section|Containers"
expected="postgres litellm openwebui"
[[ "$PROFILES" == *,guard,* ]] && expected="$expected ollama"
[[ "$PROFILES" == *,search,* ]] && expected="$expected searxng"
ps_out=$(docker compose ps --format '{{.Service}}|{{.State}}|{{.Health}}|{{.Image}}' 2>/dev/null)
for s in $expected; do
  line=$(printf '%s\n' "$ps_out" | grep "^$s|")
  state=$(printf '%s' "$line" | cut -d'|' -f2)
  health=$(printf '%s' "$line" | cut -d'|' -f3)
  image=$(printf '%s' "$line" | cut -d'|' -f4)
  if [[ "$state" != running ]]; then
    report <<< "fail|$s isn't running: make up, then make logs S=$s"
  elif [[ -n "$health" && "$health" != healthy ]]; then
    report <<< "fail|$s is $health: make logs S=$s"
  else
    report <<< "ok|$s ($image)"
  fi
done
running() { printf '%s\n' "$ps_out" | grep -q "^$1|running|"; }
if ! running openwebui || ! running litellm || ! running postgres; then
  report <<< "info|Skipping the rest: it needs openwebui, litellm, and postgres running."
  finish
fi

# --- Connections (Open WebUI -> LiteLLM) -------------------------------------
report <<< "section|Connections (.env OPENAI_API_*)"
conn_out=$(docker compose exec -T openwebui python3 - <<'PY'
import json, os, urllib.request, urllib.error
urls = [u for u in os.environ.get("OPENAI_API_BASE_URLS", "").split(";") if u]
keys = [k for k in os.environ.get("OPENAI_API_KEYS", "").split(";") if k]
try:
    configs = json.loads(os.environ.get("OPENAI_API_CONFIGS") or "{}")
except ValueError:
    print("fail|OPENAI_API_CONFIGS isn't valid JSON (.env)")
    configs = {}
if not (len(urls) == len(keys) == len(configs)):
    print(f"fail|The three lists differ in length: {len(urls)} URLs, {len(keys)} keys, {len(configs)} configs (.env, docs/setup.md step 4)")
mapping = []
for i, key in enumerate(keys):
    prefix = (configs.get(str(i)) or {}).get("prefix_id", "")
    label = f"{i} ({prefix or 'no prefix'})"
    if not prefix:
        print(f"fail|Connection {label} has no prefix_id, so model IDs can collide (.env OPENAI_API_CONFIGS)")
    try:
        req = urllib.request.Request("http://litellm:4000/key/info", headers={"Authorization": "Bearer " + key})
        info = json.loads(urllib.request.urlopen(req, timeout=15).read())["info"]
    except urllib.error.HTTPError as e:
        hint = " It looks like an OpenRouter key; those go in OPENROUTER_API_KEY*." if key.startswith("sk-or-") else ""
        print(f"fail|Connection {label}: LiteLLM rejects its key ({e.code}). It must be a LiteLLM key from scripts/create-*-key.sh.{hint}")
        continue
    except Exception as e:
        print(f"fail|Connection {label}: can't reach LiteLLM ({e})")
        continue
    alias = info.get("key_alias") or "?"
    kid = bool((info.get("metadata") or {}).get("birthdate"))
    mapping.append(f"{prefix}={alias}={'kid' if kid else 'parent'}")
    if info.get("blocked"):
        print(f"fail|Connection {label}: key {alias} is blocked")
    elif kid and prefix != alias:
        print(f"warn|Connection {label} uses kid key {alias}; prefix and alias differ, which makes logs confusing")
    else:
        print(f"ok|Connection {label}: {'kid' if kid else 'parent'} key {alias}")
print("map|" + ";".join(mapping))
PY
)
MAP=$(printf '%s\n' "$conn_out" | sed -n 's/^map|//p')
report <<< "$(printf '%s\n' "$conn_out" | grep -v '^map|')"

# --- LiteLLM: models, provider keys, kid keys ---------------------------------
report <<< "section|LiteLLM keys and models"
report <<< "$(docker compose exec -T -e MAP="$MAP" litellm python3 - <<'PY'
import json, os, sys, urllib.request, yaml
sys.path.insert(0, "/app")
cfg = yaml.safe_load(open("/app/config.yaml"))
models = {}
for m in cfg.get("model_list", []):
    env = str(m.get("litellm_params", {}).get("api_key", ""))
    models[m["model_name"]] = env.removeprefix("os.environ/") if env.startswith("os.environ/") else ""
parent_models = {n for n, env in models.items() if env.endswith("_PARENTS")}
empty = sorted({env for env in models.values() if env and not os.environ.get(env)})
for env in empty:
    users = ", ".join(n for n, e in models.items() if e == env)
    print(f"fail|{env} is empty (.env), so these models fail: {users}")
if not empty:
    print(f"ok|Provider keys set for all {len(models)} models")

req = urllib.request.Request("http://localhost:4000/key/list?return_full_object=true&size=100",
                             headers={"Authorization": "Bearer " + os.environ["LITELLM_MASTER_KEY"]})
keys = [k for k in json.loads(urllib.request.urlopen(req, timeout=15).read()).get("keys", []) if isinstance(k, dict)]
connected = {p.split("=")[1] for p in os.environ.get("MAP", "").split(";") if p.count("=") == 2}
from age_prompt import age_on, system_prompt
import datetime
for k in sorted(keys, key=lambda k: k.get("key_alias") or ""):
    alias = k.get("key_alias")
    if not alias or k.get("blocked"):
        continue
    meta = k.get("metadata") or {}
    allowed = k.get("models") or []
    budget, spend = k.get("max_budget"), k.get("spend") or 0
    if not meta.get("birthdate"):
        if alias not in connected:
            print(f"warn|Parent key {alias} isn't used by any connection. Spare? Block or delete it (LiteLLM admin UI > Virtual Keys)")
        continue
    problems = []
    if not allowed:
        problems.append("fail|can use every model, parent models included (make set-models)")
    if set(allowed) & parent_models:
        problems.append(f"fail|has parent models: {', '.join(sorted(set(allowed) & parent_models))} (make set-models)")
    unknown = [m for m in allowed if m not in models]
    if unknown:
        problems.append(f"warn|lists models not in litellm/config.yaml: {', '.join(unknown)}")
    try:
        system_prompt(meta.get("kid_name") or alias, meta["birthdate"])
        age = age_on(datetime.date.fromisoformat(meta["birthdate"]), datetime.date.today())
    except Exception as e:
        problems.append(f"fail|age prompt fails, so every request is rejected: {e}")
        age = "?"
    if not budget:
        problems.append("warn|has no budget (make set-budget)")
    elif spend / budget >= 0.8:
        problems.append(f"warn|has used {spend / budget:.0%} of ${budget:g} (make spending)")
    if alias not in connected:
        problems.append("warn|isn't used by any Open WebUI connection (make add-kid, or delete the key)")
    for p in problems:
        level, msg = p.split("|", 1)
        print(f"{level}|Kid key {alias}: {msg}")
    if not problems:
        print(f"ok|Kid key {alias}: age {age}, models {', '.join(allowed)}, ${spend:.2f} of ${budget:g}")
PY
)"

# --- Web search -----------------------------------------------------------------
if [[ "$SEARCH_ON" == true ]] && running searxng; then
  report <<< "section|Web search (SearXNG)"
  report <<< "$(docker compose exec -T openwebui python3 - <<'PY'
import json, urllib.request, urllib.parse
def search(q, safe, engines=""):
    p = urllib.parse.urlencode({"q": q, "format": "json", "safesearch": safe, "engines": engines})
    return json.loads(urllib.request.urlopen("http://searxng:8080/search?" + p, timeout=30).read())
try:
    r = search("photosynthesis", "2")
except Exception as e:
    print(f"fail|SearXNG doesn't answer: {e} (make logs S=searxng)")
    raise SystemExit
results = r.get("results", [])
engines = sorted({e for x in results for e in x.get("engines", [])})
broken = sum("///" in x.get("url", "") for x in results)
down = ", ".join(f"{e} ({why})" for e, why in r.get("unresponsive_engines", []))
if not results:
    print(f"fail|No results from any engine{': ' + down if down else ''}. Engines get blocked; see searxng/settings.yml")
else:
    print(f"ok|{len(results)} results from {', '.join(engines)}")
if broken:
    print(f"warn|{broken} results have broken links (an engine's parser is out of date; drop it in searxng/settings.yml)")
if down:
    print(f"info|Not answering: {down}")
# Same query with safe search off and strict should match if the lock holds.
# Bing only, and overlap rather than equality: live results jitter.
a = {x["url"] for x in search("beach", "0", "bing").get("results", [])[:10]}
b = {x["url"] for x in search("beach", "2", "bing").get("results", [])[:10]}
if a and b and len(a & b) < 0.8 * min(len(a), len(b)):
    print("fail|Safe search lock isn't holding: safesearch=0 changes results (searxng/settings.yml preferences.lock)")
else:
    print("ok|Strict safe search is locked")
PY
)"
fi

# --- Open WebUI: presets, groups, users, alerts -------------------------------
report <<< "section|Open WebUI (presets, groups, alerts)"
report <<< "$(docker compose exec -T -e MAP="$MAP" openwebui python3 - <<'PY'
import json, os, sqlite3
try:
    db = sqlite3.connect("file:/app/backend/data/webui.db?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    q = lambda sql, *a: db.execute(sql, a).fetchall()
    by_prefix = {}
    for p in os.environ.get("MAP", "").split(";"):
        if p.count("=") == 2:
            prefix, alias, kind = p.split("=")
            by_prefix[prefix] = (alias, kind)
    groups = {r["id"]: r for r in q('SELECT id, name, data FROM "group"')}
    presets = {r["id"]: r for r in q("SELECT id, name, base_model_id, is_active FROM model WHERE base_model_id IS NOT NULL")}
    grants = {}
    for g in q("SELECT resource_id, principal_type, principal_id FROM access_grant WHERE resource_type = 'model'"):
        grants.setdefault(g["resource_id"], []).append(g)

    for mid, m in presets.items():
        prefix = (m["base_model_id"] or "").split(".")[0]
        owner, kind = by_prefix.get(prefix, (prefix, "?"))
        label = f"Preset '{m['name']}' (on {owner}'s key)"
        gs = grants.get(mid, [])
        public = [g for g in gs if g["principal_id"] == "*"]
        group_names = [groups[g["principal_id"]]["name"] for g in gs
                       if g["principal_type"] == "group" and g["principal_id"] in groups]
        if public:
            print(f"fail|{label} is public: any user can run it on that key (Workspace > Models > Access)")
        elif not gs:
            print(f"fail|{label} has no access entry, so only admins see it (Workspace > Models > Access)")
        elif kind == "parent":
            print(f"fail|{label} is shared with {', '.join(group_names)}: parent keys have every model and no age prompt")
        elif kind == "?":
            print(f"warn|{label}: base model {m['base_model_id']} isn't from any connection")
        else:
            wrong = [n for n in group_names if owner.lower() not in n.lower()]
            base_groups = {g["principal_id"] for g in grants.get(m["base_model_id"], [])
                           if g["principal_type"] == "group"}
            blocked = [groups[g["principal_id"]]["name"] for g in gs if g["principal_type"] == "group"
                       and g["principal_id"] in groups and g["principal_id"] not in base_groups]
            if blocked:
                print(f"fail|{label}: {', '.join(blocked)} can't use base model {m['base_model_id']}, so chats fail with 'Model not found' (Admin Panel > Settings > Models > Access)")
            elif wrong:
                print(f"warn|{label} is shared with {', '.join(wrong)}: they'd chat with {owner}'s age, budget, and name")
            else:
                print(f"ok|{label} shared with {', '.join(group_names)}")
    for mid in grants:
        if mid not in presets and any(g["principal_id"] == "*" for g in grants[mid]):
            print(f"fail|Base model {mid} is public: any kid can call it by ID (Admin Panel > Settings > Models)")

    members = {}
    for r in q("SELECT group_id, user_id FROM group_member"):
        members.setdefault(r["group_id"], []).append(r["user_id"])
    for gid, g in groups.items():
        cfg = (json.loads(g["data"] or "{}") or {}).get("config") or {}
        defaults = cfg.get("default_models") or []
        if not members.get(gid):
            print(f"warn|Group '{g['name']}' has no members")
        for d in defaults:
            if d in presets:
                owner = by_prefix.get(presets[d]["base_model_id"].split(".")[0], ("?", ""))[0]
                if owner.lower() not in g["name"].lower():
                    print(f"warn|Group '{g['name']}' defaults to '{presets[d]['name']}', which runs on {owner}'s key")
            else:
                print(f"warn|Group '{g['name']}' defaults to {d}, which isn't a preset")
    in_groups = {u for us in members.values() for u in us}
    for u in q("SELECT id, name, role FROM user WHERE role != 'admin'"):
        if u["role"] == "pending":
            print(f"info|{u['name']} is pending (Admin Panel > Users)")
        elif u["id"] not in in_groups:
            print(f"warn|{u['name']} isn't in any group, so sees no presets")

    fn = q("SELECT is_active, is_global, valves FROM function WHERE id = 'parent_alert'")
    if not fn:
        print("warn|Parent alerts aren't installed (docs/setup.md step 8)")
    else:
        f = fn[0]
        valves = json.loads(f["valves"] or "{}") or {}
        off = [why for ok, why in [(f["is_active"], "switched off"), (f["is_global"], "not global"),
                                    (valves.get("webhook_url"), "no webhook_url")] if not ok]
        if off:
            print(f"warn|Parent alerts are off: {', '.join(off)} (Admin Panel > Functions, docs/setup.md step 8)")
        else:
            print("ok|Parent alerts on")
except Exception as e:
    print(f"warn|Couldn't read Open WebUI's database (schema changed after an upgrade?): {e}")
PY
)"

# --- Backups --------------------------------------------------------------------
report <<< "section|Backups"
latest=$(ls -1d backups/20*/ 2>/dev/null | tail -1)
if [[ -z "$latest" ]]; then
  report <<< "warn|No backups yet: make backup (and schedule it, docs/setup.md step 10)"
elif [[ -n "$(find backups -maxdepth 1 -type d -name '20*' -mtime -7 2>/dev/null | head -1)" ]]; then
  report <<< "ok|Latest: ${latest%/}"
else
  report <<< "warn|Latest backup is over a week old: ${latest%/} (make backup)"
fi

finish
