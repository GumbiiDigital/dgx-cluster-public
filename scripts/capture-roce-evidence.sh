#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

stamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${OUT_DIR:-evidence/roce-${stamp}}"
mkdir -p "$out_dir"

echo "Writing RoCE evidence to: $out_dir"

{
  echo "# RoCE Evidence Capture"
  echo
  echo "- Captured at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "- Host: $(hostname)"
  echo "- Working directory: $(pwd)"
  echo "- Git commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "- IB pass threshold: ${IB_PASS_GBPS:-90} Gbits/sec"
  echo "- CRS804 SSH target: ${CRS804_SSH:-not set}"
} >"$out_dir/README.md"

set +e
scripts/verify-roce-underlay.sh 2>&1 | tee "$out_dir/host-roce-underlay.log"
verify_status=${PIPESTATUS[0]}
set -e
echo "$verify_status" >"$out_dir/host-roce-underlay.exitcode"

if [[ -n "${CRS804_SSH:-}" ]]; then
  echo "Capturing CRS804 switch counters from $CRS804_SSH"
  ssh "$CRS804_SSH" >"$out_dir/crs804-switch-counters.txt" <<'ROUTEROS'
/system resource print
/system routerboard print
/interface ethernet switch print detail
/interface bridge print detail where name="cluster-bridge"
/interface ethernet print detail where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
/interface ethernet switch qos profile print detail
/interface ethernet switch qos map ip print detail
/interface ethernet switch qos tx-manager queue print detail
/interface ethernet switch qos priority-flow-control print detail
/interface ethernet switch port print detail where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
/interface ethernet print stats where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
ROUTEROS
else
  cat >"$out_dir/crs804-switch-counters.todo.txt" <<'EOF'
Set CRS804_SSH=public-admin@192.0.2.10 to capture switch counters automatically, or
paste these commands into the CRS804 terminal during/after the verifier run:

/system resource print
/system routerboard print
/interface ethernet switch print detail
/interface bridge print detail where name="cluster-bridge"
/interface ethernet print detail where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
/interface ethernet switch qos profile print detail
/interface ethernet switch qos map ip print detail
/interface ethernet switch qos tx-manager queue print detail
/interface ethernet switch qos priority-flow-control print detail
/interface ethernet switch port print detail where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
/interface ethernet print stats where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
EOF
fi

if [[ "$verify_status" -eq 0 ]]; then
  echo "Host RoCE verifier passed. Evidence bundle: $out_dir"
else
  echo "Host RoCE verifier failed with exit code $verify_status. Evidence bundle: $out_dir"
fi

exit "$verify_status"
