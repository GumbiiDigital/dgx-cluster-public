#!/usr/bin/env bash
set -euo pipefail

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

if [[ -n "${HOSTS_OVERRIDE:-}" ]]; then
  # shellcheck disable=SC2206
  HOSTS=(${HOSTS_OVERRIDE})
else
  HOSTS=(
    "${SPARK1_MGMT:-spark-a.example}"
    "${SPARK2_MGMT:-spark-b.example}"
    "${SPARK3_MGMT:-spark-c.example}"
    "${SPARK4_MGMT:-spark-d.example}"
  )
fi
MPI_HOME="${MPI_HOME:-/usr/lib/aarch64-linux-gnu/openmpi}"

if [[ "${BUILD_NCCL_TESTS:-0}" != "1" ]]; then
  cat <<'EOF'
Dry-run only. Set BUILD_NCCL_TESTS=1 after libnccl-dev is installed on all
four Sparks and raw RoCE is passing.
EOF
  exit 0
fi

for host in "${HOSTS[@]}"; do
  echo "===== ${host} build nccl-tests ====="
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" '
    set -euo pipefail
    test -f /usr/include/nccl.h || test -f /usr/local/cuda/include/nccl.h
    cd "$HOME"
    if [ -d nccl-tests/.git ]; then
      cd nccl-tests
      git fetch --tags --prune
    else
      git clone https://github.com/NVIDIA/nccl-tests.git
      cd nccl-tests
    fi
    make MPI=1 MPI_HOME='"${MPI_HOME}"' CUDA_HOME=/usr/local/cuda -j"$(nproc)"
    test -x build/all_reduce_perf
    test -x build/all_gather_perf
  '
done

echo "nccl-tests built on all hosts."
