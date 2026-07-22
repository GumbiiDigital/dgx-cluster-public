#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

SRC_MGMT="${SRC_MGMT:-spark-a.example}"
DST_MGMT="${DST_MGMT:-spark-b.example}"

PRIMARY_NETDEV="${PRIMARY_NETDEV:-enp1s0f0np0}"
PRIMARY_RDMA="${PRIMARY_RDMA:-rocep1s0f0}"
PRIMARY_SRC_IP="${PRIMARY_SRC_IP:-192.0.2.10}"
PRIMARY_DST_IP="${PRIMARY_DST_IP:-192.0.2.10}"

SECONDARY_NETDEV="${SECONDARY_NETDEV:-enP2p1s0f0np0}"
SECONDARY_RDMA="${SECONDARY_RDMA:-roceP2p1s0f0}"
SECONDARY_SRC_IP="${SECONDARY_SRC_IP:-192.0.2.10}"
SECONDARY_DST_IP="${SECONDARY_DST_IP:-192.0.2.10}"
SECONDARY_MTU="${SECONDARY_MTU:-9000}"

IB_SECONDS="${IB_SECONDS:-12}"
IB_SIZE="${IB_SIZE:-8388608}"
IB_QPS="${IB_QPS:-8}"
PRIMARY_PORT="${PRIMARY_PORT:-18515}"
SECONDARY_PORT="${SECONDARY_PORT:-18516}"
SINGLE_HALF_PASS_GBPS="${SINGLE_HALF_PASS_GBPS:-90}"
DUAL_AGG_PASS_GBPS="${DUAL_AGG_PASS_GBPS:-180}"
APPLY_TEMP_SECONDARY="${APPLY_TEMP_SECONDARY:-0}"

stamp="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-evidence/dual-rail-underlay-${stamp}}"
mkdir -p "$OUT_DIR"

ssh_run() {
  local host="$1"
  shift
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "$@"
}

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$OUT_DIR/run.log"
}

cleanup_temp_secondary() {
  if [[ "$APPLY_TEMP_SECONDARY" == "1" ]]; then
    log "Cleaning temporary secondary test IPs and MTU"
    ssh_run "$SRC_MGMT" "sudo -n ip addr del ${SECONDARY_SRC_IP}/24 dev ${SECONDARY_NETDEV} 2>/dev/null || true" || true
    ssh_run "$DST_MGMT" "sudo -n ip addr del ${SECONDARY_DST_IP}/24 dev ${SECONDARY_NETDEV} 2>/dev/null || true" || true
    if [[ -s "$OUT_DIR/source-secondary-original-mtu" ]]; then
      local src_mtu
      src_mtu="$(cat "$OUT_DIR/source-secondary-original-mtu")"
      ssh_run "$SRC_MGMT" "sudo -n ip link set dev ${SECONDARY_NETDEV} mtu ${src_mtu} 2>/dev/null || true" || true
    fi
    if [[ -s "$OUT_DIR/destination-secondary-original-mtu" ]]; then
      local dst_mtu
      dst_mtu="$(cat "$OUT_DIR/destination-secondary-original-mtu")"
      ssh_run "$DST_MGMT" "sudo -n ip link set dev ${SECONDARY_NETDEV} mtu ${dst_mtu} 2>/dev/null || true" || true
    fi
  fi
}

trap cleanup_temp_secondary EXIT

host_snapshot() {
  local label="$1" host="$2"
  log "Capturing host state: ${label} ${host}"
  ssh_run "$host" "bash -s" >"$OUT_DIR/${label}.host.txt" 2>&1 <<REMOTE
set -u
hostname
date -u +%Y-%m-%dT%H:%M:%SZ
ip -br addr show ${PRIMARY_NETDEV} ${SECONDARY_NETDEV} 2>/dev/null || true
ibdev2netdev 2>/dev/null | grep -E '${PRIMARY_RDMA}|${SECONDARY_RDMA}' || true
rdma link show 2>/dev/null | grep -E '${PRIMARY_RDMA}|${SECONDARY_RDMA}' || true
for dev in ${PRIMARY_NETDEV} ${SECONDARY_NETDEV}; do
  echo "--- \$dev ethtool ---"
  ethtool "\$dev" 2>/dev/null | egrep 'Speed|Lanes|Duplex|Link detected' || true
  echo "--- \$dev selected stats ---"
  ethtool -S "\$dev" 2>/dev/null | egrep 'rx_crc|rx_symbol|rx_discards|tx_discards|tx_queue_dropped|rx_prio[0-7]|tx_prio[0-7]|pause|ecn|err|drop|discard' | sed -n '1,160p' || true
done
REMOTE
}

ensure_secondary_ips() {
  if [[ "$APPLY_TEMP_SECONDARY" != "1" ]]; then
    log "APPLY_TEMP_SECONDARY is not 1; secondary IPs must already exist for secondary tests"
    return
  fi

  log "Adding temporary secondary test IPs and MTU ${SECONDARY_MTU}: ${SECONDARY_SRC_IP}/24 and ${SECONDARY_DST_IP}/24"
  ssh_run "$SRC_MGMT" "cat /sys/class/net/${SECONDARY_NETDEV}/mtu" >"$OUT_DIR/source-secondary-original-mtu"
  ssh_run "$DST_MGMT" "cat /sys/class/net/${SECONDARY_NETDEV}/mtu" >"$OUT_DIR/destination-secondary-original-mtu"
  ssh_run "$SRC_MGMT" "sudo -n ip link set dev ${SECONDARY_NETDEV} mtu ${SECONDARY_MTU}; sudo -n ip addr replace ${SECONDARY_SRC_IP}/24 dev ${SECONDARY_NETDEV}; sudo -n ip link set ${SECONDARY_NETDEV} up"
  ssh_run "$DST_MGMT" "sudo -n ip link set dev ${SECONDARY_NETDEV} mtu ${SECONDARY_MTU}; sudo -n ip addr replace ${SECONDARY_DST_IP}/24 dev ${SECONDARY_NETDEV}; sudo -n ip link set ${SECONDARY_NETDEV} up"
}

check_secondary_ready() {
  if ! ssh_run "$SRC_MGMT" "ip -br addr show ${SECONDARY_NETDEV} | grep -q '${SECONDARY_SRC_IP}/24'"; then
    cat <<EOF
Secondary source IP ${SECONDARY_SRC_IP}/24 is not present on ${SRC_MGMT}:${SECONDARY_NETDEV}.

Re-run with APPLY_TEMP_SECONDARY=1 to add non-persistent test IPs and remove
them automatically on exit, or configure the secondary rail persistently first.
EOF
    exit 20
  fi
  if ! ssh_run "$DST_MGMT" "ip -br addr show ${SECONDARY_NETDEV} | grep -q '${SECONDARY_DST_IP}/24'"; then
    cat <<EOF
Secondary destination IP ${SECONDARY_DST_IP}/24 is not present on ${DST_MGMT}:${SECONDARY_NETDEV}.

Re-run with APPLY_TEMP_SECONDARY=1 to add non-persistent test IPs and remove
them automatically on exit, or configure the secondary rail persistently first.
EOF
    exit 21
  fi
}

run_ping_gate() {
  log "Running jumbo ping gates"
  ssh_run "$SRC_MGMT" "ping -c 2 -s 8972 -M do ${PRIMARY_DST_IP}" | tee "$OUT_DIR/primary.ping.log"
  ssh_run "$SRC_MGMT" "ping -I ${SECONDARY_NETDEV} -c 2 -s 8972 -M do ${SECONDARY_DST_IP}" | tee "$OUT_DIR/secondary.ping.log"
}

kill_ib() {
  ssh_run "$SRC_MGMT" 'sudo -n pkill ib_write_bw 2>/dev/null || true' || true
  ssh_run "$DST_MGMT" 'sudo -n pkill ib_write_bw 2>/dev/null || true' || true
  sleep 1
}

parse_avg() {
  awk '/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+/ {avg=$4} END {print avg+0}' "$1"
}

run_ib_pair() {
  local label="$1" rdma_dev="$2" dst_ip="$3"
  log "Running ${label}: ${rdma_dev} -> ${dst_ip}"
  kill_ib

  ssh_run "$DST_MGMT" \
    "sudo -n bash -lc 'ulimit -l unlimited; timeout 35 ib_write_bw -R -d ${rdma_dev} -F --report_gbits -q ${IB_QPS} -s ${IB_SIZE} -D ${IB_SECONDS}'" \
    >"$OUT_DIR/${label}.server.log" 2>&1 &
  local server_pid=$!
  sleep 3

  ssh_run "$SRC_MGMT" \
    "sudo -n bash -lc 'ulimit -l unlimited; ib_write_bw -R -d ${rdma_dev} -F --report_gbits -q ${IB_QPS} -s ${IB_SIZE} -D ${IB_SECONDS} ${dst_ip}'" \
    | tee "$OUT_DIR/${label}.client.log"
  wait "$server_pid" || true

  local avg
  avg="$(parse_avg "$OUT_DIR/${label}.client.log")"
  log "${label} average: ${avg} Gbits/sec"
  printf '%s\n' "$avg" >"$OUT_DIR/${label}.avg"
}

run_dual_ib_pair() {
  log "Running concurrent dual-half RDMA test"
  kill_ib

  ssh_run "$DST_MGMT" \
    "sudo -n bash -lc 'ulimit -l unlimited; timeout 40 ib_write_bw -R -d ${PRIMARY_RDMA} -F --report_gbits -q ${IB_QPS} -s ${IB_SIZE} -D ${IB_SECONDS} -p ${PRIMARY_PORT}'" \
    >"$OUT_DIR/dual-primary.server.log" 2>&1 &
  local primary_server_pid=$!
  ssh_run "$DST_MGMT" \
    "sudo -n bash -lc 'ulimit -l unlimited; timeout 40 ib_write_bw -R -d ${SECONDARY_RDMA} -F --report_gbits -q ${IB_QPS} -s ${IB_SIZE} -D ${IB_SECONDS} -p ${SECONDARY_PORT}'" \
    >"$OUT_DIR/dual-secondary.server.log" 2>&1 &
  local secondary_server_pid=$!
  sleep 4

  ssh_run "$SRC_MGMT" \
    "sudo -n bash -lc 'ulimit -l unlimited; ib_write_bw -R -d ${PRIMARY_RDMA} -F --report_gbits -q ${IB_QPS} -s ${IB_SIZE} -D ${IB_SECONDS} -p ${PRIMARY_PORT} ${PRIMARY_DST_IP}'" \
    >"$OUT_DIR/dual-primary.client.log" 2>&1 &
  local primary_client_pid=$!
  ssh_run "$SRC_MGMT" \
    "sudo -n bash -lc 'ulimit -l unlimited; ib_write_bw -R -d ${SECONDARY_RDMA} -F --report_gbits -q ${IB_QPS} -s ${IB_SIZE} -D ${IB_SECONDS} -p ${SECONDARY_PORT} ${SECONDARY_DST_IP}'" \
    >"$OUT_DIR/dual-secondary.client.log" 2>&1 &
  local secondary_client_pid=$!

  wait "$primary_client_pid" || true
  wait "$secondary_client_pid" || true
  wait "$primary_server_pid" || true
  wait "$secondary_server_pid" || true

  local primary_avg secondary_avg total_avg
  primary_avg="$(parse_avg "$OUT_DIR/dual-primary.client.log")"
  secondary_avg="$(parse_avg "$OUT_DIR/dual-secondary.client.log")"
  total_avg="$(awk -v a="$primary_avg" -v b="$secondary_avg" 'BEGIN { printf "%.2f", a + b }')"
  log "dual primary average: ${primary_avg} Gbits/sec"
  log "dual secondary average: ${secondary_avg} Gbits/sec"
  log "dual aggregate average: ${total_avg} Gbits/sec"
  {
    echo "primary=${primary_avg}"
    echo "secondary=${secondary_avg}"
    echo "aggregate=${total_avg}"
  } >"$OUT_DIR/dual.aggregate"
}

write_summary() {
  local primary secondary dual_primary dual_secondary dual_total
  primary="$(cat "$OUT_DIR/primary.avg" 2>/dev/null || echo 0)"
  secondary="$(cat "$OUT_DIR/secondary.avg" 2>/dev/null || echo 0)"
  dual_primary="$(awk -F= '/^primary=/{print $2}' "$OUT_DIR/dual.aggregate" 2>/dev/null || echo 0)"
  dual_secondary="$(awk -F= '/^secondary=/{print $2}' "$OUT_DIR/dual.aggregate" 2>/dev/null || echo 0)"
  dual_total="$(awk -F= '/^aggregate=/{print $2}' "$OUT_DIR/dual.aggregate" 2>/dev/null || echo 0)"

  {
    echo "# Dual-Rail Underlay Verification"
    echo
    echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Source: ${SRC_MGMT}"
    echo "- Destination: ${DST_MGMT}"
    echo "- Primary: ${PRIMARY_RDMA}/${PRIMARY_NETDEV} ${PRIMARY_SRC_IP} -> ${PRIMARY_DST_IP}"
    echo "- Secondary: ${SECONDARY_RDMA}/${SECONDARY_NETDEV} ${SECONDARY_SRC_IP} -> ${SECONDARY_DST_IP}"
    echo
    echo "## Results"
    echo
    echo "| Test | Gbits/sec | Pass gate |"
    echo "| --- | ---: | --- |"
    echo "| Primary single-half | ${primary} | >= ${SINGLE_HALF_PASS_GBPS} |"
    echo "| Secondary single-half | ${secondary} | >= ${SINGLE_HALF_PASS_GBPS} |"
    echo "| Dual concurrent primary | ${dual_primary} | informational |"
    echo "| Dual concurrent secondary | ${dual_secondary} | informational |"
    echo "| Dual concurrent aggregate | ${dual_total} | >= ${DUAL_AGG_PASS_GBPS} |"
  } >"$OUT_DIR/SUMMARY.md"

  cat "$OUT_DIR/SUMMARY.md"

  local failures=0
  awk -v avg="$primary" -v min="$SINGLE_HALF_PASS_GBPS" 'BEGIN { exit !(avg >= min) }' || failures=$((failures + 1))
  awk -v avg="$secondary" -v min="$SINGLE_HALF_PASS_GBPS" 'BEGIN { exit !(avg >= min) }' || failures=$((failures + 1))
  awk -v avg="$dual_total" -v min="$DUAL_AGG_PASS_GBPS" 'BEGIN { exit !(avg >= min) }' || failures=$((failures + 1))

  if (( failures > 0 )); then
    log "Dual-rail underlay verification failed: ${failures} gate(s) below threshold"
    return 1
  fi

  log "Dual-rail underlay verification passed"
}

log "Output directory: ${OUT_DIR}"
host_snapshot source-before "$SRC_MGMT"
host_snapshot destination-before "$DST_MGMT"
ensure_secondary_ips
check_secondary_ready
host_snapshot source-after-secondary-ready "$SRC_MGMT"
host_snapshot destination-after-secondary-ready "$DST_MGMT"
run_ping_gate
run_ib_pair primary "$PRIMARY_RDMA" "$PRIMARY_DST_IP"
run_ib_pair secondary "$SECONDARY_RDMA" "$SECONDARY_DST_IP"
run_dual_ib_pair
host_snapshot source-after "$SRC_MGMT"
host_snapshot destination-after "$DST_MGMT"
write_summary
