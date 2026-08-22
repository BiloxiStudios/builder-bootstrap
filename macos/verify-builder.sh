#!/usr/bin/env bash
# verify-builder.sh — macOS StudioBrain builder gate
set -euo pipefail
fail=0
# NOTE: redirect the inner probe's own stdout here, not at the call site
# (`check 'x' cmd >/dev/null` redirects check()'s own [OK]/[FAIL] echo too,
# which silently hid every per-tool diagnostic line — SBAI-7502).
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [ OK ] $n"; else echo "  [FAIL] $n"; fail=$((fail+1)); fi; }
echo "== StudioBrain macOS builder verification =="
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

check 'git' command -v git
check 'cmake' command -v cmake
check 'protoc' command -v protoc
check 'node' command -v node
check 'gh' command -v gh
check 'rustc' command -v rustc
check 'cargo' command -v cargo
check 'xcode-select' xcode-select -p

scratch="$(mktemp -d /tmp/sbverify.XXXXXX)"
if cargo new "$scratch/app" --bin >/dev/null 2>&1 && (cd "$scratch/app" && cargo build >/dev/null 2>&1); then
  echo "  [ OK ] scratch cargo build"
else
  echo "  [FAIL] scratch cargo build"; fail=$((fail+1))
fi
rm -rf "$scratch"
[[ $fail -eq 0 ]] && echo "== ALL CHECKS PASSED ==" || echo "== $fail CHECK(S) FAILED =="
exit "$fail"
