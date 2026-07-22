# NVIDIA Support Escalation Draft - DGX Spark RoCE Cap

Use this only if the full cold-drain procedure does not recover raw RDMA to the
expected performance class.

Related NVIDIA forum thread:
<https://forums.developer.nvidia.com/t/dgx-spark-direct-qsfp-connection-only-getting-13-16-gbps-instead-of-expected-200g-performance/370035>

In that thread, a direct DGX Spark QSFP link with a 200G negotiated link but
roughly `13-16 Gbps` payload recovered to around `109 Gbits/sec` after a full
power-off and unplug cycle.

## Proposed Title

DGX Spark ConnectX-7 RoCE capped at 6-8 Gbit/s after CRS804 RoCE QoS validated

## Summary

I have four NVIDIA DGX Spark systems connected through a MikroTik CRS804-4DDQ
using 2x200G QSFP-DD breakout cabling. The CRS804 and all four host links
negotiate at `200G-baseCR4`, and the switch now classifies RoCE traffic into the
expected hardware queue after upgrading RouterOS to `7.23.1`.

Despite that, raw RDMA remains capped around `6.6-6.7 Gbits/sec` with
`ib_write_bw` across multiple Spark pairs, directions, and switch cages. TCP
payload throughput is also low. I have intentionally not moved to NCCL
throughput conclusions because low-level RDMA has not passed.

## Hardware / Software

- Switch: MikroTik CRS804-4DDQ
- RouterOS: `7.23.1 (stable)`
- RouterBOOT: `7.23.1`
- Switch chip: `Marvell-98DX7335`
- Connected nodes: four DGX Spark systems
- Host OS: NVIDIA DGX Spark Version 7.5.0 / Ubuntu 24.04 family
- GPU: NVIDIA GB10
- NVIDIA driver: `580.159.03`
- ConnectX driver: `mlx5_core`
- ConnectX firmware: `28.45.4028 (NVD0000000087)`
- Fabric MTU: `9000` at Linux Ethernet layer, RDMA test MTU reports `4096`
- Fabric IPs:
  - Spark 1: `192.0.2.10/24`
  - Spark 2: `192.0.2.10/24`
  - Spark 3: `192.0.2.10/24`
  - Spark 4: `192.0.2.10/24`

## Switch Evidence

CRS804 state:

```text
RouterOS: 7.23.1 (stable)
RouterBOOT current-firmware: 7.23.1
qos-hw-offloading=yes
Spark ports: fabric-port-a, fabric-port-b, fabric-port-c, fabric-port-d
Port speed: 200G-baseCR4 on all four
Port MTU: mtu=9000, l2mtu=9022 on all four
```

QoS/DCB state:

```text
DSCP 26 -> profile roce -> traffic-class 3
DSCP 48 -> profile cnp -> traffic-class 6
TC3 ecn=yes, ecn-actual=yes
PFC profile pfc-tc3 traffic-class=3 rx=yes tx=yes, hardware offloaded
Spark ports trust-l3=trust, pfc=pfc-tc3, egress-rate-queue3=100.0Gbps
```

Queue evidence after test traffic:

```text
fabric-port-a tx-queue3-packet moved, tx-drop-queue3-packet=0
fabric-port-b tx-queue3-packet moved, tx-drop-queue3-packet=0
fabric-port-c tx-queue3-packet moved, tx-drop-queue3-packet=0
No tx-drop, no FCS errors, no rx-too-long increments during measured tests
```

## Host Evidence

All four hosts:

```text
rocep1s0f0 -> enp1s0f0np0 (Up)
roceP2p1s0f0 -> enP2p1s0f0np0 (Up)
dcb pfc: priority 3 on, all other priorities off
dcb app: AF31:3 CS6:6
dgx-roce-qos.service active
ssh active
```

Privileged checks previously showed `cma_roce_tos -d rocep1s0f0 -p 1` = `106`
on all four. A non-public-root verifier can read that value only on nodes where public-root or
passwordless sudo is available.

All four hosts log the same mlx5 power message after reboot:

```text
Detected insufficient power on the PCIe slot (27W).
```

## RDMA Tests

Command shape:

```bash
ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12 <peer-fabric-ip>
```

Observed results:

```text
Spark 1 -> Spark 2: 6.62 Gbits/sec
Spark 1 -> Spark 2 evidence-wrapper retest: 6.67 Gbits/sec
Spark 2 -> Spark 1: 6.70 Gbits/sec
Spark 3 -> Spark 4: 6.63-6.67 Gbits/sec
Spark 1 -> Spark 3: 6.74 Gbits/sec
Spark 1 -> Spark 2 using roceP2p1s0f0: 6.67 Gbits/sec
```

Perftest output consistently reports:

```text
Link type: Ethernet
GID index: 3
MTU: 4096
rdma_cm QPs: ON
Transport type: IB
Connection type: RC
```

## Already Tried

- Upgraded CRS804 from RouterOS `7.21.4` to `7.23.1`.
- Upgraded RouterBOOT to `7.23.1`.
- Configured CRS804 DSCP/PFC/ECN policy for RoCEv2 and CNP.
- Configured host DCB PFC priority 3 and DSCP app mapping.
- Set `cma_roce_tos=106`.
- Rebooted all four Sparks with final cabling connected.
- Tested Spark 1/2, Spark 3/4, cross-cage Spark 1/3, and alternate RoCE
  function paths.
- Confirmed CRS804 queue3 classification and zero queue drops during tests.

## Evidence Bundle

The local repo includes a capture wrapper:

```bash
cd "/path/to/dgx-cluster"
CRS804_SSH=public-admin@192.0.2.10 scripts/capture-roce-evidence.sh
```

This writes host verifier output, pass/fail exit code, and optional CRS804
counter snapshots under `evidence/`.

## Question

Is this a known DGX Spark / ConnectX-7 power-state or firmware issue? If the
full cold power drain does not recover the link, what driver/firmware or
platform diagnostic should be collected next?
