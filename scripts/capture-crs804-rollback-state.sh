#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

CRS804_SSH="${CRS804_SSH:-public-admin@192.0.2.10}"
CRS804_KEY="${CRS804_KEY:-$HOME/.ssh/crs804_dgx_temp_ed25519}"
PORT_EXPR='name="fabric-port-e" or name="fabric-port-f" or name="fabric-port-g" or name="fabric-port-h"'
OUT_DIR="${OUT_DIR:-evidence/crs804-rollback-state-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUT_DIR"

SSH_OPTS=(-i "$CRS804_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

routeros() {
  ssh "${SSH_OPTS[@]}" "$CRS804_SSH" "$@"
}

routeros "/export terse" >"$OUT_DIR/export-terse.rsc"

routeros >"$OUT_DIR/readable-state.txt" <<ROUTEROS
/system identity print
/system resource print
/interface ethernet switch print detail
/interface bridge print detail
/interface bridge port print detail
/interface ethernet print detail where ${PORT_EXPR}
/interface ethernet print stats where ${PORT_EXPR}
/interface ethernet switch qos profile print detail
/interface ethernet switch qos map ip print detail
/interface ethernet switch qos map vlan print detail
/interface ethernet switch qos tx-manager print detail
/interface ethernet switch qos tx-manager queue print detail
/interface ethernet switch qos priority-flow-control print detail
/interface ethernet switch qos port print detail where ${PORT_EXPR}
/interface ethernet switch qos monitor once
ROUTEROS

rollback="$OUT_DIR/rollback-note.rsc"
cat >"$rollback" <<'ROLLBACK'
# CRS804 Sparks 5-8 known-good fallback commands.
# Review against readable-state.txt before applying.
# These commands intentionally restore the active 5-8 ports to the current
# non-lossless known-good physical profile used for 23.8 GB/s NCCL evidence.

/interface ethernet set [find where name="fabric-port-e" or name="fabric-port-f" or name="fabric-port-g" or name="fabric-port-h"] mtu=9000 l2mtu=9216 auto-negotiation=no speed=200G-baseCR4 fec-mode=fec91 tx-flow-control=off rx-flow-control=off

# If a QoS experiment changes port classification, return active ports to the
# currently documented default/non-lossless state before rerunning the baseline.
/interface ethernet switch qos port set [find where name="fabric-port-e" or name="fabric-port-f" or name="fabric-port-g" or name="fabric-port-h"] profile=default map=default trust-l2=ignore trust-l3=ignore pfc=disabled

# If a QoS experiment adds temporary rate limits or queue overrides, inspect
# readable-state.txt and unset only fields that differ from the pre-change state.
ROLLBACK

{
  echo "# CRS804 Rollback State Capture"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- CRS804 target: ${CRS804_SSH}"
  echo "- Text export: export-terse.rsc"
  echo "- Readable state: readable-state.txt"
  echo "- Rollback note: rollback-note.rsc"
  echo
  echo "## Active Port Shape"
  grep -E 'name="fabric-port-[e-h]"|mtu=|l2mtu=|speed=|fec-mode=|tx-flow-control|rx-flow-control|profile=|trust-l[23]=|pfc=' "$OUT_DIR/readable-state.txt" | sed -n '1,220p' || true
  echo
  echo "## Rollback Note"
  cat "$rollback"
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
