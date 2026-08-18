#!/usr/bin/env bash
# Host-side: compare pct swap config vs guest-active swap + toolchain.
# Run from BRAINZ (ssh pve1/pve2/pve3).
set -euo pipefail
audit() {
  local node=$1 ct=$2
  echo "#### $node CT$ct"
  ssh -o ConnectTimeout=10 -o BatchMode=yes "$node" "pct config $ct | grep -E '^(hostname|memory|swap):'; pct exec $ct -- bash -lc '
    export RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/local/cargo/bin:/usr/sbin:/usr/bin:/sbin:/bin
    echo HOST=\$(hostname)
    echo SWAP_GUEST=\$(free -b | awk \"/^Swap:/{print \\\$2}\")
    echo UNZIP=\$(command -v unzip || echo MISSING)
    echo PROTOC=\$(protoc --version 2>/dev/null || echo MISSING)
    echo RUSTC=\$(rustc --version 2>/dev/null || echo MISSING)
    echo NODE=\$(node -v 2>/dev/null || echo MISSING)
    echo NODE20=\$(node20 -v 2>/dev/null || echo MISSING)
    echo NODE22=\$(node22 -v 2>/dev/null || echo MISSING)
  '"
}
for ct in 145 146 147 148 154 157; do audit pve1 $ct; done
for ct in 163 164 165; do audit pve2 $ct; done
for ct in 158 159; do audit pve3 $ct; done
