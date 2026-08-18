#!/usr/bin/env bash
# bootstrap.sh — Linux/macOS entrypoint (SimpleHelp / curl | bash)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/BiloxiStudios/builder-bootstrap/main/bootstrap.sh | sudo bash -s -- --site bx
set -euo pipefail

BRANCH="${BRANCH:-main}"
SITE="bx"
OS_OVERRIDE=""
VERIFY_ONLY=0
SKIP_PROVISION=0
BASE="https://raw.githubusercontent.com/BiloxiStudios/builder-bootstrap/${BRANCH}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="$2"; shift 2 ;;
    --os) OS_OVERRIDE="$2"; shift 2 ;;
    --branch) BRANCH="$2"; BASE="https://raw.githubusercontent.com/BiloxiStudios/builder-bootstrap/${BRANCH}"; shift 2 ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    --skip-provision) SKIP_PROVISION=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

uname_s="$(uname -s)"
if [[ -n "$OS_OVERRIDE" ]]; then
  os="$OS_OVERRIDE"
elif [[ "$uname_s" == Darwin ]]; then
  os=mac
else
  os=linux
fi

work="$(mktemp -d /tmp/builder-bootstrap.XXXXXX)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

echo "[bootstrap] os=$os site=$SITE work=$work"
curl -fsSL "$BASE/${os}/provision.sh" -o "$work/provision.sh"
curl -fsSL "$BASE/${os}/verify-builder.sh" -o "$work/verify-builder.sh"
curl -fsSL "$BASE/${os}/register-runner.sh" -o "$work/register-runner.sh" || true
chmod +x "$work"/*.sh

if [[ "$VERIFY_ONLY" -eq 0 && "$SKIP_PROVISION" -eq 0 ]]; then
  sudo env SITE="$SITE" "$work/provision.sh"
fi
"$work/verify-builder.sh"

cat <<EOF
[bootstrap] Toolchain verify finished.
Next: register runner with a short-lived org token (mint from VW, do not store PAT):
  sudo $work/register-runner.sh --site $SITE --name "\$(hostname -s)" 
EOF
