# Four Spark Cluster Baseline - 2026-06-29

This note records the four-node CRS804/DGX Spark baseline after adapting the
playbook to use `public-user` as the cluster user.

## Scope

Only the first four Sparks are connected:

| Alias | Hostname | Tailscale name | Fabric IP | CRS804 port |
| --- | --- | --- | --- | --- |
| `spark-a.example` | `spark-a.example` | `spark-a.example` | `192.0.2.10/24` | `fabric-port-a` |
| `spark-b.example` | `spark-b.example` | `spark-b.example` | `192.0.2.10/24` | `fabric-port-b` |
| `spark-c.example` | `spark-c.example` | `spark-c.example` | `192.0.2.10/24` | `fabric-port-c` |
| `spark-d.example` | `spark-d.example` | `spark-d.example` | `192.0.2.10/24` | `fabric-port-d` |

## Uniform Baseline

All four nodes now match on the cluster-facing baseline:

- OS: Ubuntu 24.04.4 LTS.
- Kernel: `6.17.0-1021-nvidia`.
- NVIDIA driver: `580.159.03`.
- CUDA header reported by `nvidia-smi`: `13.0`.
- Fabric NIC: `enp1s0f0np0`.
- Fabric NIC state: `carrier=1`, `speed=200000`, `mtu=9000`.
- Cluster user: `public-user`.
- Tailscale and OpenSSH services: active.
- `/etc/hosts` includes `spark-a.example` through `spark-d.example` on `192.0.2.10/24`.
- `/opt/public-user/.ssh/config` has a cluster `Host spark-*.example` block using `/opt/public-user/.ssh/id_ed25519`.
- `/opt/public-user/.ssh/authorized_keys` contains the four normalized cluster public keys:
  - `spark-a.example-cluster`
  - `spark-b.example-cluster`
  - `spark-c.example-cluster`
  - `spark-d.example-cluster`
- `/opt/public-user/.bashrc` starts with the cluster environment block:
  - `UCX_NET_DEVICES=enp1s0f0np0`
  - `NCCL_SOCKET_IFNAME=enp1s0f0np0`
  - `OMPI_MCA_btl_tcp_if_include=enp1s0f0np0`
  - `NCCL_IB_DISABLE=0`
  - `NCCL_IB_HCA=rocep1s0f0`
  - `NCCL_NET_GDR_LEVEL=2`

The env block is intentionally placed at the top of `.bashrc` so `source /opt/public-user/.bashrc`
sets the variables even from non-interactive test shells.

## Installed Benchmark Baseline

All four nodes have:

- `iperf3` 3.16.
- Open MPI 4.1.6.
- GCC 13.3.0.
- GNU Make 4.3.
- Git 2.43.0.
- `build-essential`, `libopenmpi-dev`, and `pkg-config`.

## Verified

Passwordless cluster SSH works from every node to every node:

```text
spark-a.example -> spark-a.example/spark-b.example/spark-c.example/spark-d.example OK
spark-b.example -> spark-a.example/spark-b.example/spark-c.example/spark-d.example OK
spark-c.example -> spark-a.example/spark-b.example/spark-c.example/spark-d.example OK
spark-d.example -> spark-a.example/spark-b.example/spark-c.example/spark-d.example OK
```

Jumbo-frame mesh passed earlier after setting the CRS804 fabric ports and
`cluster-bridge` to `mtu=9000` and `l2mtu=9022`.

UFW was normalized for the fabric:

- Spark 1 and Spark 2 have active UFW and allow `192.0.2.10/24`.
- Spark 3 and Spark 4 have UFW inactive, with the same allow rule recorded.

## Current Stop Point

The playbook `iperf3` step runs, but throughput is below the runbook expectation:

| Test | Result |
| --- | ---: |
| `spark-a.example -> spark-b.example` | `9.42 Gbits/sec` receiver |
| `spark-a.example -> spark-c.example` | `9.30 Gbits/sec` receiver |
| `spark-a.example -> spark-d.example` | `9.43 Gbits/sec` receiver |

Each run used:

```bash
iperf3 -c spark0X -p 5201 -t 10 -P 4
```

The runbook expected roughly `18-22 Gbits/sec` for this TCP test. Because the
results are consistently lower and show many TCP retransmits, NCCL testing was
not started yet.

Read-only diagnostics showed:

- All four fabric NICs report `200000Mb/s`, full duplex, link detected.
- All four use TCP congestion control `cubic`.
- Host-side `ip -s link` shows zero RX/TX errors on `enp1s0f0np0`.
- Selected ConnectX stats show zero CRC, symbol, discard, and PHY TX error
  counters on the tested nodes, aside from small lane error counters.

Next investigation should check CRS804 interface statistics, bridge hardware
offload flags, switch-side error counters, and whether TCP/RDMA tuning is needed
before moving to NCCL tests.

## RDMA Inventory

RDMA inventory was checked before NCCL testing. NVIDIA DGX Spark does not support
GPUDirect RDMA as a Spark tuning target, but RoCE/RDMA and NCCL `NET/IB`
selection still need to be validated.

| Node | RDMA device for fabric | `ibv_devinfo` | Notes |
| --- | --- | --- | --- |
| `spark-a.example` | `rocep1s0f0` | present | Maps to `enp1s0f0np0`; `PORT_ACTIVE`; firmware `28.45.4028`. |
| `spark-b.example` | `rocep1s0f0` | present | Maps to `enp1s0f0np0`; `PORT_ACTIVE`; firmware `28.45.4028`. |
| `spark-c.example` | `rocep1s0f0` | present | Maps to `enp1s0f0np0`; `PORT_ACTIVE`; firmware `28.45.4028`. |
| `spark-d.example` | `rocep1s0f0` | present | Maps to `enp1s0f0np0`; `PORT_ACTIVE`; firmware `28.45.4028`. |

All four nodes already had `ibv_devinfo`, `rdma`, `ibdev2netdev`, and
`ib_write_bw`. The cluster env was corrected from `NCCL_IB_HCA=mlx5_0` to
`NCCL_IB_HCA=rocep1s0f0` on all four nodes after `ibdev2netdev` showed the
actual active HCA name.

### RDMA Verbs Stop Point

NCCL testing was not started because low-level RDMA verbs are working but badly
underperforming on the first Spark 1 -> Spark 2 test pair.

| Test | Result | Notes |
| --- | ---: | --- |
| `ib_write_bw -d rocep1s0f0 -F --report_gbits` | `0.23 Gbits/sec` average, `7.31 Gbits/sec` peak | Passed; default 64 KiB size, 5000 iterations. |
| `ib_write_bw -d rocep1s0f0 -F --report_gbits -s 1048576 -n 100 spark-b.example` | `0.12 Gbits/sec` average, `8.60 Gbits/sec` peak | Passed; GID index `3`, IPv4 RoCEv2 GIDs `192.0.2.10` and `192.0.2.10`. |
| `ib_write_bw -d rocep1s0f0 -F --report_gbits -s 1048576 -D 10 spark-b.example` | `0.096469 Gbits/sec` average | Passed; duration-based run completed 69 iterations. |
| `ib_write_bw -d rocep1s0f0 -F --report_gbits -s 8388608 -n 1000 spark-b.example` | inconclusive | The local protective timeout killed the server while the slow client was still running, causing client completion `status 12`, syndrome `0x81`; do not treat this as the public-root cause by itself. |

Read-only diagnostics after the verbs tests showed:

- Spark 1 and Spark 2 still had active RDMA links on `rocep1s0f0/1` and
  `roceP2p1s0f0/1`.
- `show_gids` confirmed `rocep1s0f0` has IPv4 RoCEv2 GID index `3` for the
  `192.0.2.10/24` fabric. `roceP2p1s0f0` is up but did not have the fabric IPv4
  GID, so it is not the current cluster fabric device.
- Host-side `ethtool -S enp1s0f0np0` did not show CRC, symbol, discard, pause,
  or PHY TX/RX error counters increasing on the checked pair.
- Kernel logs on the checked pair reported ConnectX firmware `28.45.4028` and
  `126.028 Gb/s available PCIe bandwidth (32.0 GT/s PCIe x4 link)`.
- Kernel logs also included `Detected insufficient power on the PCIe slot (27W)`
  for the mlx5 functions during link bring-up. Treat that as evidence to
  research, not a confirmed public-root cause yet.

Next checks should happen on the CRS804 before NCCL:

```routeros
/interface ethernet monitor fabric-port-a once
/interface ethernet monitor fabric-port-b once
/interface ethernet print stats where name="fabric-port-a" or name="fabric-port-b"
/interface bridge port print detail where interface="fabric-port-a" or interface="fabric-port-b"
```

The immediate question is whether the switch ports show FEC, pause, MAC, PCS,
lane, or discard counters that explain why RoCE works functionally but performs
far below the already-low TCP result.

### CRS804 Switch-Side Evidence

The first switch-side check for Spark 1 and Spark 2 did not show an obvious
physical-link or hardware-offload failure.

| Port | Node | Link | FEC | Queue drops | RS-FEC corrected | RS-FEC uncorrected | Notable errors |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `fabric-port-a` | `spark-a.example` | `200Gbps`, full duplex | `fec91` | `0` | `0` | `0` | `rx-too-long=49`, `rx-error-events=49` |
| `fabric-port-b` | `spark-b.example` | `200Gbps`, full duplex | `fec91` | `0` | `2` | `0` | `rx-too-long=53`, `rx-error-events=53` |

Both ports report the FS `QDD-400G-2QPC015` 2 m breakout assembly, module state
`ready`, and eeprom checksum `good`. Both bridge-port entries are on
`cluster-bridge` with `hw=yes`, and RouterOS prints the hardware offload flag.

This mostly clears the switch physical layer:

- `rs-fec-uncorrected=0` on both ports.
- `rs-fec-corrected=0` and `2` across more than `271B` codewords, which is
  effectively clean.
- `tx-drop-packet=0`, all per-queue transmit drops `0`.
- `rx-pause=0` and `tx-pause=0`.
- No FCS, fragment, overflow, jabber, underrun, or collision errors.

The remaining switch-side item to prove is whether `rx-too-long` increments
during an RDMA test. MikroTik documents `rx-too-long` as frames larger than the
maximum supported frame size for the network device, related to `max-l2mtu`.
The current counts are tiny relative to total packets, so they are suspicious
but not enough by themselves to explain sustained RDMA bandwidth below
`1 Gbits/sec`.

### CRS804 Counter Delta During RDMA Test

A before/after switch counter delta was captured around this test:

```bash
ib_write_bw -d rocep1s0f0 -F --report_gbits -s 1048576 -D 10 spark-b.example
```

The perftest result still reported only `0.095072 Gbits/sec` average, but the
CRS804 counters did not show an error/drop/MTU failure while the test was
running.

| Counter delta | `fabric-port-a` / Spark 1 | `fabric-port-b` / Spark 2 |
| --- | ---: | ---: |
| `rx-bytes` | `+17,594,807,240` | `+1,799,880` |
| `rx-packet` | `+4,231,536` | `+25,674` |
| `tx-bytes` | `+1,769,020` | `+12,951,272,501` |
| `tx-packet` | `+25,187` | `+3,114,801` |
| `rx-too-long` | `+0` | `+0` |
| `rx-error-events` | `+0` | `+0` |
| `tx-drop-packet` | `+0` | `+0` |
| `rs-fec-corrected` | `+0` | `+0` |
| `rs-fec-uncorrected` | `+0` | `+0` |

This makes a CRS804 physical-layer, FEC, queue-drop, or L2MTU rejection issue
less likely for the Spark 1 -> Spark 2 RDMA test. The next layer to investigate
is the Spark-side RDMA/perftest behavior: why `ib_write_bw` reports low
application-level bandwidth even though the switch sees multi-GB traffic during
the test window.

### Spark-Side RDMA Discriminator Tests

Additional Spark-side tests show the low-speed state is not resolved by changing
message size or adding QPs, and it is symmetric between Spark 1 and Spark 2.

| Test | Direction | Result | Notes |
| --- | --- | ---: | --- |
| `ib_write_bw -R -s 1048576 -D 10` | `spark-a.example -> spark-b.example` | `4.67 Gbits/sec` | RDMA-CM improved over non-RDMA-CM mode but stayed low. |
| `ib_write_bw -R -q 8 -s 1048576 -D 10` | `spark-a.example -> spark-b.example` | `5.83 Gbits/sec` | Multiple QPs helped slightly. |
| `ib_write_bw -R -q 16 -s 1048576 -D 10` | `spark-a.example -> spark-b.example` | `6.96 Gbits/sec` | Still far below expected. |
| `ib_write_bw -R -s 65536 -n 20000` | `spark-a.example -> spark-b.example` | `4.84 Gbits/sec` average, `9.40 Gbits/sec` peak | Forum-style fixed-iteration shape. |
| `ib_write_bw -R -q 4 -D 30` | `spark-a.example -> spark-b.example` | `4.70 Gbits/sec` | NVIDIA benchmarking-guide shape. |
| `ib_write_bw -R -q 4 -D 30` | `spark-b.example -> spark-a.example` | `4.71 Gbits/sec` | Same low-speed state in reverse direction. |

The local runbook confirms the intended cluster interface is `enp1s0f0np0`
(`rocep1s0f0`) for inter-node traffic. The Sparks also expose
`enP2p1s0f0np0` / `roceP2p1s0f0` on the same switch port, and the CRS804 learns
both MAC addresses, but the runbook does not instruct assigning the cluster IP
to the `P2p` interface.

An NVIDIA Developer Forum thread describes the same failure family: DGX Spark
ConnectX-7 links show `200000Mb/s`, PCIe `32GT/s x4`, firmware `28.45.4028`,
and `mlx5_pcie_event ... Detected insufficient power on the PCIe slot (27W)`,
while payload is stuck around `12.8-13.5 Gbits/sec`; users report recovery after
rebooting the affected endpoint with the final cabling connected:
<https://forums.developer.nvidia.com/t/connectx-7-inter-spark-link-capped-at-13-gbps-expected-200-gbps-pcie-power-throttling-27w/363461>

NVIDIA forum replies also say the `27W` power warning can be cosmetic because
the platform advertises `SlotPowerLimit 0W`, so this warning should not be
treated as the sole public-root cause:
<https://forums.developer.nvidia.com/t/pcie-power-related-and-pcie-aer-errors/353343>

Next recommended action is to reboot Spark 1 and Spark 2 with the current final
cabling left in place, then rerun:

```bash
ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 4 -D 30
ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 4 -D 30 spark-b.example
```

Expected healthy recovery is roughly `90-110 Gbits/sec` per direction before
moving on to NCCL.

### Spark 1 / Spark 2 Reboot Retest

Spark 1 and Spark 2 were rebooted with the current final cabling left connected.
Both returned over Tailscale, kept the expected fabric IPs, and showed
`rocep1s0f0` mapped to `enp1s0f0np0`.

| Check | Spark 1 | Spark 2 |
| --- | --- | --- |
| Hostname | `spark-a.example` | `spark-b.example` |
| Fabric IP | `192.0.2.10/24` | `192.0.2.10/24` |
| RDMA mapping | `rocep1s0f0 -> enp1s0f0np0 (Up)` | `rocep1s0f0 -> enp1s0f0np0 (Up)` |
| Link log | `enp1s0f0np0: Link up` | `enp1s0f0np0: Link up` |
| Firmware log | `28.45.4028` | `28.45.4028` |
| PCIe bandwidth log | `126.028 Gb/s available PCIe bandwidth (32.0 GT/s PCIe x4 link)` | `126.028 Gb/s available PCIe bandwidth (32.0 GT/s PCIe x4 link)` |

The reboot did not clear the low-speed RDMA state:

| Test | Direction | Before reboot | After reboot |
| --- | --- | ---: | ---: |
| `ib_write_bw -R -q 4 -D 30` | `spark-a.example -> spark-b.example` | `4.70 Gbits/sec` | `5.33 Gbits/sec` |
| `ib_write_bw -R -q 4 -D 30` | `spark-b.example -> spark-a.example` | `4.71 Gbits/sec` | `5.35 Gbits/sec` |

Post-reboot host counters stayed clean on both nodes:

- `rx_crc_errors_phy=0`, `rx_symbol_err_phy=0`, `rx_discards_phy=0`,
  `tx_discards_phy=0`, `tx_errors_phy=0`.
- `rx_out_of_buffer=0`, `rx_ecn_mark=0`, all priority discards `0`.
- InfiniBand/RDMA counters showed `port_rcv_errors=0`,
  `port_xmit_discards=0`, `port_xmit_wait=0`, and `symbol_error=0`.
- `devlink health show` reported healthy firmware, TX, and RX reporters with
  zero errors and zero recoveries.

This rules out the simple switch/cable/MTU/drop explanation for Spark 1 and
Spark 2. The remaining issue is a clean-but-slow Spark-side RoCE/ConnectX state.
Next escalation should compare against NVIDIA's official DGX Spark benchmarking
guide and consider NVIDIA support/forum escalation with this evidence bundle:
RouterOS bridge/port stats, `ibdev2netdev`, `ib_write_bw` before/after reboot,
host `ethtool -S`, `/sys/class/infiniband/.../counters`, and devlink health.

### Official Dual-Interface Benchmark Shape

NVIDIA's DGX Spark performance benchmarking guide assigns IPv4 addresses to
both up RoCE functions on each connected Spark:

- `rocep1s0f0` / `enp1s0f0np0`
- `roceP2p1s0f0` / `enP2p1s0f0np0`

The current cluster baseline only persists `192.0.2.10/24` on
`enp1s0f0np0`. To test the official two-function benchmark shape without
changing the baseline, temporary non-persistent addresses were added on Spark 1
and Spark 2 only:

| Node | Temporary interface | Temporary IP |
| --- | --- | --- |
| `spark-a.example` | `enP2p1s0f0np0` / `roceP2p1s0f0` | `192.0.2.10/24` |
| `spark-b.example` | `enP2p1s0f0np0` / `roceP2p1s0f0` | `192.0.2.10/24` |

The temporary `192.0.2.10/24` IPs were removed after testing. No persistent
Netplan, UFW, or systemd-networkd change was made.

Results:

| Test | Path | Result | Notes |
| --- | --- | ---: | --- |
| `ping -I enP2p1s0f0np0 192.0.2.10` | P2p function | `0%` loss | L3 reachability passed. |
| `ib_write_bw -R -d roceP2p1s0f0 -q 4 -D 30` | P2p function | `5.21 Gbits/sec` | Same low-speed class as `rocep1s0f0`. |
| Dual `ib_write_bw -R -q 4 -D 30` streams | Main + P2p functions | `3.76 + 3.71 = 7.47 Gbits/sec` | Two streams add slightly but remain far below expectation. |
| `iperf3 -B 192.0.2.10 -c 192.0.2.10 -P 8 -t 15` | Main function | `7.71 Gbits/sec` receiver | `30,030` TCP retransmits. |
| `iperf3 -B 192.0.2.10 -c 192.0.2.10 -P 8 -t 15` | P2p function | `8.12 Gbits/sec` receiver | Required a temporary runtime UFW allow on `192.0.2.10/24`; `32,677` TCP retransmits. |

The first P2p `iperf3` attempt hung because UFW allows `192.0.2.10/24` but not
the temporary `192.0.2.10/24` subnet. A runtime-only `iptables` allow was
inserted for the test and removed immediately afterward. With that firewall
gate removed, the P2p TCP result matched the main path, so the second function
is not dead.

Post-test host counters stayed clean:

- `rx_crc_errors_phy=0`, `rx_symbol_err_phy=0`, `rx_discards_phy=0`,
  `tx_discards_phy=0`, `tx_errors_phy=0`.
- `rx_out_of_buffer=0`, `rx_ecn_mark=0`, all priority discards `0`.
- RDMA counters stayed at `port_rcv_errors=0`,
  `port_xmit_discards=0`, and `local_link_integrity_errors=0`.

Interpretation: using the second RoCE function is necessary to mirror NVIDIA's
benchmarking guide, but it does not explain the current low throughput. Both
functions are clean, link-up at `200000Mb/s`, and similarly slow at the
application level. The remaining blocker is a clean-but-low host or ConnectX
data path, not a single dead switch port, cable, MTU, FEC, or UFW-only issue.

### RoCE QoS / DCB Evidence

Official source anchors:

- [MikroTik RouterOS Quality of Service](https://help.mikrotik.com/docs/spaces/ROS/pages/189497483/Quality%2Bof%2BService)
  lists CRS804 / `98DX7335` in the QoS support table and documents lossless
  RoCEv2 with PFC and ECN. It specifies DSCP `26` for RoCEv2, DSCP `48` for
  CNP, traffic-class `3` for RoCEv2, and traffic-class `6` for CNP. It also
  says RouterOS releases before `7.23` require manual DSCP-to-profile maps.
- [MikroTik RouterOS `7.23` stable release notes](https://forum.mikrotik.com/t/v7-23-stable-is-released/270721)
  explicitly add `qos-hw - added ECN and PFC support on CRS8xx switches`.
  The CRS804 was later moved to the newer
  [RouterOS `7.23.1`](https://forum.mikrotik.com/t/v7-23-1-stable-is-released/270884)
  stable patch before testing. This makes `7.23+` the first source-backed stable
  target for the CRS804 RoCE QoS test, even though the generic QoS menus exist
  on `7.21.4`.
- [NVIDIA's DGX Spark performance benchmarking guide](https://raw.githubusercontent.com/NVIDIA/dgx-spark-playbooks/main/nvidia/connect-two-sparks/assets/performance_benchmarking_guide.md)
  expects roughly `92.57 Gbits/sec` plus `97.28 Gbits/sec` across the two Spark
  RoCE functions in its two-Spark benchmark shape, for about
  `189.85 Gbits/sec` aggregate.
- An [NVIDIA Developer Forum response on DGX Spark GPUDirect RDMA](https://forums.developer.nvidia.com/t/dgx-spark-gpudirect-rdma/348787)
  says GPUDirect RDMA technology is not supported on DGX Spark, so the target
  here is a healthy host/RNIC RoCE path, not direct GPU-memory RDMA.

Live CRS804 read-only evidence from `switch-a`:

| Check | Result |
| --- | --- |
| RouterOS | `7.21.4 (long-term)` |
| Switch chip | `Marvell-98DX7335` |
| `qos-hw-offloading` | `yes` |
| Spark ports | `fabric-port-a`, `fabric-port-b`, `fabric-port-c`, `fabric-port-d` |
| Port QoS profile | `profile=default map=default` on all four Spark ports |
| Port trust | `trust-l2=ignore trust-l3=ignore` on all four Spark ports |
| Port PFC | `pfc=disabled` on all four Spark ports |
| Defined QoS profiles | only `default`, with `pcp=0 dscp=0 traffic-class=1` |
| DSCP map | empty |
| VLAN/PCP map | empty |
| Tx manager | only `default` |
| Tx queues | TC1 is hardware-offloaded low-priority; TC3 is inactive and `ecn=no` |
| Spark 1 queue counters | queue0/queue1 traffic only; queue3-queue7 zero; all queue drops zero |
| Spark 2 queue counters | queue0/queue1 traffic only; queue3-queue7 zero; all queue drops zero |
| PFC counters | `pfc=disabled`, all `pfc*-use` counters zero on checked port |

Host-side DCB/QoS read-only evidence from Spark 1 and Spark 2:

| Check | Result |
| --- | --- |
| `mlnx_qos` | `DCBX mode: OS controlled` |
| Priority trust | `pcp` |
| PFC configuration | enabled `0` for priorities `0-7` |
| `dcb pfc show` | `prio-pfc` all `off` |
| `dcb ets show` | vendor/default traffic-class mapping |
| `dcb app show` | no application-priority entries returned |
| TCP ECN sysctl | `net.ipv4.tcp_ecn = 2` |
| Jumbo ping | `ping -s 8972 -M do` succeeds both directions over `192.0.2.10/24` |
| LLDP | `lldpd` active; CRS804 visible on `enp1s0f0np0` and `enP2p1s0f0np0` |
| LLDP DCB TLVs | DCBX-like unknown TLVs visible from CRS804, but PFC-related TLV content is default/zero |

Interpretation before the write test: the switch had the QoS engine available
and enabled, but the Spark ports and hosts were both best-effort/default. After
the bounded write test below, the source-backed hypothesis is narrower:
RouterOS `7.21.4` exposes CRS804 QoS objects, but MikroTik's own `7.23` stable
notes are the first clear release note for CRS8xx ECN/PFC support. This is
separate from the Perplexity-generated framework's wrong NCCL defaults; the
low-level `ib_write_bw` and TCP tests already underperform before
application-level NCCL tuning can matter.

No intended switch config changes were made during this evidence pass. While
unpaging a RouterOS stats table, the terminal pager created `console-dump.txt`;
that scratch file was removed immediately.

Read-only CRS804 commands used or still useful:

```routeros
/interface ethernet switch print detail
/interface ethernet switch qos port print detail where name~"fabric-port-a|fabric-port-b|fabric-port-c|fabric-port-d"
/interface ethernet switch qos port print stats where name="fabric-port-a"
/interface ethernet switch qos port print stats where name="fabric-port-b"
/interface ethernet switch qos port print pfc where name="fabric-port-a"
/interface ethernet switch qos profile print detail
/interface ethernet switch qos map ip print detail
/interface ethernet switch qos map vlan print detail
/interface ethernet switch qos tx-manager print detail
/interface ethernet switch qos tx-manager queue print detail
/interface bridge print detail where name="cluster-bridge"
/interface bridge port print detail where interface="fabric-port-a"
/interface bridge port print detail where interface="fabric-port-b"
```

Read-only Spark host commands used or still useful:

```bash
mlnx_qos -i enp1s0f0np0
mlnx_qos -i enP2p1s0f0np0
dcb pfc show dev enp1s0f0np0
dcb ets show dev enp1s0f0np0
dcb app show dev enp1s0f0np0
ping -I enp1s0f0np0 -s 8972 -M do -c 3 <peer-192.0.2.x>
lldpcli show neighbors details
ethtool --show-pause enp1s0f0np0
ethtool -S enp1s0f0np0 | egrep -i 'pfc|pause|ecn|prio|discard|drop|crc|symbol|out_of_buffer|cnp'
show_gids
rdma link show
```

DO NOT RUN YET write-plan direction, pending maintenance approval:

- CRS804: upgrade from `7.21.4 (long-term)` to a `7.23+` stable release, because
  MikroTik explicitly added CRS8xx ECN/PFC support in `7.23`.
- CRS804: only after the upgrade, repeat the same two-port Spark 1 / Spark 2
  RoCE/CNP QoS test with explicit profiles, DSCP maps, PFC on TC3, and ECN on
  TC3.
- Sparks: configure DCB/PFC consistently with the switch on the same priority
  or traffic class, then verify `mlnx_qos`, `dcb pfc`, host priority counters,
  and CRS804 queue/PFC counters before rerunning NCCL.
- After any test change, rollback by returning CRS804 ports to
  `profile=default map=default trust-l2=ignore trust-l3=ignore pfc=disabled`
  and returning host PFC to all priorities off.

Conservative CRS804 upgrade outline for the next maintenance window:

```routeros
/export file=crs804-before-7-23-stable
/system backup save name=crs804-before-7-23-stable
/system package update set channel=stable
/system package update check-for-updates
/system package update install

# after reconnecting:
/system resource print
/system package update print
/system routerboard print
/system routerboard upgrade
/system reboot

# after the second reconnect:
/system routerboard print
/interface ethernet switch print detail
/interface ethernet switch qos tx-manager queue print detail
/interface ethernet switch qos priority-flow-control print detail
```

### Spark 1 / Spark 2 RoCE QoS Test And Rollback

A bounded two-port CRS804 + host DCB test was run on Spark 1 and Spark 2 only.
The switch was exported and backed up first:

- `crs804-before-roce-qos-2026-06-30.rsc`
- `crs804-before-roce-qos-2026-06-30.backup`

Switch-side test configuration:

- Added `roce` QoS profile: DSCP `26`, traffic-class `3`.
- Added `cnp` QoS profile: DSCP `48`, traffic-class `6`.
- Added IP DSCP maps: `26 -> roce`, `48 -> cnp`.
- Changed tx-manager queues per MikroTik RoCE example:
  - TC1: `schedule=high-priority-group weight=1`
  - TC3: `schedule=high-priority-group weight=1 ecn=yes`
  - TC6: `schedule=strict-priority`
- Added `pfc-tc3` priority-flow-control profile.
- Applied the port policy to `fabric-port-a` and `fabric-port-b` only.
  RouterOS rejected `egress-rate-queue3=200.0Gbps` with
  `failure: max bit rate is 100G`, so the accepted value was
  `egress-rate-queue3=100.0Gbps`.

Host-side test configuration on Spark 1 and Spark 2:

```bash
dcb pfc set dev enp1s0f0np0 prio-pfc all:off 3:on
dcb app replace dev enp1s0f0np0 dscp-prio 26:3 48:6
cma_roce_tos -d rocep1s0f0 -p 1 -t 106
```

Verification after host-side config showed:

- `mlnx_qos`: priority trust changed to `dscp`.
- `dcb pfc show`: priority `3:on`, all other priorities off.
- `dcb app show`: DSCP `26 -> prio 3`, DSCP `48 -> prio 6`.
- `cma_roce_tos -d rocep1s0f0 -p 1`: `106`.

Results:

| Test | Switch port mode | Result | Queue observation |
| --- | --- | ---: | --- |
| `ib_write_bw -R -q 4 -D 30` | `trust-l3=keep` | `5.49 Gbits/sec` | queue0 incremented; queue3 stayed `0` |
| `ib_write_bw -R --tos=106 -q 4 -D 15` | `trust-l3=keep` | `5.48 Gbits/sec` | queue0 incremented; queue3 stayed `0` |
| `ib_write_bw -R --tos=106 -q 4 -D 10` | `trust-l3=trust` | `5.58 Gbits/sec` | queue0 incremented; queue3 stayed `0` |
| `iperf3 --tos 0x68 -P 4 -t 5` | `trust-l3=trust` | `6.98 Gbits/sec` receiver | queue0 incremented; queue3 stayed `0` |
| `iperf3 -P 2 -t 3` | forced `profile=roce trust-l3=ignore` | `6.72 Gbits/sec` receiver | queue0 incremented; queue3 stayed `0` |

Reasserting `/interface ethernet switch set switch1 qos-hw-offloading=yes` did
not change the result. The important blocker is now narrower than generic
"missing RoCE QoS": even with the documented profiles/maps/PFC profile present,
and even with the two test ports temporarily forced to `profile=roce`, CRS804
tx queue stats continued to place traffic in queue0 rather than queue3.

Rollback completed:

- CRS804 Spark ports returned to
  `profile=default map=default trust-l2=ignore trust-l3=ignore pfc=disabled`.
- Temporary `egress-rate-queue3=100.0Gbps` was removed with RouterOS `unset`.
- Temporary `roce`, `cnp`, and `pfc-tc3` objects were removed.
- TC1/TC3/TC6 tx-manager settings were returned to their baseline values.
- Spark 1 and Spark 2 host PFC/app/TOS changes were reverted:

```bash
dcb pfc set dev enp1s0f0np0 prio-pfc all:off
dcb app del dev enp1s0f0np0 dscp-prio 26:3 48:6
cma_roce_tos -d rocep1s0f0 -p 1 -t 0
mlnx_qos -i <dev> --prio2buffer=1,1,1,1,1,1,1,1 \
  --buffer_size=0,525024,0,0,0,0,0,0
```

Final post-rollback verification matched the original safe baseline on the
switch and on the Spark 1 / Spark 2 host interfaces. The next investigation
should not retry this generic recipe on RouterOS `7.21.4`. MikroTik's `7.23`
stable release note explicitly says ECN and PFC support were added on CRS8xx
switches. Upgrade the CRS804 to a `7.23+` stable release first, then rerun the
same two-port classification test
and require queue3, host prio3, PFC, and ECN counters to move before NCCL.

### Spark PP Framework Zip Triage

The downloaded framework was found already extracted at:

```text
/path/to/spark_pp_framework
```

It contains the expected modules (`telemetry.py`, `scheduler.py`,
`balancer.py`, `comm.py`, `torch_integration.py`) and all Python files compile
with `python3 -m py_compile`. Treat it as a prototype application-layer
experiment, not a fix for the current fabric underlay problem.

Important caveats before importing it into the cluster repo:

- It defaults to `rdma_device="mlx5_0"`, but the Sparks expose
  `rocep1s0f0` and `roceP2p1s0f0`.
- It defaults to an 8-node topology, `SSH_USER="nvidia"`, and a conda env named
  `spark_pp`; the current four-node baseline uses `public-user`.
- It still initializes `torch.distributed` with backend `nccl`. Its main value
  is changing the communication pattern from all-reduce-heavy tensor parallel
  traffic to pipeline point-to-point activation passing. It does not replace or
  repair NCCL/RoCE itself.
- The framework may become useful after the underlay is healthy, especially for
  comparing pipeline-parallel inference against tensor-parallel/NCCL behavior,
  but it should not be used to mask a fabric that is currently only delivering
  single-digit Gbps in both RDMA and TCP tests.
