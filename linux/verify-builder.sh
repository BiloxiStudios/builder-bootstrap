#!/usr/bin/env bash
# verify-builder.sh — Linux StudioBrain builder gate (exit non-zero on fail)
set -euo pipefail
fail=0
check(){
  local name="$1"; shift
  if "$@"; then echo "  [ OK ] $name"; else echo "  [FAIL] $name"; fail=$((fail+1)); fi
}
echo "== StudioBrain Linux builder verification =="
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
export PATH="/usr/local/sbin:/usr/local/bin:${CARGO_HOME}/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

check 'git' command -v git >/dev/null
check 'unzip' command -v unzip >/dev/null
check 'cmake' command -v cmake >/dev/null
check 'protoc' command -v protoc >/dev/null
check 'node' command -v node >/dev/null
check 'npm' command -v npm >/dev/null
check 'gh' command -v gh >/dev/null
check 'rustc' command -v rustc >/dev/null
check 'cargo' command -v cargo >/dev/null

echo "  ... scratch cargo build ..."
scratch="$(mktemp -d /tmp/sbverify.XXXXXX)"
if cargo new "$scratch/app" --bin >/dev/null 2>&1 && (cd "$scratch/app" && cargo build >/dev/null 2>&1); then
  echo "  [ OK ] scratch cargo build"
else
  echo "  [FAIL] scratch cargo build"
  fail=$((fail+1))
fi
rm -rf "$scratch"

if [[ $fail -eq 0 ]]; then echo "== ALL CHECKS PASSED =="; else echo "== $fail CHECK(S) FAILED =="; fi
exit "$fail"
