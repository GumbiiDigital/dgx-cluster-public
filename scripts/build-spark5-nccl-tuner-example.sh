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
REMOTE_PLUGIN="${REMOTE_SRC}/ext-tuner/example/libnccl-tuner-example.so"
PEERS="${PEERS:-192.0.2.10 192.0.2.10 192.0.2.10}"
GROUP_LABEL="${GROUP_LABEL:-Sparks 5-8}"
PEER_LABEL="${PEER_LABEL:-Sparks 6-8}"
OUT_DIR="${OUT_DIR:-evidence/nccl-tuner-build-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUT_DIR"

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new)

log="$OUT_DIR/build.log"
set +e
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}" "bash -s" >"$log" 2>&1 <<REMOTE
set -euo pipefail
if [[ ! -d "${REMOTE_SRC}/.git" ]]; then
  mkdir -p "\$(dirname "${REMOTE_SRC}")"
  git clone --depth 1 --branch "${REMOTE_TAG}" https://github.com/NVIDIA/nccl.git "${REMOTE_SRC}"
else
  git -C "${REMOTE_SRC}" fetch --depth 1 origin tag "${REMOTE_TAG}" || true
  git -C "${REMOTE_SRC}" checkout -q "${REMOTE_TAG}"
fi
make -C "${REMOTE_SRC}/ext-tuner/example" CUDA_HOME=/usr/local/cuda -j"\$(nproc)"
test -s "${REMOTE_PLUGIN}"
file "${REMOTE_PLUGIN}" || true
for h in ${PEERS}; do
  echo "===== syncing tuner to \$h ====="
  ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "\$h" "mkdir -p '${REMOTE_SRC}/ext-tuner/example'"
  scp -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "${REMOTE_PLUGIN}" "\$h:${REMOTE_SRC}/ext-tuner/example/"
  ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "\$h" "test -s '${REMOTE_PLUGIN}' && ls -lh '${REMOTE_PLUGIN}'"
done
echo "plugin=${REMOTE_PLUGIN}"
REMOTE
rc=$?
set -e

{
  echo "# ${GROUP_LABEL} NCCL Tuner Example Build"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- NCCL tag: ${REMOTE_TAG}"
  echo "- Remote plugin: ${REMOTE_PLUGIN}"
  echo "- Exit: ${rc}"
  echo
  if [[ "$rc" -eq 0 ]]; then
    echo "PASS: tuner example plugin built and synced to ${PEER_LABEL}."
  else
    echo "FAIL: tuner example build or sync failed. See build.log."
  fi
  echo
  rg -n 'plugin=|libnccl-tuner-example|syncing tuner|error:|Error|FAIL|No such file|undefined reference' "$log" || true
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
exit "$rc"
