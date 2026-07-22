# DGX Spark / CRS804 Known-Good Gap - 2026-06-30

## Why This Exists

The current CRS804 fabric passes basic link and jumbo-frame checks, but it does
not yet match the source-backed DGX Spark performance shape.

The most important source-backed correction is that a DGX Spark high-speed
physical attachment exposes two active logical RoCE functions. Validating only
`rocep1s0f0` / `enp1s0f0np0` is not enough to prove the Spark fabric is running
as intended.

## Sources Checked

NVIDIA's DGX Spark performance guide identifies both active RoCE functions from
`ibdev2netdev`, assigns IPs to both active ports, and runs `ib_write_bw` on both
functions concurrently:

- `rocep1s0f0` / `enp1s0f0np0`
- `roceP2p1s0f0` / `enP2p1s0f0np0`

The guide's example shows roughly `92.57 Gbits/sec` on one function and
`97.28 Gbits/sec` on the other, for an aggregate of `189.85 Gbits/sec`.

Source:
<https://raw.githubusercontent.com/NVIDIA/dgx-spark-playbooks/main/nvidia/connect-two-sparks/assets/performance_benchmarking_guide.md>

The closest community known-good switch report found so far is a DGX Spark /
MikroTik CRS812 thread. It reports that a four-node CRS812 setup only "clicked"
after treating the single physical Spark port as two logical halves, assigning
IPs to both, and driving both concurrently. The reported results were
`196-198 Gbits/sec` aggregate iperf3 between node pairs and NCCL all-reduce
around `23.76 GB/s` bus bandwidth with NET=IB and the RDMA plugin.

Source:
<https://forums.developer.nvidia.com/t/connectx-7-200gbe-via-mikrotik-crs812-qsfp-dd-400g-2xqsfp56-200g-breakout/357162>

MikroTik's CRS804 manual confirms the switch has four 400G QSFP56-DD ports and
uses Marvell `98DX7335` switching silicon.

Source:
<https://help.mikrotik.com/docs/spaces/UM/pages/357302325/CRS804-4DDQ-hRM>

## Current Live Gap

Read-only checks on 2026-06-30 showed all four Sparks expose both active RoCE
functions:

```text
rocep1s0f0   -> enp1s0f0np0   (Up)
roceP2p1s0f0 -> enP2p1s0f0np0 (Up)
```

But only the first function currently has a persistent IPv4 fabric address:

| Host | `enp1s0f0np0` | `enP2p1s0f0np0` |
| --- | --- | --- |
| `spark-a.example` | `192.0.2.10/24` | link-local IPv6 only |
| `spark-b.example` | `192.0.2.10/24` | link-local IPv6 only |
| `spark-c.example` | `192.0.2.10/24` | link-local IPv6 only |
| `spark-d.example` | `192.0.2.10/24` | link-local IPv6 only |

This does not by itself explain the very low CRS804 result. Earlier temporary
secondary-half testing between Spark 1 and Spark 2 also stayed slow. But it does
mean the primary verifier and NCCL runbook were not yet shaped like the NVIDIA
known-good test.

## New Gate

The new source-backed underlay gate is:

1. Both active halves have IPv4 addresses on distinct subnets.
2. Jumbo ping passes on both halves.
3. `ib_write_bw` on each half individually reaches roughly `90+ Gbits/sec`.
4. Concurrent `ib_write_bw` on both halves reaches roughly `180+ Gbits/sec`
   aggregate.
5. Only after that should NCCL be treated as a meaningful throughput test.

The helper for this gate is:

```bash
scripts/verify-dual-rail-underlay.sh
```

By default it is conservative and stops if the secondary rail is not already
addressed. To run a non-persistent Spark 1 / Spark 2 test using temporary
`198.51.100.x/24` addresses:

```bash
APPLY_TEMP_SECONDARY=1 scripts/verify-dual-rail-underlay.sh
```

The script removes the temporary secondary addresses on exit. Evidence is
written under ignored `evidence/dual-rail-underlay-*`.

## Important Current Result

A dry run without `APPLY_TEMP_SECONDARY=1` stopped before traffic and confirmed
the source/destination secondary IPv4 addresses are not present. That is the
expected guard behavior:

```text
Secondary source IP 192.0.2.10/24 is not present on spark-a.example:enP2p1s0f0np0.
```

## Next Safe Action

Run the temporary dual-half gate on Spark 1 and Spark 2:

```bash
cd "/path/to/dgx-cluster"
APPLY_TEMP_SECONDARY=1 scripts/verify-dual-rail-underlay.sh
```

If it still returns single-digit or low-double-digit aggregate throughput, the
gap is no longer "we forgot the second half." The evidence should then be sent
to NVIDIA/MikroTik with the known-good comparison:

- NVIDIA guide: about `189.85 Gbits/sec` aggregate dual-half RDMA.
- CRS812 community report: about `196-198 Gbits/sec` aggregate and NCCL
  `23.76 GB/s` bus bandwidth.
- Current CRS804/Spark evidence: `~6.5-6.8 Gbits/sec` RDMA-CM via switch,
  `~8.8-9.8 Gbits/sec` TCP via switch, and earlier direct-cable tests still far
  below the known-good aggregate class.
