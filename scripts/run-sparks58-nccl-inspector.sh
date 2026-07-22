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
REMOTE_PLUGIN="${REMOTE_PLUGIN:-${REMOTE_SRC}/ext-profiler/inspector/libnccl-profiler-inspector.so}"
STAMP="${STAMP:-$(date +%Y%m%d%H%M%S)}"
POLICY_PREFIX="${POLICY_PREFIX:-sparks58}"
GROUP_LABEL="${GROUP_LABEL:-Sparks 5-8}"
REMOTE_DUMP_DIR="${REMOTE_DUMP_DIR:-/var/tmp/public-run/${POLICY_PREFIX}-nccl-inspector-${STAMP}}"
OUT_DIR="${OUT_DIR:-evidence/nccl-inspector-run-$(date +%Y%m%d-%H%M%S)}"
HOSTS="${HOSTS:-192.0.2.10 192.0.2.10 192.0.2.10 192.0.2.10}"

mkdir -p "$OUT_DIR"

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new)

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}" "bash -s" >"$OUT_DIR/preflight.log" 2>&1 <<REMOTE
set -euo pipefail
for h in ${HOSTS}; do
  echo "===== \$h ====="
  ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "\$h" "rm -rf '${REMOTE_DUMP_DIR}'; mkdir -p '${REMOTE_DUMP_DIR}'; test -s '${REMOTE_PLUGIN}'; ls -lh '${REMOTE_PLUGIN}'"
done
REMOTE

set +e
NCCL_PROFILER_PLUGIN="$REMOTE_PLUGIN" \
NCCL_INSPECTOR_ENABLE=1 \
NCCL_INSPECTOR_DUMP_THREAD_INTERVAL_MICROSECONDS="${NCCL_INSPECTOR_DUMP_THREAD_INTERVAL_MICROSECONDS:-500000}" \
NCCL_INSPECTOR_DUMP_DIR="$REMOTE_DUMP_DIR" \
NCCL_INSPECTOR_DUMP_VERBOSE="${NCCL_INSPECTOR_DUMP_VERBOSE:-0}" \
NCCL_INSPECTOR_REQUIRE_KERNEL_TIMING="${NCCL_INSPECTOR_REQUIRE_KERNEL_TIMING:-0}" \
NCCL_DEBUG_VALUE="${NCCL_DEBUG_VALUE:-INFO}" \
NCCL_DEBUG_SUBSYS_VALUE="${NCCL_DEBUG_SUBSYS_VALUE:-PROFILE}" \
CONFIG_LABEL="${CONFIG_LABEL:-inspector-256M}" \
ITERS="${ITERS:-20}" \
WARMUP_ITERS="${WARMUP_ITERS:-5}" \
OUT_DIR="$OUT_DIR/nccl-run" \
scripts/run-sparks58-nccl-profile.sh
rc=$?
set -e

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}" "bash -s" >"$OUT_DIR/pull.log" 2>&1 <<REMOTE
set -euo pipefail
mkdir -p /var/tmp/public-run/${POLICY_PREFIX}-inspector-pull-${STAMP}
for h in ${HOSTS}; do
  safe="\${h//./-}"
  echo "===== listing \$h ====="
  ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "\$h" "find '${REMOTE_DUMP_DIR}' -maxdepth 3 -type f -print -exec ls -lh {} \\;" || true
  echo "===== archiving \$h ====="
  ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "\$h" "cd '${REMOTE_DUMP_DIR}' 2>/dev/null && tar -czf /var/tmp/public-run/${POLICY_PREFIX}-inspector-\${safe}-${STAMP}.tgz . || true"
  scp -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "\$h:/var/tmp/public-run/${POLICY_PREFIX}-inspector-\${safe}-${STAMP}.tgz" "/var/tmp/public-run/${POLICY_PREFIX}-inspector-pull-${STAMP}/" || true
done
REMOTE

scp "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}:/var/tmp/public-run/${POLICY_PREFIX}-inspector-pull-${STAMP}/*.tgz" "$OUT_DIR/" >"$OUT_DIR/local-scp.log" 2>&1 || true

mkdir -p "$OUT_DIR/pulled"
for archive in "$OUT_DIR"/*.tgz; do
  [[ -e "$archive" ]] || continue
  name="$(basename "$archive" .tgz)"
  mkdir -p "$OUT_DIR/pulled/$name"
  tar -xzf "$archive" -C "$OUT_DIR/pulled/$name" || true
done

{
  echo "# ${GROUP_LABEL} NCCL Inspector Run"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Remote plugin: ${REMOTE_PLUGIN}"
  echo "- Remote dump dir: ${REMOTE_DUMP_DIR}"
  echo "- NCCL run exit: ${rc}"
  echo
  echo "## NCCL Parsed Results"
  if [[ -f "$OUT_DIR/nccl-run/parsed.tsv" ]]; then
    cat "$OUT_DIR/nccl-run/parsed.tsv"
  else
    echo "No parsed NCCL TSV emitted."
  fi
  echo
  echo "## Inspector Files"
  find "$OUT_DIR/pulled" -type f -maxdepth 5 -print | sort || true
  echo
  echo "## Inspector Debug Lines"
  if [[ -f "$OUT_DIR/nccl-run/nccl.log" ]]; then
    rg -n 'PROFILE|INSPECTOR|Inspector|profiler|NCCL_PROFILER_PLUGIN|coll_perf|error|warn|WARN|Failed' "$OUT_DIR/nccl-run/nccl.log" || true
  fi
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
exit "$rc"
