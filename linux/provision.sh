#!/usr/bin/env bash
# provision.sh — Ubuntu/Debian StudioBrain Linux builder toolchain (idempotent)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
log(){ echo "[linux-provision] $*"; }

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (sudo)" >&2
  exit 1
fi

log "apt base packages..."
apt-get update -qq
apt-get install -y -qq \
  curl ca-certificates git build-essential pkg-config \
  cmake unzip zip \
  libssl-dev libwebkit2gtk-4.1-dev libgtk-3-dev \
  libayatana-appindicator3-dev librsvg2-dev patchelf \
  openssh-server jq

log "ensuring unzip present (arduino/setup-protoc hard-requires it)..."
command -v unzip >/dev/null

# Node 20 via NodeSource
if ! command -v node >/dev/null || [[ "$(node -v 2>/dev/null | tr -d v | cut -d. -f1)" -lt 20 ]]; then
  log "installing Node 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi

# gh CLI
if ! command -v gh >/dev/null; then
  log "installing gh..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
  apt-get update -qq && apt-get install -y -qq gh
fi

# Rust (system-wide under /usr/local/cargo for service accounts)
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
if [[ ! -x /usr/local/cargo/bin/rustc ]]; then
  log "installing rustup..."
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --no-modify-path
  chmod -R a+rX /usr/local/rustup /usr/local/cargo
fi
# Always refresh stable — deps drift (jsonwebtoken/time/icu needed 1.88 while runners sat on 1.85.1; SBAI cloud #901/#902).
# Directory overrides can beat `rustup default`; CI should also set RUSTUP_TOOLCHAIN=stable.
log "rustup update stable..."
/usr/local/cargo/bin/rustup update stable || true
/usr/local/cargo/bin/rustup default stable || true
ln -sfn /usr/local/cargo/bin/rustc /usr/local/bin/rustc
ln -sfn /usr/local/cargo/bin/cargo /usr/local/bin/cargo
ln -sfn /usr/local/cargo/bin/rustup /usr/local/bin/rustup
echo 'export PATH=/usr/local/cargo/bin:$PATH' > /etc/profile.d/rust.sh
echo 'export RUSTUP_TOOLCHAIN=stable' >> /etc/profile.d/rust.sh

# protoc
if ! command -v protoc >/dev/null; then
  log "installing protoc..."
  PROTOC_VERSION="$(curl -fsSL https://api.github.com/repos/protocolbuffers/protobuf/releases/latest | jq -r .tag_name | sed 's/^v//')"
  curl -fsSL -o /tmp/protoc.zip "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip"
  unzip -qo /tmp/protoc.zip -d /usr/local
  rm -f /tmp/protoc.zip
fi

systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true

log "done. run verify-builder.sh next."
