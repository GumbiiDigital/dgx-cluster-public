# Sparks 5-8 NCCL Tuning

Date: 2026-07-01

Raw local evidence: `evidence/nccl-tuning-5-8-20260701-103908/`

Follow-up experiment program:
`docs/sparks-5-8-nccl-experiment-program-2026-07-01.md`

Status: PASS. Non-destructive NCCL tuning on Sparks 5-8 found a stable
four-node `all_reduce_perf` 256MiB configuration that matches the public CRS812
comparison class while keeping wrong/out-of-bounds values at `0`.

## Best Configuration

```bash
NCCL_IB_QPS_PER_CONNECTION=4
NCCL_IB_SPLIT_DATA_ON_QPS=1
NCCL_MIN_NCHANNELS=8
NCCL_MAX_NCHANNELS=8
NCCL_IGNORE_CPU_AFFINITY=1
```

Ten-repeat fixed 256MiB result:

- Mean avg bus bandwidth: `23.8370 GB/s`
- Median avg bus bandwidth: `23.8365 GB/s`
- Range: `23.8123-23.8720 GB/s`
- Wrong/out-of-bounds values: `0` on every repeat

This improves the prior fixed 256MiB public benchmark result of `21.1473 GB/s`
and is slightly above the public CRS812 forum comparison target of approximately
`23.76 GB/s`.

## Launch Notes

The first `NCCL_DEBUG`-unset run without OpenMPI interface pinning stuck during
MPI startup after an OpenMPI peer warning on Spark 8. Subsequent runs used the
same fabric MPI host list plus explicit OpenMPI control-plane pinning:

```bash
mpirun -np 4 \
  -H 192.0.2.10:1,192.0.2.10:1,192.0.2.10:1,192.0.2.10:1 \
  --mca plm_rsh_agent "ssh -i /opt/public-user/.ssh/dgx_cluster_mpi_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no" \
  --mca plm_rsh_no_tree_spawn 1 \
  --mca oob_tcp_if_include enp1s0f1np1 \
  --mca btl_tcp_if_include enp1s0f1np1
```

The pinned MPI hostname smoke passed before NCCL was rerun. This should be kept
in future public benchmark harnesses so OpenMPI does not advertise LAN,
Tailscale, or Docker addresses while the NCCL job itself is intended to run over
the fabric.

## Sweep Highlights

| Label | Avg bus bandwidth | Wrong |
| --- | ---: | ---: |
| `qps4split1-ch8-ignore` | `23.8509 GB/s` | `0` |
| `qps4split1-ch8` | `23.8258 GB/s` | `0` |
| `qps4-split1` | `23.7693 GB/s` | `0` |
| `qps4-split0` | `23.6291 GB/s` | `0` |
| `channels-8` | `23.5092 GB/s` | `0` |
| `qps2-split0` | `23.4882 GB/s` | `0` |
| `channels-4` | `23.3041 GB/s` | `0` |

Negative controls:

- `NCCL_ALGO=Ring NCCL_PROTO=LL128`: `8.16594 GB/s`
- `NCCL_ALGO=Tree NCCL_PROTO=Simple`: `14.4655 GB/s`
- `NCCL_ALGO=Tree NCCL_PROTO=LL128`: `4.56787 GB/s`
- Primary rail only: `13.8222 GB/s`
- Secondary rail only: `13.8811 GB/s`
- Reversed HCA order: `20.0248 GB/s`

## Switch Counter Notes

Read-only CRS804 counter samples were captured during the best 10-repeat run on
`fabric-port-e`, `fabric-port-f`, `fabric-port-g`, and `fabric-port-h`.

- `rx-error-events` stayed `0 0 0 0`.
- `rx-fcs-error` stayed `0 0 0 0`.
- `tx-drop-packet` stayed `0 11857 9524 0`; the visible drops did not increase
  during the run.
- `rs-fec-uncorrected` stayed `0 6 0 0`.
- `tx-queue1-packet` increased during the run.
- `tx-queue3-packet` stayed `0 0 0 0`.

Interpretation: the tuned NCCL path reached target-class bandwidth without
new visible CRS804 errors or drops in this read-only sample window. Queue
accounting still appears under queue1 rather than queue3.

## Next Actions

1. Add these NCCL env knobs to the repeatable benchmark harness, with the
   OpenMPI control-plane pinning included.
2. Run the same tuned fixed 256MiB test on additional four-node groupings when
   more Sparks are cabled.
3. Run an eight-node tuned benchmark after the remaining cables are installed.
4. Preserve the raw counter evidence locally unless selected files are approved
   for publication.

## Follow-Up Experiment Program

The broader ten-lane experiment program has now been captured in
`docs/sparks-5-8-nccl-experiment-program-2026-07-01.md`. It adds the repeatable
profile harness, MPI control-plane detector, topology/GID evidence, size-aware
tuning table, CRS804 queue-correlation repeat, Nsight/workload blockers, static
profile artifact, and the physical stop point for scaling beyond Sparks 5-8.
