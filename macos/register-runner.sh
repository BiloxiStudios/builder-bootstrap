#!/usr/bin/env bash
# register-runner.sh — BiloxiStudios org runner (macOS)
set -euo pipefail
ORG=BiloxiStudios
SITE=bx
NAME="$(hostname -s)"
LABELS="self-hosted,macOS,ARM64,macos"
ROOT="$HOME/actions-runner"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --site) SITE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --labels) LABELS="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
PAT="${GH_PAT:-${GITHUB_TOKEN:-}}"
[[ -n "$PAT" ]] || { echo "Set GH_PAT" >&2; exit 1; }

arch="$(uname -m)"
case "$arch" in
  arm64|aarch64) asset_arch=osx-arm64 ;;
  x86_64) asset_arch=osx-x64 ;;
  *) echo "unsupported arch $arch" >&2; exit 1 ;;
esac

hdr=(-H "Authorization: token $PAT" -H "Accept: application/vnd.github+json")
reg="$(curl -fsSL "${hdr[@]}" -X POST "https://api.github.com/orgs/${ORG}/actions/runners/registration-token" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')"

mkdir -p "$ROOT" && cd "$ROOT"
if [[ ! -f ./config.sh ]]; then
  ver="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | python3 -c 'import sys,json;print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"
  curl -fsSL -o actions-runner.tgz "https://github.com/actions/runner/releases/download/v${ver}/actions-runner-${asset_arch}-${ver}.tar.gz"
  tar xzf actions-runner.tgz && rm -f actions-runner.tgz
fi
rm -f .runner .credentials .credentials_rsaparams .runner_migrated 2>/dev/null || true
./config.sh --url "https://github.com/${ORG}" --token "$reg" --name "$NAME" --labels "$LABELS" --unattended --replace
echo "[register] configured $NAME — install as launchd service per infra-macos skill (GUI session caveats apply)"
