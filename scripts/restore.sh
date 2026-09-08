#!/bin/sh
# =============================================================================
# restore.sh — restore runtime state from a snapshot
# =============================================================================
# Usage:
#   sh scripts/restore.sh [path/to/snapshot.tar.gz]
# With no argument, restores the NEWEST archive found in backups/.
#
# Overwrites data/ and config/ in the repo. Stop the stack first:
#   docker compose down && sh scripts/restore.sh && docker compose up -d
# =============================================================================
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SNAP="${1:-$(ls -1t "$REPO"/backups/headscale-stack-*.tar.gz 2>/dev/null | head -n 1)}"

if [ -z "$SNAP" ] || [ ! -f "$SNAP" ]; then
  echo "[restore] FATAL: no snapshot found (pass a path or put one in backups/)" >&2
  exit 1
fi

echo "[restore] restoring $SNAP over $REPO"
tar -xzf "$SNAP" -C "$REPO"
echo "[restore] done — bring the stack up: docker compose up -d"
