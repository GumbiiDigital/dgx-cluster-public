#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a
# shellcheck disable=SC1091
source "${PROFILE_FILE:-${SCRIPT_DIR}/sparks14-nccl-profile.env}"
set +a

OUT_DIR="${OUT_DIR:-evidence/sparks14-nccl-inspector-build-$(date +%Y%m%d-%H%M%S)}"
export OUT_DIR

exec "${SCRIPT_DIR}/build-spark5-nccl-inspector.sh" "$@"
