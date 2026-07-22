# Sparks 1-4 CRS804 NCCL Validation

Date: 2026-07-01

Raw local evidence: `evidence/sparks14-validated-tuning-20260701-135950/`

Status: PASS for the reachable Sparks 1-4 CRS804 fabric. No hardware changes
were required during this validation pass after the public-user recabled the nodes.
No switch write commands were run; CRS804 access was read-only telemetry only.

## Scope

This pass repeated the Sparks 5-8 NCCL validation program on Sparks 1-4 and
added a few Perplexity-inspired sanity checks around MTU/L2MTU, GID selection,
socket fallback, and rail asymmetry.

Validated nodes:

| Node | Hostname | Management target | Rail 0 | Rail 1 |
| --- | --- | --- | --- | --- |
| Spark 1 | `spark-a.example` | `192.0.2.10` | `192.0.2.10/24` | `192.0.2.10/24` |
| Spark 2 | `spark-b.example` | `192.0.2.10` | `192.0.2.10/24` | `192.0.2.10/24` |
| Spark 3 | `spark-c.example` | `192.0.2.10` | `192.0.2.10/24` | `192.0.2.10/24` |
| Spark 4 | `spark-d.example` | `192.0.2.10` | `192.0.2.10/24` | `192.0.2.10/24` |

Active RDMA devices:

```bash
NCCL_IB_HCA=rocep1s0f1,roceP2p1s0f1
NCCL_SOCKET_IFNAME=enp1s0f1np1,enP2p1s0f1np1
UCX_NET_DEVICES=enp1s0f1np1,enP2p1s0f1np1
```

## Transport Gates

The host readiness gate passed after installing matching NCCL packages and
building `nccl-tests` on Sparks 1 and 2:

- All four nodes reachable.
- Both f1 rail IPs present.
- Both RDMA devices present.
- `nccl-tests` present.
- No stale MPI/NCCL jobs.

All ordered jumbo ping checks passed with `-s 8972 -M do`, both rails, all
directions.

The ordered RDMA matrix passed on every pair:

| Result class | Observation |
| --- | --- |
| Single rail | Every ordered pair and rail reported `111.85 Gbits/sec`. |
| Concurrent dual rail | Aggregate ranged `195.79-195.82 Gbits/sec`. |
| GID | RDMA-CM selected IPv4 RoCE GID index `5`. |

This is the expected healthy transport class and is materially different from
the earlier single-digit CRS804 failure mode.

## NCCL Results

Baseline fixed `256MiB` with `NCCL_DEBUG` unset and tuned knobs disabled:

| Config | Avg bus bandwidth | Wrong |
| --- | ---: | ---: |
| baseline/debug-unset | `21.3203 GB/s` | `0` |

Tuned fixed `256MiB`:

| Config | Avg bus bandwidth | Wrong |
| --- | ---: | ---: |
| profile default | `23.8618 GB/s` | `0` |
| debug INFO RoCE/GID audit | `23.8276 GB/s` | `0` |

Verbose NCCL logs confirmed:

- `Using network IB`
- both `rocep1s0f1` and `roceP2p1s0f1`
- channel alternation across `NET/IB/0` and `NET/IB/1`
- GID index `5`
- expected `GPU Direct RDMA Disabled` lines
- no `NET/Socket` fallback evidence in the transport selection path

## 256MiB Tuning Matrix

| Label | Avg bus bandwidth | Wrong |
| --- | ---: | ---: |
| `baseline` | `21.3282 GB/s` | `0` |
| `channels4` | `23.2644 GB/s` | `0` |
| `channels8` | `23.7208 GB/s` | `0` |
| `qps2-split0` | `23.6542 GB/s` | `0` |
| `qps4-split0` | `23.6221 GB/s` | `0` |
| `qps4-split1` | `23.8109 GB/s` | `0` |
| `qps4split1-ch8` | `23.8624 GB/s` | `0` |
| `qps4split1-ch8-ignore` | `23.8071 GB/s` | `0` |
| `ring-simple` | `21.4074 GB/s` | `0` |
| `ring-ll128` | `8.54757 GB/s` | `0` |
| `tree-simple` | `13.3227 GB/s` | `0` |
| `tree-ll128` | `4.53725 GB/s` | `0` |
| `primary-rail-only` | `21.2419 GB/s` | `0` |
| `secondary-rail-only` | `21.1948 GB/s` | `0` |
| `reversed-hca` | `21.2943 GB/s` | `0` |

Best single-run config:

```bash
NCCL_IB_QPS_PER_CONNECTION=4
NCCL_IB_SPLIT_DATA_ON_QPS=1
NCCL_MIN_NCHANNELS=8
NCCL_MAX_NCHANNELS=8
```

Unlike the Sparks 5-8 run, `NCCL_IGNORE_CPU_AFFINITY=1` was not part of the
best single-run 1-4 result. It stayed close, but slightly lower.

## Longer Median Set

Ten-repeat fixed `256MiB`, best 1-4 profile:

| Metric | Avg bus bandwidth |
| --- | ---: |
| Mean | `23.8246 GB/s` |
| Median | `23.8226 GB/s` |
| Min | `23.8068 GB/s` |
| Max | `23.8571 GB/s` |

Wrong/out-of-bounds values were `0` on every repeat.

## Size-Aware Sweep

| Size | Profile | Avg bus bandwidth | Wrong |
| --- | --- | ---: | ---: |
| `8K` | baseline | `0.18331 GB/s` | `0` |
| `64K` | channels8 | `1.09531 GB/s` | `0` |
| `1M` | channels8 | `4.81759 GB/s` | `0` |
| `8M` | channels8 | `8.00411 GB/s` | `0` |
| `32M` | channels8 | `22.9921 GB/s` | `0` |
| `256M` | qps4split1-ch8 | `23.8141 GB/s` | `0` |
| `1G` | qps4split1 | `24.1952 GB/s` | `0` |
| `4G` | qps4split1 | `24.2936 GB/s` | `0` |

The size contour matches Sparks 5-8: channel control helps medium messages,
the combined profile is best around the public `256MiB` target, and QP/split
alone is strong at `1G-4G`.

## Pairwise Scaling

Two-node `all_gather_perf` at `16G`:

| Pair | Avg bus bandwidth | Wrong |
| --- | ---: | ---: |
| `1-2` | `22.4905 GB/s` | `0` |
| `1-3` | `23.7992 GB/s` | `0` |
| `1-4` | `23.7323 GB/s` | `0` |
| `2-3` | `23.7332 GB/s` | `0` |
| `2-4` | `23.8182 GB/s` | `0` |
| `3-4` | `23.7352 GB/s` | `0` |

The initial `1-2` value did not reproduce. A three-repeat `1-2` rerun produced
`23.779`, `23.685`, and `23.8129 GB/s`, wrong `0`, so the lower first sample is
currently classified as a transient first-run outlier rather than a raw fabric
problem.

## Novel Findings

- Sparks 1-4 are cleaner than the earlier broken CRS804 state: ordered RDMA is
  symmetric at `111.85 Gbits/sec` per rail and roughly `195.8 Gbits/sec`
  aggregate.
- Rail-only NCCL is much stronger on 1-4 than it was on 5-8: about `21.2 GB/s`
  rather than the prior `13.8 GB/s` class.
- Reversing HCA order is also less punitive on 1-4: `21.2943 GB/s`.
- `--bind-to core --map-by slot` produced a small positive result
  (`23.8507 GB/s`) in the binding sweep.
- Forced `NCCL_IB_GID_INDEX=5` and forced `NCCL_IB_GID_INDEX=4` both completed
  around `23.80 GB/s`, wrong `0`; the adjacent IPv4 GID entry is not a hidden
  failure mode in this setup.
- All four Sparks 1-4 are running `6.17.0-1026-nvidia` with
  `nvidia-driver-580-open 580.159.03`, so the 5/6 versus 7/8 kernel split
  hypothesis does not apply to this group.

## CRS804 Read-Only Telemetry

During five tuned repeats:

| Repeat | Avg bus bandwidth | Wrong |
| ---: | ---: | ---: |
| 1 | `23.8527 GB/s` | `0` |
| 2 | `23.8131 GB/s` | `0` |
| 3 | `23.8138 GB/s` | `0` |
| 4 | `23.8052 GB/s` | `0` |
| 5 | `23.8044 GB/s` | `0` |

Read-only counter notes on `fabric-port-a`, `fabric-port-b`,
`fabric-port-c`, and `fabric-port-d`:

- `rx-error-events` stayed `0 0 0 0`.
- `rx-fcs-error` stayed `0 0 0 0`.
- `tx-drop-packet` stayed `0 6913 17860 0`.
- `rs-fec-uncorrected` stayed `65 63 66 54`.
- `tx-queue1-packet` increased during traffic.
- `tx-queue3-packet` had historical nonzero counts but did not increase during
  this sample window.

## Partial / Blocked Lanes

Nsight Systems is installed on Spark 1:

```text
NVIDIA Nsight Systems version 2192.0.2.10-253236389321v0
```

This pass did not wrap the distributed OpenMPI run with Nsight because the
Sparks 5-8 attempt showed that doing so can perturb ORTE routing. Treat Nsight
as a separate profiling project.

The real workload lane remains blocked non-destructively:

| Node group | Present | Missing |
| --- | --- | --- |
| Sparks 1-2 | `torch`, `transformers`, `datasets` | `deepspeed`, `mpi4py` |
| Sparks 3-4 | none of the checked Python workload packages | `torch`, `transformers`, `datasets`, `deepspeed`, `mpi4py` |

No package installs were performed for workload stacks.

## Evidence Map

| Lane | Evidence |
| --- | --- |
| Preflight and CRS804 read-only state | `preflight-*.log`, `crs804-readonly-preflight.log` |
| NCCL package/build prep | `task02-nccl-prereqs/` |
| Temporary host rail IPs | `task03-host-rail-ips/` |
| Host readiness and jumbo/RDMA transport | `task04-readiness-after-ip/`, `task04-transport/` |
| MPI control plane | `task05-mpi-control-plane-keyed/` |
| Baseline/tuned NCCL | `task06-*` |
| RoCE/GID debug | `task07-roce-gid-debug-info/` |
| 256MiB matrix | `task08-256M-tuning-matrix/` |
| Size-aware sweep | `task09-size-aware-sweep/` |
| CRS804 telemetry | `task10-crs804-telemetry/` |
| Ten-repeat median | `task11-best-10repeat-qps4split1-ch8/` |
| Pairwise all-gather | `task12-pairwise-allgather-16G/` |
| Topology/graph dump | `task13-topology-graph-dumps/` |
| Workload dependency check | `task14-real-workload-dependency-check/` |
| Nsight check | `task15-nsight-check/` |
| Kernel comparison | `task16-kernel-version-comparison/` |
| Binding sweep | `task17-cpu-rank-binding-sweep/` |
| Expanded QP sweep | `task18-qps-expanded-sweep/` |
| GID index sanity | `task19-gid-index-sanity/` |

## Next Actions

1. Use `qps4split1-ch8` as the Sparks 1-4 public `256MiB` profile unless a
   longer binding-aware run proves `--bind-to core --map-by slot` is stable.
2. Repeat the same program on any new four-node cable set before mixing node
   groups.
3. Revisit switch-side QoS only as a separate experiment with a captured
   fallback config, because the host-side/read-only-switch path already reaches
   target-class NCCL bandwidth.
