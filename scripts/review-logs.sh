#!/usr/bin/env bash
# Dump the last N exchanges from LiteLLM's audit log (independent of Open WebUI).
# Usage: ./scripts/review-logs.sh [limit] [kid-key-alias]
#
# "who" is the Open WebUI user (tells parents apart on the shared key).
# "prompt" is the newest message in the request (the kid's turn); the full
# history, including the system prompt, is in proxy_server_request.
set -euo pipefail
cd "$(dirname "$0")/.."

LIMIT="${1:-20}"
ALIAS="${2:-}"
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "limit must be a number" >&2; exit 1; }

docker compose exec -T postgres psql -U litellm -d litellm -v limit="$LIMIT" -v alias="$ALIAS" <<'SQL'
SELECT "startTime",
       metadata->>'user_api_key_alias' AS key,
       end_user AS who,
       model,
       spend,
       left(proxy_server_request->'messages'->-1->>'content', 300) AS prompt,
       left(response->'choices'->0->'message'->>'content', 300) AS reply
FROM "LiteLLM_SpendLogs"
WHERE :'alias' = '' OR metadata->>'user_api_key_alias' = :'alias'
ORDER BY "startTime" DESC
LIMIT :limit;
SQL
