# Six Spark Firmware Sweep - 2026-06-30

This note records the six-node firmware inventory after Spark 1 and Spark 2
were powered back on from the cold-drain test window.

## Repository State Before Sweep

Before running this firmware verification, the working tree was clean and the
branch was already pushed:

```text
codex/nccl-rdma-validation...origin/codex/nccl-rdma-validation
a8f51d3 Record Spark 5 and 6 baseline
```

## Reachability

All six Sparks were online in Tailscale and reachable over SSH with the NVIDIA
Sync key.

| Alias | Hostname | Tailscale IP | Uptime during sweep |
| --- | --- | --- | --- |
| `spark-a.example` | `spark-a.example` | `192.0.2.10` | `up 4 minutes` |
| `spark-b.example` | `spark-b.example` | `192.0.2.10` | `up 4 minutes` |
| `spark-c.example` | `spark-c.example` | `192.0.2.10` | `up 1 hour, 35 minutes` |
| `spark-d.example` | `spark-d.example` | `192.0.2.10` | `up 1 hour, 35 minutes` |
| `spark-e.example` | `spark-e.example` | `192.0.2.10` | `up 9 minutes` |
| `spark-f.example` | `spark-f.example` | `192.0.2.10` | `up 3 minutes` |

All six reported `reboot_required=no`.

## fwupd State

All six nodes ran `fwupdmgr get-upgrades`. Every node reported no available
firmware updates.

`fwupdmgr --version` reported:

```text
runtime org.freedesktop.fwupd-efi 1.4
runtime org.freedesktop.fwupd     2.0.20
```

The platform firmware inventory was uniform across all six nodes:

| Device | Version |
| --- | --- |
| DGX Spark Platform Key | `2025` |
| Embedded Controller | `0x03000302` |
| UEFI CA | `2023` |
| UEFI Device Firmware | `0x0200980f` |
| UEFI Device Firmware | `0x00000516` |
| UEFI dbx | `20230501` |
| Windows UEFI CA | `2023` |

## ConnectX-7 Firmware

Spark 1 through Spark 4 had visible ConnectX-7 devices in `mlxfwmanager` and all
reported the same firmware baseline:

```text
Device Type: ConnectX7
Description: NVIDIA DGX Spark P4242
PSID: NVD0000000087
FW: 28.45.4028
UEFI: 14.37.0014
Available: N/A
Status: No matching image found
```

Per-node ConnectX-7 base GUIDs:

| Alias | Hostname | PCI device | Base GUID |
| --- | --- | --- | --- |
| `spark-a.example` | `spark-a.example` | `0000:01:00.0` | `4cbb4703002bab32` |
| `spark-b.example` | `spark-b.example` | `0000:01:00.0` | `4cbb4703002afaf5` |
| `spark-c.example` | `spark-c.example` | `0000:01:00.0` | `4cbb4703002d5e4a` |
| `spark-d.example` | `spark-d.example` | `0000:01:00.0` | `4cbb4703002d782a` |

Spark 5 and Spark 6 did not expose ConnectX-7 devices during this sweep:

```text
mlxfwmanager: No devices found or specified
mst status: No MST devices were found
lspci: no Mellanox/ConnectX function present
ibdev2netdev: no RDMA device output
```

This is not marked as a firmware-update failure because Spark 5 and Spark 6 are
not yet physically connected to the QSFP fabric. Recheck their ConnectX-7
firmware after the QSFP links are cabled and enumerated.

## Result

No firmware update is currently pending on any visible DGX Spark platform
firmware device.

ConnectX-7 firmware is current and uniform on Spark 1 through Spark 4. Spark 5
and Spark 6 need a follow-up NIC firmware inventory after high-speed fabric
cabling.

## Spark 1 To Spark 2 Cold-Drain Retest

After Spark 1 and Spark 2 were powered back on, both visible 200G functions came
up on each host:

```text
enp1s0f0np0:   200000Mb/s, lanes=2, link detected=yes
enP2p1s0f0np0: 200000Mb/s, lanes=2, link detected=yes
rocep1s0f0:    ACTIVE, LINK_UP
roceP2p1s0f0:  ACTIVE, LINK_UP
```

The primary fabric IPs persisted:

```text
spark-a.example enp1s0f0np0 192.0.2.10/24
spark-b.example enp1s0f0np0 192.0.2.10/24
```

The temporary secondary-rail `192.0.2.10/24` addresses did not persist, which is
expected because they were not written as persistent netplan/systemd-networkd
configuration.

Primary-rail validation from Spark 1 to Spark 2:

| Check | Result |
| --- | --- |
| Jumbo ping | `3/3` packets, `0%` loss with `ping -s 8972 -M do 192.0.2.10` |
| TCP | `iperf3 -P 16 -t 15` reported `111 Gbits/sec`, `0` retransmits |
| RDMA | `ib_write_bw -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12 192.0.2.10` reported `111.85 Gbits/sec` |

The first non-sudo RDMA run failed with `Couldn't allocate MR` because the shell
memlock limit was `8192` KB. Re-running with sudo and `ulimit -l unlimited`
cleared that test-resource limit.

Reverse primary-rail validation from Spark 2 to Spark 1:

| Check | Result |
| --- | --- |
| Jumbo ping | `3/3` packets, `0%` loss with `ping -s 8972 -M do 192.0.2.10` |
| TCP | `iperf3 -P 16 -t 15` reported `111 Gbits/sec`, `0` retransmits |
| RDMA | `ib_write_bw -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12 192.0.2.10` reported `111.85 Gbits/sec` |

This confirms the direct Spark 1 / Spark 2 primary rail is healthy in both
directions after the cold-drain procedure. The next validation step is to move
the links back through the CRS804 and retest the same traffic class with switch
and host counters captured around the run.
