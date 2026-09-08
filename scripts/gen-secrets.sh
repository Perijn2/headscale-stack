#!/bin/sh
# =============================================================================
# gen-secrets.sh — generate host-local secrets for the stack
# =============================================================================
# Produces:
#   config/headplane/headplane.yaml   from the tracked .example template:
#       __DOMAIN__          <- DOMAIN from .env
#       __SESSION_SECRET__  <- fresh 32-byte random hex (never printed)
#   data/{headscale,headplane,caddy}/ and backups/  runtime dirs, mode 750
#
# Refuses to overwrite an existing headplane.yaml (that is YOUR secret) unless
# --force is passed. The generated file is git-ignored by design.
# =============================================================================
set -eu

cd "$(dirname "$0")/.."

FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

if [ ! -f .env ]; then
  echo "[secrets] FATAL: no .env — run: cp .env.example .env, then re-run." >&2
  exit 1
fi
# Plain KEY=value file (see .env.example); safe to source.
. ./.env
if [ -z "${DOMAIN:-}" ]; then
  echo "[secrets] FATAL: DOMAIN is not set in .env" >&2
  exit 1
fi

TPL="config/headplane/headplane.yaml.example"
OUT="config/headplane/headplane.yaml"

if [ -f "$OUT" ] && [ "$FORCE" -ne 1 ]; then
  echo "[secrets] $OUT already exists — keeping it (pass --force to regenerate)."
else
  # openssl if present, raw /dev/urandom otherwise. The secret never hits stdout.
  if command -v openssl >/dev/null 2>&1; then
    SECRET="$(openssl rand -hex 32)"
  else
    SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  sed -e "s|__DOMAIN__|${DOMAIN}|g" \
      -e "s|__SESSION_SECRET__|${SECRET}|g" \
      "$TPL" > "$OUT"
  chmod 600 "$OUT"
  echo "[secrets] wrote $OUT (mode 600; the secret itself was not printed)"
fi

# Create runtime dirs up front so docker bind-mounts never initialize them
# as root-owned surprises mid-run.
for d in data/headscale data/headplane data/caddy backups; do
  mkdir -p "$d"
  chmod 750 "$d"
done

echo "[secrets] done"
