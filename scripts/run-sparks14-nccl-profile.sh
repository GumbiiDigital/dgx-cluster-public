#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_FILE="${PROFILE_FILE:-${SCRIPT_DIR}/sparks14-nccl-profile.env}"
export PROFILE_FILE

exec "${SCRIPT_DIR}/run-sparks58-nccl-profile.sh" "$@"
