#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

KEY_DEFAULT="$HOME/.ssh/id_ed25519"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
OUT_DIR="${OUT_DIR:-evidence/sparks14-host-fabric-readiness-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o StrictHostKeyChecking=accept-new)

nodes=(
  "spark-a.example|spark-a.example|192.0.2.10 192.0.2.10|192.0.2.10|192.0.2.10"
  "spark-b.example|spark-b.example|192.0.2.10 192.0.2.10 192.0.2.10|192.0.2.10|192.0.2.10"
  "spark-c.example|spark-c.example|spark-c.example 192.0.2.10 192.0.2.10|192.0.2.10|192.0.2.10"
  "spark-d.example|spark-d.example|spark-d.example 192.0.2.10 192.0.2.10|192.0.2.10|192.0.2.10"
)

summary_tsv="$OUT_DIR/readiness.tsv"
echo -e "node\thostname\tssh_target\tssh\tprimary_ip\tsecondary_ip\tf1_netdevs\trdma_devs\tnccl_tests\tstale_processes" >"$summary_tsv"

run_remote_probe() {
  local target="$1"
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${target}" "bash -s" <<'REMOTE'
set -euo pipefail
echo "hostname=$(hostname)"
echo "uname=$(uname -r)"
echo "driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)"
echo "addr_begin"
ip -br addr || true
echo "addr_end"
echo "link_begin"
ip -br link || true
echo "link_end"
echo "rdma_begin"
ls -1 /sys/class/infiniband 2>/dev/null || true
ibdev2netdev 2>/dev/null || true
echo "rdma_end"
echo "nccl_tests=$(test -x "$HOME/nccl-tests/build/all_reduce_perf" && echo yes || echo no)"
echo "proc_begin"
ps -eo pid,comm,args | grep -E 'mpirun|orted|all_reduce_perf|all_gather_perf|nccl-tests' | grep -v grep || true
echo "proc_end"
REMOTE
}

for node_entry in "${nodes[@]}"; do
  IFS='|' read -r label expected targets primary secondary <<<"$node_entry"
  log="$OUT_DIR/${label}.log"
  : >"$log"
  target_used="none"
  ssh_status="fail"

  for target in $targets; do
    if run_remote_probe "$target" >"$log" 2>"$OUT_DIR/${label}-${target}.stderr"; then
      target_used="$target"
      ssh_status="ok"
      break
    fi
  done

  if [[ "$ssh_status" != "ok" ]]; then
    echo -e "${label}\t${expected}\t${target_used}\tfail\tmissing\tmissing\tmissing\tmissing\tunknown\tunknown" >>"$summary_tsv"
    continue
  fi

  primary_status="missing"
  secondary_status="missing"
  f1_netdevs="missing"
  rdma_devs="missing"
  nccl_tests="unknown"
  stale_processes="no"

  if rg -q " ${primary}/" "$log"; then
    primary_status="present"
  fi
  if rg -q " ${secondary}/" "$log"; then
    secondary_status="present"
  fi
  if rg -q 'enp1s0f1np1|enP2p1s0f1np1' "$log"; then
    f1_netdevs="present"
  fi
  if rg -q 'rocep1s0f1|roceP2p1s0f1' "$log"; then
    rdma_devs="present"
  fi
  nccl_tests="$(awk -F= '/^nccl_tests=/ {print $2; exit}' "$log")"
  if awk '/^proc_begin$/ {inproc=1; next} /^proc_end$/ {inproc=0} inproc && NF {found=1} END {exit found ? 0 : 1}' "$log"; then
    stale_processes="yes"
  fi

  echo -e "${label}\t${expected}\t${target_used}\tok\t${primary_status}\t${secondary_status}\t${f1_netdevs}\t${rdma_devs}\t${nccl_tests}\t${stale_processes}" >>"$summary_tsv"
done

{
  echo "# Sparks 1-4 Host Fabric Readiness"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Scope: host-side SSH, interface, RDMA-device, NCCL-test, and stale-process checks only."
  echo "- CRS804 access: not used."
  echo
  echo "## Summary"
  echo
  cat "$summary_tsv"
  echo
  echo "## Gate"
  if awk -F'\t' 'NR > 1 && ($4 != "ok" || $5 != "present" || $6 != "present" || $7 != "present" || $8 != "present" || $9 != "yes" || $10 != "no") {bad=1} END {exit bad ? 0 : 1}' "$summary_tsv"; then
    echo "BLOCKED: one or more Sparks 1-4 host/fabric prerequisites are missing. Do not start four-node NCCL yet."
    exit_code=1
  else
    echo "PASS: all four Sparks are reachable with both f1 rails, expected RDMA devices, nccl-tests, and no stale MPI/NCCL jobs."
    exit_code=0
  fi
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
exit "$exit_code"
