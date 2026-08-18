#!/usr/bin/env bash
# verify-builder.sh — macOS StudioBrain builder gate
set -euo pipefail
fail=0
check(){ local n="$1"; shift; if "$@"; then echo "  [ OK ] $n"; else echo "  [FAIL] $n"; fail=$((fail+1)); fi; }
echo "== StudioBrain macOS builder verification =="
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

check 'git' command -v git >/dev/null
check 'cmake' command -v cmake >/dev/null
check 'protoc' command -v protoc >/dev/null
check 'node' command -v node >/dev/null
check 'gh' command -v gh >/dev/null
check 'rustc' command -v rustc >/dev/null
check 'cargo' command -v cargo >/dev/null
check 'xcode-select' xcode-select -p >/dev/null

scratch="$(mktemp -d /tmp/sbverify.XXXXXX)"
if cargo new "$scratch/app" --bin >/dev/null 2>&1 && (cd "$scratch/app" && cargo build >/dev/null 2>&1); then
  echo "  [ OK ] scratch cargo build"
else
  echo "  [FAIL] scratch cargo build"; fail=$((fail+1))
fi
rm -rf "$scratch"
[[ $fail -eq 0 ]] && echo "== ALL CHECKS PASSED ==" || echo "== $fail CHECK(S) FAILED =="
exit "$fail"
