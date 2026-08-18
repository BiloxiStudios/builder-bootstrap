#!/usr/bin/env bash
# Guest-side remediator: make last night's bake *usable* by GH runners.
# Cause of BAKE_OK + RUSTC/NODE20/NODE22=MISSING: pct exec PATH omitted
# /usr/local/bin, and rustc (rustup proxy) had no RUSTUP_HOME so it
# re-downloaded into $HOME/.rustup on every invocation.
#
# Idempotent. Fast. Does NOT rustup-update. Does NOT restart the runner.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH="/usr/local/sbin:/usr/local/bin:${CARGO_HOME}/bin:/usr/sbin:/usr/bin:/sbin:/bin"
PROTOC_PIN="${PROTOC_PIN:-29.3}"
NODE20_VER="${NODE20_VER:-20.19.4}"
NODE22_VER="${NODE22_VER:-22.18.0}"
log(){ echo "[remediate $(hostname)] $*"; }

need_bin() {
  local bin=$1 pkg=${2:-$1}
  if ! command -v "$bin" >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq "$pkg"
  fi
}
need_bin unzip unzip
need_bin xz xz-utils
need_bin curl curl
# CI (MM) also checks the apt package, not just /usr/bin/protoc from the official zip.
if ! dpkg -s protobuf-compiler >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq protobuf-compiler
fi

# --- protoc (pinned; never hit GH API — unauth 60/hr shared NAT) ---
if ! command -v protoc >/dev/null 2>&1 && [[ ! -x /usr/local/bin/protoc ]]; then
  log "installing protoc ${PROTOC_PIN}"
  curl -fsSL -o /tmp/protoc.zip \
    "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_PIN}/protoc-${PROTOC_PIN}-linux-x86_64.zip"
  unzip -qo /tmp/protoc.zip -d /usr/local
  rm -f /tmp/protoc.zip
fi

# --- node 20/22 official tarballs ---
install_node() {
  local ver=$1 dest=$2
  if [[ -x "$dest/bin/node" ]]; then
    return 0
  fi
  log "installing node ${ver} -> ${dest}"
  mkdir -p "$dest"
  curl -fsSL "https://nodejs.org/dist/v${ver}/node-v${ver}-linux-x64.tar.xz" -o "/tmp/node${ver}.txz"
  tar -xJf "/tmp/node${ver}.txz" -C "$dest" --strip-components=1
  rm -f "/tmp/node${ver}.txz"
  test -x "$dest/bin/node"
}
install_node "$NODE20_VER" /usr/local/node20
install_node "$NODE22_VER" /usr/local/node22

# --- rustup: restore if a previous remediator followed the symlink and
#     overwrote /usr/local/cargo/bin/rustup with a shell wrapper ---
if [[ ! -x /usr/local/cargo/bin/rustup ]] || head -c 2 /usr/local/cargo/bin/rustup 2>/dev/null | grep -q '#'; then
  log "restoring rustup binary (was overwritten by symlink-follow)"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain none --no-modify-path
fi
if [[ -x /usr/local/cargo/bin/rustup ]] && [[ ! -d /usr/local/rustup/toolchains/stable-x86_64-unknown-linux-gnu ]]; then
  /usr/local/cargo/bin/rustup default stable || /usr/local/cargo/bin/rustup toolchain install stable
fi
# rustup proxy writes /usr/local/rustup/tmp. a+rX is not enough — first
# mm-linux-1 job died Permission denied (bake was root-owned). Chown to
# the GH runner user when it exists; otherwise world-writable tmp.
mkdir -p /usr/local/rustup/tmp /usr/local/cargo
if id runner >/dev/null 2>&1; then
  chown -R runner:runner /usr/local/rustup /usr/local/cargo
else
  chmod -R a+rX /usr/local/rustup /usr/local/cargo || true
  chmod -R a+rwx /usr/local/rustup/tmp || true
fi

# --- symlinks on BOTH /usr/local/bin AND /usr/bin (pct + GH service PATH) ---
link() {
  local src=$1 dest=$2
  [[ -e "$src" || -L "$src" ]] || return 0
  ln -sfn "$src" "$dest"
}
link /usr/local/bin/protoc              /usr/bin/protoc
# rustc/cargo/rustup MUST export RUSTUP_HOME — GH runner services
# do not pick up /etc/environment until restart, and rustc is a rustup
# proxy that otherwise re-downloads into $HOME/.rustup.
install_rust_wrap() {
  local name=$1
  local src=/usr/local/cargo/bin/$name
  [[ -e "$src" ]] || return 0
  local wrap
  for wrap in /usr/local/bin/$name /usr/bin/$name; do
    # rm the path first — `cat >` follows a symlink and would overwrite
    # /usr/local/cargo/bin/rustup (the real binary). Hit that 2026-08-18.
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
link /usr/local/node20/bin/node         /usr/local/bin/node20
link /usr/local/node22/bin/node         /usr/local/bin/node22
link /usr/local/node20/bin/npm          /usr/local/bin/npm20
link /usr/local/node22/bin/npm          /usr/local/bin/npm22
link /usr/local/node20/bin/node         /usr/bin/node20
link /usr/local/node22/bin/node         /usr/bin/node22
link /usr/local/node20/bin/npm          /usr/bin/npm20
link /usr/local/node22/bin/npm          /usr/bin/npm22
if ! command -v node >/dev/null 2>&1; then
  link /usr/local/node20/bin/node /usr/local/bin/node
  link /usr/local/node20/bin/npm  /usr/local/bin/npm
  link /usr/local/node20/bin/node /usr/bin/node
  link /usr/local/node20/bin/npm  /usr/bin/npm
fi

# --- system env (login shells + some PAM) ---
cat > /etc/profile.d/sb-builder.sh <<'EOF'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/local/cargo/bin:$PATH"
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export RUSTUP_TOOLCHAIN=stable
EOF
chmod 644 /etc/profile.d/sb-builder.sh

# Merge into /etc/environment without clobbering existing keys
touch /etc/environment
python3 - <<'PY'
from pathlib import Path
p = Path("/etc/environment")
wanted = {
    "RUSTUP_HOME": "/usr/local/rustup",
    "CARGO_HOME": "/usr/local/cargo",
    "RUSTUP_TOOLCHAIN": "stable",
}
lines = p.read_text().splitlines() if p.exists() else []
keys = {}
out = []
for line in lines:
    if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
        out.append(line)
        continue
    k, _, v = line.partition("=")
    keys[k.strip()] = (len(out), v)
    out.append(line)
# PATH: ensure prefixes
prefix = "/usr/local/sbin:/usr/local/bin:/usr/local/cargo/bin"
if "PATH" in keys:
    i, raw = keys["PATH"]
    cur = raw.strip().strip('"').strip("'")
    parts = [x for x in cur.split(":") if x]
    for pth in reversed(prefix.split(":")):
        if pth not in parts:
            parts.insert(0, pth)
    out[i] = 'PATH="' + ":".join(parts) + '"'
else:
    out.append('PATH="' + prefix + ':/usr/sbin:/usr/bin:/sbin:/bin"')
for k, v in wanted.items():
    if k in keys:
        out[keys[k][0]] = f'{k}={v}'
    else:
        out.append(f'{k}={v}')
p.write_text("\n".join(out) + "\n")
PY

# --- GH Actions runner .env (service does NOT source profile.d) ---
patch_runner_env() {
  local envf=$1
  local dir
  dir=$(dirname "$envf")
  [[ -d "$dir" ]] || return 0
  touch "$envf"
  python3 - "$envf" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
wanted = {
    "RUSTUP_HOME": "/usr/local/rustup",
    "CARGO_HOME": "/usr/local/cargo",
    "RUSTUP_TOOLCHAIN": "stable",
}
text = p.read_text() if p.exists() else ""
lines = text.splitlines()
idx = {}
out = []
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        k = line.split("=", 1)[0].strip()
        idx[k] = len(out)
    out.append(line)
# PATH
prefix = "/usr/local/sbin:/usr/local/bin:/usr/local/cargo/bin"
if "PATH" in idx:
    i = idx["PATH"]
    raw = out[i].split("=", 1)[1].strip().strip('"').strip("'")
    parts = [x for x in raw.split(":") if x]
    for pth in reversed(prefix.split(":")):
        if pth not in parts:
            parts.insert(0, pth)
    out[i] = "PATH=" + ":".join(parts)
else:
    out.append("PATH=" + prefix + ":/usr/sbin:/usr/bin:/sbin:/bin")
for k, v in wanted.items():
    if k in idx:
        out[idx[k]] = f"{k}={v}"
    else:
        out.append(f"{k}={v}")
p.write_text("\n".join(out) + "\n")
print(f"patched {p}")
PY
}
# common runner homes
shopt -s nullglob
for envf in \
  /home/runner/actions-runner/.env \
  /opt/actions-runner/.env \
  /actions-runner/.env \
  /home/github/actions-runner/.env \
  /root/actions-runner/.env
do
  patch_runner_env "$envf"
done
for d in /home/*/actions-runner /opt/*runner* /home/runner /home/github; do
  [[ -f "$d/.runner" || -f "$d/run.sh" || -d "$d/_work" ]] || continue
  patch_runner_env "$d/.env"
done
shopt -u nullglob

# --- verify (full paths + env; NEVER invoke rustc without RUSTUP_HOME) ---
ok=1
v() {
  local name=$1 cmd=$2
  if eval "$cmd" >/tmp/sbv.out 2>/tmp/sbv.err; then
    echo "  [ OK ] $name $(tr '\n' ' ' </tmp/sbv.out | head -c 80)"
  else
    echo "  [FAIL] $name $(tr '\n' ' ' </tmp/sbv.err | head -c 120)"
    ok=0
  fi
}
echo "== remediate verify $(hostname) =="
v unzip    'command -v unzip'
v protoc   'protoc --version'
# Prefer the toolchain binary (never talks to the rustup proxy / network).
v rustc    '/usr/local/rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin/rustc --version'
v cargo    '/usr/local/rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin/cargo --version || cargo --version'
v node20   'node20 -v'
v node22   'node22 -v'
v node     'node -v || true'
echo "SWAP=$(free -b | awk '/^Swap:/{print $2}')"
if [[ $ok -eq 1 ]]; then echo REMEDIATE_OK; else echo REMEDIATE_FAIL; exit 1; fi
