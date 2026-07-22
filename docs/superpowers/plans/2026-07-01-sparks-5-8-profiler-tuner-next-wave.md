# Sparks 5-8 Profiler And Tuner Next Wave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and validate the next DGX Spark + CRS804 NCCL experiment wave: NCCL Inspector profiler telemetry first, then a size-aware tuner artifact, then continue with safe observability and switch-change preparation.

**Architecture:** Keep the existing Sparks 5-8 harness as the launcher and add narrow scripts that create ignored evidence directories. Build any NCCL plugin artifacts on Spark 5 from the upstream NCCL `v2.28.9-1` tag to match the installed `libnccl-dev 2.28.9-1+cuda13.0` ABI. Switch writes are allowed only after a current export, backup/rollback note, and explicit before/after evidence are captured.

**Tech Stack:** Bash, OpenMPI, NCCL tests, NCCL profiler/tuner plugin envs, RouterOS SSH, Markdown evidence summaries.

---

## File Structure

- Modify: `scripts/run-sparks58-nccl-profile.sh`
  - Pass optional profiler, tuner, RAS, OOB, and QoS-related NCCL environment variables through MPI.
- Create: `scripts/build-spark5-nccl-inspector.sh`
  - Clone or update NVIDIA NCCL `v2.28.9-1` on Spark 5 and build `plugins/profiler/inspector/libnccl-profiler-inspector.so`.
- Create: `scripts/run-sparks58-nccl-inspector.sh`
  - Run the existing profile harness with Inspector variables enabled, pull Inspector JSON/Prometheus files, and summarize whether profiler telemetry was emitted.
- Create: `scripts/generate-sparks58-size-policy.sh`
  - Convert the known size-aware evidence into a reusable policy table and env-profile selector for current NCCL env-based execution.
- Create: `scripts/run-sparks58-size-policy.sh`
  - Run one selected policy matrix and compare policy-selected runs against the static 256MiB profile.
- Create: `scripts/capture-crs804-rollback-state.sh`
  - Capture `/export`, current QoS/port state, and a rollback command note before any switch writes.
- Create: `docs/sparks-5-8-profiler-tuner-next-wave-2026-07-01.md`
  - Durable tracked report for the profiler, tuner, telemetry, and switch-safety work.
- Evidence: `evidence/nccl-next-wave-5-8-<timestamp>/`
  - Ignored raw logs, pulled plugin build output, Inspector output, policy tables, benchmark logs, and switch snapshots.

## Tasks

### Task 1: Harness Env Pass-Through

**Files:**
- Modify: `scripts/run-sparks58-nccl-profile.sh`

- [ ] **Step 1: Add optional NCCL env pass-through**

Allow these variables to pass into the remote MPI job when defined:

```bash
NCCL_PROFILER_PLUGIN
NCCL_INSPECTOR_ENABLE
NCCL_INSPECTOR_ENABLE_P2P
NCCL_INSPECTOR_DUMP_THREAD_ENABLE
NCCL_INSPECTOR_DUMP_THREAD_INTERVAL_MICROSECONDS
NCCL_INSPECTOR_DUMP_DIR
NCCL_INSPECTOR_DUMP_VERBOSE
NCCL_INSPECTOR_PROM_DUMP
NCCL_INSPECTOR_DUMP_MIN_SIZE_BYTES
NCCL_INSPECTOR_REQUIRE_KERNEL_TIMING
NCCL_TUNER_PLUGIN
NCCL_TUNER_CONFIG
NCCL_RAS_ENABLE
NCCL_RAS_ADDR
NCCL_OOB_NET_ENABLE
NCCL_OOB_NET_IFNAME
NCCL_IB_TC
NCCL_IB_FIFO_TC
```

- [ ] **Step 2: Syntax check**

Run:

```bash
bash -n scripts/run-sparks58-nccl-profile.sh
```

Expected: exit `0`.

### Task 2: NCCL Inspector Build And Probe

**Files:**
- Create: `scripts/build-spark5-nccl-inspector.sh`
- Create: `scripts/run-sparks58-nccl-inspector.sh`
- Evidence: `task01-inspector-build/`, `task02-inspector-run/`

- [ ] **Step 1: Build matching Inspector plugin on Spark 5**

Clone or fetch NVIDIA NCCL `v2.28.9-1` under `/opt/public-user/src/nccl-v2.28.9-1`, then build `plugins/profiler/inspector`.

- [ ] **Step 2: Run a short four-node Inspector-enabled NCCL job**

Use the profile harness with:

```bash
NCCL_PROFILER_PLUGIN=$HOME/src/nccl-v2.28.9-1/plugins/profiler/inspector/libnccl-profiler-inspector.so
NCCL_INSPECTOR_ENABLE=1
NCCL_INSPECTOR_DUMP_THREAD_INTERVAL_MICROSECONDS=500000
NCCL_INSPECTOR_DUMP_DIR=/var/tmp/public-run/sparks58-nccl-inspector-<stamp>
NCCL_DEBUG=INFO
NCCL_DEBUG_SUBSYS=PROFILE
```

- [ ] **Step 3: Pull and summarize Inspector output**

Expected: either JSON/Prometheus output files exist, or the summary records the exact build/runtime blocker.

### Task 3: Size-Aware Policy Artifact

**Files:**
- Create: `scripts/generate-sparks58-size-policy.sh`
- Create: `scripts/run-sparks58-size-policy.sh`
- Evidence: `task03-size-policy/`, `task04-size-policy-verify/`

- [ ] **Step 1: Generate the current policy table**

Create a TSV policy with the current best-by-size choices:

```text
8K baseline
64K channels8
1M channels8
8M channels8
32M channels8
256M qps4split1-ch8-ignore
1G qps4split1
4G qps4split1
```

- [ ] **Step 2: Run policy verification**

Run the selected policy over the same size points with low iteration counts and summarize bus bandwidth and wrong counts.

Expected: every selected size returns exit `0` and wrong `0`; deviations from the previous best table are documented.

### Task 4: CRS804 Telemetry Recorder

**Files:**
- Create or update: `scripts/capture-crs804-nccl-telemetry.sh`
- Evidence: `task05-crs804-telemetry/`

- [ ] **Step 1: Capture RouterOS stats once per second during NCCL**

Sample read-only stats and QoS monitor output during a tuned 256MiB NCCL run.

- [ ] **Step 2: Summarize counter deltas**

Expected: summary includes queue, drop, FEC, and pool-use deltas.

### Task 5: Switch Rollback Gate For Future Writes

**Files:**
- Create: `scripts/capture-crs804-rollback-state.sh`
- Create or update: `docs/crs804-switch-change-rollback-2026-07-01.md`
- Evidence: `task06-switch-rollback-state/`

- [ ] **Step 1: Capture current CRS804 export and readable QoS state**

Run RouterOS read-only `/export terse`, port details, QoS profiles, maps, queue managers, PFC profiles, and monitor output.

- [ ] **Step 2: Generate rollback command note**

Expected: doc includes fallback commands to restore active Sparks 5-8 ports to the current known-good shape before any later switch-write test.

### Task 6: Final Verification

**Files:**
- Modify: `docs/sparks-5-8-profiler-tuner-next-wave-2026-07-01.md`

- [ ] **Step 1: Run syntax checks**

Run:

```bash
bash -n scripts/*.sh
```

- [ ] **Step 2: Verify evidence and process cleanup**

Confirm raw evidence is ignored and no stray `mpirun`, `orted`, `all_reduce_perf`, or `all_gather_perf` processes remain.

- [ ] **Step 3: Record git status**

Run:

```bash
git status --short --branch
```
