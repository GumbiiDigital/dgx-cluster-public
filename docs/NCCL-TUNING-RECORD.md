# NCCL Tuning Record

## Prerequisite

NCCL tuning started only after the dual-rail RoCE fabric passed directed connectivity and RDMA gates. The tuning record does not substitute for the underlay proof in [FABRIC-TROUBLESHOOTING.md](FABRIC-TROUBLESHOOTING.md).

## Transport selection retained across profiles

```text
NCCL_IB_HCA=rocep1s0f1,roceP2p1s0f1
NCCL_SOCKET_IFNAME=enp1s0f1np1,enP2p1s0f1np1
UCX_NET_DEVICES=enp1s0f1np1,enP2p1s0f1np1
NCCL_IB_DISABLE=0
NCCL_NET_GDR_LEVEL=2
```

The public launcher aliases are documented in [nccl-profiles.json](../examples/nccl-profiles.json). They do not reproduce the live inventory.

## Four-system profiles

The two four-system cohorts converged on four QPs per connection, split data across QPs, and eight channels.

### Cohort A

```text
NCCL_IB_QPS_PER_CONNECTION=4
NCCL_IB_SPLIT_DATA_ON_QPS=1
NCCL_MIN_NCHANNELS=8
NCCL_MAX_NCHANNELS=8
```

Recorded `256 MiB` repeat set:

| Metric | Average bus bandwidth |
| --- | ---: |
| Best observation | `23.8624 GB/s` |
| Ten-run mean | `23.8246 GB/s` |
| Ten-run median | `23.8226 GB/s` |
| Ten-run range | `23.8068-23.8571 GB/s` |
| Wrong | `0` |

### Cohort B

Cohort B used the same QP, split, and channel profile plus `NCCL_IGNORE_CPU_AFFINITY=1`.

| Metric | Average bus bandwidth |
| --- | ---: |
| Ten-run mean | `23.8370 GB/s` |
| Ten-run median | `23.8365 GB/s` |
| Ten-run range | `23.8123-23.8720 GB/s` |
| Wrong | `0` |

The difference between cohorts was kept explicit rather than forcing one environment variable onto every group.

## Eight-system profile

The eight-system sweep favored a different shape:

```text
NCCL_IB_QPS_PER_CONNECTION=2
NCCL_IB_SPLIT_DATA_ON_QPS=0
NCCL_MIN_NCHANNELS=12
NCCL_MAX_NCHANNELS=12
```

### Harness correction

An early sweep attempted to use `env VAR=... ssh ...` to inject tuning values into the remote shell. That did not reliably propagate arbitrary variables. Those rows were retained privately but excluded from conclusions.

Valid sweeps printed the remote `NCCL_` and `UCX_` environment before `mpirun`. That printout became part of the acceptance evidence for every tuning run.

### Fixed 256 MiB result

The pre-tuning repair proof was `21.7487 GB/s` average bus bandwidth at `256 MiB`, wrong `0`.

The final profile used `50` iterations and `15` warmup iterations:

| Run | Average bus bandwidth | Out-of-place | In-place | Wrong |
| --- | ---: | ---: | ---: | ---: |
| 1 | `22.9494 GB/s` | `22.14 GB/s` | `23.76 GB/s` | `0/0` |
| 2 | `23.0400 GB/s` | `22.25 GB/s` | `23.83 GB/s` | `0/0` |
| 3 | `23.0002 GB/s` | `22.18 GB/s` | `23.82 GB/s` | `0/0` |

| Summary | Average bus bandwidth |
| --- | ---: |
| Mean | `22.9965 GB/s` |
| Median | `23.0002 GB/s` |
| Range | `22.9494-23.0400 GB/s` |

That was about `5.7%` above the pre-tuning baseline.

Two shorter observations reached `23.3216 GB/s` and `23.2391 GB/s`, both wrong `0`, but they were not frozen. The longer head-to-head set favored the twelve-channel profile for stability.

### Size contour

Wrong was `0` at every tested size.

| Size | Out-of-place busbw | In-place busbw |
| ---: | ---: | ---: |
| `8 KiB` | `0.00 GB/s` | `0.09 GB/s` |
| `16 KiB` | `0.20 GB/s` | `0.20 GB/s` |
| `32 KiB` | `0.36 GB/s` | `0.35 GB/s` |
| `64 KiB` | `0.77 GB/s` | `0.67 GB/s` |
| `128 KiB` | `1.21 GB/s` | `1.38 GB/s` |
| `256 KiB` | `1.52 GB/s` | `1.48 GB/s` |
| `512 KiB` | `1.85 GB/s` | `1.76 GB/s` |
| `1 MiB` | `4.68 GB/s` | `4.41 GB/s` |
| `2 MiB` | `4.61 GB/s` | `4.74 GB/s` |
| `4 MiB` | `5.45 GB/s` | `5.65 GB/s` |
| `8 MiB` | `6.62 GB/s` | `6.67 GB/s` |
| `16 MiB` | `7.19 GB/s` | `7.37 GB/s` |
| `32 MiB` | `22.99 GB/s` | `22.85 GB/s` |
| `64 MiB` | `23.33 GB/s` | `23.47 GB/s` |
| `128 MiB` | `22.88 GB/s` | `22.93 GB/s` |
| `256 MiB` | `23.73 GB/s` | `23.83 GB/s` |
| `512 MiB` | `23.91 GB/s` | `23.88 GB/s` |
| `1 GiB` | `24.14 GB/s` | `24.04 GB/s` |
| `2 GiB` | `24.15 GB/s` | `24.23 GB/s` |
| `4 GiB` | `24.26 GB/s` | `24.29 GB/s` |

### Transport proof

The final debug canary recorded:

| Check | Result |
| --- | ---: |
| Exit code | `0` |
| `Using network IB` | present |
| `NET/IB` lines | `103` |
| `NET/Socket` lines | `0` |
| Connected rings | present |
| Out-of-bounds values | `0 OK` |

The tuned result therefore used RoCE/IB rather than socket fallback.

## Findings that survived the sweep

- The eight-system profile was not the four-system profile scaled up.
- `NCCL_IGNORE_CPU_AFFINITY=1` did not help the eight-system finalist.
- Forced `Tree/Simple` performed poorly at fixed `256 MiB`; default NCCL selection remained better among the tested choices.
- A single rail produced about `13.39 GB/s` at fixed `256 MiB`; the tuned dual-rail profile reached the `23 GB/s` class.
- At large messages, the tuned profile reached the `24 GB/s` class, with `24.26-24.29 GB/s` at `4 GiB`.
- The post-run sweep found no lingering `mpirun`, `orted`, `all_reduce_perf`, `all_gather_perf`, or `ib_write_bw` processes beyond the check itself.

## Parser

[summarize_nccl_log.py](../scripts/summarize_nccl_log.py) extracts the fixed-size result rows and the reported average bus bandwidth from a local `nccl-tests` log. It does not connect to a cluster or claim that an input log came from this environment.
