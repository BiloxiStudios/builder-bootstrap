#!/usr/bin/env bash
# Disable IPv6 on GitHub Actions runner CTs to prevent npm/Node.js hangs.
# SBAI-14371: Node.js v20/npm 10 undici follows AAAA records first, but
# runner CTs have IPv6 enabled with only link-local addresses (no global route).
# This causes `npm ci` to hang for minutes on "resolving registry.npmjs.org".
#
# Affected CTs: 145, 146, 147, 148 (proxmox-linux-1/2/3/4 on pve1)
# Run from BRAINZ or any host with SSH access to Proxmox nodes.
#
# Usage: ./disable-ipv6-runners.sh [--dry-run]
set -euo pipefail

DRY_RUN="${1:-}"
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  echo "[DRY-RUN] Would disable IPv6 on CTs 145-148"
  DRY_RUN_CMD="echo [DRY-RUN]"
else
  DRY_RUN_CMD=""
fi

# CTs to fix (pve1 runner CTs with build-cf-worker label)
CT_IDS="145 146 147 148"
PVE_HOST="10.15.0.30"

# Guest-side script to disable IPv6 (pushed via pct)
GUEST_SCRIPT=$(cat <<'GUEST_EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "[disable-ipv6] Disabling IPv6 on $(hostname)"

# 1. Disable via sysctl immediately
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# 2. Persist in /etc/sysctl.d/
cat > /etc/sysctl.d/60-disable-ipv6.conf <<'SYSCTL'
# Disable IPv6 - SBAI-14371
# Node.js/npm undici follows AAAA records first, but no IPv6 route exists
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
SYSCTL

# 3. Verify
if sysctl net.ipv6.conf.all.disable_ipv6 | grep -q '= 1'; then
  echo "[OK] IPv6 disabled successfully"
else
  echo "[FAIL] IPv6 disable did not persist"
  exit 1
fi
GUEST_EOF
)

for ct_id in $CT_IDS; do
  echo "=== CT${ct_id} ==="

  # Pre-check: verify CT is running
  if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$PVE_HOST" \
    "pct status $ct_id | grep -qi 'status: running'"; then
    echo "[WARN] CT${ct_id} is not running, skipping"
    continue
  fi

  echo "[INFO] CT${ct_id} is running, applying fix..."

  # Push and execute the script
  if [[ -n "$DRY_RUN_CMD" ]]; then
    echo "[DRY-RUN] Would execute on CT${ct_id}:"
    echo "$GUEST_SCRIPT"
  else
    # Method 1: Direct exec via pct
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$PVE_HOST" \
      "pct exec $ct_id -- bash -s" <<< "$GUEST_SCRIPT"

    # Verify the fix took
    result=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$PVE_HOST" \
      "pct exec $ct_id -- sysctl net.ipv6.conf.all.disable_ipv6 2>&1")

    if echo "$result" | grep -q "= 1"; then
      echo "[OK] CT${ct_id}: IPv6 disabled successfully"
    else
      echo "[FAIL] CT${ct_id}: IPv6 disable verification failed"
      echo "  Output: $result"
    fi
  fi

  echo ""
done

if [[ -z "$DRY_RUN_CMD" ]]; then
  echo "=== Complete ==="
  echo "IPv6 has been disabled on all runner CTs."
  echo "To re-enable (if needed): remove /etc/sysctl.d/60-disable-ipv6.conf and set disable_ipv6=0"
fi
