#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

# Host-side only validation for the switchless Sparks 5-8 direct mesh.
# No CRS804 or switch commands belong in this harness.

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi
SUDO="${SUDO-sudo -n}"

MODE="${MODE:-all}" # snapshot, apply, cleanup, underlay, nccl-pairs, nccl-ring, all
OUT_DIR="${OUT_DIR:-evidence/sparks58-switchless-mesh-$(date +%Y%m%d-%H%M%S)}"
IB_SECONDS="${IB_SECONDS:-8}"
IB_SIZE="${IB_SIZE:-8388608}"
IB_QPS="${IB_QPS:-8}"
JUMBO_SIZE="${JUMBO_SIZE:-8972}"
RUN_NCCL="${RUN_NCCL:-0}"
NCCL_TIMEOUT="${NCCL_TIMEOUT:-180}"
MPI_KEY="${MPI_KEY:-/opt/public-user/.ssh/dgx_cluster_mpi_ed25519}"
MPI_MGMT_IF="${MPI_MGMT_IF:-tailscale0}"
NCCL_TESTS_DIR="${NCCL_TESTS_DIR:-\$HOME/nccl-tests/build}"
TWO_NODE_COLL="${TWO_NODE_COLL:-all_gather_perf}"
FOUR_NODE_COLL="${FOUR_NODE_COLL:-all_reduce_perf}"
TWO_NODE_BYTES="${TWO_NODE_BYTES:-16G}"
FOUR_NODE_BYTES="${FOUR_NODE_BYTES:-256M}"
NCCL_ITERS="${NCCL_ITERS:-20}"
NCCL_WARMUP="${NCCL_WARMUP:-5}"
USE_PRLIMIT="${USE_PRLIMIT:-0}"
NCCL_LOGIN_USER="${NCCL_LOGIN_USER:-}"
SPARK05_MPI="${SPARK05_MPI:-192.0.2.10}"
SPARK06_MPI="${SPARK06_MPI:-192.0.2.10}"
SPARK07_MPI="${SPARK07_MPI:-192.0.2.10}"
SPARK08_MPI="${SPARK08_MPI:-192.0.2.10}"

mkdir -p "$OUT_DIR"

NODES=(
  "spark-e.example|spark-e.example|spark-e.example"
  "spark-f.example|spark-f.example|spark-f.example"
  "spark-g.example|spark-h.example|spark-g.example"
  "spark-h.example|spark-g.example|spark-h.example"
)

LINKS=(
  "s5-s6-f0|spark-e.example|spark-f.example|enp1s0f0np0|rocep1s0f0|192.0.2.10|192.0.2.10|enP2p1s0f0np0|roceP2p1s0f0|192.0.2.10|192.0.2.10"
  "s7-s8-f0|spark-g.example|spark-h.example|enp1s0f0np0|rocep1s0f0|192.0.2.10|192.0.2.10|enP2p1s0f0np0|roceP2p1s0f0|192.0.2.10|192.0.2.10"
  "s5-s7-f1|spark-e.example|spark-g.example|enp1s0f1np1|rocep1s0f1|192.0.2.10|192.0.2.10|enP2p1s0f1np1|roceP2p1s0f1|192.0.2.10|192.0.2.10"
  "s6-s8-f1|spark-f.example|spark-h.example|enp1s0f1np1|rocep1s0f1|192.0.2.10|192.0.2.10|enP2p1s0f1np1|roceP2p1s0f1|192.0.2.10|192.0.2.10"
)

node_field() {
  local wanted="$1" field="$2" row
  for row in "${NODES[@]}"; do
    IFS="|" read -r alias host mgmt <<<"$row"
    if [[ "$alias" == "$wanted" ]]; then
      case "$field" in
        host) printf '%s\n' "$host" ;;
        mgmt) printf '%s\n' "$mgmt" ;;
        *) return 2 ;;
      esac
      return 0
    fi
  done
  return 1
}

ssh_run() {
  local alias="$1"
  shift
  local mgmt
  mgmt="$(node_field "$alias" mgmt)"
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${mgmt}" "$@"
}

ssh_launcher() {
  if [[ -n "$NCCL_LOGIN_USER" ]]; then
    local mgmt
    mgmt="$(node_field spark-e.example mgmt)"
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${mgmt}" "su - ${NCCL_LOGIN_USER} -c 'bash -s'"
  else
    ssh_run spark-e.example "bash -s"
  fi
}

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$OUT_DIR/run.log"
}

remote_snapshot_script='
set -u
hostname
date -u +%Y-%m-%dT%H:%M:%SZ
uptime
echo "--- stale jobs ---"
pgrep -af "[m]pirun|[o]rted|[a]ll_reduce_perf|[a]ll_gather_perf|[n]ccl-tests|[i]b_write_bw|[i]perf3" || true
echo "--- ip link ---"
ip -br link show | egrep "enp1s0f[01]|enP2p1s0f[01]|tailscale0" || true
echo "--- ip addr ---"
ip -br addr show | egrep "enp1s0f[01]|enP2p1s0f[01]|tailscale0" || true
echo "--- ibdev2netdev ---"
ibdev2netdev 2>/dev/null || true
echo "--- rdma link ---"
rdma link show 2>/dev/null || true
echo "--- show_gids ---"
for d in /sys/class/infiniband/*; do
  [ -e "$d" ] || continue
  dev=$(basename "$d")
  echo "### $dev"
  show_gids -d "$dev" 2>/dev/null | sed -n "1,18p" || true
done
echo "--- ethtool ---"
for dev in enp1s0f0np0 enp1s0f1np1 enP2p1s0f0np0 enP2p1s0f1np1; do
  echo "### $dev"
  ethtool "$dev" 2>/dev/null | egrep "Speed|Lanes|Duplex|Link detected" || true
done
'

snapshot_hosts() {
  local alias
  for row in "${NODES[@]}"; do
    IFS="|" read -r alias _host _mgmt <<<"$row"
    log "Capturing host snapshot for ${alias}"
    ssh_run "$alias" "bash -s" >"$OUT_DIR/${alias}.snapshot.txt" 2>&1 <<<"$remote_snapshot_script"
  done
}

apply_ips() {
  local row label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1
  for row in "${LINKS[@]}"; do
    IFS="|" read -r label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1 <<<"$row"
    log "Applying ${label}: ${a}/${b} ${dev0} 198.51.100.x and ${dev1} 203.0.113.x"
    ssh_run "$a" "${SUDO} ip link set dev ${dev0} mtu 9000; ${SUDO} ip link set dev ${dev1} mtu 9000; ${SUDO} ip addr replace ${ip_a0}/30 dev ${dev0}; ${SUDO} ip addr replace ${ip_a1}/30 dev ${dev1}; ${SUDO} ip link set dev ${dev0} up; ${SUDO} ip link set dev ${dev1} up"
    ssh_run "$b" "${SUDO} ip link set dev ${dev0} mtu 9000; ${SUDO} ip link set dev ${dev1} mtu 9000; ${SUDO} ip addr replace ${ip_b0}/30 dev ${dev0}; ${SUDO} ip addr replace ${ip_b1}/30 dev ${dev1}; ${SUDO} ip link set dev ${dev0} up; ${SUDO} ip link set dev ${dev1} up"
  done
}

cleanup_ips() {
  local row label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1
  for row in "${LINKS[@]}"; do
    IFS="|" read -r label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1 <<<"$row"
    log "Cleaning ${label} temporary IPs"
    ssh_run "$a" "${SUDO} ip addr del ${ip_a0}/30 dev ${dev0} 2>/dev/null || true; ${SUDO} ip addr del ${ip_a1}/30 dev ${dev1} 2>/dev/null || true" || true
    ssh_run "$b" "${SUDO} ip addr del ${ip_b0}/30 dev ${dev0} 2>/dev/null || true; ${SUDO} ip addr del ${ip_b1}/30 dev ${dev1} 2>/dev/null || true" || true
  done
}

run_ping() {
  local label="$1" src="$2" dev="$3" dst_ip="$4" out="$5"
  log "Jumbo ping ${label}: ${src} ${dev} -> ${dst_ip}"
  ssh_run "$src" "ping -I ${dev} -c 3 -s ${JUMBO_SIZE} -M do ${dst_ip}" >"$out" 2>&1
}

kill_pair_tools() {
  local a="$1" b="$2"
  ssh_run "$a" "${SUDO} pkill ib_write_bw 2>/dev/null || true" || true
  ssh_run "$b" "${SUDO} pkill ib_write_bw 2>/dev/null || true" || true
  sleep 1
}

parse_ib_avg() {
  awk '/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+/ {avg=$4} END {print avg+0}' "$1"
}

run_ib_one_direction() {
  local label="$1" src="$2" dst="$3" rdma="$4" dst_ip="$5" port="$6"
  local prefix="$OUT_DIR/${label}.${src}-to-${dst}"
  log "ib_write_bw ${label}: ${src} ${rdma} -> ${dst_ip}"
  kill_pair_tools "$src" "$dst"
  ssh_run "$dst" "${SUDO} bash -lc 'ulimit -l unlimited; timeout 35 ib_write_bw -R -d ${rdma} -F --report_gbits -q ${IB_QPS} -s ${IB_SIZE} -D ${IB_SECONDS} -p ${port}'" >"${prefix}.server.log" 2>&1 &
  local server_pid=$!
  sleep 3
  set +e
  ssh_run "$src" "${SUDO} bash -lc 'ulimit -l unlimited; ib_write_bw -R -d ${rdma} -F --report_gbits -q ${IB_QPS} -s ${IB_SIZE} -D ${IB_SECONDS} -p ${port} ${dst_ip}'" >"${prefix}.client.log" 2>&1
  local client_rc=$?
  wait "$server_pid" || true
  set -e
  local avg
  avg="$(parse_ib_avg "${prefix}.client.log")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$src" "$dst" "$rdma" "$avg" "$client_rc" >>"$OUT_DIR/ib-write-bw.tsv"
  if [[ "$client_rc" != "0" ]]; then
    log "ib_write_bw ${label} failed with rc=${client_rc}; see ${prefix}.client.log"
    return "$client_rc"
  fi
  log "ib_write_bw ${label} avg ${avg} Gbits/sec"
}

run_underlay() {
  printf 'link\tsrc\tdst\trdma\tavg_gbits\trc\n' >"$OUT_DIR/ib-write-bw.tsv"
  local row label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1 port
  port=18515
  for row in "${LINKS[@]}"; do
    IFS="|" read -r label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1 <<<"$row"
    run_ping "${label}.rail0.forward" "$a" "$dev0" "$ip_b0" "$OUT_DIR/${label}.rail0.forward.ping.log"
    run_ping "${label}.rail0.reverse" "$b" "$dev0" "$ip_a0" "$OUT_DIR/${label}.rail0.reverse.ping.log"
    run_ping "${label}.rail1.forward" "$a" "$dev1" "$ip_b1" "$OUT_DIR/${label}.rail1.forward.ping.log"
    run_ping "${label}.rail1.reverse" "$b" "$dev1" "$ip_a1" "$OUT_DIR/${label}.rail1.reverse.ping.log"
    run_ib_one_direction "${label}.rail0.forward" "$a" "$b" "$rdma0" "$ip_b0" "$port"; port=$((port + 1))
    run_ib_one_direction "${label}.rail0.reverse" "$b" "$a" "$rdma0" "$ip_a0" "$port"; port=$((port + 1))
    run_ib_one_direction "${label}.rail1.forward" "$a" "$b" "$rdma1" "$ip_b1" "$port"; port=$((port + 1))
    run_ib_one_direction "${label}.rail1.reverse" "$b" "$a" "$rdma1" "$ip_a1" "$port"; port=$((port + 1))
  done
}

remote_nccl_env() {
  local netdevs="$1" rdmas="$2"
  cat <<EOF
unset NCCL_DEBUG_SUBSYS NCCL_TOPO_DUMP_FILE NCCL_GRAPH_DUMP_FILE NCCL_PROTO NCCL_MIN_NCHANNELS NCCL_MAX_NCHANNELS NCCL_IB_QPS_PER_CONNECTION NCCL_IB_SPLIT_DATA_ON_QPS NCCL_CROSS_NIC NCCL_PXN_DISABLE NCCL_NETDEVS_POLICY NCCL_NET_MERGE_POLICY NCCL_NET_SHARED_COMMS NCCL_NET_SHARED_BUFFERS NCCL_RUNTIME_CONNECT
EOF
  local name value
  for name in REMOTE_NCCL_HOME; do
    value="${!name:-}"
    if [[ -n "$value" ]]; then
      printf 'export %s=%q\n' "$name" "$value"
    fi
  done
  cat <<EOF
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\${LD_LIBRARY_PATH:-}
if [[ -n "\${REMOTE_NCCL_HOME:-}" ]]; then
  export NCCL_HOME="\${REMOTE_NCCL_HOME}"
  export LD_LIBRARY_PATH="\${REMOTE_NCCL_HOME}/lib:\${LD_LIBRARY_PATH}"
fi
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,NET,GRAPH
export NCCL_IB_DISABLE=0
export NCCL_IB_HCA=${rdmas}
export UCX_NET_DEVICES=${netdevs}
export NCCL_SOCKET_IFNAME=${MPI_MGMT_IF}
export NCCL_NET_GDR_LEVEL=2
export NCCL_ALGO=Ring
export NCCL_IB_MERGE_NICS=0
export NCCL_IB_SUBNET_AWARE_ROUTING=1
EOF
  for name in NCCL_CROSS_NIC NCCL_PXN_DISABLE NCCL_NETDEVS_POLICY NCCL_NET_MERGE_POLICY NCCL_NET_SHARED_COMMS NCCL_NET_SHARED_BUFFERS NCCL_RUNTIME_CONNECT NCCL_MIN_NCHANNELS NCCL_MAX_NCHANNELS NCCL_IB_QPS_PER_CONNECTION NCCL_IB_SPLIT_DATA_ON_QPS NCCL_PROTO; do
    value="${!name:-}"
    if [[ -n "$value" ]]; then
      printf 'export %s=%q\n' "$name" "$value"
    fi
  done
}

run_nccl_from_spark5() {
  local label="$1" hosts="$2" np="$3" netdevs="$4" rdmas="$5" collective="$6" bytes="$7"
  local log_file="$OUT_DIR/${label}.nccl.log"
  local env_block run_prefix
  env_block="$(remote_nccl_env "$netdevs" "$rdmas")"
  run_prefix=""
  if [[ "$USE_PRLIMIT" == "1" ]]; then
    run_prefix="prlimit --memlock=unlimited:unlimited"
  fi
  log "NCCL ${label}: hosts=${hosts} netdevs=${netdevs} rdmas=${rdmas}"
  set +e
  ssh_launcher >"$log_file" 2>&1 <<REMOTE
set -euo pipefail
${env_block}
env | grep -E '^(NCCL_|UCX_)' | sort
timeout ${NCCL_TIMEOUT} ${run_prefix} mpirun -np '${np}' \
  -H '${hosts}' \
  --mca plm_rsh_agent 'ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' \
  --mca plm_rsh_no_tree_spawn 1 \
  --mca orte_keep_fqdn_hostnames 1 \
  --mca oob_tcp_if_include '${MPI_MGMT_IF}' \
  --mca btl_tcp_if_include '${MPI_MGMT_IF}' \
  -x LD_LIBRARY_PATH -x NCCL_DEBUG -x NCCL_DEBUG_SUBSYS -x NCCL_IB_DISABLE -x NCCL_IB_HCA -x UCX_NET_DEVICES -x NCCL_SOCKET_IFNAME -x NCCL_NET_GDR_LEVEL -x NCCL_ALGO -x NCCL_IB_MERGE_NICS -x NCCL_IB_SUBNET_AWARE_ROUTING -x NCCL_CROSS_NIC -x NCCL_PXN_DISABLE -x NCCL_NETDEVS_POLICY -x NCCL_NET_MERGE_POLICY -x NCCL_NET_SHARED_COMMS -x NCCL_NET_SHARED_BUFFERS -x NCCL_RUNTIME_CONNECT -x NCCL_MIN_NCHANNELS -x NCCL_MAX_NCHANNELS -x NCCL_IB_QPS_PER_CONNECTION -x NCCL_IB_SPLIT_DATA_ON_QPS -x NCCL_PROTO \
  "${NCCL_TESTS_DIR}/${collective}" -b '${bytes}' -e '${bytes}' -f 2 -g 1 -n '${NCCL_ITERS}' -w '${NCCL_WARMUP}' -c 1
REMOTE
  local rc=$?
  set -e
  printf '%s\t%s\n' "$label" "$rc" >>"$OUT_DIR/nccl-runs.tsv"
  if grep -q 'NET/Socket' "$log_file"; then
    log "NCCL ${label} log contains NET/Socket; stop before treating as direct RoCE proof"
    return 40
  fi
  if ! grep -q 'NET/IB' "$log_file"; then
    log "NCCL ${label} log does not contain NET/IB; stop before treating as direct RoCE proof"
    return 41
  fi
  return "$rc"
}

run_nccl_pairs() {
  printf 'label\trc\n' >"$OUT_DIR/nccl-runs.tsv"
  run_nccl_from_spark5 "s5-s6-f0" "${SPARK05_MPI}:1,${SPARK06_MPI}:1" 2 "enp1s0f0np0,enP2p1s0f0np0" "rocep1s0f0,roceP2p1s0f0" "$TWO_NODE_COLL" "$TWO_NODE_BYTES"
  run_nccl_from_spark5 "s7-s8-f0" "${SPARK07_MPI}:1,${SPARK08_MPI}:1" 2 "enp1s0f0np0,enP2p1s0f0np0" "rocep1s0f0,roceP2p1s0f0" "$TWO_NODE_COLL" "$TWO_NODE_BYTES"
  run_nccl_from_spark5 "s5-s7-f1" "${SPARK05_MPI}:1,${SPARK07_MPI}:1" 2 "enp1s0f1np1,enP2p1s0f1np1" "rocep1s0f1,roceP2p1s0f1" "$TWO_NODE_COLL" "$TWO_NODE_BYTES"
  run_nccl_from_spark5 "s6-s8-f1" "${SPARK06_MPI}:1,${SPARK08_MPI}:1" 2 "enp1s0f1np1,enP2p1s0f1np1" "rocep1s0f1,roceP2p1s0f1" "$TWO_NODE_COLL" "$TWO_NODE_BYTES"
}

run_nccl_ring() {
  run_nccl_from_spark5 "s5-s6-s8-s7-ring" "${SPARK05_MPI}:1,${SPARK06_MPI}:1,${SPARK08_MPI}:1,${SPARK07_MPI}:1" 4 "enp1s0f0np0,enP2p1s0f0np0,enp1s0f1np1,enP2p1s0f1np1" "rocep1s0f0,roceP2p1s0f0,rocep1s0f1,roceP2p1s0f1" "$FOUR_NODE_COLL" "$FOUR_NODE_BYTES"
}

write_summary() {
  {
    echo "# Sparks 5-8 Switchless Direct Mesh Run"
    echo
    echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Mode: ${MODE}"
    echo "- Output directory: ${OUT_DIR}"
    echo "- Temporary IPs: 198.51.100.* on enp... halves, 203.0.113.* on enP2p... halves"
    echo "- MPI/OOB management interface for NCCL: ${MPI_MGMT_IF}"
    echo
    if [[ -f "$OUT_DIR/ib-write-bw.tsv" ]]; then
      echo "## ib_write_bw"
      echo
      cat "$OUT_DIR/ib-write-bw.tsv"
      echo
    fi
    if [[ -f "$OUT_DIR/nccl-runs.tsv" ]]; then
      echo "## NCCL runs"
      echo
      cat "$OUT_DIR/nccl-runs.tsv"
      echo
    fi
  } >"$OUT_DIR/SUMMARY.md"
  cat "$OUT_DIR/SUMMARY.md"
}

log "Output directory: ${OUT_DIR}"

case "$MODE" in
  snapshot)
    snapshot_hosts
    ;;
  apply)
    snapshot_hosts
    apply_ips
    snapshot_hosts
    ;;
  cleanup)
    cleanup_ips
    snapshot_hosts
    ;;
  underlay)
    snapshot_hosts
    apply_ips
    snapshot_hosts
    run_underlay
    snapshot_hosts
    ;;
  nccl-pairs)
    [[ "$RUN_NCCL" == "1" ]] || { echo "Set RUN_NCCL=1 for NCCL stages" >&2; exit 22; }
    run_nccl_pairs
    ;;
  nccl-ring)
    [[ "$RUN_NCCL" == "1" ]] || { echo "Set RUN_NCCL=1 for NCCL stages" >&2; exit 22; }
    run_nccl_ring
    ;;
  all)
    snapshot_hosts
    apply_ips
    snapshot_hosts
    run_underlay
    snapshot_hosts
    if [[ "$RUN_NCCL" == "1" ]]; then
      run_nccl_pairs
      run_nccl_ring
    else
      log "RUN_NCCL is not 1; underlay validation complete and NCCL stages skipped"
    fi
    ;;
  *)
    echo "Unknown MODE=${MODE}" >&2
    exit 2
    ;;
esac

write_summary
