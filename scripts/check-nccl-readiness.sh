#!/usr/bin/env bash
set -euo pipefail

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

HOSTS=(
  "${SPARK1_MGMT:-spark-a.example}"
  "${SPARK2_MGMT:-spark-b.example}"
  "${SPARK3_MGMT:-spark-c.example}"
  "${SPARK4_MGMT:-spark-d.example}"
)

ssh_run() {
  local host="$1"
  shift
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "$@"
}

failures=0

for host in "${HOSTS[@]}"; do
  echo "===== ${host} NCCL readiness ====="
  if ! ssh_run "$host" '
    set -u
    missing=0
    hostname
    echo "-- CUDA --"
    readlink -f /usr/local/cuda 2>/dev/null || true
    if test -x /usr/local/cuda/bin/nvcc; then
      /usr/local/cuda/bin/nvcc --version | tail -4
    else
      echo "MISSING: /usr/local/cuda/bin/nvcc"
      missing=1
    fi
    echo "-- OpenMPI --"
    if command -v mpirun; then
      mpirun --version | head -3 || true
    else
      echo "MISSING: mpirun"
      missing=1
    fi
    echo "-- NCCL --"
    find /usr /opt -name "libnccl.so*" 2>/dev/null | sort | sed -n "1,20p"
    find /usr /opt -name "nccl.h" 2>/dev/null | sort | sed -n "1,20p"
    if ! find /usr /opt -name "libnccl.so*" 2>/dev/null | grep -q .; then
      echo "MISSING: libnccl.so"
      apt-cache policy libnccl2 2>/dev/null | sed -n "1,12p" || true
      missing=1
    fi
    if ! find /usr /opt -name "nccl.h" 2>/dev/null | grep -q .; then
      echo "MISSING: nccl.h"
      apt-cache policy libnccl-dev 2>/dev/null | sed -n "1,12p" || true
      missing=1
    fi
    echo "-- nccl-tests --"
    if ! test -x "$HOME/nccl-tests/build/all_reduce_perf"; then
      echo "MISSING: $HOME/nccl-tests/build/all_reduce_perf"
      missing=1
    fi
    if ! test -x "$HOME/nccl-tests/build/all_gather_perf"; then
      echo "MISSING: $HOME/nccl-tests/build/all_gather_perf"
      missing=1
    fi
    exit "$missing"
  '; then
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  cat <<'EOF'
NCCL readiness failed.

Do not run NCCL yet. Current expected remediation, after raw RoCE passes and
with public-user approval, is to install matching NCCL runtime/dev packages on all
four Sparks, then build nccl-tests uniformly.
EOF
  exit 1
fi

echo "NCCL readiness passed."
