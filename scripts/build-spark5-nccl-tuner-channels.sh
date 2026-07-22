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
MPI_KEY="${MPI_KEY:-/opt/public-user/.ssh/dgx_cluster_mpi_ed25519}"
REMOTE_TAG="${REMOTE_TAG:-v2.28.9-1}"
REMOTE_NCCL_SRC="${REMOTE_NCCL_SRC:-/opt/public-user/src/nccl-${REMOTE_TAG}}"
REMOTE_BUILD_DIR="${REMOTE_BUILD_DIR:-/opt/public-user/src/sparks58-tuner-channels}"
REMOTE_PLUGIN="${REMOTE_BUILD_DIR}/libnccl-tuner-sparks58-channels.so"
PEERS="${PEERS:-192.0.2.10 192.0.2.10 192.0.2.10}"
GROUP_LABEL="${GROUP_LABEL:-Sparks 5-8}"
PEER_LABEL="${PEER_LABEL:-Sparks 6-8}"
OUT_DIR="${OUT_DIR:-evidence/nccl-tuner-channels-build-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUT_DIR"

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new)

log="$OUT_DIR/build.log"
set +e
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${LAUNCHER}" \
  "REMOTE_TAG='${REMOTE_TAG}' REMOTE_NCCL_SRC='${REMOTE_NCCL_SRC}' REMOTE_BUILD_DIR='${REMOTE_BUILD_DIR}' MPI_KEY='${MPI_KEY}' PEERS='${PEERS}' bash -s" >"$log" 2>&1 <<'REMOTE'
set -euo pipefail
REMOTE_TAG="${REMOTE_TAG:-v2.28.9-1}"
REMOTE_NCCL_SRC="${REMOTE_NCCL_SRC:-/opt/public-cluster/src/nccl-${REMOTE_TAG}}"
REMOTE_BUILD_DIR="${REMOTE_BUILD_DIR:-/opt/public-cluster/src/sparks58-tuner-channels}"
REMOTE_PLUGIN="${REMOTE_BUILD_DIR}/libnccl-tuner-sparks58-channels.so"
MPI_KEY="${MPI_KEY:-/opt/public-user/.ssh/dgx_cluster_mpi_ed25519}"
PEERS="${PEERS:-192.0.2.10 192.0.2.10 192.0.2.10}"

if [[ ! -d "${REMOTE_NCCL_SRC}/.git" ]]; then
  mkdir -p "$(dirname "${REMOTE_NCCL_SRC}")"
  git clone --depth 1 --branch "${REMOTE_TAG}" https://github.com/NVIDIA/nccl.git "${REMOTE_NCCL_SRC}"
fi

rm -rf "${REMOTE_BUILD_DIR}"
mkdir -p "${REMOTE_BUILD_DIR}"
cp -a "${REMOTE_NCCL_SRC}/ext-tuner/example/nccl" "${REMOTE_BUILD_DIR}/"
cat >"${REMOTE_BUILD_DIR}/plugin.c" <<'C'
#include "nccl/tuner.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define __hidden __attribute__ ((visibility("hidden")))
#define MAX_CONFIGS 64
#define MAX_LINE 256

typedef struct {
  size_t minBytes;
  size_t maxBytes;
  int channels;
  int nNodes;
  int nRanks;
} SparkTikRule;

typedef struct {
  SparkTikRule rules[MAX_CONFIGS];
  int nrules;
  size_t nRanks;
  size_t nNodes;
  ncclDebugLogger_t log;
} SparkTikCtx;

static ncclResult_t loadRules(SparkTikCtx* ctx, const char* path) {
  FILE* f = fopen(path, "r");
  if (!f) {
    if (ctx->log) ctx->log(NCCL_LOG_INFO, NCCL_TUNING, __FILE__, __LINE__,
      "TUNER/SparkTikChannels: config file %s not found", path);
    return ncclSuccess;
  }

  char line[MAX_LINE];
  while (fgets(line, sizeof(line), f) && ctx->nrules < MAX_CONFIGS) {
    if (line[0] == '#' || line[0] == '\n') continue;
    line[strcspn(line, "\n")] = 0;

    char copy[MAX_LINE];
    strncpy(copy, line, sizeof(copy));
    copy[sizeof(copy) - 1] = '\0';

    char* fields[10] = {0};
    int n = 0;
    char* tok = strtok(copy, ",");
    while (tok && n < 10) {
      while (*tok == ' ' || *tok == '\t') tok++;
      char* end = tok + strlen(tok) - 1;
      while (end > tok && (*end == ' ' || *end == '\t')) {
        *end = '\0';
        end--;
      }
      fields[n++] = tok;
      tok = strtok(NULL, ",");
    }
    if (n < 8 || strcmp(fields[0], "allreduce") != 0) continue;

    SparkTikRule* r = &ctx->rules[ctx->nrules++];
    r->minBytes = (size_t)strtoull(fields[1], NULL, 10);
    r->maxBytes = (size_t)strtoull(fields[2], NULL, 10);
    r->channels = atoi(fields[5]);
    r->nNodes = atoi(fields[6]);
    r->nRanks = atoi(fields[7]);
    if (ctx->log) ctx->log(NCCL_LOG_INFO, NCCL_TUNING, __FILE__, __LINE__,
      "TUNER/SparkTikChannels: loaded allreduce [%zu-%zu] channels=%d nodes=%d ranks=%d",
      r->minBytes, r->maxBytes, r->channels, r->nNodes, r->nRanks);
  }
  fclose(f);
  return ncclSuccess;
}

__hidden ncclResult_t pluginInit(void** context, uint64_t commId, size_t nRanks, size_t nNodes,
    ncclDebugLogger_t logFunction, ncclNvlDomainInfo_v5_t* nvlDomainInfo, ncclTunerConstants_v5_t* constants) {
  (void)commId;
  (void)nvlDomainInfo;
  (void)constants;
  SparkTikCtx* ctx = (SparkTikCtx*)calloc(1, sizeof(SparkTikCtx));
  if (!ctx) return ncclSystemError;
  ctx->nRanks = nRanks;
  ctx->nNodes = nNodes;
  ctx->log = logFunction;
  const char* config = getenv("NCCL_TUNER_CONFIG_FILE");
  if (!config) config = "nccl_tuner.conf";
  if (ctx->log) ctx->log(NCCL_LOG_INFO, NCCL_TUNING, __FILE__, __LINE__,
    "TUNER/SparkTikChannels: init nodes=%zu ranks=%zu config=%s", nNodes, nRanks, config);
  ncclResult_t rc = loadRules(ctx, config);
  if (rc != ncclSuccess) {
    free(ctx);
    return rc;
  }
  *context = ctx;
  return ncclSuccess;
}

__hidden ncclResult_t pluginGetCollInfo(void* context, ncclFunc_t collType, size_t nBytes,
    int numPipeOps, float** collCostTable, int numAlgo, int numProto, int regBuff, int* nChannels) {
  (void)numPipeOps;
  (void)collCostTable;
  (void)numAlgo;
  (void)numProto;
  (void)regBuff;
  SparkTikCtx* ctx = (SparkTikCtx*)context;
  if (!ctx) return ncclInternalError;
  if (collType != ncclFuncAllReduce) return ncclSuccess;

  for (int i = 0; i < ctx->nrules; i++) {
    SparkTikRule* r = &ctx->rules[i];
    int nodeMatch = (r->nNodes == -1 || r->nNodes == (int)ctx->nNodes);
    int rankMatch = (r->nRanks == -1 || r->nRanks == (int)ctx->nRanks);
    if (nBytes >= r->minBytes && nBytes <= r->maxBytes && nodeMatch && rankMatch) {
      if (r->channels > 0) {
        *nChannels = r->channels;
        if (ctx->log) ctx->log(NCCL_LOG_INFO, NCCL_TUNING, __FILE__, __LINE__,
          "TUNER/SparkTikChannels: applied channels=%d bytes=%zu nodes=%zu ranks=%zu",
          r->channels, nBytes, ctx->nNodes, ctx->nRanks);
      } else if (ctx->log) {
        ctx->log(NCCL_LOG_INFO, NCCL_TUNING, __FILE__, __LINE__,
          "TUNER/SparkTikChannels: kept default channels bytes=%zu nodes=%zu ranks=%zu",
          nBytes, ctx->nNodes, ctx->nRanks);
      }
      return ncclSuccess;
    }
  }
  return ncclSuccess;
}

__hidden ncclResult_t pluginFinalize(void* context) {
  free(context);
  return ncclSuccess;
}

const ncclTuner_v5_t ncclTunerPlugin_v5 = {
  .name = "SparkTikChannels",
  .init = pluginInit,
  .getCollInfo = pluginGetCollInfo,
  .finalize = pluginFinalize
};
C

gcc -I"${REMOTE_BUILD_DIR}" -fPIC -shared -O2 -Wall -Wextra \
  -o "${REMOTE_PLUGIN}" -Wl,-soname,libnccl-tuner-sparks58-channels.so \
  "${REMOTE_BUILD_DIR}/plugin.c"
test -s "${REMOTE_PLUGIN}"
file "${REMOTE_PLUGIN}" || true

for h in ${PEERS}; do
  echo "===== syncing channels tuner to ${h} ====="
  ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "${h}" "mkdir -p '${REMOTE_BUILD_DIR}'"
  scp -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "${REMOTE_PLUGIN}" "${h}:${REMOTE_PLUGIN}"
  ssh -i ${MPI_KEY} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no "${h}" "test -s '${REMOTE_PLUGIN}' && ls -lh '${REMOTE_PLUGIN}'"
done
echo "plugin=${REMOTE_PLUGIN}"
REMOTE
rc=$?
set -e

{
  echo "# ${GROUP_LABEL} Channels Tuner Build"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Remote plugin: ${REMOTE_PLUGIN}"
  echo "- Exit: ${rc}"
  echo
  if [[ "$rc" -eq 0 ]]; then
    echo "PASS: channels-only tuner plugin built and synced to ${PEER_LABEL}."
  else
    echo "FAIL: channels-only tuner build or sync failed. See build.log."
  fi
  echo
  rg -n 'plugin=|libnccl-tuner-sparks58-channels|syncing channels|error:|Error|FAIL|No such file|undefined reference' "$log" || true
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
exit "$rc"
