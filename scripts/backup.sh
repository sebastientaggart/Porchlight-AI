#!/usr/bin/env bash
# Back up the audit log (LiteLLM Postgres) and Open WebUI's database (chats,
# users, settings) into backups/<timestamp>/. Safe to run while the stack is up.
# Usage: ./scripts/backup.sh
# Cron (nightly at 3am): 0 3 * * * /path/to/Porchlight-AI/scripts/backup.sh
#
# No pruning: delete old folders yourself, or add a find -mtime line here.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"

docker compose exec -T postgres pg_dump -U litellm -d litellm | gzip > "$DEST/litellm.sql.gz"

# sqlite3's online backup API gives a consistent copy of a live database.
docker compose exec -T openwebui python3 -c "
import sqlite3
src = sqlite3.connect('/app/backend/data/webui.db')
dst = sqlite3.connect('/tmp/webui-backup.db')
src.backup(dst)
dst.close()
"
docker compose cp openwebui:/tmp/webui-backup.db "$DEST/webui.db"
docker compose exec -T openwebui rm /tmp/webui-backup.db
gzip "$DEST/webui.db"

echo "Backed up to $DEST"
