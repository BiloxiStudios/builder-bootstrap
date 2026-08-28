#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scripts=(
  "$repo_root/linux/provision.sh"
  "$repo_root/scripts/remediate-linux-toolchain.sh"
)

for script in "${scripts[@]}"; do
  function_body=$(
    awk '
      /^install_rustup_link\(\) \{/ { capture = 1 }
      capture { print }
      capture && /^}/ { exit }
    ' "$script"
  )

  if [[ -z "$function_body" ]]; then
    echo "FAIL: $script does not define install_rustup_link" >&2
    exit 1
  fi

  layout=$(mktemp -d /tmp/builder-bootstrap-rustup.XXXXXXXXXX)
  mkdir -p \
    "$layout/usr/local/cargo/bin" \
    "$layout/usr/local/bin" \
    "$layout/usr/bin"
  printf '#!/bin/sh\nexit 0\n' > "$layout/usr/local/cargo/bin/rustup"
  chmod 755 "$layout/usr/local/cargo/bin/rustup"

  (
    export RUSTUP_LAYOUT_ROOT="$layout"
    eval "$function_body"
    install_rustup_link

    test -L "$layout/usr/local/bin/rustup"
    test -L "$layout/usr/bin/rustup"

    PATH="$layout/usr/local/bin:/usr/bin:/bin"
    command -v rustup >/dev/null

    rm -f "$layout/usr/local/cargo/bin/rustup"
    hash -r
    if command -v rustup >/dev/null; then
      echo "FAIL: $script masks a missing real rustup as command-resolvable" >&2
      exit 1
    fi

    rm -f "$layout/usr/local/bin/rustup" "$layout/usr/bin/rustup"
    printf '#!/bin/sh\nexit 127\n' > "$layout/usr/local/bin/rustup"
    chmod 755 "$layout/usr/local/bin/rustup"
    install_rustup_link
    hash -r
    if command -v rustup >/dev/null; then
      echo "FAIL: $script preserves a stale rustup wrapper when the real binary is missing" >&2
      exit 1
    fi
  )

  rm -rf "$layout"
done

echo "PASS: rustup command paths stop resolving when the real rustup is missing"
