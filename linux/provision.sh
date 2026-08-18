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
  cmake unzip zip xz-utils protobuf-compiler \
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

# pct exec / GH runner services often have PATH=/usr/bin:/bin only.
# rustc is a rustup proxy and MUST see RUSTUP_HOME or it re-downloads into $HOME/.rustup.
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH="/usr/local/sbin:/usr/local/bin:${CARGO_HOME}/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Rust (system-wide under /usr/local/cargo for service accounts)
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
# Wrappers (not bare rustup-proxy symlinks): GH runner services ignore
# /etc/environment until restart. rustc without RUSTUP_HOME re-downloads.
install_rust_wrap() {
  local name=$1 src=/usr/local/cargo/bin/$1
  [[ -e "$src" ]] || return 0
  for wrap in /usr/local/bin/$name /usr/bin/$name; do
    rm -f "$wrap"
    cat > "$wrap" <<EOF
#!/bin/sh
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export RUSTUP_TOOLCHAIN="\${RUSTUP_TOOLCHAIN:-stable}"
exec $src "\$@"
EOF
    chmod 755 "$wrap"
  done
}
install_rust_wrap rustc
install_rust_wrap cargo
install_rust_wrap rustup
cat > /etc/profile.d/sb-builder.sh <<'EOF'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/local/cargo/bin:$PATH"
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export RUSTUP_TOOLCHAIN=stable
EOF

# protoc — pin; do not query GH API (unauth 60/hr shared NAT)
PROTOC_PIN="${PROTOC_PIN:-29.3}"
if ! command -v protoc >/dev/null; then
  log "installing protoc ${PROTOC_PIN}..."
  curl -fsSL -o /tmp/protoc.zip "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_PIN}/protoc-${PROTOC_PIN}-linux-x86_64.zip"
  unzip -qo /tmp/protoc.zip -d /usr/local
  rm -f /tmp/protoc.zip
fi
ln -sfn /usr/local/bin/protoc /usr/bin/protoc 2>/dev/null || true

# Node 20 + 22 side-by-side (wrangler ≥22). Default `node` stays existing or becomes 20.
install_node() {
  local ver=$1 dest=$2
  if [[ -x "$dest/bin/node" ]]; then return 0; fi
  log "installing node ${ver} -> ${dest}"
  mkdir -p "$dest"
  curl -fsSL "https://nodejs.org/dist/v${ver}/node-v${ver}-linux-x64.tar.xz" -o "/tmp/node${ver}.txz"
  tar -xJf "/tmp/node${ver}.txz" -C "$dest" --strip-components=1
  rm -f "/tmp/node${ver}.txz"
}
install_node 20.19.4 /usr/local/node20
install_node 22.18.0 /usr/local/node22
ln -sfn /usr/local/node20/bin/node /usr/local/bin/node20
ln -sfn /usr/local/node22/bin/node /usr/local/bin/node22
ln -sfn /usr/local/node20/bin/node /usr/bin/node20
ln -sfn /usr/local/node22/bin/node /usr/bin/node22
if ! command -v node >/dev/null; then
  ln -sfn /usr/local/node20/bin/node /usr/local/bin/node
  ln -sfn /usr/local/node20/bin/npm  /usr/local/bin/npm
fi

systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true

log "done. run verify-builder.sh next."
