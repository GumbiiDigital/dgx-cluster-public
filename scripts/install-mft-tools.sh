#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

KEY_DEFAULT="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
SSH_USER="${SSH_USER:-public-user}"
SSH_KEY="${SSH_KEY:-$KEY_DEFAULT}"
SSH_OPTS=(-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
MFT_VERSION="${MFT_VERSION:-}"

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

cat <<EOF
NVIDIA MFT package prep

Default mode is dry-run. Set APPLY_MFT_INSTALL=1 only after:
- passwordless sudo works on all four Sparks;
- public-user approves package changes;
- the candidate version is acceptable on all four hosts.

Optional: set MFT_VERSION=<version> to pin the install, for example:
  MFT_VERSION=192.0.2.10-1 APPLY_MFT_INSTALL=1 $0
EOF

failures=0

for host in "${HOSTS[@]}"; do
  echo "===== ${host} MFT package prep ====="
  if ! ssh_run "$host" "MFT_VERSION='${MFT_VERSION}' APPLY_MFT_INSTALL='${APPLY_MFT_INSTALL:-0}' bash -s" <<'REMOTE'
set -euo pipefail
hostname

if ! sudo -n true 2>/dev/null; then
  echo "MISSING-SUDO: passwordless sudo is required for MFT install"
  exit 10
fi

echo "Current MFT state:"
dpkg-query -W mft 2>/dev/null || true
  for tool in mst mlxlink mlxfwmanager mlxconfig mstflint; do
    command -v "$tool" || echo "${tool}: missing"
  done
  command -v mlxstat || echo "mlxstat: missing (optional on this MFT package)"

echo "Available MFT candidates:"
apt-cache policy mft | sed -n '1,12p'

pkg="mft"
if [[ -n "$MFT_VERSION" ]]; then
  if ! apt-cache madison mft 2>/dev/null | awk -v ver="$MFT_VERSION" '$3 == ver { found=1 } END { exit !found }'; then
    echo "MISSING-CANDIDATE: mft=${MFT_VERSION}"
    exit 20
  fi
  pkg="mft=${MFT_VERSION}"
fi

cmd=(sudo apt-get install -y "$pkg")
if [[ "$APPLY_MFT_INSTALL" == "1" ]]; then
  sudo apt-get update
  "${cmd[@]}"
  for tool in mst mlxlink mlxfwmanager mlxconfig mstflint; do
    command -v "$tool" || { echo "MISSING-TOOL-AFTER-INSTALL: $tool"; exit 30; }
  done
  command -v mlxstat || echo "OPTIONAL-TOOL-MISSING-AFTER-INSTALL: mlxstat"
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
  echo "MFT package prep failed on ${failures} host(s)."
  exit 1
fi

if [[ "${APPLY_MFT_INSTALL:-0}" == "1" ]]; then
  echo "MFT installed. Run scripts/capture-mft-evidence.sh next."
else
  echo "Dry-run complete. No packages were installed."
fi
