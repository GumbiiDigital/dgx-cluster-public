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
NCCL_LOGIN_USER="${NCCL_LOGIN_USER:-}"
MPI_KEY="${MPI_KEY:-/opt/public-user/.ssh/dgx_cluster_mpi_ed25519}"
REMOTE_BRANCH="${REMOTE_BRANCH:-v2.30u1}"
REMOTE_REPO="${REMOTE_REPO:-https://github.com/NVIDIA/nccl.git}"
REMOTE_SRC="${REMOTE_SRC:-/opt/public-user/src/nccl-${REMOTE_BRANCH}}"
PEERS="${PEERS:-192.0.2.10 192.0.2.10 192.0.2.10}"
OUT_DIR="${OUT_DIR:-evidence/sparks58-switchless-nccl-build-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUT_DIR"

SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new)
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

log="$OUT_DIR/build.log"
remote_env="REMOTE_BRANCH='${REMOTE_BRANCH}' REMOTE_REPO='${REMOTE_REPO}' REMOTE_SRC='${REMOTE_SRC}' MPI_KEY='${MPI_KEY}' PEERS='${PEERS}'"
if [[ -n "$NCCL_LOGIN_USER" ]]; then
  remote_cmd="su - ${NCCL_LOGIN_USER} -c \"${remote_env} bash -s\""
else
  remote_cmd="${remote_env} bash -s"
fi
set +e
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}" "$remote_cmd" >"$log" 2>&1 <<'REMOTE'
set -euo pipefail
echo "host=$(hostname)"
echo "repo=${REMOTE_REPO}"
echo "branch=${REMOTE_BRANCH}"
echo "src=${REMOTE_SRC}"
command -v git
command -v make
command -v gcc
command -v g++
test -d /usr/local/cuda
test -d /usr/lib/aarch64-linux-gnu/openmpi

if [[ ! -d "${REMOTE_SRC}/.git" ]]; then
  mkdir -p "$(dirname "${REMOTE_SRC}")"
  git clone --depth 1 --branch "${REMOTE_BRANCH}" "${REMOTE_REPO}" "${REMOTE_SRC}"
else
  git -C "${REMOTE_SRC}" fetch --depth 1 origin "${REMOTE_BRANCH}"
  git -C "${REMOTE_SRC}" checkout -q FETCH_HEAD
fi

git -C "${REMOTE_SRC}" rev-parse --short HEAD
make -C "${REMOTE_SRC}" -j"$(nproc)" src.build NVCC_GENCODE="-gencode=arch=compute_121,code=sm_121"
test -s "${REMOTE_SRC}/build/lib/libnccl.so"
ls -lh "${REMOTE_SRC}/build/lib/libnccl.so"*

for h in ${PEERS}; do
  echo "===== syncing NCCL build to ${h} ====="
  ssh -i "${MPI_KEY}" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${h}" "mkdir -p '${REMOTE_SRC}/build'"
  rsync -az -e "ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no" \
    "${REMOTE_SRC}/build/" "${h}:${REMOTE_SRC}/build/"
  ssh -i "${MPI_KEY}" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${h}" \
    "test -s '${REMOTE_SRC}/build/lib/libnccl.so' && ls -lh '${REMOTE_SRC}/build/lib/libnccl.so'"
done

echo "remote_nccl_home=${REMOTE_SRC}/build"
REMOTE
rc=$?
set -e

{
  echo "# Sparks 5-8 Switchless NCCL Build"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Launcher: ${LAUNCHER}"
  echo "- Repository: ${REMOTE_REPO}"
  echo "- Branch: ${REMOTE_BRANCH}"
  echo "- Remote source: ${REMOTE_SRC}"
  echo "- Exit: ${rc}"
  echo
  if [[ "$rc" -eq 0 ]]; then
    echo "PASS: NCCL built under the Spark user home and synced to peers."
  else
    echo "FAIL: NCCL build or sync failed. See build.log."
  fi
  echo
  echo "## Key Lines"
  rg -n 'host=|repo=|branch=|src=|rev-parse|libnccl.so|syncing NCCL|remote_nccl_home|error:|Error|FAIL|No such file|not found|undefined reference' "$log" || true
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
exit "$rc"
