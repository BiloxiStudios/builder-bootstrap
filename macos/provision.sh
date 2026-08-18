#!/usr/bin/env bash
# provision.sh — macOS StudioBrain builder toolchain (idempotent). Prefer Homebrew.
set -euo pipefail
log(){ echo "[mac-provision] $*"; }

if ! xcode-select -p >/dev/null 2>&1; then
  log "installing Xcode CLT (may prompt GUI)..."
  xcode-select --install || true
  echo "Re-run after CLT finishes installing." >&2
  exit 1
fi

if ! command -v brew >/dev/null; then
  log "installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # shellenv for Apple Silicon
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

log "brew packages..."
brew update
brew install git cmake protobuf node@20 gh rust unzip || true
brew link --overwrite node@20 2>/dev/null || true

# Ensure rustup default if brew rust insufficient for some workflows
if ! command -v rustc >/dev/null; then
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
fi

log "Remote Login (SSH): enable in System Settings → Sharing, or:"
log "  sudo systemsetup -setremotelogin on"

log "done. run verify-builder.sh next."
