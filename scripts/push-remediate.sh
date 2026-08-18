#!/usr/bin/env bash
# Host-side: copy remediator into each runner CT and exec it.
# Run from BRAINZ. Does not restart runners.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
GUEST="$SCRIPT_DIR/remediate-linux-toolchain.sh"
[[ -f "$GUEST" ]] || { echo "missing $GUEST" >&2; exit 1; }

# node  CT...
declare -A CTS=(
  [pve1]="145 146 147 148 154 157"
  [pve2]="163 164 165"
  [pve3]="158 159"
)

run_node() {
  local node=$1
  local cts=${CTS[$node]}
  echo "######## $node ########"
  scp -o ConnectTimeout=12 -o BatchMode=yes "$GUEST" "$node:/tmp/remediate-linux-toolchain.sh"
  ssh -o ConnectTimeout=12 -o BatchMode=yes "$node" "chmod +x /tmp/remediate-linux-toolchain.sh
    for ct in $cts; do
      echo \"==== BAKE $node \$ct ====\"
      if ! pct status \$ct 2>/dev/null | grep -q running; then
        echo SKIP_NOT_RUNNING
        continue
      fi
      pct push \$ct /tmp/remediate-linux-toolchain.sh /tmp/remediate-linux-toolchain.sh
      pct exec \$ct -- chmod +x /tmp/remediate-linux-toolchain.sh
      pct exec \$ct -- env RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH=/usr/local/sbin:/usr/local/bin:/usr/local/cargo/bin:/usr/sbin:/usr/bin:/sbin:/bin /tmp/remediate-linux-toolchain.sh \
        || echo REMEDIATE_FAIL_CT\$ct
    done"
}

# parallel per node
run_node pve1 > /tmp/remediate-pve1.log 2>&1 &
p1=$!
run_node pve2 > /tmp/remediate-pve2.log 2>&1 &
p2=$!
run_node pve3 > /tmp/remediate-pve3.log 2>&1 &
p3=$!
fail=0
wait $p1 || fail=1
wait $p2 || fail=1
wait $p3 || fail=1
echo "===== pve1 ====="; tail -n 80 /tmp/remediate-pve1.log
echo "===== pve2 ====="; tail -n 80 /tmp/remediate-pve2.log
echo "===== pve3 ====="; tail -n 80 /tmp/remediate-pve3.log
exit $fail
