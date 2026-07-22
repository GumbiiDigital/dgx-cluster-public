# Sparks 5-8 NCCL Experiment Program

Date: 2026-07-01

Raw local evidence: `evidence/nccl-experiment-program-5-8-20260701-110837/`

Status: PASS for the reachable Sparks 5-8 fabric. STOP at the 8-node scaling
lane because the candidate Sparks 1-4 fabric IPs are not reachable from Spark 5
and the read-only CRS804 snapshot shows ports 1/2 configured but not running.
Continuing to all 8 nodes requires physical/link-side work.

No switch write commands were used in this pass.

## Baseline Profile

The repeatable Sparks 5-8 harness now applies the current known-good profile:

```bash
NCCL_IB_QPS_PER_CONNECTION=4
NCCL_IB_SPLIT_DATA_ON_QPS=1
NCCL_MIN_NCHANNELS=8
NCCL_MAX_NCHANNELS=8
NCCL_IGNORE_CPU_AFFINITY=1
NCCL_IB_HCA=rocep1s0f1,roceP2p1s0f1
NCCL_SOCKET_IFNAME=enp1s0f1np1,enP2p1s0f1np1
UCX_NET_DEVICES=enp1s0f1np1,enP2p1s0f1np1
```

The harness also pins OpenMPI control traffic to `enp1s0f1np1` so the MPI
launcher does not drift onto LAN, Tailscale, or Docker interfaces while NCCL
traffic is intended to use the CRS804 fabric.

## Ten-Lane Results

| Lane | Result | Evidence |
| --- | --- | --- |
| 1. Profile harness | PASS. Fixed 256MiB four-node `all_reduce_perf` hit `23.8308 GB/s`, wrong `0`. | `task01-profile/` |
| 2. MPI control-plane detector | PASS. Hostname smoke returned the four Spark hosts and no unexpected LAN/Tailscale/Docker URI was found. | `task02-control-plane/` |
| 3. NCCL topology/graph dumps | PASS. Tuned run hit `23.8566 GB/s`, wrong `0`; topology and graph XML files were pulled. | `task03-topology/` |
| 4. Size-aware tuning | PASS. Best config changes by size: baseline at `8K`, `channels8` from `64K-32M`, combined profile at `256M`, and `qps4split1` at `1G-4G`. | `task04-size-aware/` |
| 5. RoCE/GID audit | PASS. NCCL selected both RDMA devices, used GID index `5`, alternated channels across `NET/IB/0` and `NET/IB/1`, and reported expected GPUDirect RDMA disabled lines. | `task05-roce-gid/` |
| 6. CRS804 queue correlation | PASS. Five tuned repeats ranged from `23.7996-23.8344 GB/s`, wrong `0`; no new FCS/error/drop counter growth was seen. | `task06-queue-classification/` |
| 7. Nsight Systems | PARTIAL. Nsight Systems is installed, but this build does not accept `-t nccl`; fallback tracing generated `.nsys-rep` files but wrapping `mpirun` changed ORTE routing before NCCL ran. | `task07-nsight/` |
| 8. Real workload | BLOCKED NON-DESTRUCTIVELY. Default Python lacks PyTorch, Transformers, Datasets, DeepSpeed, Megatron, and mpi4py. No package installs were performed. | `task08-real-workload/` |
| 9. Profile artifact | PASS. Static profile file verified at `23.8437 GB/s`, wrong `0`; tuner-plugin notes created. | `task09-profile-artifact/` |
| 10. Scaling boundary | PASS for Sparks 5-8. All six two-node pairs ran in the `23.7448-23.9507 GB/s` class, wrong `0`; four-node tuned `256MiB` hit `23.8255 GB/s`, wrong `0`; 1-4 rail probes were unreachable. | `task10-scaling/` |

## Size-Aware Policy

The size sweep shows that one static profile is excellent for the public 256MiB
benchmark target, but not universally optimal:

| Message size | Best config | Avg bus bandwidth |
| --- | --- | ---: |
| `8K` | baseline | `0.226138 GB/s` |
| `64K` | `channels8` | `1.20046 GB/s` |
| `1M` | `channels8` | `4.8328 GB/s` |
| `8M` | `channels8` | `8.43228 GB/s` |
| `32M` | `channels8` | `23.1458 GB/s` |
| `256M` | `qps4split1-ch8-ignore` | `23.8216 GB/s` |
| `1G` | `qps4split1` | `24.1885 GB/s` |
| `4G` | `qps4split1` | `24.2944 GB/s` |

Interpretation: use the static profile for repeatable public 256MiB evidence
and fixed large-message benchmarking. A future NCCL tuner plugin is plausible,
but it should encode size-aware thresholds after the same table is repeated on
more node counts.

## CRS804 Read-Only Counter Notes

During the queue-classification lane, the active Sparks 5-8 ports showed:

- `rx-error-events`: unchanged at `0 0 0 0`
- `rx-fcs-error`: unchanged at `0 0 0 0`
- `tx-drop-packet`: unchanged at `0 11857 9524 0`
- `tx-drop-queue1-packet`: unchanged at `0 11857 9524 0`
- `rs-fec-uncorrected`: unchanged at `0 6 0 0`
- `tx-queue1-packet`: increased during traffic
- `tx-queue3-packet`: unchanged at `0 0 0 0`

Interpretation: the tuned path is not creating new visible CRS804 receive
errors, FCS errors, packet drops, or FEC uncorrected growth in this sample
window. Queue accounting still lands under queue1, so a future switch-side QoS
experiment should remain separate from the current known-good profile.

## Scaling Boundary

The reachable Sparks 5-8 subcluster is healthy:

| Pair | Tuned `all_gather_perf` 16G avg bus bandwidth | Wrong |
| --- | ---: | ---: |
| 5-6 | `23.86 GB/s` | `0` |
| 5-7 | `23.9507 GB/s` | `0` |
| 5-8 | `23.7669 GB/s` | `0` |
| 6-7 | `23.7448 GB/s` | `0` |
| 6-8 | `23.7603 GB/s` | `0` |
| 7-8 | `23.7745 GB/s` | `0` |

The same profile on all four reachable nodes produced `23.8255 GB/s` at fixed
256MiB `all_reduce_perf`, wrong `0`.

Spark 5 could not reach the candidate rail IPs for Sparks 1-4:

```text
192.0.2.10 unreachable
192.0.2.10 unreachable
192.0.2.10 unreachable
192.0.2.10 unreachable
192.0.2.10 unreachable
192.0.2.10 unreachable
192.0.2.10 unreachable
192.0.2.10 unreachable
```

The CRS804 read-only snapshot shows `fabric-port-a`, `fabric-port-b`,
`fabric-port-c`, and `fabric-port-d` configured with `mtu=9000`,
`l2mtu=9216`, `speed=200G-baseCR4`, and `fec-mode=fec91`, but without the
running flag. The active Sparks 5-8 ports remain `RS` on `fabric-port-e`,
`fabric-port-f`, `fabric-port-g`, and `fabric-port-h`.

## New Tracked Artifacts

- `scripts/run-sparks58-nccl-profile.sh`: repeatable NCCL profile harness.
- `scripts/check-mpi-fabric-control-plane.sh`: pinned MPI control-plane smoke.
- `scripts/sparks58-nccl-profile.env`: static known-good profile.
- `docs/sparks-5-8-nccl-tuner-plugin-notes-2026-07-01.md`: tuner feasibility notes.

## Final Verification

- `bash -n scripts/run-sparks58-nccl-profile.sh scripts/check-mpi-fabric-control-plane.sh`
  passed.
- Raw evidence remains ignored by `.gitignore` via the `evidence/` rule.
- Remote process scans on `192.0.2.10-18` found no lingering `mpirun`,
  `orted`, `all_reduce_perf`, `all_gather_perf`, or `nccl-tests` processes
  beyond the scan commands themselves.
- No switch write commands were run; CRS804 access in this pass was read-only
  `print`/stats inspection.

## Next Actions

1. Keep using the static profile for public 256MiB and large-message benchmark
   reproduction on Sparks 5-8.
2. Repeat the size-aware table after any physical/link changes for Sparks 1-4.
3. Re-run the all-8 scaling lane only after the 1-4 rail IPs become reachable
   and the corresponding CRS804 ports show `RS`.
4. Treat Nsight as a separate profiling project: profile one local NCCL process
   or find an Nsight invocation that does not perturb OpenMPI routing.
5. Run real workload validation only after a workload environment is selected or
   package installs are explicitly authorized.
