#!/bin/sh
# =============================================================================
# backup.sh — snapshot runtime state into backups/
# =============================================================================
# Runs inside the compose `backup` container (repo mounted read-only at /repo,
# writable /backups) or directly from the host.
#
# Covers: headscale sqlite DB + node keys, headplane sessions, caddy ACME
# certs, and the tracked config/ tree for good measure.
#
# CAVEAT: live files are tarred as-is. A write landing mid-copy can capture a
# torn SQLite state. The daily cadence keeps that window tiny; for a strictly
# consistent snapshot, stop headscale first:
#   docker compose stop headscale && sh scripts/backup.sh && docker compose up -d
#
# NOTE: the archive contains the headplane session secret — treat backups as
# sensitive and store them offsite, encrypted.
# =============================================================================
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /backups ]; then
  DEST="/backups"                          # inside the backup container
else
  DEST="${BACKUP_DIR:-$REPO/backups}"      # on the host
fi

STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT="$DEST/headscale-stack-$STAMP.tar.gz"

mkdir -p "$DEST"
tar -czf "$OUT" -C "$REPO" data config
echo "[backup] wrote $OUT ($(du -h "$OUT" | cut -f1))"

# Rotation: keep the newest 14 archives, drop the rest.
ls -1t "$DEST"/headscale-stack-*.tar.gz 2>/dev/null \
  | tail -n +15 \
  | while read -r f; do rm -f "$f"; done

echo "[backup] done"
