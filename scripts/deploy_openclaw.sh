#!/usr/bin/env bash
# Synchronise this repo to /opt/openclaw and launch docker compose.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="/opt/openclaw"

mkdir -p "$DEST_DIR"
rsync -a --delete --exclude ".git" "$SRC_DIR"/ "$DEST_DIR"/

cd "$DEST_DIR"

mkdir -p logs/openclaw
mkdir -p data

if [ ! -f .env ]; then
  cp .env.example .env
  echo ".env créé à $DEST_DIR/.env ; pensez à renseigner vos clés API et domaine."
fi

# Install backup script + cron
install -m 0755 scripts/backup.sh /usr/local/bin/openclaw-backup.sh
echo "0 3 * * * root /usr/local/bin/openclaw-backup.sh > /var/log/openclaw/backup.log 2>&1" >/etc/cron.d/openclaw-backup

docker compose build
docker compose up -d

echo "OpenClaw déployé. Journaux: docker compose logs -f"
