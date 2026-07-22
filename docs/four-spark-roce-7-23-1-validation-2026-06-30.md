# Four Spark RoCE Validation - 2026-06-30

This note records the live state after using Perplexity plus primary sources to
chase the first three CRS804/Spark fabric goals:

1. prove the CRS804 is correctly running the Spark fabric;
2. get RoCE/RDMA working as intended with observable switch and host counters;
3. validate NCCL only after the RDMA underlay is healthy.

## Result

Goal 1 is complete. The CRS804 is now on the source-backed CRS8xx QoS release
line, all four Spark fabric ports are up at 200G, jumbo MTU is active, and
traffic is hardware-classified into the intended RoCE queue.

Goal 2 is partially complete. RoCE/DCB classification is now correct on the
switch and hosts, but raw `ib_write_bw` remains capped at single-digit Gbps.
That means RDMA is connected, but not healthy enough to call the fabric done.

Goal 3 is intentionally not run as a throughput conclusion. NVIDIA's NCCL
troubleshooting guidance says to validate low-level RDMA before blaming NCCL,
and the low-level RDMA path is still capped.

## Source-Backed Decisions

- MikroTik documents RoCEv2 as DSCP `26`, CNP as DSCP `48`, RoCE traffic-class
  `3`, CNP traffic-class `6`, with PFC and ECN for lossless RoCE.
- MikroTik documents RouterOS `7.23` QoS changes for new Marvell Prestera
  switches, including auto DSCP mapping and lossless traffic classes.
- MikroTik release notes for `7.23` add ECN/PFC support on CRS8xx. The CRS804
  was upgraded to the later `7.23.1` stable patch before testing.
- NVIDIA's DGX Spark performance guide expects the active RoCE interfaces to
  be used for IP assignment and `ib_write_bw` testing before higher-level
  workload testing.
- NVIDIA Developer Forum reports for DGX Spark show a very similar class of
  symptoms: 200G link negotiation with `ib_write_bw`/`iperf3` capped around
  10-16 Gbps, firmware `28.45.4028`, driver `580.159.03`, and repeated
  `Detected insufficient power on the PCIe slot (27W)` mlx5 messages. Forum
  replies disagree on whether that warning is cosmetic, but several users
  recovered by rebooting or fully power-draining after final QSFP topology was
  connected.

Sources:

- MikroTik QoS documentation:
  <https://help.mikrotik.com/docs/spaces/ROS/pages/189497483/Quality%2Bof%2BService>
- MikroTik RouterOS `7.23` release note:
  <https://forum.mikrotik.com/t/v7-23-stable-is-released/270721>
- MikroTik RouterOS `7.23.1` release note:
  <https://forum.mikrotik.com/t/v7-23-1-stable-is-released/270884>
- NVIDIA DGX Spark performance guide:
  <https://raw.githubusercontent.com/NVIDIA/dgx-spark-playbooks/main/nvidia/connect-two-sparks/assets/performance_benchmarking_guide.md>
- NVIDIA forum, ConnectX-7 27W / low-throughput thread:
  <https://forums.developer.nvidia.com/t/connectx-7-inter-spark-link-capped-at-13-gbps-expected-200-gbps-pcie-power-throttling-27w/363461>
- NVIDIA forum, direct QSFP low-throughput thread:
  <https://forums.developer.nvidia.com/t/dgx-spark-direct-qsfp-connection-only-getting-13-16-gbps-instead-of-expected-200g-performance/370035>

## Switch State

The CRS804 was backed up, upgraded, and verified:

- Pre-upgrade export: `crs804-before-goal123-2026-06-30.rsc`
- Pre-upgrade backup: `crs804-before-goal123-2026-06-30.backup`
- Post-upgrade export before QoS: `crs804-after-7-23-1-before-qos-test.rsc`
- Post-QoS export: `crs804-after-7-23-1-roce-qos-four-spark.rsc`
- Post-QoS backup: `crs804-after-7-23-1-roce-qos-four-spark.backup`

Verified live state:

| Item | State |
| --- | --- |
| Model | `CRS804-4DDQ` |
| RouterOS | `7.23.1 (stable)` |
| RouterBOOT | `7.23.1` |
| Switch chip | `Marvell-98DX7335` |
| QoS offload | `qos-hw-offloading=yes` |
| Fabric bridge | `cluster-bridge`, MTU `9000`, protocol-mode `none` |
| Spark ports | `fabric-port-a`, `fabric-port-b`, `fabric-port-c`, `fabric-port-d` |
| Port speed | `200G-baseCR4` on all four |
| Port MTU | `mtu=9000`, `l2mtu=9022` on all four |

## CRS804 QoS/DCB Policy

The current CRS804 policy is intentionally kept, because it fixed the earlier
classification problem:

| Object | State |
| --- | --- |
| QoS profile `roce` | DSCP `26`, traffic-class `3`, hardware offloaded |
| QoS profile `cnp` | DSCP `48`, traffic-class `6`, hardware offloaded |
| IP DSCP maps | `26 -> roce`, `48 -> cnp`, hardware offloaded |
| VLAN PCP map | `pcp=0 -> roce`, hardware offloaded |
| TC1 | high-priority-group, weight `1` |
| TC3 | high-priority-group, weight `1`, `ecn=yes`, `ecn-actual=yes` |
| TC6 | strict-priority |
| PFC profile | `pfc-tc3`, traffic-class `3`, `rx=yes`, `tx=yes`, hardware offloaded |
| Spark port policy | `trust-l3=trust`, `pfc=pfc-tc3`, `egress-rate-queue3=100.0Gbps` |

The important change from the failed RouterOS `7.21.4` test is that queue3 now
moves. Final switch stats showed Spark traffic landing in `tx-queue3` with zero
per-queue drops:

| Port | Observed queue evidence |
| --- | --- |
| `fabric-port-a` | `tx-queue3-packet=7,596,406`, `tx-drop-queue3-packet=0` |
| `fabric-port-b` | `tx-queue3-packet=21,517,170`, `tx-drop-queue3-packet=0` |
| `fabric-port-c` | `tx-queue3-packet=4,560,164`, `tx-drop-queue3-packet=0` |

Final stats also showed no `rx-too-long`, no FCS errors, no overflow, no jabber,
and no transmit drops. `rs-fec-uncorrected` had a small cumulative value of `6`
on the visible ports after reboot/cabling, so it should be watched, but it did
not increment in the measured tests and does not explain the sustained
single-digit Gbps cap by itself.

## Spark Host State

All four connected Sparks are reachable over Tailscale SSH and have the same
RoCE host policy:

| Alias | Hostname | Tailscale name | Fabric IP | CRS804 port |
| --- | --- | --- | --- | --- |
| Spark 1 | `spark-a.example` | `spark-a.example` | `192.0.2.10/24` | `fabric-port-a` |
| Spark 2 | `spark-b.example` | `spark-b.example` | `192.0.2.10/24` | `fabric-port-b` |
| Spark 3 | `spark-c.example` | `spark-c.example` | `192.0.2.10/24` | `fabric-port-c` |
| Spark 4 | `spark-d.example` | `spark-d.example` | `192.0.2.10/24` | `fabric-port-d` |

Uniform host checks:

- `ssh` is active on all four.
- `dgx-roce-qos.service` is active on all four.
- `enp1s0f0np0` is up with the expected `192.0.2.x/24` address on all four.
- `rocep1s0f0 -> enp1s0f0np0 (Up)` on all four.
- `roceP2p1s0f0 -> enP2p1s0f0np0 (Up)` on all four.
- `dcb pfc show dev enp1s0f0np0` reports priority `3:on`, all other priorities
  off on all four.
- `dcb app show dev enp1s0f0np0` reports `AF31:3 CS6:6` on all four.
- `cma_roce_tos -d rocep1s0f0 -p 1` reports `106` on all four.
- NVIDIA driver is `580.159.03` on all four.
- ConnectX firmware is `28.45.4028 (NVD0000000087)` on all four.
- Each Spark logs `Detected insufficient power on the PCIe slot (27W)` for the
  ConnectX functions after reboot.

The persistent host policy lives here on each Spark:

```text
/usr/local/sbin/dgx-roce-qos.sh
/etc/systemd/system/dgx-roce-qos.service
```

## Throughput Evidence

The final retest after reboot and persistent host QoS still capped raw RDMA:

```text
spark-a.example -> spark-b.example
ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12 spark-b.example

BW average: 6.70 Gbits/sec
GID index: 3
MTU: 4096
Link type: Ethernet
```

Earlier discriminator tests matched the same failure family:

| Test | Result |
| --- | ---: |
| Spark 1 -> Spark 2, `rocep1s0f0`, `-R -q 4 -D 30` | `5.42 Gbits/sec` |
| Spark 1 -> Spark 2, `rocep1s0f0`, `-R -q 8 -s 8388608 -D 20` | `6.72 Gbits/sec` |
| Spark 2 -> Spark 1, `rocep1s0f0`, reverse direction | `6.70 Gbits/sec` |
| Spark 1 -> Spark 2, `roceP2p1s0f0`, temporary `192.0.2.10/24` | `6.67 Gbits/sec` |
| Spark 1 -> Spark 3, cross-cage on CRS804 | `6.74 Gbits/sec` |
| Spark 1 -> Spark 2, TCP `iperf3 --tos 0x68 -P 8` | `8.20 Gbits/sec` receiver with heavy retransmits |
| Spark 3 -> Spark 4, `rocep1s0f0`, LAN SSH retest | `6.64-6.67 Gbits/sec` |
| Verifier shakedown, Spark 1 -> Spark 2 via LAN aliases | `6.62 Gbits/sec` |
| Evidence wrapper shakedown, Spark 1 -> Spark 2 | `6.67 Gbits/sec` |
| Evidence wrapper shakedown, Spark 3 -> Spark 4 | `6.63 Gbits/sec` |

Interpretation: the switch now classifies the traffic correctly, but both RDMA
and TCP payload throughput remain capped. Because the cap reproduces across
directions, RoCE functions, and cross-cage switch paths, this is now best
classified as a Spark/ConnectX/firmware/power-state issue rather than a CRS804
queue classification problem.

## Post-Cold-Drain / PFC Bypass Evidence

After the full Spark cold power-cycle, the hosts and switch still showed healthy
physical link state:

- all four Sparks were reachable over SSH;
- `192.0.2.10-14/24` were present on `enp1s0f0np0`;
- `ethtool` still reported `200000Mb/s`, full duplex, link detected;
- `rdma link` reported `ACTIVE` / `LINK_UP`;
- jumbo `ping -s 8972 -M do` from Spark 1 to Spark 2 passed;
- CRS804 Spark ports stayed at `200G-baseCR4`, `mtu=9000`, `l2mtu=9022`;
- CRS804 switch counters still showed zero transmit drops, zero pause frames,
  zero FCS errors, and zero `rx-error-events` during the bad runs.

The post-drain verifier still failed the raw RDMA gate:

| Test | Result |
| --- | ---: |
| Spark 1 -> Spark 2, verifier `ib_write_bw` | `6.64 Gbits/sec` |
| Spark 3 -> Spark 4, verifier `ib_write_bw` | `6.70 Gbits/sec` |
| Spark 1 -> Spark 2, `iperf3 -P 16 -t 20` | `8.85 Gbits/sec`, about `51k` retransmits |
| Spark 1 -> Spark 2, `iperf3 --dscp 26 -P 16 -t 20` | `8.93 Gbits/sec`, about `57k` retransmits |
| Spark 1 -> Spark 3, cross-cage `iperf3 --dscp 26 -P 16 -t 20` | `9.06 Gbits/sec`, about `55k` retransmits |
| Spark 1 -> Spark 2, zero-copy `iperf3 --dscp 26 -Z -P 16 -t 20` | `8.77 Gbits/sec`, about `60k` retransmits |

This disproves the weaker "single `ib_write_bw` artifact" explanation. Plain
TCP over the same fabric is also capped around 9 Gbps and retransmitting heavily.

An additional CRS804 isolation test temporarily changed only the Spark 1 and
Spark 2 switch QoS port objects from:

```text
trust-l3=trust pfc=pfc-tc3
```

to:

```text
trust-l3=ignore pfc=disabled
```

The CRS804 config was exported first as `crs804-before-pfc-bypass-test`, and
the two ports were restored after the test. While bypassed, TCP did not improve:

```text
Spark 1 -> Spark 2 iperf3 -P 16 -t 20
receiver: 9.13 Gbits/sec
sender retransmits: 55,020
```

RDMA also did not improve. With the bypass active,
`ib_write_bw -d rocep1s0f0 -x 3 -F --report_gbits -q 8 -s 8388608 -D 12
192.0.2.10` failed immediately:

```text
Completion with error at client
Failed status 12: wr_id 7 syndrom 0x81
```

The live switch restore was verified:

```text
fabric-port-a trust-l3=trust pfc=pfc-tc3 egress-rate-queue3=100.0Gbps
fabric-port-b trust-l3=trust pfc=pfc-tc3 egress-rate-queue3=100.0Gbps
```

Current interpretation: the obvious CRS804 DSCP/PFC trust path is not the fix.
The next isolation step is either a direct Spark-to-Spark QSFP link that bypasses
the CRS804 entirely, or host-side MFT diagnostics with `mlxlink` so the
ConnectX lane/state details are no longer inferred from `ethtool` alone.

## MFT Diagnostic Gate

Two repeatable helpers now exist for the next host-side diagnostic step:

```bash
scripts/install-mft-tools.sh
scripts/capture-mft-evidence.sh
```

`scripts/install-mft-tools.sh` is dry-run by default. It was then run with
`APPLY_MFT_INSTALL=1` after Spark 3 and Spark 4 had passwordless sudo. The
NVIDIA `mft` package installed uniformly on all four Sparks:

```text
mft 192.0.2.10-1
```

The current `mft` package on these ARM64 DGX Spark systems provides `mst`,
`mlxlink`, `mlxfwmanager`, `mlxconfig`, and `mstflint`, but not `mlxstat`. The
helper scripts were updated to treat `mlxstat` as optional.

`mst start` reports missing `mst_pci` / `mst_pciconf` modules on the
`6.17.0-1021-nvidia` kernel, but `mst status -v` still exposes the ConnectX-7
PCI functions and `mlxlink -d <PCI-BDF>` works. The source evidence bundle is:

```bash
evidence/mft-20260630-100025/
```

MFT verdict for every active ConnectX function on every Spark:

| Host | PCI function | State | Speed | Width | FEC | MFT recommendation |
| --- | --- | --- | ---: | ---: | --- | --- |
| `spark-a.example` | `0000:01:00.0` | `Active` | `200G` | `4x` | `Standard_RS-FEC - (544,514)` | `No issue was observed` |
| `spark-a.example` | `0002:01:00.0` | `Active` | `200G` | `4x` | `Standard_RS-FEC - (544,514)` | `No issue was observed` |
| `spark-b.example` | `0000:01:00.0` | `Active` | `200G` | `4x` | `Standard_RS-FEC - (544,514)` | `No issue was observed` |
| `spark-b.example` | `0002:01:00.0` | `Active` | `200G` | `4x` | `Standard_RS-FEC - (544,514)` | `No issue was observed` |
| `spark-c.example` | `0000:01:00.0` | `Active` | `200G` | `4x` | `Standard_RS-FEC - (544,514)` | `No issue was observed` |
| `spark-c.example` | `0002:01:00.0` | `Active` | `200G` | `4x` | `Standard_RS-FEC - (544,514)` | `No issue was observed` |
| `spark-d.example` | `0000:01:00.0` | `Active` | `200G` | `4x` | `Standard_RS-FEC - (544,514)` | `No issue was observed` |
| `spark-d.example` | `0002:01:00.0` | `Active` | `200G` | `4x` | `Standard_RS-FEC - (544,514)` | `No issue was observed` |

The inactive `.1` functions report `Cable is unplugged`, which matches the
current single-link-per-Spark cabling and is not the active-fabric failure.

Current interpretation after MFT: the NIC physical layer also looks clean. The
next source-backed isolation step was a direct Spark 1 <-> Spark 2 QSFP link
test that bypassed the CRS804 entirely.

The RoCE verifier was rerun after MFT installation. MFT did not change the
underlay result:

| Test | Post-MFT result |
| --- | ---: |
| Spark 1 -> Spark 2, verifier `ib_write_bw` | `6.71 Gbits/sec` |
| Spark 3 -> Spark 4, verifier `ib_write_bw` | `6.71 Gbits/sec` |

So MFT cleared the physical-link diagnostic gate, but the raw RDMA throughput
gate still fails.

## Direct Spark Cable Gate

Spark 1 and Spark 2 were physically connected with the NVIDIA-supplied
Spark-to-Spark cable, bypassing the CRS804. This removed the switch from the
test path.

Both hosts detected the cable and re-enumerated the ConnectX-7 functions:

| Host | Interface | Link state |
| --- | --- | --- |
| `spark-a.example` | `enp1s0f0np0` | `200000Mb/s`, `Lanes: 2`, `LINK_UP` |
| `spark-a.example` | `enP2p1s0f0np0` | `200000Mb/s`, `Lanes: 2`, `LINK_UP` |
| `spark-b.example` | `enp1s0f0np0` | `200000Mb/s`, `Lanes: 2`, `LINK_UP` |
| `spark-b.example` | `enP2p1s0f0np0` | `200000Mb/s`, `Lanes: 2`, `LINK_UP` |

Jumbo ping over the primary direct path passed:

```text
spark-a.example -> 192.0.2.10
ping -c 3 -s 8972 -M do 192.0.2.10
3 packets transmitted, 3 received, 0% packet loss
```

Direct TCP improved versus the CRS804 path because retransmits disappeared, but
throughput was still far below the expected fabric class:

```text
iperf3 -c 192.0.2.10 -P 16 -t 20
[SUM] 0.00-20.00 sec 29.9 GBytes 12.8 Gbits/sec 0 retransmits
```

Direct RDMA stayed in the same low-throughput family:

```text
ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12 192.0.2.10
BW average: 12.71 Gbits/sec
GID index: 3
MTU: 4096
Link type: Ethernet
```

This is the current discriminator: the CRS804 path made the symptom worse
(`~6.7 Gbits/sec` RDMA and TCP retransmits), but a clean direct Spark cable only
recovers to `~12.7 Gbits/sec`. The primary bottleneck now follows the DGX Spark
host/NIC/driver stack even when the switch is absent.

Perplexity was used as a sidekick after the direct cable result. It converged on
the same next diagnostic lane: collect PCIe slot power capability, driver/kernel
state, NIC firmware, and mlx5 health logs before continuing NCCL or switch QoS
tuning.

Support-grade host evidence collected on Spark 1 and Spark 2:

| Evidence | Spark 1 | Spark 2 |
| --- | --- | --- |
| Kernel | `6.17.0-1021-nvidia` | `6.17.0-1021-nvidia` |
| mlx5 module | `/lib/modules/6.17.0-1021-nvidia/.../mlx5_core.ko.zst` | same |
| PCIe link | `Speed 32GT/s, Width x4` | `Speed 32GT/s, Width x4` |
| Slot power | `SlotPowerLimit 0W` | `SlotPowerLimit 0W` |
| dmesg | `PCIe slot power capability was not advertised`; `Detected insufficient power on the PCIe slot (27W)` | same |
| Topology | GPU to NICs is `NODE`; NIC pairs are `PIX` within their local pair | same |

The NIC firmware query on Spark 2 reported:

```text
Device Type: ConnectX7
Part Number: cx7_P4242_HORIZON_PK_Ax
Description: NVIDIA DGX Spark P4242
PSID: NVD0000000087
FW: 28.45.4028
Status: No matching image found
```

## NCCL Decision

Do not use NCCL throughput as the next grading step yet. Running NCCL now would
only prove that NCCL rides on a broken underlay. The next valid NCCL gate is:

- at least one two-node `ib_write_bw` path reaches the expected order of
  magnitude, roughly `90+ Gbits/sec` per active RoCE function;
- switch queue3 continues to move with zero drops during that test;
- host priority-3 counters and `cma_roce_tos=106` stay in place;
- no new switch FEC/error counters increment during the test window.

## Next Safe Action

The source-backed recovery path to try next is a full cold power drain, not more
NCCL tuning. A step-by-step version lives in
`docs/roce-cold-drain-runbook-2026-06-30.md`.

The post-drain verifier is `scripts/verify-roce-underlay.sh`. It defaults to the
working mDNS names `spark-a.example`, `spark-b.example`, `spark-c.example`,
and `spark-d.example`, then fails if either tested RDMA pair is below
`90 Gbits/sec`.

For a support-grade run, use `scripts/capture-roce-evidence.sh`. It writes a
timestamped ignored bundle under `evidence/` with host verifier logs, exit code,
and optional CRS804 switch counters when `CRS804_SSH=public-admin@192.0.2.10` is set.

1. Leave the final QSFP topology connected.
2. Shut down all four Sparks cleanly.
3. Disconnect Spark power leads.
4. Wait a few minutes.
5. Press each Spark power button while unplugged to discharge residual state.
6. Reconnect power and boot.
7. Verify `dgx-roce-qos.service`, `ssh`, `192.0.2.x`, `cma_roce_tos=106`, and
   `dcb app` again.
8. Run `ib_write_bw` in both directions for Spark 1/2 and Spark 3/4 before
   touching NCCL.

If a cold drain does not recover at least one pair to the expected
`90+ Gbits/sec` class, the next move should be an NVIDIA support/forum post with
this evidence bundle: RouterOS `7.23.1`, queue3 classification proven, host DCB
uniform, firmware `28.45.4028`, driver `580.159.03`, PCIe x4 Gen5 bandwidth
present, and `ib_write_bw` still capped at `6.70 Gbits/sec`.
