#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

KEY_DEFAULT="$HOME/.ssh/id_ed25519"
LAUNCHER="${LAUNCHER:-192.0.2.10}"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
MPI_KEY="${MPI_KEY:-/opt/public-user/.ssh/dgx_cluster_mpi_ed25519}"
MPI_HOSTS="${MPI_HOSTS:-192.0.2.10:1,192.0.2.10:1,192.0.2.10:1,192.0.2.10:1}"
GROUP_LABEL="${GROUP_LABEL:-Sparks 5-8}"
SNAPSHOT_HOSTS="${SNAPSHOT_HOSTS:-192.0.2.10 192.0.2.10 192.0.2.10}"
OUT_DIR="${OUT_DIR:-evidence/mpi-fabric-control-plane-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new)

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}" "bash -s" >"$OUT_DIR/hostname-smoke.log" 2>&1 <<REMOTE
set -euo pipefail
mpirun -np 4 \
  -H '${MPI_HOSTS}' \
  --mca plm_rsh_agent 'ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' \
  --mca plm_rsh_no_tree_spawn 1 \
  --mca oob_tcp_if_include enp1s0f1np1 \
  --mca btl_tcp_if_include enp1s0f1np1 \
  hostname
REMOTE

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}" "bash -s" >"$OUT_DIR/process-snapshot.log" 2>&1 <<REMOTE
set -euo pipefail
mpirun -np 4 \
  -H '${MPI_HOSTS}' \
  --mca plm_rsh_agent 'ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' \
  --mca plm_rsh_no_tree_spawn 1 \
  --mca oob_tcp_if_include enp1s0f1np1 \
  --mca btl_tcp_if_include enp1s0f1np1 \
  bash -lc 'sleep 8' &
job=\$!
sleep 2
echo "===== launcher processes ====="
ps -eo pid,etime,cmd | egrep 'mpirun|orted|bash -lc sleep 8' | grep -v egrep || true
for h in ${SNAPSHOT_HOSTS}; do
  echo "===== \$h processes ====="
  ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no public-user@\$h "ps -eo pid,etime,cmd | egrep 'orted|bash -lc sleep 8' | grep -v egrep || true" || true
done
wait \$job
REMOTE

leak_file="$OUT_DIR/leaks.txt"
: >"$leak_file"

if rg -n 'tcp://([^ ]*(192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|DOCUMENTATION_IPV6_PLACEHOLDER))|orte_hnp_uri.*(192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|DOCUMENTATION_IPV6_PLACEHOLDER)' "$OUT_DIR/process-snapshot.log" >"$leak_file"; then
  {
    echo "# ${GROUP_LABEL} MPI Fabric Control Plane Check"
    echo
    echo "FAIL: unexpected non-fabric address appeared in OpenMPI process state."
    echo
    cat "$leak_file"
  } >"$OUT_DIR/SUMMARY.md"
  cat "$OUT_DIR/SUMMARY.md"
  exit 1
fi

{
  echo "# ${GROUP_LABEL} MPI Fabric Control Plane Check"
  echo
  echo "PASS: pinned MPI hostname smoke completed and no unexpected LAN/Tailscale/Docker advertised URI was found in process snapshots."
  echo
  echo "## Hostname Smoke"
  echo
  cat "$OUT_DIR/hostname-smoke.log"
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
