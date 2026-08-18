#!/usr/bin/env bash
# register-runner.sh — BiloxiStudios org runner (Linux). Pass PAT via env, never argv if possible.
#   GH_PAT=... sudo -E ./register-runner.sh --site bx --name actions-linux-X --labels self-hosted,linux,proxmox
set -euo pipefail
ORG=BiloxiStudios
SITE=bx
NAME="$(hostname -s)"
LABELS=""
ROOT=/opt/actions-runner

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
[[ -n "$LABELS" ]] || LABELS="self-hosted,linux,proxmox"
PAT="${GH_PAT:-${GITHUB_TOKEN:-}}"
[[ -n "$PAT" ]] || { echo "Set GH_PAT to org admin PAT (mint token only; do not persist)" >&2; exit 1; }

hdr=(-H "Authorization: token $PAT" -H "Accept: application/vnd.github+json")
reg="$(curl -fsSL "${hdr[@]}" -X POST "https://api.github.com/orgs/${ORG}/actions/runners/registration-token" | jq -r .token)"
[[ "$reg" != null && -n "$reg" ]] || { echo "failed to mint registration token" >&2; exit 1; }

mkdir -p "$ROOT"
cd "$ROOT"
if [[ ! -f ./config.sh ]]; then
  ver="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')"
  curl -fsSL -o actions-runner.tgz "https://github.com/actions/runner/releases/download/v${ver}/actions-runner-linux-x86_64-${ver}.tar.gz"
  tar xzf actions-runner.tgz && rm -f actions-runner.tgz
fi
# purge stale registration files for re-run
rm -f .runner .credentials .credentials_rsaparams .runner_migrated 2>/dev/null || true
./config.sh --url "https://github.com/${ORG}" --token "$reg" --name "$NAME" --labels "$LABELS" --unattended --replace
./svc.sh install || true
./svc.sh start
echo "[register] $NAME online with labels: $LABELS"
