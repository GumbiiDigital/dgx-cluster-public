#!/usr/bin/env bash
set -euo pipefail

if grep -Fq "192.0.2.10" "$0"; then
  printf "%s\n" "This public template contains redacted address placeholders. Copy it to a private configuration and replace those values before running." >&2
  exit 2
fi

CRS804_SSH="${CRS804_SSH:-public-admin@192.0.2.10}"
APPLY_SWITCH="${APPLY_SWITCH:-0}"
L2MTU="${L2MTU:-9216}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-evidence/crs804-fec91-l2mtu-${STAMP}}"

PORTS=(
  fabric-port-a
  fabric-port-b
  fabric-port-c
  fabric-port-d
)

PORT_EXPR='name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"'
BRIDGE_PORT_EXPR='interface="fabric-port-a" or interface="fabric-port-b" or interface="fabric-port-c" or interface="fabric-port-d"'

mkdir -p "$OUT_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$OUT_DIR/run.log"
}

routeros() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$CRS804_SSH" "$@"
}

capture_switch() {
  local label="$1"
  log "Capturing CRS804 state: ${label}"
  routeros >"$OUT_DIR/switch-${label}.txt" <<ROUTEROS
/system resource print
/system routerboard print
/interface ethernet switch print detail
/interface bridge print detail where name="cluster-bridge"
/interface bridge port print detail where ${BRIDGE_PORT_EXPR}
/interface ethernet monitor fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d once
/interface ethernet print detail where ${PORT_EXPR}
/interface ethernet print stats where ${PORT_EXPR}
/interface ethernet switch qos port print detail where ${PORT_EXPR}
ROUTEROS
}

write_routeros_plan() {
  local plan="$OUT_DIR/apply-fec91-l2mtu.rsc"
  {
    echo "/export file=crs804-before-fec91-l2mtu-${STAMP}"
    echo "/system backup save name=crs804-before-fec91-l2mtu-${STAMP}"
    echo "/interface ethernet"
    for port in "${PORTS[@]}"; do
      printf 'set [find name="%s"] speed=200G-baseCR4 fec-mode=fec91 mtu=9000 l2mtu=%s\n' "$port" "$L2MTU"
    done
    echo "/interface ethernet monitor fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d once"
    echo "/interface ethernet print detail where ${PORT_EXPR}"
  } >"$plan"
  log "Wrote RouterOS plan: ${plan}"
}

apply_switch() {
  log "Saving CRS804 export and backup before FEC/L2MTU test"
  routeros "/export file=crs804-before-fec91-l2mtu-${STAMP}; /system backup save name=crs804-before-fec91-l2mtu-${STAMP}" \
    >"$OUT_DIR/switch-backup.log" 2>&1

  log "Applying fec-mode=fec91 mtu=9000 l2mtu=${L2MTU} to Spark CRS804 ports"
  for port in "${PORTS[@]}"; do
    routeros "/interface ethernet set [find name=\"${port}\"] speed=200G-baseCR4 fec-mode=fec91 mtu=9000 l2mtu=${L2MTU}" \
      >"$OUT_DIR/apply-${port}.log" 2>&1
  done
}

write_summary() {
  {
    echo "# CRS804 FEC91/L2MTU Test"
    echo
    echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- CRS804 target: ${CRS804_SSH}"
    echo "- APPLY_SWITCH: ${APPLY_SWITCH}"
    echo "- Requested L2MTU: ${L2MTU}"
    echo "- Output directory: ${OUT_DIR}"
    echo
    echo "## Current/After State"
    local latest
    latest="$(ls -1 "$OUT_DIR"/switch-*.txt 2>/dev/null | tail -1 || true)"
    if [[ -n "$latest" ]]; then
      grep -E 'name="qsfp56-dd|mtu=|l2mtu=|speed=|fec-mode=|tx-drop-packet|rx-error-events|rs-fec' "$latest" | sed -n '1,220p'
    fi
    echo
    echo "## Next Verification"
    echo
    echo 'Run `scripts/verify-roce-underlay.sh` after the ports return to `200G-baseCR4`.'
  } >"$OUT_DIR/SUMMARY.md"
  log "Wrote summary: $OUT_DIR/SUMMARY.md"
}

log "Output directory: ${OUT_DIR}"
capture_switch "before"
write_routeros_plan

if [[ "$APPLY_SWITCH" != "1" ]]; then
  log "Dry run only. Re-run with APPLY_SWITCH=1 to apply the RouterOS plan."
  write_summary
  exit 0
fi

apply_switch
capture_switch "after"
write_summary
log "Complete"
