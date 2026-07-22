# NCCL Post-RoCE Runbook - 2026-06-30

NCCL validation is deliberately gated behind raw RoCE. Do not use NCCL
throughput to judge the CRS804 fabric while `ib_write_bw` is still capped around
single-digit Gbps.

## Current NCCL Readiness

Read-only inventory on all four connected Sparks showed:

| Check | State |
| --- | --- |
| CUDA toolkit | present at `/usr/local/cuda-13.0` |
| `nvcc` | `/usr/local/cuda/bin/nvcc`, CUDA `13.0`, `V13.0.88` |
| OpenMPI | present, `mpirun (Open MPI) 4.1.6` |
| `libnccl.so` | missing |
| `nccl.h` | missing |
| `libnccl2` candidate | apt default `2.30.7-1+cuda13.3`; CUDA 13.0 matching candidate `2.28.9-1+cuda13.0` |
| `libnccl-dev` candidate | apt default `2.30.7-1+cuda13.3`; CUDA 13.0 matching candidate `2.28.9-1+cuda13.0` |

This means the cluster is not NCCL-build-ready yet. It is CUDA/OpenMPI-ready,
but NCCL runtime/dev packages still need to be installed uniformly after the raw
RoCE gate is healthy and the public-user approves package changes.

## Preflight Commands

Check raw RoCE first:

```bash
cd "/path/to/dgx-cluster"
scripts/verify-roce-underlay.sh
```

Check NCCL readiness without running NCCL:

```bash
scripts/check-nccl-readiness.sh
```

Expected current result before NCCL packages are installed:

```text
MISSING: libnccl.so
MISSING: nccl.h
MISSING: /opt/public-cluster/nccl-tests/build/all_reduce_perf
MISSING: /opt/public-cluster/nccl-tests/build/all_gather_perf
NCCL readiness failed.
```

## Gated NCCL Runner

The NCCL runner refuses to proceed unless raw RoCE passes first:

```bash
scripts/run-nccl-after-roce.sh
```

Diagnostic shakedown with `SKIP_ROCE_GATE=1` confirmed the runner still refuses
before NCCL because `check-nccl-readiness.sh` fails on missing `libnccl.so`,
`nccl.h`, and `nccl-tests` binaries on all four Sparks.

Only after raw RoCE passes, NCCL packages are installed, and `nccl-tests` is
built, run:

```bash
RUN_NCCL=1 scripts/run-nccl-after-roce.sh
```

`SKIP_ROCE_GATE=1` exists for diagnostics only. Do not use it for final fabric
validation.

## Package Remediation Placeholder

Do not run this until the raw RDMA underlay passes and package changes are
approved. NVIDIA's NCCL install guidance uses `libnccl2` and `libnccl-dev` for
Ubuntu installs, and says to pin an explicit package version when staying on an
older CUDA line. Because these Sparks currently have CUDA `13.0`, the helper
defaults to the latest available `+cuda13.0` package:

```text
libnccl2=2.28.9-1+cuda13.0
libnccl-dev=2.28.9-1+cuda13.0
```

Dry-run the package plan:

```bash
scripts/install-nccl-prereqs.sh
```

Verified dry-run result: all four hosts have
`libnccl2=2.28.9-1+cuda13.0` and `libnccl-dev=2.28.9-1+cuda13.0` available, and
the helper prints the exact `sudo apt-get install` command without installing.

Apply only after approval:

```bash
APPLY_NCCL_INSTALL=1 scripts/install-nccl-prereqs.sh
```

After installation, build `nccl-tests` uniformly:

```bash
BUILD_NCCL_TESTS=1 scripts/build-nccl-tests.sh
```

Then rerun:

```bash
scripts/check-nccl-readiness.sh
scripts/run-nccl-after-roce.sh
```

## Pass Criteria

NCCL validation is only meaningful when:

- raw RoCE verifier passes at the expected class, roughly `90+ Gbits/sec`;
- `check-nccl-readiness.sh` passes on all four Sparks;
- NCCL logs show `NET/IB` rather than a socket fallback;
- the CRS804 queue3 counters continue moving with zero drops during the NCCL
  test window.
