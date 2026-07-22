#!/usr/bin/env bash
set -euo pipefail

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
NCCL_VERSION="${NCCL_VERSION:-2.28.9-1+cuda13.0}"

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

ssh_run() {
  local host="$1"
  shift
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "$@"
}

cat <<EOF
Target NCCL package version: ${NCCL_VERSION}

Default mode is dry-run. Set APPLY_NCCL_INSTALL=1 only after:
- raw RoCE passes;
- public-user approves package changes;
- this target version is confirmed on all four hosts.
EOF

failures=0

for host in "${HOSTS[@]}"; do
  echo "===== ${host} NCCL package prep ====="
  if ! ssh_run "$host" "NCCL_VERSION='${NCCL_VERSION}' APPLY_NCCL_INSTALL='${APPLY_NCCL_INSTALL:-0}' bash -s" <<'REMOTE'
set -euo pipefail
hostname
for pkg in libnccl2 libnccl-dev; do
  if ! apt-cache madison "$pkg" 2>/dev/null | awk -v ver="$NCCL_VERSION" '$3 == ver { found=1 } END { exit !found }'; then
    echo "MISSING-CANDIDATE: ${pkg}=${NCCL_VERSION}"
    exit 20
  fi
done
echo "Found libnccl2/libnccl-dev version ${NCCL_VERSION}"

cmd=(sudo apt-get install -y "libnccl2=${NCCL_VERSION}" "libnccl-dev=${NCCL_VERSION}")
if [[ "$APPLY_NCCL_INSTALL" == "1" ]]; then
  sudo apt-get update
  "${cmd[@]}"
else
  printf "DRY-RUN:"
  printf " %q" "${cmd[@]}"
  printf "\n"
fi
REMOTE
  then
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  echo "NCCL package prep failed on ${failures} host(s)."
  exit 1
fi

if [[ "${APPLY_NCCL_INSTALL:-0}" == "1" ]]; then
  echo "NCCL packages installed. Re-run scripts/check-nccl-readiness.sh."
else
  echo "Dry-run complete. No packages were installed."
fi
