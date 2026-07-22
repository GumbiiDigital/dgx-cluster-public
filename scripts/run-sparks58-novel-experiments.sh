#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

# Novel software-only experiments for the switchless Sparks 5-8 direct mesh.
# Host-side only: no CRS804 or switch commands belong here.

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-root}"
SSH_KEY="${SSH_KEY:-}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

MODE="${MODE:-all}" # readiness, concurrent-ib, nccl-phases, hca-probe, per-rank-hca, topo-dump, topo-file, classify-graph, custom-ring-tcp, ucx-ring, all
HCA_FILTER="${HCA_FILTER:-}"
OUT_DIR="${OUT_DIR:-evidence/sparks58-novel-$(date +%Y%m%d-%H%M%S)}"
NCCL_LOGIN_USER="${NCCL_LOGIN_USER:-public-user}"
MPI_KEY="${MPI_KEY:-/opt/public-user/.ssh/dgx_cluster_mpi_ed25519}"
MPI_MGMT_IF="${MPI_MGMT_IF:-tailscale0}"
NCCL_TESTS_DIR="${NCCL_TESTS_DIR:-\$HOME/nccl-tests/build}"
NCCL_TIMEOUT="${NCCL_TIMEOUT:-180}"
NCCL_ITERS="${NCCL_ITERS:-5}"
NCCL_WARMUP="${NCCL_WARMUP:-2}"
TWO_NODE_BYTES="${TWO_NODE_BYTES:-1M}"
FOUR_NODE_BYTES="${FOUR_NODE_BYTES:-1M}"
CUSTOM_RING_ELEMENTS="${CUSTOM_RING_ELEMENTS:-65536}"
CUSTOM_RING_PORT="${CUSTOM_RING_PORT:-19250}"
UCX_SECONDS="${UCX_SECONDS:-10}"
UCX_PORT_BASE="${UCX_PORT_BASE:-19300}"
IB_SECONDS="${IB_SECONDS:-12}"
IB_SIZE="${IB_SIZE:-8388608}"
IB_QPS="${IB_QPS:-8}"
JUMBO_SIZE="${JUMBO_SIZE:-8972}"
REMOTE_NCCL_HOME="${REMOTE_NCCL_HOME:-/opt/public-cluster/src/nccl-v2.30u1/build}"

SPARK05_MPI="${SPARK05_MPI:-192.0.2.10}"
SPARK06_MPI="${SPARK06_MPI:-192.0.2.10}"
SPARK07_MPI="${SPARK07_MPI:-192.0.2.10}"
SPARK08_MPI="${SPARK08_MPI:-192.0.2.10}"

mkdir -p "$OUT_DIR"

NODES=(
  "spark-e.example|spark-e.example|spark-e.example|${SPARK05_MPI}"
  "spark-f.example|spark-f.example|spark-f.example|${SPARK06_MPI}"
  "spark-g.example|spark-h.example|spark-g.example|${SPARK07_MPI}"
  "spark-h.example|spark-g.example|spark-h.example|${SPARK08_MPI}"
)

LINKS=(
  "s5-s6-f0|spark-e.example|spark-f.example|enp1s0f0np0|rocep1s0f0|192.0.2.10|192.0.2.10|enP2p1s0f0np0|roceP2p1s0f0|192.0.2.10|192.0.2.10"
  "s6-s8-f1|spark-f.example|spark-h.example|enp1s0f1np1|rocep1s0f1|192.0.2.10|192.0.2.10|enP2p1s0f1np1|roceP2p1s0f1|192.0.2.10|192.0.2.10"
  "s8-s7-f0|spark-h.example|spark-g.example|enp1s0f0np0|rocep1s0f0|192.0.2.10|192.0.2.10|enP2p1s0f0np0|roceP2p1s0f0|192.0.2.10|192.0.2.10"
  "s7-s5-f1|spark-g.example|spark-e.example|enp1s0f1np1|rocep1s0f1|192.0.2.10|192.0.2.10|enP2p1s0f1np1|roceP2p1s0f1|192.0.2.10|192.0.2.10"
)

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$OUT_DIR/run.log"
}

node_field() {
  local wanted="$1" field="$2" row
  for row in "${NODES[@]}"; do
    IFS="|" read -r alias host mgmt mpi <<<"$row"
    if [[ "$alias" == "$wanted" ]]; then
      case "$field" in
        host) printf '%s\n' "$host" ;;
        mgmt) printf '%s\n' "$mgmt" ;;
        mpi) printf '%s\n' "$mpi" ;;
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
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@$(node_field "$alias" mgmt)" "$@"
}

scp_to() {
  local alias="$1" src="$2" dst="$3"
  scp "${SSH_OPTS[@]}" "$src" "${SSH_USER}@$(node_field "$alias" mgmt):$dst"
}

ssh_launcher() {
  if [[ -n "$NCCL_LOGIN_USER" ]]; then
    ssh_run spark-e.example "su - ${NCCL_LOGIN_USER} -c 'bash -s'"
  else
    ssh_run spark-e.example "bash -s"
  fi
}

mpi_ip() {
  node_field "$1" mpi
}

stale_scan() {
  local alias row
  : >"$OUT_DIR/stale-jobs.txt"
  for row in "${NODES[@]}"; do
    IFS="|" read -r alias _host _mgmt _mpi <<<"$row"
    {
      echo "===== ${alias} ====="
      ssh_run "$alias" "ps -eo pid,user,comm,args | grep -E 'all_reduce_perf|all_gather_perf|mpirun|orted|ib_write_bw|iperf3' | grep -v grep || true"
    } >>"$OUT_DIR/stale-jobs.txt" 2>&1
  done
  if grep -Eq 'all_reduce_perf|all_gather_perf|mpirun|orted|ib_write_bw|iperf3' "$OUT_DIR/stale-jobs.txt"; then
    log "Stale job scan found active benchmark processes; see $OUT_DIR/stale-jobs.txt"
    return 12
  fi
}

readiness() {
  log "Readiness gate: reachability, stale jobs, link/IP state, jumbo ping"
  stale_scan
  local row label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1
  for row in "${NODES[@]}"; do
    IFS="|" read -r alias _host _mgmt _mpi <<<"$row"
    ssh_run "$alias" "hostname; ip -br addr show | grep -E 'enp1s0f0np0|enP2p1s0f0np0|enp1s0f1np1|enP2p1s0f1np1|tailscale0'; rdma link show | grep -E 'rocep1s0f0|roceP2p1s0f0|rocep1s0f1|roceP2p1s0f1'" >"$OUT_DIR/${alias}.readiness.txt" 2>&1
  done
  for row in "${LINKS[@]}"; do
    IFS="|" read -r label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1 <<<"$row"
    ssh_run "$a" "ping -I ${dev0} -c 2 -s ${JUMBO_SIZE} -M do ${ip_b0}" >"$OUT_DIR/${label}.rail0.ping.log" 2>&1
    ssh_run "$a" "ping -I ${dev1} -c 2 -s ${JUMBO_SIZE} -M do ${ip_b1}" >"$OUT_DIR/${label}.rail1.ping.log" 2>&1
  done
  log "Readiness gate passed"
}

parse_ib_avg() {
  awk '/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+/ {avg=$4} END {print avg+0}' "$1"
}

ib_server_cmd() {
  local rdma="$1" port="$2"
  printf "bash -lc 'ulimit -l unlimited; timeout %s ib_write_bw -R -d %s -F --report_gbits -q %s -s %s -D %s -p %s'" \
    "$((IB_SECONDS + 25))" "$rdma" "$IB_QPS" "$IB_SIZE" "$IB_SECONDS" "$port"
}

ib_client_cmd() {
  local rdma="$1" peer_ip="$2" port="$3"
  printf "bash -lc 'ulimit -l unlimited; ib_write_bw -R -d %s -F --report_gbits -q %s -s %s -D %s -p %s %s'" \
    "$rdma" "$IB_QPS" "$IB_SIZE" "$IB_SECONDS" "$port" "$peer_ip"
}

concurrent_ib() {
  log "Concurrent ib_write_bw ring saturation"
  if [[ ! -s "$OUT_DIR/concurrent-ib.tsv" ]]; then
    printf 'label\trail\tsrc\tdst\trdma\tavg_gbits\trc\n' >"$OUT_DIR/concurrent-ib.tsv"
  fi
  local rail="$1" row label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1 port pids=()
  local alias _host _mgmt _mpi
  for row in "${NODES[@]}"; do
    IFS="|" read -r alias _host _mgmt _mpi <<<"$row"
    ssh_run "$alias" "pkill ib_write_bw 2>/dev/null || true" || true
  done
  port=19100
  for row in "${LINKS[@]}"; do
    IFS="|" read -r label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1 <<<"$row"
    if [[ "$rail" == "rail0" ]]; then
      rdma="$rdma0"; peer="$ip_b0"
    else
      rdma="$rdma1"; peer="$ip_b1"
    fi
    ssh_run "$b" "$(ib_server_cmd "$rdma" "$port")" >"$OUT_DIR/${label}.${rail}.server.log" 2>&1 &
    pids+=("$!")
    port=$((port + 1))
  done
  sleep 3
  port=19100
  local client_pids=()
  for row in "${LINKS[@]}"; do
    IFS="|" read -r label a b dev0 rdma0 ip_a0 ip_b0 dev1 rdma1 ip_a1 ip_b1 <<<"$row"
    if [[ "$rail" == "rail0" ]]; then
      rdma="$rdma0"; peer="$ip_b0"
    else
      rdma="$rdma1"; peer="$ip_b1"
    fi
    (
      set +e
      ssh_run "$a" "$(ib_client_cmd "$rdma" "$peer" "$port")" >"$OUT_DIR/${label}.${rail}.client.log" 2>&1
      rc=$?
      avg="$(parse_ib_avg "$OUT_DIR/${label}.${rail}.client.log")"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$rail" "$a" "$b" "$rdma" "$avg" "$rc" >>"$OUT_DIR/concurrent-ib.tsv"
      exit "$rc"
    ) &
    client_pids+=("$!")
    port=$((port + 1))
  done
  local rc=0 pid
  for pid in "${client_pids[@]}"; do
    wait "$pid" || rc=1
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done
  return "$rc"
}

remote_nccl_env() {
  local rdmas="$1" netdevs="$2"
  cat <<EOF
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\${LD_LIBRARY_PATH:-}
if [[ -n "${REMOTE_NCCL_HOME}" ]]; then
  export LD_LIBRARY_PATH="${REMOTE_NCCL_HOME}/lib:\${LD_LIBRARY_PATH}"
  export NCCL_HOME="${REMOTE_NCCL_HOME}"
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
export NCCL_MIN_NCHANNELS=1
export NCCL_MAX_NCHANNELS=1
EOF
}

run_pair_nccl() {
  local label="$1" hosts="$2" rdmas="$3" netdevs="$4" log_file="$5"
  ssh_launcher >"$log_file" 2>&1 <<REMOTE
set -euo pipefail
$(remote_nccl_env "$rdmas" "$netdevs")
env | grep -E '^(NCCL_|UCX_)' | sort
timeout ${NCCL_TIMEOUT} mpirun -np 2 \
  -H '${hosts}' \
  --mca plm_rsh_agent 'ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' \
  --mca plm_rsh_no_tree_spawn 1 \
  --mca orte_keep_fqdn_hostnames 1 \
  --mca oob_tcp_if_include '${MPI_MGMT_IF}' \
  --mca btl_tcp_if_include '${MPI_MGMT_IF}' \
  -x LD_LIBRARY_PATH -x NCCL_HOME -x NCCL_DEBUG -x NCCL_DEBUG_SUBSYS -x NCCL_IB_DISABLE -x NCCL_IB_HCA -x UCX_NET_DEVICES -x NCCL_SOCKET_IFNAME -x NCCL_NET_GDR_LEVEL -x NCCL_ALGO -x NCCL_IB_MERGE_NICS -x NCCL_IB_SUBNET_AWARE_ROUTING -x NCCL_MIN_NCHANNELS -x NCCL_MAX_NCHANNELS \
  "${NCCL_TESTS_DIR}/all_gather_perf" -b '${TWO_NODE_BYTES}' -e '${TWO_NODE_BYTES}' -f 2 -g 1 -n '${NCCL_ITERS}' -w '${NCCL_WARMUP}' -c 1
REMOTE
}

nccl_phases() {
  log "Concurrent disjoint two-node NCCL phases"
  printf 'phase\tlabel\trc\tnet_ib\tsocket\twrong_zero\n' >"$OUT_DIR/nccl-phases.tsv"
  local phase label hosts rdmas netdevs log_file rc
  for phase in A B; do
    local specs=()
    if [[ "$phase" == "A" ]]; then
      specs+=("s5-s6-f0|$(mpi_ip spark-e.example):1,$(mpi_ip spark-f.example):1|rocep1s0f0,roceP2p1s0f0|enp1s0f0np0,enP2p1s0f0np0")
      specs+=("s8-s7-f0|$(mpi_ip spark-h.example):1,$(mpi_ip spark-g.example):1|rocep1s0f0,roceP2p1s0f0|enp1s0f0np0,enP2p1s0f0np0")
    else
      specs+=("s6-s8-f1|$(mpi_ip spark-f.example):1,$(mpi_ip spark-h.example):1|rocep1s0f1,roceP2p1s0f1|enp1s0f1np1,enP2p1s0f1np1")
      specs+=("s7-s5-f1|$(mpi_ip spark-g.example):1,$(mpi_ip spark-e.example):1|rocep1s0f1,roceP2p1s0f1|enp1s0f1np1,enP2p1s0f1np1")
    fi
    local pids=()
    for spec in "${specs[@]}"; do
      IFS="|" read -r label hosts rdmas netdevs <<<"$spec"
      log_file="$OUT_DIR/nccl-phase-${phase}.${label}.log"
      (set +e; run_pair_nccl "$label" "$hosts" "$rdmas" "$netdevs" "$log_file"; echo "$?" >"$log_file.rc") &
      pids+=("$!")
    done
    for pid in "${pids[@]}"; do wait "$pid" || true; done
    for spec in "${specs[@]}"; do
      IFS="|" read -r label hosts rdmas netdevs <<<"$spec"
      log_file="$OUT_DIR/nccl-phase-${phase}.${label}.log"
      rc="$(cat "$log_file.rc" 2>/dev/null || echo 99)"
      net_ib=0; socket=0; wrong_zero=0
      grep -q 'NET/IB' "$log_file" && net_ib=1
      grep -q 'NET/Socket' "$log_file" && socket=1
      grep -q '# Out of bounds values : 0 OK' "$log_file" && wrong_zero=1
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$phase" "$label" "$rc" "$net_ib" "$socket" "$wrong_zero" >>"$OUT_DIR/nccl-phases.tsv"
    done
  done
}

run_four_rank_probe() {
  local label="$1" rdmas="$2" netdevs="$3" extra_env="$4"
  local log_file="$OUT_DIR/hca-probe.${label}.log"
  ssh_launcher >"$log_file" 2>&1 <<REMOTE
set -euo pipefail
$(remote_nccl_env "$rdmas" "$netdevs")
${extra_env}
env | grep -E '^(NCCL_|UCX_)' | sort
set +e
timeout ${NCCL_TIMEOUT} mpirun -np 4 \
  -H '$(mpi_ip spark-e.example):1,$(mpi_ip spark-f.example):1,$(mpi_ip spark-h.example):1,$(mpi_ip spark-g.example):1' \
  --mca plm_rsh_agent 'ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' \
  --mca plm_rsh_no_tree_spawn 1 \
  --mca orte_keep_fqdn_hostnames 1 \
  --mca oob_tcp_if_include '${MPI_MGMT_IF}' \
  --mca btl_tcp_if_include '${MPI_MGMT_IF}' \
  -x LD_LIBRARY_PATH -x NCCL_HOME -x NCCL_DEBUG -x NCCL_DEBUG_SUBSYS -x NCCL_IB_DISABLE -x NCCL_IB_HCA -x UCX_NET_DEVICES -x NCCL_SOCKET_IFNAME -x NCCL_NET_GDR_LEVEL -x NCCL_ALGO -x NCCL_IB_MERGE_NICS -x NCCL_IB_SUBNET_AWARE_ROUTING -x NCCL_MIN_NCHANNELS -x NCCL_MAX_NCHANNELS -x NCCL_CROSS_NIC -x NCCL_NETDEVS_POLICY \
  "${NCCL_TESTS_DIR}/all_reduce_perf" -b '${FOUR_NODE_BYTES}' -e '${FOUR_NODE_BYTES}' -f 2 -g 1 -n '${NCCL_ITERS}' -w '${NCCL_WARMUP}' -c 1
echo "Exit code: \$?"
REMOTE
}

run_four_rank_app_context_probe() {
  local label="$1"
  local log_file="$OUT_DIR/per-rank-hca.${label}.log"
  ssh_launcher >"$log_file" 2>&1 <<REMOTE
set -euo pipefail
$(remote_nccl_env "rocep1s0f0,rocep1s0f1,roceP2p1s0f0,roceP2p1s0f1" "enp1s0f0np0,enp1s0f1np1,enP2p1s0f0np0,enP2p1s0f1np1")
export NCCL_CROSS_NIC=1
env | grep -E '^(NCCL_|UCX_)' | sort
set +e
timeout ${NCCL_TIMEOUT} mpirun \
  --mca plm_rsh_agent 'ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' \
  --mca plm_rsh_no_tree_spawn 1 \
  --mca orte_keep_fqdn_hostnames 1 \
  --mca oob_tcp_if_include '${MPI_MGMT_IF}' \
  --mca btl_tcp_if_include '${MPI_MGMT_IF}' \
  -np 1 -H '$(mpi_ip spark-e.example):1' -x LD_LIBRARY_PATH -x NCCL_HOME -x NCCL_DEBUG -x NCCL_DEBUG_SUBSYS -x NCCL_IB_DISABLE -x NCCL_SOCKET_IFNAME -x NCCL_NET_GDR_LEVEL -x NCCL_ALGO -x NCCL_IB_MERGE_NICS -x NCCL_IB_SUBNET_AWARE_ROUTING -x NCCL_MIN_NCHANNELS -x NCCL_MAX_NCHANNELS -x NCCL_CROSS_NIC -x NCCL_IB_HCA='rocep1s0f0,rocep1s0f1,roceP2p1s0f0,roceP2p1s0f1' "${NCCL_TESTS_DIR}/all_reduce_perf" -b '${FOUR_NODE_BYTES}' -e '${FOUR_NODE_BYTES}' -f 2 -g 1 -n '${NCCL_ITERS}' -w '${NCCL_WARMUP}' -c 1 \
  : -np 1 -H '$(mpi_ip spark-f.example):1' -x LD_LIBRARY_PATH -x NCCL_HOME -x NCCL_DEBUG -x NCCL_DEBUG_SUBSYS -x NCCL_IB_DISABLE -x NCCL_SOCKET_IFNAME -x NCCL_NET_GDR_LEVEL -x NCCL_ALGO -x NCCL_IB_MERGE_NICS -x NCCL_IB_SUBNET_AWARE_ROUTING -x NCCL_MIN_NCHANNELS -x NCCL_MAX_NCHANNELS -x NCCL_CROSS_NIC -x NCCL_IB_HCA='rocep1s0f0,rocep1s0f1,roceP2p1s0f0,roceP2p1s0f1' "${NCCL_TESTS_DIR}/all_reduce_perf" -b '${FOUR_NODE_BYTES}' -e '${FOUR_NODE_BYTES}' -f 2 -g 1 -n '${NCCL_ITERS}' -w '${NCCL_WARMUP}' -c 1 \
  : -np 1 -H '$(mpi_ip spark-h.example):1' -x LD_LIBRARY_PATH -x NCCL_HOME -x NCCL_DEBUG -x NCCL_DEBUG_SUBSYS -x NCCL_IB_DISABLE -x NCCL_SOCKET_IFNAME -x NCCL_NET_GDR_LEVEL -x NCCL_ALGO -x NCCL_IB_MERGE_NICS -x NCCL_IB_SUBNET_AWARE_ROUTING -x NCCL_MIN_NCHANNELS -x NCCL_MAX_NCHANNELS -x NCCL_CROSS_NIC -x NCCL_IB_HCA='rocep1s0f1,rocep1s0f0,roceP2p1s0f1,roceP2p1s0f0' "${NCCL_TESTS_DIR}/all_reduce_perf" -b '${FOUR_NODE_BYTES}' -e '${FOUR_NODE_BYTES}' -f 2 -g 1 -n '${NCCL_ITERS}' -w '${NCCL_WARMUP}' -c 1 \
  : -np 1 -H '$(mpi_ip spark-g.example):1' -x LD_LIBRARY_PATH -x NCCL_HOME -x NCCL_DEBUG -x NCCL_DEBUG_SUBSYS -x NCCL_IB_DISABLE -x NCCL_SOCKET_IFNAME -x NCCL_NET_GDR_LEVEL -x NCCL_ALGO -x NCCL_IB_MERGE_NICS -x NCCL_IB_SUBNET_AWARE_ROUTING -x NCCL_MIN_NCHANNELS -x NCCL_MAX_NCHANNELS -x NCCL_CROSS_NIC -x NCCL_IB_HCA='rocep1s0f0,rocep1s0f1,roceP2p1s0f0,roceP2p1s0f1' "${NCCL_TESTS_DIR}/all_reduce_perf" -b '${FOUR_NODE_BYTES}' -e '${FOUR_NODE_BYTES}' -f 2 -g 1 -n '${NCCL_ITERS}' -w '${NCCL_WARMUP}' -c 1
echo "Exit code: \$?"
REMOTE
}

per_rank_hca_probe() {
  log "Per-rank HCA app-context probe"
  local label="appctx-ring-neighbor-biased" log_file rc non_neighbor version launcher_rc=0
  run_four_rank_app_context_probe "$label" || launcher_rc=$?
  log_file="$OUT_DIR/per-rank-hca.${label}.log"
  echo "Launcher rc: ${launcher_rc}" >>"$log_file"
  printf 'label\trc\tversion23007\tnon_neighbor_gid\n' >"$OUT_DIR/per-rank-hca.tsv"
  rc="$(awk '/Exit code:/ {x=$3} /Launcher rc:/ && x == "" {x=$3} END {if (x == "") x=99; print x+0}' "$log_file")"
  version=0; non_neighbor=0
  grep -q 'nccl-library=23007\|NCCL version 2.30.7' "$log_file" && version=1
  grep -q '192.0.2.10, remote GID ::ffff:192.0.2.10\|192.0.2.10, remote GID ::ffff:192.0.2.10' "$log_file" && non_neighbor=1
  printf '%s\t%s\t%s\t%s\n' "$label" "$rc" "$version" "$non_neighbor" >>"$OUT_DIR/per-rank-hca.tsv"
}

hca_probe() {
  log "Rank-to-NIC permutation probes"
  if [[ ! -s "$OUT_DIR/hca-probe.tsv" ]]; then
    printf 'label\trc\tversion23007\tnon_neighbor_gid\n' >"$OUT_DIR/hca-probe.tsv"
  fi
  local label rc non_neighbor version launcher_rc rdmas netdevs extra_env spec
  for spec in \
    "f0-first|rocep1s0f0,roceP2p1s0f0,rocep1s0f1,roceP2p1s0f1|enp1s0f0np0,enP2p1s0f0np0,enp1s0f1np1,enP2p1s0f1np1|export NCCL_CROSS_NIC=1" \
    "f1-first|rocep1s0f1,roceP2p1s0f1,rocep1s0f0,roceP2p1s0f0|enp1s0f1np1,enP2p1s0f1np1,enp1s0f0np0,enP2p1s0f0np0|export NCCL_CROSS_NIC=1" \
    "all-policy|rocep1s0f0,roceP2p1s0f0,rocep1s0f1,roceP2p1s0f1|enp1s0f0np0,enP2p1s0f0np0,enp1s0f1np1,enP2p1s0f1np1|export NCCL_CROSS_NIC=1; export NCCL_NETDEVS_POLICY=ALL" \
    "crossnic0|rocep1s0f0,roceP2p1s0f0,rocep1s0f1,roceP2p1s0f1|enp1s0f0np0,enP2p1s0f0np0,enp1s0f1np1,enP2p1s0f1np1|export NCCL_CROSS_NIC=0"; do
    IFS="|" read -r label rdmas netdevs extra_env <<<"$spec"
    if [[ -n "$HCA_FILTER" && "$label" != "$HCA_FILTER" ]]; then
      continue
    fi
    launcher_rc=0
    run_four_rank_probe "$label" "$rdmas" "$netdevs" "$extra_env" || launcher_rc=$?
    echo "Launcher rc: ${launcher_rc}" >>"$OUT_DIR/hca-probe.${label}.log"
  done
  for log_file in "$OUT_DIR"/hca-probe.*.log; do
    label="${log_file##*/hca-probe.}"
    label="${label%.log}"
    if [[ -n "$HCA_FILTER" && "$label" != "$HCA_FILTER" ]]; then
      continue
    fi
    sed -i.bak "/^${label}[[:space:]]/d" "$OUT_DIR/hca-probe.tsv"
    rm -f "$OUT_DIR/hca-probe.tsv.bak"
    rc="$(awk '/Exit code:/ {x=$3} /Launcher rc:/ && x == "" {x=$3} END {if (x == "") x=99; print x+0}' "$log_file")"
    version=0; non_neighbor=0
    grep -q 'nccl-library=23007\|NCCL version 2.30.7' "$log_file" && version=1
    grep -q '192.0.2.10, remote GID ::ffff:192.0.2.10\|192.0.2.10, remote GID ::ffff:192.0.2.10' "$log_file" && non_neighbor=1
    printf '%s\t%s\t%s\t%s\n' "$label" "$rc" "$version" "$non_neighbor" >>"$OUT_DIR/hca-probe.tsv"
  done
}

classify_graph() {
  log "Classify NCCL attempted GID edges"
  chmod +x scripts/parse_nccl_switchless_edges.py
  local logs=()
  while IFS= read -r file; do
    logs+=("$file")
  done < <(find "$OUT_DIR" -maxdepth 1 -type f \( -name 'hca-probe.*.log' -o -name 'per-rank-hca.*.log' \) | sort)
  if [[ "${#logs[@]}" -eq 0 ]]; then
    log "No NCCL logs found to classify in ${OUT_DIR}"
    return 0
  fi
  set +e
  scripts/parse_nccl_switchless_edges.py "${logs[@]}" >"$OUT_DIR/nccl-edge-classification.tsv" 2>"$OUT_DIR/nccl-edge-classification.stderr"
  local rc=$?
  set -e
  {
    echo -e "count\tlocal_ip\tremote_ip\tclass\tedge"
    awk -F'\t' 'NR > 1 && $1 !~ /^#/ {key=$4 "\t" $5 "\t" $6 "\t" $7; counts[key]++} END {for (key in counts) print counts[key] "\t" key}' "$OUT_DIR/nccl-edge-classification.tsv" | sort -rn
  } >"$OUT_DIR/nccl-edge-classification-summary.tsv"
  return "$rc"
}

topo_dump() {
  log "NCCL topology/graph dump probe"
  local launcher_rc=0 row alias _host _mgmt _mpi
  run_four_rank_probe "topo-dump" "rocep1s0f0,roceP2p1s0f0,rocep1s0f1,roceP2p1s0f1" "enp1s0f0np0,enP2p1s0f0np0,enp1s0f1np1,enP2p1s0f1np1" "export NCCL_CROSS_NIC=1; export NCCL_TOPO_DUMP_FILE=/var/tmp/public-run/sparks58-topo.xml; export NCCL_GRAPH_DUMP_FILE=/var/tmp/public-run/sparks58-graph.xml" || launcher_rc=$?
  echo "Launcher rc: ${launcher_rc}" >>"$OUT_DIR/hca-probe.topo-dump.log"
  for row in "${NODES[@]}"; do
    IFS="|" read -r alias _host _mgmt _mpi <<<"$row"
    ssh_run "$alias" >"$OUT_DIR/topo-dump.${alias}.collect.log" 2>&1 <<'REMOTE'
set -euo pipefail
for f in /var/tmp/public-run/sparks58-topo.xml /var/tmp/public-run/sparks58-graph.xml; do
  if [[ -s "$f" ]]; then
    echo "===== $f ====="
    sed -n '1,240p' "$f"
  else
    echo "missing $f"
  fi
done
REMOTE
  done
}

topo_file_probe() {
  log "NCCL_TOPO_FILE read/bias probe"
  local topo_src="$OUT_DIR/topo-dump.spark-e.example.collect.log"
  local topo_xml="$OUT_DIR/sparks58-topo-from-dump.xml"
  if [[ ! -s "$topo_src" ]]; then
    topo_dump
  fi
  awk '/===== \/tmp\/sparks58-topo.xml =====/{in_topo=1; next} /===== \/tmp\/sparks58-graph.xml =====/{in_topo=0} in_topo {print}' "$topo_src" >"$topo_xml"
  if [[ ! -s "$topo_xml" ]]; then
    log "No topology XML could be extracted from ${topo_src}"
    return 3
  fi
  local row alias _host _mgmt _mpi
  for row in "${NODES[@]}"; do
    IFS="|" read -r alias _host _mgmt _mpi <<<"$row"
    scp_to "$alias" "$topo_xml" "/var/tmp/public-run/sparks58-topo-file.xml" >/dev/null
  done
  local launcher_rc=0
  run_four_rank_probe "topo-file-read" "rocep1s0f0,roceP2p1s0f0,rocep1s0f1,roceP2p1s0f1" "enp1s0f0np0,enP2p1s0f0np0,enp1s0f1np1,enP2p1s0f1np1" "export NCCL_CROSS_NIC=1; export NCCL_TOPO_FILE=/var/tmp/public-run/sparks58-topo-file.xml; export NCCL_TOPO_DUMP_FILE=/var/tmp/public-run/sparks58-topo-file-after.xml; export NCCL_GRAPH_DUMP_FILE=/var/tmp/public-run/sparks58-graph-topofile.xml" || launcher_rc=$?
  echo "Launcher rc: ${launcher_rc}" >>"$OUT_DIR/hca-probe.topo-file-read.log"
  classify_graph || true
}

custom_ring_tcp() {
  log "Custom edge-orchestrated TCP ring all-reduce over direct QSFP IPs"
  printf 'rank\talias\trc\tok\telapsed_sec\tsend_src\tnext\trecv_ip\n' >"$OUT_DIR/custom-ring-tcp.tsv"
  local row alias _host _mgmt _mpi
  for row in "${NODES[@]}"; do
    IFS="|" read -r alias _host _mgmt _mpi <<<"$row"
    scp_to "$alias" "scripts/sparks58_custom_ring.py" "/var/tmp/public-run/sparks58_custom_ring.py" >/dev/null
  done

  local specs=(
    "0|spark-e.example|192.0.2.10|192.0.2.10|192.0.2.10"
    "1|spark-f.example|192.0.2.10|192.0.2.10|192.0.2.10"
    "2|spark-h.example|192.0.2.10|192.0.2.10|192.0.2.10"
    "3|spark-g.example|192.0.2.10|192.0.2.10|192.0.2.10"
  )
  local pids=() rank recv_ip send_src next_ip log_file
  for spec in "${specs[@]}"; do
    IFS="|" read -r rank alias recv_ip send_src next_ip <<<"$spec"
    log_file="$OUT_DIR/custom-ring-tcp.rank${rank}.${alias}.log"
    (
      set +e
      ssh_run "$alias" "python3 -u /var/tmp/public-run/sparks58_custom_ring.py --rank ${rank} --world 4 --recv-ip ${recv_ip} --send-src-ip ${send_src} --next-ip ${next_ip} --port ${CUSTOM_RING_PORT} --elements ${CUSTOM_RING_ELEMENTS}" >"$log_file" 2>&1
      echo "$?" >"$log_file.rc"
    ) &
    pids+=("$!")
  done
  local pid
  for pid in "${pids[@]}"; do wait "$pid" || true; done
  local rc ok elapsed
  for spec in "${specs[@]}"; do
    IFS="|" read -r rank alias recv_ip send_src next_ip <<<"$spec"
    log_file="$OUT_DIR/custom-ring-tcp.rank${rank}.${alias}.log"
    rc="$(cat "$log_file.rc" 2>/dev/null || echo 99)"
    ok="$(awk '/^RESULT / {for (i=1;i<=NF;i++) if ($i ~ /^ok=/) {split($i,a,"="); print a[2]}}' "$log_file")"
    elapsed="$(awk '/^RESULT / {for (i=1;i<=NF;i++) if ($i ~ /^elapsed_sec=/) {split($i,a,"="); print a[2]}}' "$log_file")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rank" "$alias" "$rc" "${ok:-0}" "${elapsed:-0}" "$send_src" "$next_ip" "$recv_ip" >>"$OUT_DIR/custom-ring-tcp.tsv"
  done
  awk 'NR > 1 && ($3 != 0 || $4 != 1) {bad=1} END {exit bad ? 1 : 0}' "$OUT_DIR/custom-ring-tcp.tsv"
}

ucx_ring() {
  log "UCX explicit-edge direct ring transport probe"
  printf 'label\tsrc\tdst\tsrc_ip\tdst_ip\trdma\trc\n' >"$OUT_DIR/ucx-ring.tsv"
  local specs=(
    "s5-s6|spark-e.example|spark-f.example|192.0.2.10|192.0.2.10|rocep1s0f0"
    "s6-s8|spark-f.example|spark-h.example|192.0.2.10|192.0.2.10|rocep1s0f1"
    "s8-s7|spark-h.example|spark-g.example|192.0.2.10|192.0.2.10|rocep1s0f0"
    "s7-s5|spark-g.example|spark-e.example|192.0.2.10|192.0.2.10|rocep1s0f1"
  )
  local spec label src dst src_ip dst_ip rdma port pids=() pid
  port="$UCX_PORT_BASE"
  for spec in "${specs[@]}"; do
    IFS="|" read -r label src dst src_ip dst_ip rdma <<<"$spec"
    ssh_run "$dst" "pkill ucx_perftest 2>/dev/null || true" || true
    ssh_run "$dst" "UCX_TLS=rc_x,ud_x,self UCX_NET_DEVICES=${rdma}:1 timeout $((UCX_SECONDS + 25)) ucx_perftest -p ${port} -t tag_bw -s 1048576 -n 1000" >"$OUT_DIR/ucx-ring.${label}.server.log" 2>&1 &
    pids+=("$!")
    port=$((port + 1))
  done
  sleep 3
  port="$UCX_PORT_BASE"
  local client_pids=()
  for spec in "${specs[@]}"; do
    IFS="|" read -r label src dst src_ip dst_ip rdma <<<"$spec"
    (
      set +e
      ssh_run "$src" "UCX_TLS=rc_x,ud_x,self UCX_NET_DEVICES=${rdma}:1 timeout $((UCX_SECONDS + 25)) ucx_perftest -p ${port} -t tag_bw -s 1048576 -n 1000 ${dst_ip}" >"$OUT_DIR/ucx-ring.${label}.client.log" 2>&1
      rc=$?
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$src" "$dst" "$src_ip" "$dst_ip" "$rdma" "$rc" >>"$OUT_DIR/ucx-ring.tsv"
      exit "$rc"
    ) &
    client_pids+=("$!")
    port=$((port + 1))
  done
  local rc=0
  for pid in "${client_pids[@]}"; do wait "$pid" || rc=1; done
  for pid in "${pids[@]}"; do wait "$pid" || true; done
  return "$rc"
}

write_summary() {
  {
    echo "# Sparks 5-8 Novel Switchless Experiments"
    echo
    echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Mode: ${MODE}"
    echo "- Output directory: ${OUT_DIR}"
    echo "- Hardware stop policy: stop only for host/link/RDMA physical failures"
    echo
    for f in concurrent-ib.tsv nccl-phases.tsv hca-probe.tsv per-rank-hca.tsv nccl-edge-classification-summary.tsv custom-ring-tcp.tsv ucx-ring.tsv stale-jobs.txt; do
      if [[ -f "$OUT_DIR/$f" ]]; then
        echo "## ${f}"
        echo
        cat "$OUT_DIR/$f"
        echo
      fi
    done
  } >"$OUT_DIR/SUMMARY.md"
  cat "$OUT_DIR/SUMMARY.md"
}

log "Output directory: ${OUT_DIR}"

case "$MODE" in
  readiness)
    readiness
    ;;
  concurrent-ib)
    readiness
    concurrent_ib rail0
    concurrent_ib rail1
    ;;
  nccl-phases)
    readiness
    nccl_phases
    ;;
  hca-probe)
    readiness
    hca_probe
    ;;
  per-rank-hca)
    readiness
    per_rank_hca_probe
    classify_graph || true
    ;;
  topo-dump)
    readiness
    topo_dump
    ;;
  topo-file)
    readiness
    topo_file_probe
    ;;
  classify-graph)
    classify_graph || true
    ;;
  custom-ring-tcp)
    readiness
    custom_ring_tcp
    ;;
  ucx-ring)
    readiness
    ucx_ring
    ;;
  all)
    readiness
    concurrent_ib rail0
    concurrent_ib rail1
    stale_scan
    nccl_phases
    stale_scan
    hca_probe
    stale_scan
    per_rank_hca_probe
    stale_scan
    topo_dump
    stale_scan
    topo_file_probe
    stale_scan
    classify_graph || true
    custom_ring_tcp
    stale_scan
    ucx_ring
    stale_scan
    ;;
  *)
    echo "Unknown MODE=${MODE}" >&2
    exit 2
    ;;
esac

write_summary
