#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
CRS804_SSH="${CRS804_SSH:-public-admin@192.0.2.10}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

HOSTS=(
  "spark-a.example:spark-a.example"
  "spark-b.example:spark-b.example"
  "spark-c.example:spark-c.example"
  "spark-d.example:spark-d.example"
)

PORT_EXPR='name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"'
stamp="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-evidence/known-good-delta-${stamp}}"
mkdir -p "$OUT_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$OUT_DIR/run.log"
}

ssh_host() {
  local host="$1"
  shift
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "$@"
}

routeros() {
  ssh -o BatchMode=yes "$CRS804_SSH" "$@"
}

capture_switch() {
  log "Capturing read-only CRS804 physical/QoS delta"
  routeros >"$OUT_DIR/crs804-known-good-delta.txt" <<ROUTEROS
/system resource print
/system routerboard print
/interface ethernet switch print detail
/interface bridge print detail where name="cluster-bridge"
/interface bridge port print detail where interface="fabric-port-a" or interface="fabric-port-b" or interface="fabric-port-c" or interface="fabric-port-d"
/interface ethernet monitor fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d once
/interface ethernet print detail where ${PORT_EXPR}
/interface ethernet print stats where ${PORT_EXPR}
/interface ethernet switch qos profile print detail
/interface ethernet switch qos map ip print detail
/interface ethernet switch qos tx-manager queue print detail
/interface ethernet switch qos priority-flow-control print detail
/interface ethernet switch qos port print detail where ${PORT_EXPR}
ROUTEROS
}

capture_host() {
  local label="$1" host="$2"
  log "Capturing read-only host logical-interface delta: ${label} ${host}"
  ssh_host "$host" 'bash -s' >"$OUT_DIR/${label}-${host}.txt" 2>&1 <<'REMOTE'
set -u
hostname
date -u +%Y-%m-%dT%H:%M:%SZ
uname -r
echo "===== logical interfaces ====="
ip -br addr show enp1s0f0np0 enP2p1s0f0np0 2>/dev/null || true
ip -br link show enp1s0f0np0 enP2p1s0f0np0 2>/dev/null || true
ip route | grep -E '10\.200|10\.201' || true
echo "===== RDMA mapping ====="
ibdev2netdev 2>/dev/null | grep -E 'rocep1s0f0|roceP2p1s0f0' || true
rdma link show 2>/dev/null | grep -E 'rocep1s0f0|roceP2p1s0f0' || true
show_gids 2>/dev/null | grep -E 'rocep1s0f0|roceP2p1s0f0|10\.200|10\.201' || true
echo "===== host DCB state ====="
for dev in enp1s0f0np0 enP2p1s0f0np0; do
  echo "--- ${dev} pfc ---"
  dcb pfc show dev "$dev" 2>/dev/null || true
  echo "--- ${dev} app ---"
  dcb app show dev "$dev" 2>/dev/null || true
done
echo "===== cma_roce_tos ====="
if sudo -n true 2>/dev/null; then
  sudo -n cma_roce_tos -d rocep1s0f0 -p 1 2>/dev/null || true
  sudo -n cma_roce_tos -d roceP2p1s0f0 -p 1 2>/dev/null || true
else
  echo "WARN: passwordless sudo unavailable; cma_roce_tos not captured"
fi
echo "===== link detail ====="
for dev in enp1s0f0np0 enP2p1s0f0np0; do
  echo "--- ${dev} ethtool ---"
  ethtool "$dev" 2>/dev/null | egrep 'Speed|Lanes|Duplex|Port|Auto-negotiation|FEC|Link detected' || true
  echo "--- ${dev} driver ---"
  ethtool -i "$dev" 2>/dev/null || true
  echo "--- ${dev} selected counters ---"
  ethtool -S "$dev" 2>/dev/null | egrep 'rx_crc|rx_symbol|rx_discards|tx_discards|tx_queue_dropped|rx_prio[0-7]|tx_prio[0-7]|pause|ecn|err|drop|discard|fec|out_of_buffer|cnp' | sed -n '1,220p' || true
done
echo "===== persistent network config names ====="
ls -1 /etc/netplan 2>/dev/null || true
systemctl is-active systemd-networkd NetworkManager 2>/dev/null || true
echo "===== recent mlx5 clues ====="
dmesg -T 2>/dev/null | grep -Ei 'mlx5|ConnectX|insufficient power|pcie|aer|syndrome|timeout|roce' | tail -120 || true
REMOTE
}

write_summary() {
  log "Writing summary"
  {
    echo "# CRS804 Known-Good Delta Capture"
    echo
    echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- CRS804 target: ${CRS804_SSH}"
    echo "- Output directory: ${OUT_DIR}"
    echo
    echo "## Switch Physical Delta"
    echo
    grep -E 'name="qsfp56-dd|mtu=|l2mtu=|speed=|fec-mode=|sfp-type|sfp-link-length|sfp-cmis-module-state|sfp-connector-type' "$OUT_DIR/crs804-known-good-delta.txt" | sed -n '1,160p'
    echo
    echo "## Host Logical Interface Delta"
    echo
    for f in "$OUT_DIR"/spark*.txt; do
      echo
      echo "### $(basename "$f")"
      grep -E '^(spark-|enp1s0f0np0|enP2p1s0f0np0|rocep1s0f0|roceP2p1s0f0|10\.200|10\.201|[0-9]+$|prio-pfc|dscp-prio|Speed:|Lanes:|Link detected:)' "$f" | sed -n '1,120p'
    done
  } >"$OUT_DIR/SUMMARY.md"
}

log "Output directory: ${OUT_DIR}"
capture_switch
for entry in "${HOSTS[@]}"; do
  IFS=: read -r label host <<<"$entry"
  capture_host "$label" "$host"
done
write_summary
log "Complete: ${OUT_DIR}"
