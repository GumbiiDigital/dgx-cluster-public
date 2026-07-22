#!/usr/bin/env bash
set -euo pipefail

if [[ "${SKIP_ROCE_GATE:-0}" != "1" ]]; then
  echo "Running raw RoCE gate before NCCL..."
  scripts/verify-roce-underlay.sh
  echo "Running dual-half DGX Spark underlay gate before NCCL..."
  scripts/verify-dual-rail-underlay.sh
else
  echo "WARNING: SKIP_ROCE_GATE=1 set; this is diagnostic only."
fi

echo "Checking NCCL build/runtime readiness..."
scripts/check-nccl-readiness.sh

if [[ "${RUN_NCCL:-0}" != "1" ]]; then
  cat <<'EOF'
NCCL readiness passed, but RUN_NCCL is not set.

Set RUN_NCCL=1 only after:
- raw RoCE is passing at the expected performance class;
- NCCL readiness passes on all four Sparks;
- cluster SSH aliases or MPI host targets have been verified.
EOF
  exit 0
fi

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
SPARK1_MGMT="${SPARK1_MGMT:-spark-a.example}"
MPI_HOSTS="${MPI_HOSTS:-spark-a.example:1,spark-b.example:1,spark-c.example:1,spark-d.example:1}"
NCCL_TEST_BIN="${NCCL_TEST_BIN:-/opt/public-cluster/nccl-tests/build/all_reduce_perf}"
NCCL_LOG="${NCCL_LOG:-/opt/public-cluster/nccl-four-node-all-reduce.log}"

SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY" "${SSH_OPTS[@]}")
fi

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SPARK1_MGMT}" "
  set -euo pipefail
  export UCX_NET_DEVICES=\${UCX_NET_DEVICES:-enp1s0f0np0,enP2p1s0f0np0}
  export NCCL_SOCKET_IFNAME=\${NCCL_SOCKET_IFNAME:-enp1s0f0np0,enP2p1s0f0np0}
  export NCCL_IB_DISABLE=\${NCCL_IB_DISABLE:-0}
  export NCCL_IB_HCA=\${NCCL_IB_HCA:-rocep1s0f0,roceP2p1s0f0}
  export NCCL_NET_GDR_LEVEL=\${NCCL_NET_GDR_LEVEL:-2}
  export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\${LD_LIBRARY_PATH:-}
  mpirun -np 4 \
    -H '${MPI_HOSTS}' \
    --mca plm_rsh_agent 'ssh -o StrictHostKeyChecking=no' \
    -x UCX_NET_DEVICES \
    -x NCCL_SOCKET_IFNAME \
    -x NCCL_IB_DISABLE \
    -x NCCL_IB_HCA \
    -x NCCL_NET_GDR_LEVEL \
    -x NCCL_DEBUG=INFO \
    -x NCCL_DEBUG_SUBSYS=INIT,NET \
    -x LD_LIBRARY_PATH \
    '${NCCL_TEST_BIN}' -b 64M -e 1G -f 2 -g 1 2>&1 | tee '${NCCL_LOG}'
"
