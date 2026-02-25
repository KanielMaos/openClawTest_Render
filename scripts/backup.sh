#!/usr/bin/env bash
# Simple backup: tar the persistent data and logs.
# Usage: sudo /usr/local/bin/openclaw-backup.sh

set -euo pipefail

SRC_DATA="/opt/openclaw/data"
SRC_LOGS="/opt/openclaw/logs"
DEST_DIR="/var/backups/openclaw"

timestamp=$(date +"%Y%m%d-%H%M%S")
mkdir -p "$DEST_DIR"

ARGS=()
[ -d "$SRC_DATA" ] && ARGS+=("${SRC_DATA#/}")
[ -d "$SRC_LOGS" ] && ARGS+=("${SRC_LOGS#/}")

if [ ${#ARGS[@]} -eq 0 ]; then
  echo "Aucune source à archiver (data/logs manquants)."
  exit 0
fi

tar czf "$DEST_DIR/openclaw-${timestamp}.tar.gz" -C / "${ARGS[@]}"

echo "Backup écrit: $DEST_DIR/openclaw-${timestamp}.tar.gz"

# Optionnel: poussez vers un stockage distant si rclone est configuré
# rclone copy "$DEST_DIR/openclaw-${timestamp}.tar.gz" remote:openclaw-backups/
