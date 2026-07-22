# Sparks 5-8 NCCL Experiment Program Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Execute and document the ten-lane DGX Spark + CRS804 NCCL experiment program without switch writes, stopping only when physical hardware changes are required.

**Architecture:** Preserve the current known-good Sparks 5-8 fabric as the public-root truth surface. Add a repeatable local harness that launches from Spark 5 over LAN management, fans out over the `198.51.100/203.0.113` CRS804 fabric, pins OpenMPI control traffic to `enp1s0f1np1`, captures read-only CRS804 evidence, and writes ignored raw evidence plus tracked documentation summaries.

**Tech Stack:** Bash, OpenMPI, NCCL tests, RouterOS read-only SSH, Nsight Systems when installed, local Markdown documentation.

---

## File Structure

- Create: `scripts/run-sparks58-nccl-profile.sh`
  - Runs the tuned Sparks 5-8 NCCL profile with configurable collective, size range, repeat count, OpenMPI control-plane pinning, and read-only CRS804 sampling.
- Create: `scripts/check-mpi-fabric-control-plane.sh`
  - Fails if MPI hostname smoke or process output shows LAN, Tailscale, Docker, or unexpected interface use for the Spark-to-Spark control plane.
- Create: `docs/sparks-5-8-nccl-experiment-program-2026-07-01.md`
  - Tracked durable summary for all ten lanes.
- Create/update ignored evidence under `evidence/nccl-experiment-program-5-8-<timestamp>/`.
  - Raw logs, parsed TSVs, topology dumps, counter snapshots, profiling output, workload attempts, and scaling blockers.
- Modify: `docs/sparks-5-8-nccl-tuning-2026-07-01.md`
  - Add a pointer to the broader experiment program once complete.

## Execution Order

1. Productize the tuned profile into a repeatable harness.
2. Build a control-plane leak detector.
3. Capture NCCL topology and graph evidence.
4. Run size-aware tuning sweeps.
5. Run RoCE/GID path audit.
6. Run read-only CRS804 queue-classification correlation.
7. Run Nsight Systems profiling if available.
8. Run a real workload validation if a suitable installed workload exists; otherwise record the exact missing dependency.
9. Prototype the tuner/profile artifact; prefer a static NCCL profile first, then document tuner-plugin feasibility.
10. Run available scaling curves and stop at the first physical cable boundary for unavailable nodes.

### Task 1: Tuned Profile Harness

**Files:**
- Create: `scripts/run-sparks58-nccl-profile.sh`
- Evidence: `evidence/nccl-experiment-program-5-8-<timestamp>/task01-profile/`

- [x] **Step 1: Write the harness**

Create a Bash script that:
- Uses `/opt/public-user/.ssh/id_ed25519` for Mac to Spark 5 LAN SSH.
- Uses Spark 5 local `/opt/public-user/.ssh/dgx_cluster_mpi_ed25519` for fabric fanout.
- Defaults to launcher `192.0.2.10`.
- Defaults to hosts `192.0.2.10:1,192.0.2.10:1,192.0.2.10:1,192.0.2.10:1`.
- Exports the tuned env:
  `NCCL_IB_QPS_PER_CONNECTION=4`,
  `NCCL_IB_SPLIT_DATA_ON_QPS=1`,
  `NCCL_MIN_NCHANNELS=8`,
  `NCCL_MAX_NCHANNELS=8`,
  `NCCL_IGNORE_CPU_AFFINITY=1`.
- Pins OpenMPI with:
  `--mca plm_rsh_no_tree_spawn 1`,
  `--mca oob_tcp_if_include enp1s0f1np1`,
  `--mca btl_tcp_if_include enp1s0f1np1`.
- Captures parsed TSV output.

- [x] **Step 2: Run fixed 256MiB verification**

Run:

```bash
OUT_DIR=evidence/nccl-experiment-program-5-8-$(date +%Y%m%d-%H%M%S)/task01-profile \
  scripts/run-sparks58-nccl-profile.sh
```

Expected:
- Exit `0`.
- `parsed.tsv` contains at least one row.
- Avg bus bandwidth is in the `23 GB/s` class.
- Wrong count is `0`.

### Task 2: Control-Plane Leak Detector

**Files:**
- Create: `scripts/check-mpi-fabric-control-plane.sh`
- Evidence: `evidence/nccl-experiment-program-5-8-<timestamp>/task02-control-plane/`

- [x] **Step 1: Write detector**

Create a Bash script that:
- Runs MPI hostname smoke using fabric hosts.
- Captures remote `orted` command lines during a short sleep command.
- Fails if command lines contain unexpected advertised addresses from:
  `198.51.100.`, `192.0.2.`, `203.0.113.`, or `DOCUMENTATION_IPV6_PLACEHOLDER`.
- Passes when pinned OpenMPI control-plane settings keep the job stable.

- [x] **Step 2: Verify detector**

Run:

```bash
OUT_DIR=evidence/nccl-experiment-program-5-8-$(date +%Y%m%d-%H%M%S)/task02-control-plane \
  scripts/check-mpi-fabric-control-plane.sh
```

Expected:
- Exit `0` for pinned path.
- Evidence includes hostname smoke output and process snapshots.

### Task 3: NCCL Topology and Graph Evidence

**Files:**
- Evidence: `task03-topology/`
- Update: `docs/sparks-5-8-nccl-experiment-program-2026-07-01.md`

- [x] **Step 1: Run NCCL with topology dump variables**

Run one tuned fixed-size job with:

```bash
NCCL_TOPO_DUMP_FILE=/var/tmp/public-run/sparks58-nccl-topo.xml
NCCL_GRAPH_DUMP_FILE=/var/tmp/public-run/sparks58-nccl-graph.xml
```

- [x] **Step 2: Pull dumps from Spark 5**

Copy `/var/tmp/public-run/sparks58-nccl-*.xml` from Spark 5 into the evidence directory if files exist.

- [x] **Step 3: Record whether NCCL accepted the dump variables**

Expected:
- Either topology/graph files exist, or the log clearly records that this NCCL version did not emit them.

### Task 4: Size-Aware Tuning Table

**Files:**
- Evidence: `task04-size-aware/`

- [x] **Step 1: Run selected configs across message sizes**

Test at least these configs:
- baseline tuned env absent except HCA/interface defaults
- `channels-8`
- `qps4-split1`
- `qps4split1-ch8-ignore`

Message sizes:
- `8K`, `64K`, `1M`, `8M`, `32M`, `256M`, `1G`, `4G`

- [x] **Step 2: Parse best config per size**

Expected:
- `summary.tsv` includes `size`, `config`, `avg_bus_GBs`, and `wrong`.
- `best-by-size.tsv` picks the best zero-wrong config per size.

### Task 5: RoCE/GID Path Audit

**Files:**
- Evidence: `task05-roce-gid/`

- [x] **Step 1: Capture GID and RDMA state on all four hosts**

From Spark 5, collect:

```bash
hostname
show_gids
ibdev2netdev
rdma link show
ip -br addr show enp1s0f1np1 enP2p1s0f1np1
```

- [x] **Step 2: Run a tuned NCCL INFO pass**

Run the tuned fixed `256MiB` profile with `NCCL_DEBUG=INFO` and `NCCL_DEBUG_SUBSYS=INIT,NET`.

- [x] **Step 3: Parse selected GID lines**

Expected:
- Summary names NCCL-selected HCA devices and GID lines.
- No switch writes.

### Task 6: CRS804 Queue Classification Correlation

**Files:**
- Evidence: `task06-queue-classification/`

- [x] **Step 1: Capture before counters**

Use read-only RouterOS SSH for:

```routeros
/interface ethernet print stats where name~"fabric-port-e|fabric-port-f|fabric-port-g|fabric-port-h"
```

- [x] **Step 2: Run tuned long enough to sample counters**

Run 10 repeats of fixed `256MiB` tuned profile while sampling switch stats.

- [x] **Step 3: Compare first/last counters**

Expected:
- Document whether queue1, queue3, drops, and FEC counters changed.

### Task 7: Nsight Systems Profiling

**Files:**
- Evidence: `task07-nsight/`

- [x] **Step 1: Check for `nsys` on Spark 5**

Run:

```bash
command -v nsys || true
nsys --version || true
```

- [x] **Step 2: If available, profile one tuned NCCL run**

Run:

```bash
nsys profile -t nccl,cuda -o /var/tmp/public-run/sparks58-nccl-tuned ...
```

- [x] **Step 3: If unavailable, document exact blocker**

Expected:
- Either `.nsys-rep` evidence exists, or a clear blocker file says `nsys` is not installed.

### Task 8: Real Workload Validation

**Files:**
- Evidence: `task08-real-workload/`

- [x] **Step 1: Inventory installed workload candidates**

Check Spark 5 for:

```bash
python3 - <<'PY'
import importlib.util
for name in ["torch", "transformers", "datasets", "deepspeed", "megatron"]:
    print(name, bool(importlib.util.find_spec(name)))
PY
```

- [x] **Step 2: If PyTorch distributed is available, run a minimal all-reduce workload**

Use `torchrun` or `mpirun` with tuned env over the four fabric hosts.

- [x] **Step 3: If no suitable workload exists, document the dependency blocker**

Expected:
- Evidence includes either workload timing or exact missing package/runtime blocker.

### Task 9: Tuner/Profile Artifact

**Files:**
- Create: `scripts/sparks58-nccl-profile.env`
- Evidence: `task09-profile-artifact/`
- Optional: `docs/sparks-5-8-nccl-tuner-plugin-notes-2026-07-01.md`

- [x] **Step 1: Create static env profile**

Write the best known-good env settings to `scripts/sparks58-nccl-profile.env`.

- [x] **Step 2: Verify the harness can source the profile**

Run one fixed `256MiB` tuned profile using the env file.

- [x] **Step 3: Document tuner-plugin feasibility**

Record whether a C tuner plugin is worth building now or whether the static env profile is the correct first artifact.

### Task 10: Scaling Curve and Physical Boundary

**Files:**
- Evidence: `task10-scaling/`

- [x] **Step 1: Run available 2-node and 4-node tuned curves on Sparks 5-8**

Pairs:
- 5-6
- 5-7
- 5-8
- 6-7
- 6-8
- 7-8

Four-node:
- 5-8 group

- [x] **Step 2: Probe whether Sparks 1-4 or 1-8 are physically cabled for the same f1 fabric**

Use read-only host/switch checks only.

- [x] **Step 3: Stop at physical boundary if missing cables are required**

Expected:
- If all 8 nodes are not physically available on the fabric, document the exact hardware boundary and stop the scaling lane there.

## Final Verification

- [x] Confirm no switch write commands were run.
- [x] Confirm no stray MPI/NCCL processes remain.
- [x] Confirm raw evidence is local/ignored unless explicitly approved.
- [x] Confirm tracked docs summarize each task and blockers.
- [x] Run `git status --short --branch`.
