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
REMOTE_TAG="${REMOTE_TAG:-v2.28.9-1}"
REMOTE_SRC="${REMOTE_SRC:-/opt/public-user/src/nccl-${REMOTE_TAG}}"
REMOTE_TUNER_PLUGIN="${REMOTE_TUNER_PLUGIN:-${REMOTE_SRC}/ext-tuner/example/libnccl-tuner-example.so}"
POLICY_PREFIX="${POLICY_PREFIX:-sparks58}"
GROUP_LABEL="${GROUP_LABEL:-Sparks 5-8}"
OUT_DIR="${OUT_DIR:-evidence/${POLICY_PREFIX}-size-policy-verify-$(date +%Y%m%d-%H%M%S)}"
POLICY_DIR="${POLICY_DIR:-$OUT_DIR/policy}"
SIZES="${SIZES:-8K 64K 1M 8M 32M 256M 1G 4G}"
SYNC_HOSTS="${SYNC_HOSTS:-192.0.2.10 192.0.2.10 192.0.2.10}"

mkdir -p "$OUT_DIR"

if [[ ! -f "$POLICY_DIR/${POLICY_PREFIX}-nccl-tuner.conf" ]]; then
  OUT_DIR="$POLICY_DIR" POLICY_PREFIX="$POLICY_PREFIX" GROUP_LABEL="$GROUP_LABEL" scripts/generate-sparks58-size-policy.sh >/dev/null
fi

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new)
REMOTE_CONF="/var/tmp/public-run/${POLICY_PREFIX}-nccl-tuner-$(date +%Y%m%d%H%M%S).conf"

scp "${SSH_OPTS[@]}" "$POLICY_DIR/${POLICY_PREFIX}-nccl-tuner.conf" "${SSH_USER}@${LAUNCHER}:${REMOTE_CONF}" >"$OUT_DIR/upload-tuner-conf.log" 2>&1
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}" "bash -s" >"$OUT_DIR/sync-tuner-conf.log" 2>&1 <<REMOTE
set -euo pipefail
for h in ${SYNC_HOSTS}; do
  scp -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "${REMOTE_CONF}" "\$h:${REMOTE_CONF}"
done
REMOTE

summary="$OUT_DIR/policy-results.tsv"
echo -e "size\tprofile\tavg_bus_GBs\toop_bus_GBs\tip_bus_GBs\twrong\texit" >"$summary"

profile_for_size() {
  case "$1" in
    8K) echo baseline ;;
    64K|1M|8M|32M) echo channels8 ;;
    256M) echo qps4split1-ch8-ignore ;;
    1G|4G) echo qps4split1 ;;
    *) echo qps4split1-ch8-ignore ;;
  esac
}

run_size() {
  local size="$1" profile="$2" dir="$OUT_DIR/${size}-${profile}"
  mkdir -p "$dir"
  local -a env_args=(
    OUT_DIR="$dir"
    CONFIG_LABEL="policy-${profile}-${size}"
    MIN_BYTES="$size"
    MAX_BYTES="$size"
    ITERS="${ITERS:-30}"
    WARMUP_ITERS="${WARMUP_ITERS:-8}"
    APPLY_TUNED_DEFAULTS=0
    NCCL_TUNER_PLUGIN="$REMOTE_TUNER_PLUGIN"
    NCCL_TUNER_CONFIG_FILE="$REMOTE_CONF"
  )
  if [[ "${TUNER_DEBUG:-0}" == "1" ]]; then
    env_args+=(NCCL_DEBUG_VALUE="${NCCL_DEBUG_VALUE:-INFO}" NCCL_DEBUG_SUBSYS_VALUE="${NCCL_DEBUG_SUBSYS_VALUE:-TUNING}")
  fi
  case "$profile" in
    channels8)
      env_args+=(NCCL_MIN_NCHANNELS=8 NCCL_MAX_NCHANNELS=8)
      ;;
    qps4split1)
      env_args+=(NCCL_IB_QPS_PER_CONNECTION=4 NCCL_IB_SPLIT_DATA_ON_QPS=1)
      ;;
    qps4split1-ch8-ignore)
      env_args+=(NCCL_IB_QPS_PER_CONNECTION=4 NCCL_IB_SPLIT_DATA_ON_QPS=1 NCCL_MIN_NCHANNELS=8 NCCL_MAX_NCHANNELS=8 NCCL_IGNORE_CPU_AFFINITY=1)
      ;;
  esac

  set +e
  env "${env_args[@]}" scripts/run-sparks58-nccl-profile.sh >"$dir/harness.stdout" 2>&1
  local rc=$?
  set -e

  local avg="NA" oop="NA" ip="NA" wrong="NA"
  if [[ -s "$dir/parsed.tsv" ]]; then
    avg="$(awk 'NR==2 {print $10}' "$dir/parsed.tsv")"
    oop="$(awk 'NR==2 {print $5}' "$dir/parsed.tsv")"
    ip="$(awk 'NR==2 {print $8}' "$dir/parsed.tsv")"
    wrong="$(awk 'NR==2 {print $6 + $9}' "$dir/parsed.tsv")"
  fi
  echo -e "${size}\t${profile}\t${avg}\t${oop}\t${ip}\t${wrong}\t${rc}" >>"$summary"
}

for size in $SIZES; do
  profile="$(profile_for_size "$size")"
  run_size "$size" "$profile"
done

{
  echo "# ${GROUP_LABEL} Size Policy Verification"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Tuner plugin: ${REMOTE_TUNER_PLUGIN}"
  echo "- Tuner config: ${REMOTE_CONF}"
  echo
  echo "## Results"
  echo
  cat "$summary"
  echo
  echo "## Tuner Debug Lines"
  rg -n 'TUNER|tuner|Loaded config|Using tuner|No config|Failed|error|WARN' "$OUT_DIR"/*/*.{log,stdout} 2>/dev/null || true
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
