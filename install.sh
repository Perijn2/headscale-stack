#!/bin/sh
# =============================================================================
# install.sh — one-shot bootstrap for a fresh host (target: Raspberry Pi OS)
# =============================================================================
# Order of operations:
#   1. Sanity checks: 64-bit arch, root or sudo available
#   2. Detect the OS from /etc/os-release (+ Raspberry Pi device-tree hint)
#   3. Install system dependencies: Docker Engine + Compose plugin
#   4. Ensure .env exists and is actually configured
#   5. Generate host-local secrets (scripts/gen-secrets.sh)
#   6. Bring the stack up
#
# Idempotent: every step no-ops when already satisfied. Re-run any time.
# Written for POSIX sh so it runs identically under dash/bash on any target.
# =============================================================================
set -eu

cd "$(dirname "$0")"

log() { printf '\n[install] %s\n' "$*"; }
die() { printf '[install] FATAL: %s\n' "$*" >&2; exit 1; }

# --- 1. sanity checks ---------------------------------------------------------
ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64|x86_64) ;;
  armv7l|armv6l) die "32-bit ARM ($ARCH) unsupported — headscale images need 64-bit; reflash the OS." ;;
  *)             die "unsupported architecture: $ARCH" ;;
esac

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "not root and no sudo available."
  SUDO="sudo"
fi

# --- 2. detect the OS ---------------------------------------------------------
[ -r /etc/os-release ] || die "/etc/os-release missing — cannot detect the OS."
# Provides ID, ID_LIKE, PRETTY_NAME
. /etc/os-release
OS_ID="${ID:-unknown}"
OS_LIKE="${ID_LIKE:-}"

IS_PI="no"
if grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
  IS_PI="yes"
fi
log "detected: ${PRETTY_NAME:-$OS_ID} on $ARCH (raspberry pi: $IS_PI)"

# --- 3. system dependencies ----------------------------------------------------
# The stack itself is fully containerized; the only host packages needed are
# the Docker Engine and its compose plugin.
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  log "docker + compose plugin already installed — skipping"
else
  log "installing Docker Engine + Compose plugin"
  case "$OS_ID $OS_LIKE" in
    *raspbian*|*debian*|*ubuntu*)
      # Docker's official convenience script: current engine + compose plugin
      # via docker's apt repo (distro repos ship stale or no compose).
      curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
      $SUDO sh /tmp/get-docker.sh
      rm -f /tmp/get-docker.sh
      ;;
    *fedora*|*rhel*|*centos*)
      $SUDO dnf -y install dnf-plugins-core
      $SUDO dnf config-manager --add-repo \
        https://download.docker.com/linux/fedora/docker-ce.repo
      $SUDO dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    *arch*|*manjaro*)
      $SUDO pacman -Sy --noconfirm docker docker-compose
      ;;
    *alpine*)
      $SUDO apk add --no-cache docker docker-cli-compose
      ;;
    *)
      die "no dependency recipe for '$OS_ID' — install Docker + the compose plugin manually, then re-run."
      ;;
  esac
fi

# Enable the daemon at boot and grant the invoking user docker access.
# Group membership only takes effect at next login, so this script keeps
# using $SUDO for its own docker calls regardless.
$SUDO systemctl enable --now docker >/dev/null 2>&1 || true
$SUDO usermod -aG docker "${SUDO_USER:-$(id -un)}" >/dev/null 2>&1 || true

docker compose version >/dev/null 2>&1 || die "compose plugin still missing after install"

# --- 4. env file -----------------------------------------------------------------
if [ ! -f .env ]; then
  cp .env.example .env
  die ".env created from .env.example — set DOMAIN and TLS_EMAIL, then re-run."
fi
# Plain KEY=value file (see .env.example); safe to source.
. ./.env
if [ -z "${DOMAIN:-}" ] || [ "${DOMAIN}" = "head.example.com" ]; then
  die "DOMAIN in .env is empty or still the example value — edit .env, then re-run."
fi

# --- 5. secrets --------------------------------------------------------------------
sh scripts/gen-secrets.sh

# --- 6. up -------------------------------------------------------------------------
log "starting the stack"
$SUDO docker compose up -d

log "done. Dashboard: https://${DOMAIN}"
log "add a device:  docker compose exec headscale preauthkeys create --user <user>"
log "nightly snapshots:  docker compose --profile backup up -d"
