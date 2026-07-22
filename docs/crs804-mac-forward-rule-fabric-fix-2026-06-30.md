# CRS804 MAC Forward Rule Fabric Fix - 2026-06-30

## Result

The CRS804 throughput cap was caused by high-rate Spark fabric traffic being
forwarded toward `switch1-cpu` and dropped, even though the bridge host table and
host ARP entries were correct.

Installing explicit Marvell Prestera switch rules for each active DGX Spark f1
MAC address moved forwarding back into the switch ASIC path and restored the
expected 200G-class dual-half fabric.

## Proof

Before the switch rules:

- TCP through the CRS804 stayed around `9 Gbits/sec` per half with tens of
  thousands of retransmits.
- UDP could be injected much faster, but the receiver only got about
  `9.9 Gbits/sec` and reported about `87%` loss.
- During one UDP burst, `fabric-port-a` received about `175 GB`,
  `fabric-port-b` transmitted about `23.5 GB`, and `switch1-cpu` queue0 drops
  increased by about `16.9M` packets / `152 GB`.
- Spark1 ARP for Spark2 primary was correct:
  `192.0.2.10 lladdr AA:BB:CC:xx:xx:01`.
- CRS804 learned that MAC on `fabric-port-b`.

With two exact Spark1/Spark2 primary MAC rules:

- Spark1 to Spark2 primary TCP jumped to `111.07 Gbits/sec` with `1`
  retransmit.

With the full eight-rule f1 fabric set installed:

- Spark1 to Spark2 dual TCP: `105.19 + 92.44 = 197.62 Gbits/sec`,
  `0` retransmits.
- Spark3 to Spark4 dual TCP: `86.84 + 111.17 = 198.00 Gbits/sec`,
  `0` retransmits.
- Spark1 to Spark3 cross-pair dual TCP: `94.02 + 102.58 = 196.61 Gbits/sec`,
  `0` retransmits.
- Spark1 to Spark2 RDMA-CM sequential:
  - primary `rocep1s0f1`: `97.98 Gbits/sec`
  - secondary `roceP2p1s0f1`: `97.98 Gbits/sec`

Evidence folder:

```text
evidence/f1-full-mac-forward-rules-20260630-183238/
```

## Installed Switch Rule Diff

These rules are currently installed on `switch-a` and are intentionally left
in place because they are the known-good fabric fix.

```routeros
/interface ethernet switch rule
add switch=switch1 ports=fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d dst-mac-address=AA:BB:CC:xx:xx:01/AA:BB:CC:xx:xx:01 new-dst-ports=fabric-port-a comment=codex-force-f1-fabric-spark-a.example-primary
add switch=switch1 ports=fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d dst-mac-address=AA:BB:CC:xx:xx:01/AA:BB:CC:xx:xx:01 new-dst-ports=fabric-port-a comment=codex-force-f1-fabric-spark-a.example-secondary
add switch=switch1 ports=fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d dst-mac-address=AA:BB:CC:xx:xx:01/AA:BB:CC:xx:xx:01 new-dst-ports=fabric-port-b comment=codex-force-f1-fabric-spark-b.example-primary
add switch=switch1 ports=fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d dst-mac-address=AA:BB:CC:xx:xx:01/AA:BB:CC:xx:xx:01 new-dst-ports=fabric-port-b comment=codex-force-f1-fabric-spark-b.example-secondary
add switch=switch1 ports=fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d dst-mac-address=AA:BB:CC:xx:xx:01/AA:BB:CC:xx:xx:01 new-dst-ports=fabric-port-c comment=codex-force-f1-fabric-spark-c.example-primary
add switch=switch1 ports=fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d dst-mac-address=AA:BB:CC:xx:xx:01/AA:BB:CC:xx:xx:01 new-dst-ports=fabric-port-c comment=codex-force-f1-fabric-spark-c.example-secondary
add switch=switch1 ports=fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d dst-mac-address=AA:BB:CC:xx:xx:01/AA:BB:CC:xx:xx:01 new-dst-ports=fabric-port-d comment=codex-force-f1-fabric-spark-d.example-primary
add switch=switch1 ports=fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d dst-mac-address=AA:BB:CC:xx:xx:01/AA:BB:CC:xx:xx:01 new-dst-ports=fabric-port-d comment=codex-force-f1-fabric-spark-d.example-secondary
```

RouterOS prints these rules with:

```text
copy-to-cpu=no redirect-to-cpu=no mirror=no
```

## Rollback

```routeros
/interface ethernet switch rule remove [find comment~"codex-force-f1-fabric"]
```

## Source Notes

- MikroTik documents switch ACL/rule actions including `new-dst-ports`,
  `copy-to-cpu`, and `redirect-to-cpu` under switch-chip features and related
  examples.
- MikroTik's Layer2 misconfiguration note says packets whose destination MAC has
  been learned should not be sent to CPU, and that ACL rules can copy or
  redirect packets to CPU when desired. Our live CRS804 behavior contradicted the
  expected learned-MAC path under high-rate traffic until the ASIC destination
  port was forced.
- NVIDIA/community reports about DGX Spark on MikroTik CRS804/CRS812 were useful
  for the physical f1/dual-half target, but they did not surface this
  CRS804-specific switch-rule requirement.

Source links:

- <https://help.mikrotik.com/docs/spaces/ROS/pages/15302988/Switch+Chip+Features>
- <https://help.mikrotik.com/docs/spaces/ROS/pages/19136718/Layer2+misconfiguration>
- <https://help.mikrotik.com/docs/spaces/ROS/pages/30474317/Marvell+Prestera+switch+chip+features>
- <https://forums.developer.nvidia.com/t/gb10-qsfp56-ports-speed-connecting-multiple-gb10-with-mikortik-crs804-ddq/364093>
- <https://forums.developer.nvidia.com/t/connectx-7-200gbe-via-mikrotik-crs812-qsfp-dd-400g-2xqsfp56-200g-breakout/357162>
