# Sparks 5-8 Public NCCL Benchmark

Date: 2026-07-01

Raw local evidence: `evidence/public-benchmark-5-8-20260701-101725/`

Status: PASS. All NCCL public-comparison tests completed with `0` wrong/out-of-bounds values.

This tracked note summarizes the ignored local evidence bundle so the repo keeps a durable, public-ready benchmark record without committing large raw logs.

## Tested Fabric

| Spark | Hostname | Kernel | Primary IP | Secondary IP | Active RDMA devices |
| --- | --- | --- | --- | --- | --- |
| 5 | `spark-e.example` | `6.17.0-1021-nvidia` | `192.0.2.10/24` | `192.0.2.10/24` | `rocep1s0f1`, `roceP2p1s0f1` |
| 6 | `spark-f.example` | `6.17.0-1021-nvidia` | `192.0.2.10/24` | `192.0.2.10/24` | `rocep1s0f1`, `roceP2p1s0f1` |
| 7 | `spark-h.example` | `6.17.0-1026-nvidia` | `192.0.2.10/24` | `192.0.2.10/24` | `rocep1s0f1`, `roceP2p1s0f1` |
| 8 | `spark-g.example` | `6.17.0-1026-nvidia` | `192.0.2.10/24` | `192.0.2.10/24` | `rocep1s0f1`, `roceP2p1s0f1` |

Common host facts:

- NVIDIA driver: `580.159.03`
- CUDA reported by `nvidia-smi`: `13.0`
- NCCL packages: `libnccl2=2.28.9-1+cuda13.0`, `libnccl-dev=2.28.9-1+cuda13.0`
- OpenMPI packages: `openmpi-bin=4.1.6-7ubuntu2`, `libopenmpi-dev=4.1.6-7ubuntu2`
- `nccl-tests`: built under `/opt/public-cluster/nccl-tests`
- Both f1 rails on each host: `200000Mb/s`, `4` lanes, full duplex, link detected
- SSH-launched rank memlock: `unlimited`

CRS804 read-only snapshot:

- Model: `CRS804-4DDQ`
- RouterOS: `7.23.1 (stable)`
- RouterBOARD current firmware: `7.23.1`
- Tested active QSFP lanes: `fabric-port-e`, `fabric-port-f`, `fabric-port-g`, `fabric-port-h`
- Active tested ports: `mtu=9000`, `l2mtu=9216`, `speed=200G-baseCR4`, `fec-mode=fec91`

## Launch Shape

All NCCL tests launched from Spark 5 over fabric IPs, not Tailscale names.

```bash
mpirun -H 192.0.2.10:1,192.0.2.10:1,192.0.2.10:1,192.0.2.10:1
```

Relevant environment:

```bash
UCX_NET_DEVICES=enp1s0f1np1,enP2p1s0f1np1
NCCL_SOCKET_IFNAME=enp1s0f1np1,enP2p1s0f1np1
NCCL_IB_DISABLE=0
NCCL_IB_HCA=rocep1s0f1,roceP2p1s0f1
NCCL_NET_GDR_LEVEL=2
```

The parent launch was wrapped with `prlimit --memlock=unlimited:unlimited`. NCCL selected `NET/IB` and both RoCE devices on every node. Logs also show `GPU Direct RDMA Disabled`, which is expected on DGX Spark.

## Results

### Two-Node `all_gather_perf`, 16GiB

Command shape:

```bash
all_gather_perf -b 16G -e 16G -f 2 -g 1 -n 20 -w 5 -c 1
```

| Pair | Out-of-place busbw | In-place busbw | Avg busbw | Wrong |
| --- | ---: | ---: | ---: | ---: |
| 5-6 | `23.30 GB/s` | `23.96 GB/s` | `23.6309 GB/s` | `0` |
| 5-7 | `23.11 GB/s` | `23.74 GB/s` | `23.4256 GB/s` | `0` |
| 5-8 | `22.99 GB/s` | `23.74 GB/s` | `23.3653 GB/s` | `0` |
| 6-7 | `24.24 GB/s` | `24.33 GB/s` | `24.2844 GB/s` | `0` |
| 6-8 | `24.24 GB/s` | `24.31 GB/s` | `24.2792 GB/s` | `0` |
| 7-8 | `24.28 GB/s` | `24.33 GB/s` | `24.3049 GB/s` | `0` |

Pair aggregate:

- Min avg bus bandwidth: `23.3653 GB/s`
- Max avg bus bandwidth: `24.3049 GB/s`
- Mean avg bus bandwidth: `23.8817 GB/s`

### Four-Node `all_reduce_perf`, 256MiB

Command shape:

```bash
all_reduce_perf -b 256M -e 256M -f 2 -g 1 -n 50 -w 10 -c 1
```

| Size | Out-of-place busbw | In-place busbw | Avg busbw | Wrong |
| ---: | ---: | ---: | ---: | ---: |
| `268435456 B` | `21.18 GB/s` | `21.12 GB/s` | `21.1473 GB/s` | `0` |

Debug-light repeat set:

- Command shape: `all_reduce_perf -b 256M -e 256M -f 2 -g 1 -n 100 -w 20 -c 1`
- Environment difference: `NCCL_DEBUG=WARN` instead of verbose `NCCL_DEBUG=INFO`
- Repeat count: `5`
- Avg bus bandwidth range: `19.9841-21.1762 GB/s`
- Mean avg bus bandwidth: `20.7278 GB/s`
- Wrong/out-of-bounds values: `0` for every repeat

### Four-Node `all_reduce_perf`, 8B to 1GiB Sweep

Command shape:

```bash
all_reduce_perf -b 8 -e 1G -f 2 -g 1 -n 20 -w 5 -c 1
```

Selected rows:

| Size | Out-of-place busbw | In-place busbw | Wrong |
| ---: | ---: | ---: | ---: |
| `16MiB` | `22.21 GB/s` | `22.23 GB/s` | `0` |
| `32MiB` | `22.82 GB/s` | `22.85 GB/s` | `0` |
| `64MiB` | `22.52 GB/s` | `22.50 GB/s` | `0` |
| `256MiB` | `21.27 GB/s` | `21.35 GB/s` | `0` |
| `512MiB` | `21.45 GB/s` | `21.53 GB/s` | `0` |
| `1GiB` | `22.60 GB/s` | `21.90 GB/s` | `0` |

The sweep's reported `Avg bus bandwidth` across all message sizes was `6.62237 GB/s`; this value includes tiny message sizes from `8B` upward and should not be interpreted as peak fabric bandwidth.

## External Comparison Notes

- NVIDIA's DGX Spark NCCL playbook recommends the large two-node all-gather shape `all_gather_perf -b 16G -e 16G -f 2`, and notes that if two QSFP cables are connected, all four interfaces must be assigned IPs for full bandwidth: <https://build.nvidia.com/spark/nccl/stacked-sparks>
- A public NVIDIA forum CRS812 report says the setup "clicked" after treating the physical port as two logical halves and driving both halves concurrently. Their reported four-node `all_reduce_perf` at `256MiB` is `~23.76 GB/s`; this run's fixed `256MiB` result is `21.1473 GB/s`, while the 8B-to-1GiB sweep reaches `22.82-22.85 GB/s` around `32MiB`: <https://forums.developer.nvidia.com/t/connectx-7-200gbe-via-mikrotik-crs812-qsfp-dd-400g-2xqsfp56-200g-breakout/357162>
- NVIDIA support says GPUDirect RDMA is not supported on DGX Spark, so the NCCL log line `GPU Direct RDMA Disabled` is expected evidence, not a failure: <https://nvidia.custhelp.com/app/answers/detail/a_id/5780/~/is-gpudirect-rdma-supported-on-dgx-spark%3F>

## Next Tuning Actions

1. Repeat the fixed 256MiB four-node all-reduce with `NCCL_DEBUG` unset entirely.
2. Sweep CPU/rank binding and `NCCL_IGNORE_CPU_AFFINITY`.
3. Sweep `NCCL_ALGO=Ring,Tree` and `NCCL_PROTO=Simple,LL128`.
4. Sweep `NCCL_MIN_NCHANNELS` and `NCCL_MAX_NCHANNELS`.
5. Isolate each rail and reverse `NCCL_IB_HCA` order to check rail asymmetry.
6. Sweep `NCCL_IB_QPS_PER_CONNECTION` and `NCCL_IB_SPLIT_DATA_ON_QPS`.
7. Compare kernel split behavior: Sparks 5/6 on `6.17.0-1021-nvidia` versus Sparks 7/8 on `6.17.0-1026-nvidia`.
8. Capture read-only CRS804 counters during a long NCCL run.
9. Run a longer median set for the best candidate configuration.
10. Once the remaining cables are installed, run the same harness on 8 nodes.
