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
WAIT_TIMEOUT_MINUTES="${WAIT_TIMEOUT_MINUTES:-480}"
PAIR_SECONDS="${PAIR_SECONDS:-12}"
IB_SECONDS="${IB_SECONDS:-12}"
SOAK_SECONDS="${SOAK_SECONDS:-300}"
TEST_BRIDGE="${TEST_BRIDGE:-br-overnight}"

SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

HOSTS=(
  "spark-a.example:spark-a.example:192.0.2.10"
  "spark-b.example:spark-b.example:192.0.2.10"
  "spark-c.example:spark-c.example:192.0.2.10"
  "spark-d.example:spark-d.example:192.0.2.10"
)

PAIRS=(
  "spark-a.example-to-spark-b.example:spark-a.example:spark-b.example:192.0.2.10"
  "spark-b.example-to-spark-a.example:spark-b.example:spark-a.example:192.0.2.10"
  "spark-c.example-to-spark-d.example:spark-c.example:spark-d.example:192.0.2.10"
  "spark-d.example-to-spark-c.example:spark-d.example:spark-c.example:192.0.2.10"
)

stamp="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-evidence/overnight-crs804-${stamp}}"
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
  local name="$1"
  log "Capturing CRS804 state: ${name}"
  routeros >"$OUT_DIR/switch-${name}.txt" <<'ROUTEROS'
/system resource print
/system routerboard print
/interface ethernet switch print detail
/interface bridge print detail where name="cluster-bridge"
/interface bridge port print detail where interface="fabric-port-a" or interface="fabric-port-b" or interface="fabric-port-c" or interface="fabric-port-d"
/interface bridge host print where bridge=cluster-bridge
/interface ethernet print detail where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
/interface ethernet switch qos profile print detail
/interface ethernet switch qos map ip print detail
/interface ethernet switch qos tx-manager queue print detail
/interface ethernet switch qos priority-flow-control print detail
/interface ethernet switch qos port print detail where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
/interface ethernet print stats where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
ROUTEROS
}

export_switch() {
  local name="$1"
  log "Saving CRS804 export: ${name}"
  routeros "/export file=${name}" >"$OUT_DIR/switch-export-${name}.log" 2>&1 || true
}

wait_for_hosts() {
  local deadline=$((SECONDS + WAIT_TIMEOUT_MINUTES * 60))
  log "Waiting up to ${WAIT_TIMEOUT_MINUTES} minutes for Sparks 1-4 to return"
  while (( SECONDS < deadline )); do
    local missing=0
    for entry in "${HOSTS[@]}"; do
      IFS=: read -r label host ip <<<"$entry"
      if ! ssh_host "$host" 'hostname >/dev/null' >/dev/null 2>&1; then
        missing=$((missing + 1))
      fi
    done
    if (( missing == 0 )); then
      log "All four Sparks are reachable"
      return 0
    fi
    log "Still waiting; ${missing} Spark(s) not reachable"
    sleep 60
  done
  log "Timed out waiting for all Sparks"
  return 1
}

capture_hosts() {
  local name="$1"
  log "Capturing host state: ${name}"
  for entry in "${HOSTS[@]}"; do
    IFS=: read -r label host ip <<<"$entry"
    ssh_host "$host" 'bash -s' >"$OUT_DIR/host-${name}-${label}.txt" 2>&1 <<'REMOTE'
set -uo pipefail
hostname
date -u +%Y-%m-%dT%H:%M:%SZ
uptime -p
test -f /var/run/reboot-required && echo reboot_required=yes || echo reboot_required=no
uname -r
ip -br addr show enp1s0f0np0 enP2p1s0f0np0 2>/dev/null || true
ibdev2netdev 2>/dev/null || true
rdma link show 2>/dev/null || true
systemctl is-active dgx-roce-qos.service 2>/dev/null || true
sudo -n dcb pfc show dev enp1s0f0np0 2>/dev/null || true
sudo -n dcb app show dev enp1s0f0np0 2>/dev/null || true
sudo -n cma_roce_tos -d rocep1s0f0 -p 1 2>/dev/null || true
ethtool enp1s0f0np0 2>/dev/null | egrep 'Speed|Lanes|Duplex|Link detected' || true
ethtool -S enp1s0f0np0 2>/dev/null | egrep 'rx_crc|rx_discards|tx_discards|tx_queue_dropped|prio[0-7]|pause|ecn|err|drop|discard' | sed -n '1,220p' || true
dmesg -T 2>/dev/null | grep -Ei 'mlx5|mellanox|pcie|aer|syndrome|timeout|insufficient power|roce' | tail -160 || true
REMOTE
  done
}

set_switch_flat() {
  log "Applying temporary CRS804 flat/no-QoS profile"
  export_switch "before-overnight-flat-${stamp}"
  routeros '/interface ethernet switch qos port set [find where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"] pfc=disabled trust-l3=ignore egress-rate-queue3=0' \
    >"$OUT_DIR/apply-switch-flat.log" 2>&1
}

set_switch_test_bridge() {
  log "Applying temporary minimal CRS804 test bridge: ${TEST_BRIDGE}"
  export_switch "before-overnight-test-bridge-${stamp}"
  routeros >"$OUT_DIR/apply-switch-test-bridge.log" 2>&1 <<ROUTEROS
/interface bridge add name="${TEST_BRIDGE}" mtu=9000 protocol-mode=none vlan-filtering=no fast-forward=yes comment="temporary overnight CRS804 test bridge" disabled=no
/interface bridge port remove [find where interface="fabric-port-a" or interface="fabric-port-b" or interface="fabric-port-c" or interface="fabric-port-d"]
/interface bridge port add bridge="${TEST_BRIDGE}" interface=fabric-port-a hw=yes comment="overnight spark-a.example"
/interface bridge port add bridge="${TEST_BRIDGE}" interface=fabric-port-b hw=yes comment="overnight spark-b.example"
/interface bridge port add bridge="${TEST_BRIDGE}" interface=fabric-port-c hw=yes comment="overnight spark-c.example"
/interface bridge port add bridge="${TEST_BRIDGE}" interface=fabric-port-d hw=yes comment="overnight spark-d.example"
/interface bridge print detail where name="${TEST_BRIDGE}"
/interface bridge port print detail where bridge="${TEST_BRIDGE}"
ROUTEROS
}

restore_cluster_bridge() {
  log "Restoring fabric ports to cluster-bridge"
  export_switch "before-overnight-restore-cluster-${stamp}"
  routeros >"$OUT_DIR/restore-cluster-bridge.log" 2>&1 <<'ROUTEROS'
/interface bridge port remove [find where interface="fabric-port-a" or interface="fabric-port-b" or interface="fabric-port-c" or interface="fabric-port-d"]
/interface bridge port add bridge=cluster-bridge interface=fabric-port-a hw=yes comment="Node-1 spark-a.example"
/interface bridge port add bridge=cluster-bridge interface=fabric-port-b hw=yes comment="Node-2 spark-b.example"
/interface bridge port add bridge=cluster-bridge interface=fabric-port-c hw=yes comment="Node-3 spark-c.example"
/interface bridge port add bridge=cluster-bridge interface=fabric-port-d hw=yes comment="Node-4 spark-d.example"
/interface bridge port print detail where interface="fabric-port-a" or interface="fabric-port-b" or interface="fabric-port-c" or interface="fabric-port-d"
ROUTEROS
}

set_switch_roce_doc() {
  log "Applying temporary CRS804 RoCE QoS profile"
  export_switch "before-overnight-roce-qos-${stamp}"
  routeros '/interface ethernet switch qos port set [find where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"] trust-l3=keep pfc=pfc-tc3 egress-rate-queue3=100G' \
    >"$OUT_DIR/apply-switch-roce-qos.log" 2>&1
}

set_hosts_roce_qos() {
  log "Applying host RoCE QoS profile: PFC prio3, AF31/CS6, TOS 106"
  for entry in "${HOSTS[@]}"; do
    IFS=: read -r label host ip <<<"$entry"
    ssh_host "$host" 'sudo -n bash -s' >"$OUT_DIR/apply-host-roce-${label}.log" 2>&1 <<'REMOTE'
set -uo pipefail
for pair in "enp1s0f0np0 rocep1s0f0" "enP2p1s0f0np0 roceP2p1s0f0"; do
  set -- $pair
  dev="$1"
  rdma="$2"
  if ip link show "$dev" >/dev/null 2>&1; then
    dcb pfc set dev "$dev" prio-pfc all:off 3:on || true
    dcb app replace dev "$dev" dscp-prio 26:3 48:6 || true
  fi
  if command -v cma_roce_tos >/dev/null 2>&1 && [ -d "/sys/class/infiniband/$rdma" ]; then
    cma_roce_tos -d "$rdma" -p 1 -t 106 || true
  fi
done
REMOTE
  done
}

set_hosts_flat_qos() {
  log "Applying host flat QoS profile: PFC off, TOS 0"
  for entry in "${HOSTS[@]}"; do
    IFS=: read -r label host ip <<<"$entry"
    ssh_host "$host" 'sudo -n bash -s' >"$OUT_DIR/apply-host-flat-${label}.log" 2>&1 <<'REMOTE'
set -uo pipefail
for pair in "enp1s0f0np0 rocep1s0f0" "enP2p1s0f0np0 roceP2p1s0f0"; do
  set -- $pair
  dev="$1"
  rdma="$2"
  if ip link show "$dev" >/dev/null 2>&1; then
    dcb pfc set dev "$dev" prio-pfc all:off || true
  fi
  if command -v cma_roce_tos >/dev/null 2>&1 && [ -d "/sys/class/infiniband/$rdma" ]; then
    cma_roce_tos -d "$rdma" -p 1 -t 0 || true
  fi
done
REMOTE
  done
}

run_jumbo_mesh() {
  local profile="$1"
  log "Running jumbo ping mesh: ${profile}"
  for src in "${HOSTS[@]}"; do
    IFS=: read -r src_label src_host src_ip <<<"$src"
    for dst in "${HOSTS[@]}"; do
      IFS=: read -r dst_label dst_host dst_ip <<<"$dst"
      [[ "$src_label" == "$dst_label" ]] && continue
      ssh_host "$src_host" "ping -c 2 -s 8972 -M do ${dst_ip}" \
        >"$OUT_DIR/${profile}-${src_label}-to-${dst_label}.jumbo.log" 2>&1 || true
    done
  done
}

run_tcp_pair() {
  local profile="$1" label="$2" client="$3" server="$4" server_ip="$5"
  ssh_host "$client" 'pkill iperf3 2>/dev/null || true' || true
  ssh_host "$server" 'pkill iperf3 2>/dev/null || true' || true
  sleep 1
  ssh_host "$server" "iperf3 -s -B ${server_ip} -1" >"$OUT_DIR/${profile}-${label}.server.iperf3.log" 2>&1 &
  local server_pid=$!
  sleep 2
  ssh_host "$client" "iperf3 -c ${server_ip} -P 16 -t ${PAIR_SECONDS}" >"$OUT_DIR/${profile}-${label}.client.iperf3.log" 2>&1 || true
  wait "$server_pid" || true
}

run_tcp_soak() {
  local profile="$1" label="$2" client="$3" server="$4" server_ip="$5"
  log "${profile}: TCP soak ${label} for ${SOAK_SECONDS}s"
  ssh_host "$client" 'pkill iperf3 2>/dev/null || true' || true
  ssh_host "$server" 'pkill iperf3 2>/dev/null || true' || true
  sleep 1
  ssh_host "$server" "iperf3 -s -B ${server_ip} -1" >"$OUT_DIR/${profile}-${label}.server.soak-iperf3.log" 2>&1 &
  local server_pid=$!
  sleep 2
  ssh_host "$client" "iperf3 -c ${server_ip} -P 16 -t ${SOAK_SECONDS}" >"$OUT_DIR/${profile}-${label}.client.soak-iperf3.log" 2>&1 || true
  wait "$server_pid" || true
}

run_ib_pair() {
  local profile="$1" mode="$2" label="$3" client="$4" server="$5" server_ip="$6"
  local rdma_opt=""
  [[ "$mode" == "rdma-cm" ]] && rdma_opt="-R"
  ssh_host "$client" 'sudo -n pkill ib_write_bw 2>/dev/null || true' || true
  ssh_host "$server" 'sudo -n pkill ib_write_bw 2>/dev/null || true' || true
  sleep 1
  ssh_host "$server" "sudo -n bash -lc 'ulimit -l unlimited; timeout 30 ib_write_bw ${rdma_opt} -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D ${IB_SECONDS}'" \
    >"$OUT_DIR/${profile}-${label}.server.${mode}.log" 2>&1 &
  local server_pid=$!
  sleep 3
  ssh_host "$client" "sudo -n bash -lc 'ulimit -l unlimited; ib_write_bw ${rdma_opt} -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D ${IB_SECONDS} ${server_ip}'" \
    >"$OUT_DIR/${profile}-${label}.client.${mode}.log" 2>&1 || true
  wait "$server_pid" || true
}

run_profile() {
  local profile="$1"
  log "Starting test profile: ${profile}"
  capture_switch "${profile}-before"
  capture_hosts "${profile}-before"
  run_jumbo_mesh "$profile"
  for pair in "${PAIRS[@]}"; do
    IFS=: read -r label client server server_ip <<<"$pair"
    log "${profile}: TCP ${label}"
    run_tcp_pair "$profile" "$label" "$client" "$server" "$server_ip"
    log "${profile}: RDMA-CM ${label}"
    run_ib_pair "$profile" "rdma-cm" "$label" "$client" "$server" "$server_ip"
    log "${profile}: RDMA no-CM ${label}"
    run_ib_pair "$profile" "no-rdma-cm" "$label" "$client" "$server" "$server_ip"
  done
  run_tcp_soak "$profile" "spark-a.example-to-spark-b.example" "spark-a.example" "spark-b.example" "192.0.2.10"
  capture_switch "${profile}-after"
  capture_hosts "${profile}-after"
}

summarize() {
  log "Writing summary"
  {
    echo "# Overnight CRS804 Diagnostics"
    echo
    echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- CRS804: ${CRS804_SSH}"
    echo "- Pair seconds: ${PAIR_SECONDS}"
    echo "- IB seconds: ${IB_SECONDS}"
    echo
    echo "## Selected Results"
    grep -R -E 'SUM.*sender|SUM.*receiver|BW average|Failed status|0.000000|Unable to|Failed to|Completion with error|rx-error-events|tx-drop-packet|rs-fec-uncorrected' "$OUT_DIR" \
      | sed 's#^'"$OUT_DIR"'/##' \
      | sed -n '1,400p'
  } >"$OUT_DIR/SUMMARY.md"
}

log "Output directory: ${OUT_DIR}"
wait_for_hosts
capture_switch "initial-after-cold-drain"
capture_hosts "initial-after-cold-drain"

set_switch_flat
set_hosts_flat_qos
run_profile "flat-no-qos"

set_switch_test_bridge
set_switch_flat
set_hosts_flat_qos
run_profile "minimal-bridge-flat"

restore_cluster_bridge
set_switch_roce_doc
set_hosts_roce_qos
run_profile "roce-qos"

summarize
log "Complete: ${OUT_DIR}"
