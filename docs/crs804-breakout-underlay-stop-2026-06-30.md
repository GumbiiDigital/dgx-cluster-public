# CRS804 Breakout Underlay Stop Point - 2026-06-30

This note records the CRS804 fabric retest after returning Spark 1 through
Spark 4 to the intended `2x200G` breakout topology.

## Live Port Map

LLDP from the Spark high-speed interfaces confirmed this map:

| Alias | Hostname | Fabric IP | CRS804 port |
| --- | --- | --- | --- |
| `spark-a.example` | `spark-a.example` | `192.0.2.10/24` | `fabric-port-a` |
| `spark-b.example` | `spark-b.example` | `192.0.2.10/24` | `fabric-port-b` |
| `spark-c.example` | `spark-c.example` | `192.0.2.10/24` | `fabric-port-c` |
| `spark-d.example` | `spark-d.example` | `192.0.2.10/24` | `fabric-port-d` |

All four Sparks saw `switch-a` on the expected high-speed CRS804 port and all
four could ping the CRS804 fabric address `192.0.2.10`.

## Link State

All four primary fabric links reported:

```text
Speed: 200000Mb/s
Lanes: 4
Link detected: yes
RDMA link rocep1s0f0/1: ACTIVE, LINK_UP
```

The secondary exposed function `roceP2p1s0f0` also showed `ACTIVE, LINK_UP` on
each host because the DGX Spark exposes two RoCE functions for the same physical
fabric attachment.

## Jumbo Mesh

Full four-node jumbo mesh passed with DF set:

```bash
ping -c 2 -s 8972 -M do <peer-192.0.2.x>
```

Every source-to-peer combination among Spark 1 through Spark 4 returned `2/2`
packets and `0%` loss.

## Bandwidth Gate

The corrected breakout map did not clear the CRS804 throughput issue.

| Path | TCP result | RDMA result |
| --- | --- | --- |
| `spark-a.example -> spark-b.example` | `9.83 Gbits/sec`, `10654` retransmits | `0.011185 Gbits/sec`, incomplete one-iteration run |
| `spark-b.example -> spark-a.example` | `9.83 Gbits/sec`, `11026` retransmits | completion error, `status 12`, syndrome `0x81` |
| `spark-a.example -> spark-c.example` | `9.84 Gbits/sec`, `10819` retransmits | `0.000000 Gbits/sec`, zero completed iterations |
| `spark-c.example -> spark-d.example` | `8.93 Gbits/sec`, `27132` retransmits | completion error, `status 12`, syndrome `0x81` |

The same Spark 1 / Spark 2 primary rail had previously validated at roughly
`111 Gbits/sec` TCP and `111.85 Gbits/sec` RDMA in both directions when directly
cabled after the cold-drain procedure. This means the host NICs and Spark-to-Spark
transport can perform well, but the CRS804-switched path still fails the underlay
performance gate.

## Host Counter Snapshot

Host-side counters were captured after the CRS804 breakout tests. All four
primary fabric NICs still showed the expected link state and no obvious local
physical-drop signature:

```text
rx_crc_errors_phy: 0
rx_discards_phy: 0
tx_discards_phy: 0
rx_prio0_discards: 0
rx_prio1_discards: 0
rx_prio2_discards: 0
rx_prio3_discards: 0
rx_prio4_discards: 0
rx_prio5_discards: 0
rx_prio6_discards: 0
rx_prio7_discards: 0
tx_queue_dropped: 0
```

## Stop Point

Do not run NCCL yet.

The underlay is currently:

- Correctly mapped on the CRS804 breakout ports.
- Link-up at `200G` on Spark 1 through Spark 4.
- Passing the full jumbo-frame mesh.
- Failing TCP throughput with heavy retransmits.
- Failing or nearly failing raw RDMA verbs through the CRS804.
- Not showing an obvious Spark-side physical CRC/discard/drop counter.

The next required evidence is CRS804-side counters around the same failing test:

```routeros
/interface ethernet monitor fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d once
/interface ethernet print stats where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
/interface bridge host print where bridge=cluster-bridge
/interface bridge port print detail where interface="fabric-port-a" or interface="fabric-port-b" or interface="fabric-port-c" or interface="fabric-port-d"
/interface ethernet switch qos port print detail
/interface ethernet switch qos tx-manager queue print detail
```

Non-interactive SSH from the Mac to `public-admin@192.0.2.10` was blocked by
authentication during this pass, so the switch-side counter delta still needs to
be captured from an authenticated RouterOS session.
