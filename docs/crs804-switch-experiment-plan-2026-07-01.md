# CRS804 Switch Experiment Plan

Date: 2026-07-01

Status: planned only. No switch write commands were run while creating this
plan.

Goal: test whether CRS804-side QoS, queue, or port settings can improve
repeatability or queue classification beyond the already-working host-side
known-good profiles.

## Current Baseline

Both four-node groups can now reach target-class NCCL without switch writes:

| Group | Best fixed 256MiB class | Transport health |
| --- | ---: | --- |
| Sparks 1-4 | `23.82-23.86 GB/s` | ordered RDMA `111.85 Gbits/sec` per rail |
| Sparks 5-8 | `23.81-23.87 GB/s` | validated dual-rail CRS804 fabric |

Therefore switch work should be treated as optimization and classification
research, not as a prerequisite for correctness.

## Non-Negotiable Gates

Before every switch-write experiment:

1. Capture RouterOS export.
2. Capture binary backup.
3. Capture readable state for target ports.
4. Capture read-only counter baseline.
5. Record the exact rollback commands in the evidence directory.
6. Run the host-side known-good NCCL profile before changing switch state.

After every switch-write experiment:

1. Run the same host-side benchmark and counter capture.
2. Compare rx errors, FCS errors, tx drops, FEC corrected/uncorrected, and queue
   placement against baseline.
3. Roll back immediately if correctness fails, links flap, FEC uncorrected grows,
   or NCCL falls below the baseline class.

## Initial Target Ports

Sparks 1-4:

```text
fabric-port-a
fabric-port-b
fabric-port-c
fabric-port-d
```

Sparks 5-8:

```text
fabric-port-e
fabric-port-f
fabric-port-g
fabric-port-h
```

Known physical/port baseline:

```text
mtu=9000
l2mtu=9216
speed=200G-baseCR4
fec-mode=fec91
tx-flow-control=off
rx-flow-control=off
```

## Experiment Ladder

### 1. Baseline Repro

Purpose: verify the benchmark has not drifted before switch writes.

- Run fixed `256MiB` tuned NCCL x5 on the target four-node group.
- Capture CRS804 read-only counters during the run.
- Confirm wrong `0`, no new rx/FCS errors, no new tx drops, and no new FEC
  uncorrected growth.

### 2. Queue Classification Only

Purpose: understand whether CRS804 can classify RoCE traffic into a preferred
queue without improving or damaging performance.

Candidate tests:

- L3 trust off/default.
- L3 trust keep.
- Explicit host-side `NCCL_IB_TC` values while switch remains otherwise
  default.
- Optional PCP/DSCP mapping only after a rollback snapshot exists.

Success criteria:

- NCCL remains in the known-good class.
- Queue placement becomes explainable and repeatable.
- No correctness or counter regression.

### 3. PFC / Lossless Class Test

Purpose: determine whether PFC helps, hurts, or is irrelevant for this small
cluster workload.

Candidate tests:

- PFC disabled baseline.
- PFC enabled only for the intended RoCE traffic class.
- PFC plus matching trust/classification.

Success criteria:

- No pause storm symptoms.
- No new drops/errors/FEC uncorrected growth.
- NCCL improves or queue counters become materially more stable.

### 4. Flow-Control Variants

Purpose: verify whether link-level flow control settings matter independently
of PFC.

Candidate tests:

- Current `tx-flow-control=off rx-flow-control=off`.
- Rx only.
- Tx only.
- Tx/Rx on.

Success criteria:

- No link instability.
- NCCL does not regress.
- Counter behavior is cleaner than baseline.

### 5. Bridge / Hardware-Offload Sanity

Purpose: confirm current bridge/offload behavior is not a hidden limiter.

Candidate tests:

- Current production bridge profile.
- Minimal temporary bridge only if rollback is fully captured.
- Verify hardware offload flags before and after.

Success criteria:

- Same or better NCCL.
- No loss of management access.
- No lasting bridge topology changes after rollback.

## Stop Conditions

Stop immediately and roll back if any of these occur:

- Any NCCL wrong/out-of-bounds value is nonzero.
- A target port drops link or renegotiates unexpectedly.
- `rx-error-events` or `rx-fcs-error` increases.
- `rs-fec-uncorrected` increases.
- `tx-drop-packet` grows during the same benchmark window.
- The four-node fixed `256MiB` result falls materially below the frozen profile
  class on repeated runs.
- Management access becomes unstable.

## Preferred First Experiment

Start with queue classification only, not PFC. The current host-side profile is
already fast, and CRS804 telemetry shows traffic predominantly growing
`tx-queue1-packet` while queue3 stayed flat during the Sparks 1-4 sample window.
The safest first question is whether we can classify RoCE traffic predictably
without changing lossless behavior.
