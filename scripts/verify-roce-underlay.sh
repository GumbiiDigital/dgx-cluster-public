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
IB_PASS_GBPS="${IB_PASS_GBPS:-90}"

if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

SPARK1_MGMT="${SPARK1_MGMT:-spark-a.example}"
SPARK2_MGMT="${SPARK2_MGMT:-spark-b.example}"
SPARK3_MGMT="${SPARK3_MGMT:-spark-c.example}"
SPARK4_MGMT="${SPARK4_MGMT:-spark-d.example}"

SPARK2_FABRIC="${SPARK2_FABRIC:-192.0.2.10}"
SPARK4_FABRIC="${SPARK4_FABRIC:-192.0.2.10}"

ssh_run() {
  local host="$1"
  shift
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "$@"
}

host_check() {
  local label="$1" host="$2"
  echo "===== ${label} host state (${host}) ====="
  ssh_run "$host" '
    hostname
    ip -br addr show enp1s0f0np0 || true
    ibdev2netdev 2>/dev/null || true
    systemctl is-active ssh 2>/dev/null || true
    systemctl is-active dgx-roce-qos.service 2>/dev/null || true
    dcb pfc show dev enp1s0f0np0 2>/dev/null || true
    dcb app show dev enp1s0f0np0 2>/dev/null || true
    if [ "$(id -u)" -eq 0 ]; then
      cma_roce_tos -d rocep1s0f0 -p 1 2>/dev/null || true
    elif sudo -n true 2>/dev/null; then
      sudo -n cma_roce_tos -d rocep1s0f0 -p 1 2>/dev/null || true
    else
      echo "WARN: cma_roce_tos requires public-root or passwordless sudo"
    fi
    ethtool -i enp1s0f0np0 2>/dev/null | egrep "driver|firmware-version|bus-info" || true
    dmesg -T 2>/dev/null | grep -i "insufficient power" | tail -2 || true
  '
}

run_ib_pair() {
  local label="$1" client_mgmt="$2" server_mgmt="$3" server_fabric="$4"
  echo "===== ${label} cleanup ====="
  ssh_run "$client_mgmt" 'pkill ib_write_bw 2>/dev/null || true'
  ssh_run "$server_mgmt" 'pkill ib_write_bw 2>/dev/null || true'
  sleep 1

  echo "===== ${label} server (${server_mgmt}) ====="
  local server_log
  server_log="$(mktemp "/var/tmp/public-run/${label}.server.XXXXXX")"
  ssh_run "$server_mgmt" \
    'timeout 25 ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12' \
    >"$server_log" 2>&1 &
  local server_pid=$!
  sleep 4

  echo "===== ${label} client (${client_mgmt} -> ${server_fabric}) ====="
  local client_log
  client_log="$(mktemp "/var/tmp/public-run/${label}.client.XXXXXX")"
  ssh_run "$client_mgmt" \
    "ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12 ${server_fabric}" \
    | tee "$client_log"

  wait "$server_pid" || true
  echo "===== ${label} server tail ====="
  tail -80 "$server_log"

  local avg_gbps
  avg_gbps="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+/ {avg=$4} END {print avg+0}' "$client_log")"
  echo "===== ${label} result: ${avg_gbps} Gbits/sec average ====="
  awk -v avg="$avg_gbps" -v min="$IB_PASS_GBPS" 'BEGIN { exit !(avg >= min) }'
}

failures=0

host_check spark-a.example "$SPARK1_MGMT"
host_check spark-b.example "$SPARK2_MGMT"
host_check spark-c.example "$SPARK3_MGMT"
host_check spark-d.example "$SPARK4_MGMT"

if ! run_ib_pair spark-a.example-to-spark-b.example "$SPARK1_MGMT" "$SPARK2_MGMT" "$SPARK2_FABRIC"; then
  echo "FAIL: spark-a.example-to-spark-b.example did not reach ${IB_PASS_GBPS} Gbits/sec"
  failures=$((failures + 1))
fi

if ! run_ib_pair spark-c.example-to-spark-d.example "$SPARK3_MGMT" "$SPARK4_MGMT" "$SPARK4_FABRIC"; then
  echo "FAIL: spark-c.example-to-spark-d.example did not reach ${IB_PASS_GBPS} Gbits/sec"
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  echo "RoCE underlay verification failed: ${failures} RDMA pair(s) below threshold."
  exit 1
fi

echo "RoCE underlay verification passed."
