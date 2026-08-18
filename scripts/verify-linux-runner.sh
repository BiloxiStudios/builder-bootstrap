#!/usr/bin/env bash
# Verify a Linux runner guest meets studiobrain-app requirements (run INSIDE the CT).
# Exit non-zero on any fail. Swap must be ACTIVE (free Swap>0), not just pct-configured.
set -euo pipefail
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
export PATH="/usr/local/sbin:/usr/local/bin:${CARGO_HOME}/bin:/usr/sbin:/usr/bin:/sbin:/bin"
fail=0
check(){ local n="$1"; shift; if "$@"; then echo "  [ OK ] $n"; else echo "  [FAIL] $n"; fail=$((fail+1)); fi; }
echo "== Linux runner verify $(hostname) =="
check 'unzip' command -v unzip >/dev/null
check 'protoc' command -v protoc >/dev/null
check 'node20 or node' bash -c 'command -v node20 >/dev/null || command -v node >/dev/null'
check 'node22' command -v node22 >/dev/null
swap_b=$(free -b | awk '/^Swap:/{print $2}')
check "swap active (bytes=$swap_b)" bash -c "test ${swap_b:-0} -gt 0"
if command -v rustc >/dev/null; then
  check 'rustc' true
  echo "         $(rustc --version)"
else
  echo "  [WARN] rustc missing (ok if job uses dtolnay/rust-toolchain)"
fi
echo "== $([[ $fail -eq 0 ]] && echo PASS || echo $fail FAIL) =="
exit "$fail"
