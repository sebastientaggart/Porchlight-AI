#!/usr/bin/env bash
# Open the chat app (Open WebUI) and the LiteLLM admin UI. On a machine with
# no browser, print the URLs and the SSH tunnel to reach LiteLLM's.
# Usage: ./scripts/open.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Ports from .env, without sourcing it.
port() { sed -n "s/^$1=\([0-9][0-9]*\).*/\1/p" .env 2>/dev/null | tail -1; }
WEBUI="http://localhost:$(port OPENWEBUI_PORT | grep . || echo 3000)"
LITELLM_PORT="$(port LITELLM_PORT | grep . || echo 4000)"
LITELLM="http://localhost:$LITELLM_PORT/ui"

if command -v open >/dev/null && [[ "$(uname)" == Darwin ]]; then
  open "$WEBUI" "$LITELLM"
elif command -v xdg-open >/dev/null && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  xdg-open "$WEBUI"; xdg-open "$LITELLM"
else
  echo "Chat:          $WEBUI  (or this host's name/IP instead of localhost)"
  echo "LiteLLM admin: $LITELLM  (loopback only; from another machine:"
  echo "               ssh -L $LITELLM_PORT:localhost:$LITELLM_PORT <this-host>, then open it there)"
fi
