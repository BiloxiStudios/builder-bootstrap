#!/usr/bin/env bash
# List BiloxiStudios org self-hosted runners. PAT: GH_ADMIN_PAT or GH_TOKEN (admin:org).
set -euo pipefail
TOKEN="${GH_ADMIN_PAT:-${GH_TOKEN:-}}"
[[ -n "$TOKEN" ]] || { echo "Set GH_ADMIN_PAT (Vaultwarden: GitHub PAT — BizaNator PRIMARY)" >&2; exit 1; }
export GH_TOKEN="$TOKEN"
echo "# org=BiloxiStudios  $(date -u +%Y-%m-%dT%H:%MZ)"
printf '%s\t%s\t%s\t%s\t%s\n' ID NAME STATUS BUSY LABELS
gh api --paginate orgs/BiloxiStudios/actions/runners \
  --jq '.runners[] | [.id,.name,.status,(.busy|tostring),(.labels|map(.name)|join(","))] | @tsv'
echo
echo "# enterprise/grae count: $(gh api enterprises/grae/actions/runners --jq .total_count)"
