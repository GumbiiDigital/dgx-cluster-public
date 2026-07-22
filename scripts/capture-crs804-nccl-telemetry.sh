#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

CRS804_SSH="${CRS804_SSH:-public-admin@192.0.2.10}"
CRS804_KEY="${CRS804_KEY:-$HOME/.ssh/crs804_dgx_temp_ed25519}"
PORT_EXPR="${PORT_EXPR:-name=\"fabric-port-e\" or name=\"fabric-port-f\" or name=\"fabric-port-g\" or name=\"fabric-port-h\"}"
OUT_DIR="${OUT_DIR:-evidence/crs804-nccl-telemetry-$(date +%Y%m%d-%H%M%S)}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-1}"
NCCL_REPEATS="${NCCL_REPEATS:-3}"

mkdir -p "$OUT_DIR/samples"

SSH_OPTS=(-i "$CRS804_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

routeros() {
  ssh "${SSH_OPTS[@]}" "$CRS804_SSH" "$@"
}

capture_sample() {
  local label="$1"
  routeros >"$OUT_DIR/samples/${label}.txt" <<ROUTEROS
:put "sample=${label}"
:put "timestamp=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
/interface ethernet print stats where ${PORT_EXPR}
/interface ethernet switch qos monitor once
/interface ethernet switch qos port print stats where ${PORT_EXPR}
/interface ethernet switch qos port print usage where ${PORT_EXPR}
ROUTEROS
}

capture_sample "000-before"

set +e
OUT_DIR="$OUT_DIR/nccl-run" \
PROFILE_FILE="${PROFILE_FILE:-}" \
REPEATS="$NCCL_REPEATS" \
ITERS="${ITERS:-80}" \
WARMUP_ITERS="${WARMUP_ITERS:-10}" \
CONFIG_LABEL_OVERRIDE="${CONFIG_LABEL_OVERRIDE:-${CONFIG_LABEL:-crs804-telemetry-256M}}" \
scripts/run-sparks58-nccl-profile.sh >"$OUT_DIR/nccl.stdout" 2>&1 &
nccl_pid=$!
set -e

idx=1
while kill -0 "$nccl_pid" 2>/dev/null; do
  capture_sample "$(printf '%03d-during' "$idx")" || true
  idx=$((idx + 1))
  sleep "$SAMPLE_INTERVAL"
done

set +e
wait "$nccl_pid"
nccl_rc=$?
set -e

capture_sample "$(printf '%03d-after' "$idx")"

{
  echo "# CRS804 NCCL Telemetry"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- CRS804 target: ${CRS804_SSH}"
  echo "- NCCL exit: ${nccl_rc}"
  echo "- Samples: $(find "$OUT_DIR/samples" -type f | wc -l | tr -d ' ')"
  echo
  echo "## NCCL Parsed Results"
  if [[ -f "$OUT_DIR/nccl-run/parsed.tsv" ]]; then
    cat "$OUT_DIR/nccl-run/parsed.tsv"
  else
    echo "No parsed NCCL results."
  fi
  echo
  echo "## First Sample Selected Counters"
  grep -E 'sample=|timestamp=|rx-error-events|rx-fcs-error|tx-queue[013]-packet|tx-drop|rs-fec|lossy-pool|lossless-pool|shared-byte-use|shared-packet-use|queue[0-7].*(packet|byte)' "$OUT_DIR/samples/000-before.txt" | sed -n '1,180p' || true
  echo
  echo "## Last Sample Selected Counters"
  last_sample="$(find "$OUT_DIR/samples" -type f | sort | tail -1)"
  grep -E 'sample=|timestamp=|rx-error-events|rx-fcs-error|tx-queue[013]-packet|tx-drop|rs-fec|lossy-pool|lossless-pool|shared-byte-use|shared-packet-use|queue[0-7].*(packet|byte)' "$last_sample" | sed -n '1,180p' || true
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
exit "$nccl_rc"
