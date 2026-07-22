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
NP="${NP:-4}"

PROFILE_FILE="${PROFILE_FILE:-}"
if [[ -n "$PROFILE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PROFILE_FILE"
fi

COLLECTIVE="${COLLECTIVE:-all_reduce_perf}"
MIN_BYTES="${MIN_BYTES:-256M}"
MAX_BYTES="${MAX_BYTES:-256M}"
STEP_FACTOR="${STEP_FACTOR:-2}"
GPUS_PER_RANK="${GPUS_PER_RANK:-1}"
ITERS="${ITERS:-100}"
WARMUP_ITERS="${WARMUP_ITERS:-20}"
VALIDATE="${VALIDATE:-1}"
REPEATS="${REPEATS:-1}"
CONFIG_LABEL="${CONFIG_LABEL_OVERRIDE:-${CONFIG_LABEL:-sparks58-tuned}}"
OUT_DIR="${OUT_DIR:-evidence/nccl-sparks58-profile-$(date +%Y%m%d-%H%M%S)}"

UCX_NET_DEVICES="${UCX_NET_DEVICES:-enp1s0f1np1,enP2p1s0f1np1}"
NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-enp1s0f1np1,enP2p1s0f1np1}"
NCCL_IB_DISABLE="${NCCL_IB_DISABLE:-0}"
NCCL_IB_HCA="${NCCL_IB_HCA:-rocep1s0f1,roceP2p1s0f1}"
NCCL_NET_GDR_LEVEL="${NCCL_NET_GDR_LEVEL:-2}"
APPLY_TUNED_DEFAULTS="${APPLY_TUNED_DEFAULTS:-1}"
NCCL_IB_QPS_PER_CONNECTION="${NCCL_IB_QPS_PER_CONNECTION:-}"
NCCL_IB_SPLIT_DATA_ON_QPS="${NCCL_IB_SPLIT_DATA_ON_QPS:-}"
NCCL_MIN_NCHANNELS="${NCCL_MIN_NCHANNELS:-}"
NCCL_MAX_NCHANNELS="${NCCL_MAX_NCHANNELS:-}"
NCCL_IGNORE_CPU_AFFINITY="${NCCL_IGNORE_CPU_AFFINITY:-}"
NCCL_DEBUG_VALUE="${NCCL_DEBUG_VALUE:-${NCCL_DEBUG:-}}"
NCCL_DEBUG_SUBSYS_VALUE="${NCCL_DEBUG_SUBSYS_VALUE:-${NCCL_DEBUG_SUBSYS:-}}"
NCCL_TOPO_DUMP_FILE="${NCCL_TOPO_DUMP_FILE:-}"
NCCL_GRAPH_DUMP_FILE="${NCCL_GRAPH_DUMP_FILE:-}"
MPI_EXTRA_ARGS="${MPI_EXTRA_ARGS:-}"

if [[ "$APPLY_TUNED_DEFAULTS" == "1" ]]; then
  NCCL_IB_QPS_PER_CONNECTION="${NCCL_IB_QPS_PER_CONNECTION:-4}"
  NCCL_IB_SPLIT_DATA_ON_QPS="${NCCL_IB_SPLIT_DATA_ON_QPS:-1}"
  NCCL_MIN_NCHANNELS="${NCCL_MIN_NCHANNELS:-8}"
  NCCL_MAX_NCHANNELS="${NCCL_MAX_NCHANNELS:-8}"
  NCCL_IGNORE_CPU_AFFINITY="${NCCL_IGNORE_CPU_AFFINITY:-1}"
fi

mkdir -p "$OUT_DIR"

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new)

remote_quote() {
  printf '%q' "$1"
}

remote_env=$(
  cat <<EOF
unset NCCL_DEBUG NCCL_DEBUG_SUBSYS NCCL_ALGO NCCL_PROTO NCCL_MIN_NCHANNELS NCCL_MAX_NCHANNELS NCCL_IGNORE_CPU_AFFINITY NCCL_IB_QPS_PER_CONNECTION NCCL_IB_SPLIT_DATA_ON_QPS NCCL_TOPO_DUMP_FILE NCCL_GRAPH_DUMP_FILE NCCL_PROFILER_PLUGIN NCCL_INSPECTOR_ENABLE NCCL_INSPECTOR_ENABLE_P2P NCCL_INSPECTOR_DUMP_THREAD_ENABLE NCCL_INSPECTOR_DUMP_THREAD_INTERVAL_MICROSECONDS NCCL_INSPECTOR_DUMP_DIR NCCL_INSPECTOR_DUMP_VERBOSE NCCL_INSPECTOR_PROM_DUMP NCCL_INSPECTOR_DUMP_MIN_SIZE_BYTES NCCL_INSPECTOR_REQUIRE_KERNEL_TIMING NCCL_TUNER_PLUGIN NCCL_TUNER_CONFIG NCCL_RAS_ENABLE NCCL_RAS_ADDR NCCL_OOB_NET_ENABLE NCCL_OOB_NET_IFNAME NCCL_IB_TC NCCL_IB_FIFO_TC
export UCX_NET_DEVICES=$(remote_quote "$UCX_NET_DEVICES")
export NCCL_SOCKET_IFNAME=$(remote_quote "$NCCL_SOCKET_IFNAME")
export NCCL_IB_DISABLE=$(remote_quote "$NCCL_IB_DISABLE")
export NCCL_IB_HCA=$(remote_quote "$NCCL_IB_HCA")
export NCCL_NET_GDR_LEVEL=$(remote_quote "$NCCL_NET_GDR_LEVEL")
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\${LD_LIBRARY_PATH:-}
EOF
)

extra_x=(-x UCX_NET_DEVICES -x NCCL_SOCKET_IFNAME -x NCCL_IB_DISABLE -x NCCL_IB_HCA -x NCCL_NET_GDR_LEVEL -x LD_LIBRARY_PATH)

add_optional_nccl_env() {
  local name="$1" value="$2"
  if [[ -n "$value" ]]; then
    remote_env+=$'\n'"export ${name}=$(remote_quote "$value")"
    extra_x+=(-x "$name")
  fi
}

add_optional_nccl_env NCCL_IB_QPS_PER_CONNECTION "$NCCL_IB_QPS_PER_CONNECTION"
add_optional_nccl_env NCCL_IB_SPLIT_DATA_ON_QPS "$NCCL_IB_SPLIT_DATA_ON_QPS"
add_optional_nccl_env NCCL_MIN_NCHANNELS "$NCCL_MIN_NCHANNELS"
add_optional_nccl_env NCCL_MAX_NCHANNELS "$NCCL_MAX_NCHANNELS"
add_optional_nccl_env NCCL_IGNORE_CPU_AFFINITY "$NCCL_IGNORE_CPU_AFFINITY"
add_optional_nccl_env NCCL_ALGO "${NCCL_ALGO:-}"
add_optional_nccl_env NCCL_PROTO "${NCCL_PROTO:-}"
add_optional_nccl_env NCCL_IB_GID_INDEX "${NCCL_IB_GID_INDEX:-}"

optional_passthrough_vars=(
  NCCL_PROFILER_PLUGIN
  NCCL_INSPECTOR_ENABLE
  NCCL_INSPECTOR_ENABLE_P2P
  NCCL_INSPECTOR_DUMP_THREAD_ENABLE
  NCCL_INSPECTOR_DUMP_THREAD_INTERVAL_MICROSECONDS
  NCCL_INSPECTOR_DUMP_DIR
  NCCL_INSPECTOR_DUMP_VERBOSE
  NCCL_INSPECTOR_PROM_DUMP
  NCCL_INSPECTOR_DUMP_MIN_SIZE_BYTES
  NCCL_INSPECTOR_REQUIRE_KERNEL_TIMING
  NCCL_TUNER_PLUGIN
  NCCL_TUNER_CONFIG
  NCCL_TUNER_CONFIG_FILE
  NCCL_RAS_ENABLE
  NCCL_RAS_ADDR
  NCCL_OOB_NET_ENABLE
  NCCL_OOB_NET_IFNAME
  NCCL_IB_TC
  NCCL_IB_FIFO_TC
)

for optional_var in "${optional_passthrough_vars[@]}"; do
  optional_value="${!optional_var:-}"
  add_optional_nccl_env "$optional_var" "$optional_value"
done

if [[ -n "$NCCL_DEBUG_VALUE" ]]; then
  remote_env+=$'\n'"export NCCL_DEBUG=$(remote_quote "$NCCL_DEBUG_VALUE")"
  extra_x+=(-x NCCL_DEBUG)
fi
if [[ -n "$NCCL_DEBUG_SUBSYS_VALUE" ]]; then
  remote_env+=$'\n'"export NCCL_DEBUG_SUBSYS=$(remote_quote "$NCCL_DEBUG_SUBSYS_VALUE")"
  extra_x+=(-x NCCL_DEBUG_SUBSYS)
fi
if [[ -n "$NCCL_TOPO_DUMP_FILE" ]]; then
  remote_env+=$'\n'"export NCCL_TOPO_DUMP_FILE=$(remote_quote "$NCCL_TOPO_DUMP_FILE")"
  extra_x+=(-x NCCL_TOPO_DUMP_FILE)
fi
if [[ -n "$NCCL_GRAPH_DUMP_FILE" ]]; then
  remote_env+=$'\n'"export NCCL_GRAPH_DUMP_FILE=$(remote_quote "$NCCL_GRAPH_DUMP_FILE")"
  extra_x+=(-x NCCL_GRAPH_DUMP_FILE)
fi

printf '%s\n' "$remote_env" >"$OUT_DIR/remote-env.sh"

log="$OUT_DIR/nccl.log"
set +e
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}" "bash -s" >"$log" 2>&1 <<REMOTE
set -euo pipefail
${remote_env}
echo "config_label=${CONFIG_LABEL}"
echo "started \$(date -u +%Y-%m-%dT%H:%M:%SZ)"
env | grep -E '^(NCCL_|UCX_)' | sort
for run in \$(seq 1 ${REPEATS}); do
  echo "===== run-\${run} \$(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
  timeout 120 prlimit --memlock=unlimited:unlimited mpirun -np '${NP}' \
    -H '${MPI_HOSTS}' \
    --mca plm_rsh_agent 'ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' \
    --mca plm_rsh_no_tree_spawn 1 \
    --mca oob_tcp_if_include enp1s0f1np1 \
    --mca btl_tcp_if_include enp1s0f1np1 \
    ${MPI_EXTRA_ARGS} \
    ${extra_x[*]} \
    "\$HOME/nccl-tests/build/${COLLECTIVE}" \
    -b '${MIN_BYTES}' -e '${MAX_BYTES}' -f '${STEP_FACTOR}' -g '${GPUS_PER_RANK}' -n '${ITERS}' -w '${WARMUP_ITERS}' -c '${VALIDATE}'
done
echo "finished \$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REMOTE
rc=$?
set -e

awk -v label="$CONFIG_LABEL" '
  BEGIN {
    print "config\trun\tsize_B\toop_alg_GBs\toop_bus_GBs\toop_wrong\tip_alg_GBs\tip_bus_GBs\tip_wrong\tavg_bus_GBs"
  }
  /^===== run-/ {
    run=$2
    sub(/^run-/, "", run)
  }
  /^[[:space:]]*[0-9]+[[:space:]]+[0-9]+/ {
    size=$1
    oop_alg=$7
    oop_bus=$8
    oop_wrong=$9
    ip_alg=$11
    ip_bus=$12
    ip_wrong=$13
  }
  /Avg bus bandwidth/ {
    avg=$6
    print label "\t" run "\t" size "\t" oop_alg "\t" oop_bus "\t" oop_wrong "\t" ip_alg "\t" ip_bus "\t" ip_wrong "\t" avg
  }
' "$log" >"$OUT_DIR/parsed.tsv"

{
  echo "# ${GROUP_LABEL:-Sparks 5-8} NCCL Profile Run"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Config label: ${CONFIG_LABEL}"
  echo "- Collective: ${COLLECTIVE}"
  echo "- Size range: ${MIN_BYTES} to ${MAX_BYTES}"
  echo "- Repeats: ${REPEATS}"
  echo "- Remote exit: ${rc}"
  echo
  echo "## Parsed Results"
  echo
  cat "$OUT_DIR/parsed.tsv"
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
exit "$rc"
