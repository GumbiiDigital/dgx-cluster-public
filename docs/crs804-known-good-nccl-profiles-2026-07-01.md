# CRS804 Known-Good NCCL Profiles

Date: 2026-07-01

Status: frozen after separate four-node validation passes on Sparks 1-4 and
Sparks 5-8. These profiles are host-side NCCL/OpenMPI settings only. They do
not require CRS804 switch writes.

## Sparks 1-4

Profile file: `scripts/sparks14-nccl-profile.env`

Validated fabric:

- Rail 0: `192.0.2.10-14/24`
- Rail 1: `192.0.2.10-14/24`
- RDMA devices: `rocep1s0f1,roceP2p1s0f1`
- Netdevs: `enp1s0f1np1,enP2p1s0f1np1`

Frozen profile:

```bash
APPLY_TUNED_DEFAULTS=0
NCCL_IB_QPS_PER_CONNECTION=4
NCCL_IB_SPLIT_DATA_ON_QPS=1
NCCL_MIN_NCHANNELS=8
NCCL_MAX_NCHANNELS=8
NCCL_IB_HCA=rocep1s0f1,roceP2p1s0f1
NCCL_SOCKET_IFNAME=enp1s0f1np1,enP2p1s0f1np1
UCX_NET_DEVICES=enp1s0f1np1,enP2p1s0f1np1
```

Evidence:

- `docs/sparks-1-4-crs804-nccl-validation-2026-07-01.md`
- Raw local evidence:
  `evidence/sparks14-validated-tuning-20260701-135950/`

Key result:

- Best single fixed `256MiB` run: `23.8624 GB/s`, wrong `0`
- Ten-repeat mean: `23.8246 GB/s`
- Ten-repeat median: `23.8226 GB/s`
- Ten-repeat range: `23.8068-23.8571 GB/s`

`NCCL_IGNORE_CPU_AFFINITY=1` is intentionally not frozen for Sparks 1-4. It was
close, but the best observed 1-4 profile omitted it.

## Sparks 5-8

Profile file: `scripts/sparks58-nccl-profile.env`

Validated fabric:

- Rail 0: `192.0.2.10-18/24`
- Rail 1: `192.0.2.10-18/24`
- RDMA devices: `rocep1s0f1,roceP2p1s0f1`
- Netdevs: `enp1s0f1np1,enP2p1s0f1np1`

Frozen profile:

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

Evidence:

- `docs/sparks-5-8-nccl-tuning-2026-07-01.md`
- `docs/sparks-5-8-nccl-experiment-program-2026-07-01.md`
- Raw local evidence remains ignored under `evidence/`.

Key result:

- Ten-repeat mean: `23.8370 GB/s`
- Ten-repeat median: `23.8365 GB/s`
- Ten-repeat range: `23.8123-23.8720 GB/s`
- Wrong/out-of-bounds values: `0`

## Operational Notes

- Keep OpenMPI control traffic pinned to `enp1s0f1np1`.
- Keep MPI/OOB on fabric or explicitly verified pinned control paths; do not
  allow benchmark evidence to drift onto LAN, Tailscale, or Docker addresses.
- Treat GPUDirect RDMA disabled log lines as expected on DGX Spark unless
  NVIDIA support guidance changes.
- Re-run transport gates before trusting benchmark deltas after any cabling,
  switch profile, kernel, driver, NCCL, or OpenMPI change.
