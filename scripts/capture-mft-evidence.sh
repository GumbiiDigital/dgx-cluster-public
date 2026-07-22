#!/usr/bin/env bash
set -euo pipefail

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

HOSTS=(
  "${SPARK1_MGMT:-spark-a.example}"
  "${SPARK2_MGMT:-spark-b.example}"
  "${SPARK3_MGMT:-spark-c.example}"
  "${SPARK4_MGMT:-spark-d.example}"
)

stamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${OUT_DIR:-evidence/mft-${stamp}}"
mkdir -p "$out_dir"

ssh_run() {
  local host="$1"
  shift
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "$@"
}

{
  echo "# MFT / ConnectX Evidence Capture"
  echo
  echo "- Captured at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "- Host: $(hostname)"
  echo "- Working directory: $(pwd)"
  echo "- Git commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
} >"$out_dir/README.md"

failures=0

for host in "${HOSTS[@]}"; do
  log="$out_dir/${host//[^A-Za-z0-9_.-]/_}.txt"
  echo "===== ${host} MFT evidence ====="
  if ! ssh_run "$host" 'bash -s' >"$log" 2>&1 <<'REMOTE'
set -euo pipefail
echo "===== identity ====="
hostname
date -u +"%Y-%m-%dT%H:%M:%SZ"

echo "===== sudo/tool state ====="
if sudo -n true 2>/dev/null; then
  echo "sudo_nopass=yes"
else
  echo "sudo_nopass=no"
fi

for tool in mst mlxlink mlxfwmanager mlxconfig mstflint ethtool lspci rdma ibdev2netdev show_gids; do
  command -v "$tool" || echo "${tool}: missing"
done
command -v mlxstat || echo "mlxstat: missing (optional on this MFT package)"

if ! command -v mlxlink >/dev/null 2>&1; then
  echo "STOP: full MFT is not installed; run scripts/install-mft-tools.sh first."
  exit 11
fi

if ! sudo -n true 2>/dev/null; then
  echo "STOP: passwordless sudo is required for mst/mlxlink diagnostics."
  exit 12
fi

echo "===== package versions ====="
dpkg-query -W mft mstflint 2>/dev/null || true

echo "===== host network/RDMA state ====="
ip -br addr show enp1s0f0np0 enP2p1s0f0np0 2>/dev/null || true
ibdev2netdev 2>/dev/null || true
rdma link show 2>/dev/null || true
show_gids 2>/dev/null || true

echo "===== PCIe and driver state ====="
lspci -Dnn | grep -Ei 'mellanox|nvidia' || true
for dev in enp1s0f0np0 enP2p1s0f0np0; do
  echo "--- ${dev} ethtool ---"
  ethtool "$dev" 2>/dev/null || true
  echo "--- ${dev} driver ---"
  ethtool -i "$dev" 2>/dev/null || true
  echo "--- ${dev} stats selected ---"
  ethtool -S "$dev" 2>/dev/null | grep -Ei 'err|drop|discard|crc|symbol|pause|timeout|retry|congestion|ecn|pfc|fec|rx_|tx_' | sed -n '1,220p' || true
done

echo "===== firmware ====="
sudo -n mlxfwmanager --query 2>/dev/null || true
for pci in 0000:01:00.0 0002:01:00.0; do
  echo "--- mstflint ${pci} ---"
  sudo -n mstflint -d "$pci" q 2>/dev/null | sed -n '1,120p' || true
done

echo "===== mst devices ====="
sudo -n mst start 2>/dev/null || true
sudo -n mst status -v 2>/dev/null || true

mst_status="$(sudo -n mst status -v 2>/dev/null || true)"
printf "%s\n" "$mst_status"

mapfile -t diag_devs < <(
  printf "%s\n" "$mst_status" |
    awk '/\/dev\/mst\// {print $1} /ConnectX/ {print $3}' |
    grep -E '^(\/dev\/mst\/|[0-9a-fA-F]{4}:)' |
    sort -u
)

if ((${#diag_devs[@]} == 0)); then
  echo "WARN: no MFT diagnostic devices discovered"
fi

for diag_dev in "${diag_devs[@]}"; do
  echo "===== ${diag_dev} mlxlink ====="
  sudo -n mlxlink -d "$diag_dev" 2>/dev/null || true
  echo "===== ${diag_dev} mlxlink module/counters ====="
  sudo -n mlxlink -d "$diag_dev" -m -c -e 2>/dev/null || true
  if command -v mlxstat >/dev/null 2>&1; then
    echo "===== ${diag_dev} mlxstat ====="
    sudo -n mlxstat -d "$diag_dev" 2>/dev/null || true
  else
    echo "===== ${diag_dev} mlxstat ====="
    echo "mlxstat unavailable in this MFT package"
  fi
  echo "===== ${diag_dev} mlxconfig selected ====="
  sudo -n mlxconfig -d "$diag_dev" q 2>/dev/null | grep -Ei 'ROCE|PFC|DCB|ECN|LINK|RATE|PCI|SRIOV|FEC|LLDP|TRUST|PRIO|QOS' || true
done

echo "===== kernel clues ====="
dmesg -T 2>/dev/null | grep -Ei 'mlx5|mellanox|insufficient power|pcie|aer|fatal|timeout|syndrome|roce' | tail -220 || true
REMOTE
  then
    failures=$((failures + 1))
    echo "FAIL: ${host}; see ${log}"
  fi
done

if (( failures > 0 )); then
  echo "MFT evidence capture failed on ${failures} host(s). Evidence directory: $out_dir"
  exit 1
fi

echo "MFT evidence capture complete: $out_dir"
