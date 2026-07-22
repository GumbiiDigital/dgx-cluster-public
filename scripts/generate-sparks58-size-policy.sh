#!/usr/bin/env bash
set -euo pipefail

POLICY_PREFIX="${POLICY_PREFIX:-sparks58}"
GROUP_LABEL="${GROUP_LABEL:-Sparks 5-8}"
OUT_DIR="${OUT_DIR:-evidence/${POLICY_PREFIX}-size-policy-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"

policy_tsv="$OUT_DIR/${POLICY_PREFIX}-size-policy.tsv"
tuner_conf="$OUT_DIR/${POLICY_PREFIX}-nccl-tuner.conf"
env_matrix="$OUT_DIR/${POLICY_PREFIX}-size-env-matrix.tsv"

cat >"$policy_tsv" <<'TSV'
size	min_bytes	max_bytes	best_config	avg_bus_GBs	env_profile	tuner_algo	tuner_proto	tuner_channels
8K	0	8192	baseline	0.226138	baseline	ring	simple	-1
64K	8193	65536	channels8	1.20046	channels8	ring	simple	8
1M	65537	1048576	channels8	4.8328	channels8	ring	simple	8
8M	1048577	8388608	channels8	8.43228	channels8	ring	simple	8
32M	8388609	33554432	channels8	23.1458	channels8	ring	simple	8
256M	33554433	268435456	qps4split1-ch8-ignore	23.8216	qps4split1-ch8-ignore	ring	simple	8
1G	268435457	1073741824	qps4split1	24.1885	qps4split1	ring	simple	-1
4G	1073741825	4294967296	qps4split1	24.2944	qps4split1	ring	simple	-1
TSV

cat >"$tuner_conf" <<CONF
# ${GROUP_LABEL} CRS804 size-aware tuner prototype.
# Format: collective_type,min_bytes,max_bytes,algorithm,protocol,channels,nNodes,nRanks,numPipeOps,regBuff
# The plugin can steer NCCL algorithm/protocol/channels. QP settings remain env-level.
allreduce,0,8192,ring,simple,-1,4,4,-1,-1
allreduce,8193,65536,ring,simple,8,4,4,-1,-1
allreduce,65537,1048576,ring,simple,8,4,4,-1,-1
allreduce,1048577,8388608,ring,simple,8,4,4,-1,-1
allreduce,8388609,33554432,ring,simple,8,4,4,-1,-1
allreduce,33554433,268435456,ring,simple,8,4,4,-1,-1
allreduce,268435457,1073741824,ring,simple,-1,4,4,-1,-1
allreduce,1073741825,4294967296,ring,simple,-1,4,4,-1,-1
CONF

printf '%s\\n' \\
  'env_profile\\tAPPLY_TUNED_DEFAULTS\\tNCCL_IB_QPS_PER_CONNECTION\\tNCCL_IB_SPLIT_DATA_ON_QPS\\tNCCL_MIN_NCHANNELS\\tNCCL_MAX_NCHANNELS\\tNCCL_IGNORE_CPU_AFFINITY' \\
  'baseline\\t0\\t\\t\\t\\t\\t' \\
  'channels8\\t0\\t\\t\\t8\\t8\\t' \\
  'qps4split1\\t0\\t4\\t1\\t\\t\\t' \\
  'qps4split1-ch8-ignore\\t0\\t4\\t1\\t8\\t8\\t1' >"$env_matrix"

{
  echo "# ${GROUP_LABEL} Size-Aware Policy"
  echo
  echo "- Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Policy TSV"
  echo
  cat "$policy_tsv"
  echo
  echo "## NCCL Tuner Config"
  echo
  cat "$tuner_conf"
  echo
  echo "## Env Matrix"
  echo
  cat "$env_matrix"
} >"$OUT_DIR/SUMMARY.md"

cat "$OUT_DIR/SUMMARY.md"
