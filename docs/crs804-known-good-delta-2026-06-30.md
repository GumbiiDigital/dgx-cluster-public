# CRS804 Known-Good Delta - 2026-06-30

## Finding

The strongest missing source-of-truth step is not generic RoCE QoS. It is the
CRS804 physical breakout profile plus the DGX Spark dual-logical-interface model.

Local overnight evidence shows the CRS804 Spark ports configured as:

```text
speed=200G-baseCR4
mtu=9000
l2mtu=9022
fec-mode=auto
```

Known-good and vendor/community guidance differs in three concrete ways:

1. Force the 200G breakout ports to `fec91`.
2. Use a larger L2 MTU headroom than the current `9022` where RouterOS allows it.
3. Treat each Spark QSFP cage as two logical 100G paths and configure the paired
   interfaces consistently, on separate subnets or an explicit aggregate, instead
   of testing only one logical rail as the cluster fabric.

The first approval-gated switch test should therefore be a minimal physical-port
normalization, not another QoS profile change.

## Sources

- NVIDIA official multi-Spark switch playbook:
  <https://build.nvidia.com/spark/multi-sparks-through-switch>
- NVIDIA playbook network setup script:
  <https://raw.githubusercontent.com/NVIDIA/dgx-spark-playbooks/main/nvidia/multi-sparks-through-switch/assets/spark_cluster_setup/node_scripts/detect_and_configure_cluster_networking.py>
- MikroTik Ethernet manual, FEC table:
  <https://help.mikrotik.com/docs/spaces/ROS/pages/8323191/Ethernet>
- MikroTik QoS RoCE example:
  <https://help.mikrotik.com/docs/spaces/ROS/pages/189497483/Quality%2Bof%2BService>
- Wisp CRS804 + DGX Spark report:
  <https://wisp.net.au/blog/news/2-x-dgx-spark-cluster-connected-with-connectx-7-400gbps-breakout-cable-via-mikrotik-crs804-4ddq>
- NVIDIA forum CRS804/GB10 discussion:
  <https://forums.developer.nvidia.com/t/gb10-qsfp56-ports-speed-connecting-multiple-gb10-with-mikortik-crs804-ddq/364093>
- ServeTheHome GB10 ConnectX-7 topology explainer:
  <https://www.servethehome.com/the-nvidia-gb10-connectx-7-200gbe-networking-is-really-different/>

## Local Evidence Compared To Known-Good

Local repo evidence:

- `docs/overnight-crs804-diagnostics-2026-06-30.md` shows all profiles still
  capped around `8.8-9.8 Gbits/sec` TCP and `6.5-6.8 Gbits/sec` RDMA-CM.
- `evidence/overnight-crs804-20260630-114412/switch-*.txt` repeatedly shows
  `fec-mode=auto` on `fabric-port-a`, `fabric-port-b`, `fabric-port-c`, and
  `fabric-port-d`.
- The same captures show `l2mtu=9022`.
- Host captures show `rocep1s0f0/enp1s0f0np0` and
  `roceP2p1s0f0/enP2p1s0f0np0` are both up, but the persistent cluster fabric
  uses only `enp1s0f0np0` on `192.0.2.10/24`.

Source-backed deltas:

- MikroTik documents 200G and 400G base-R modes as requiring `fec91`; `auto` is
  documented as equivalent to no FEC in the Ethernet manual.
- The Wisp CRS804/DGX Spark setup explicitly used `200GBase-CR4`, `RS-FEC`, and
  `jumbo frames` before observing roughly `100 Gbps`-class Spark throughput.
- NVIDIA's switch playbook configures both logical interfaces on the active
  QSFP cage, using two subnets. The script chooses the active cage and then sets
  both the regular and P2P logical interfaces.
- ServeTheHome's topology explainer says a single Spark physical QSFP cage maps
  to two logical 100G MAC paths, and performance depends on using the correct
  interface pair consistently.

## Minimal Next Test

Read-only verification first:

```routeros
/interface ethernet monitor fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d once
/interface ethernet print detail where name~"fabric-port-a|fabric-port-b|fabric-port-c|fabric-port-d"
/interface ethernet print stats where name~"fabric-port-a|fabric-port-b|fabric-port-c|fabric-port-d"
```

If the public-user approves a bounded write test, export first:

```routeros
/export file=crs804-before-fec91-l2mtu-20260630
/system backup save name=crs804-before-fec91-l2mtu-20260630
```

Then normalize only the four Spark breakout ports:

```routeros
/interface ethernet
set [find name="fabric-port-a"] speed=200G-baseCR4 fec-mode=fec91 mtu=9000 l2mtu=9216
set [find name="fabric-port-b"] speed=200G-baseCR4 fec-mode=fec91 mtu=9000 l2mtu=9216
set [find name="fabric-port-c"] speed=200G-baseCR4 fec-mode=fec91 mtu=9000 l2mtu=9216
set [find name="fabric-port-d"] speed=200G-baseCR4 fec-mode=fec91 mtu=9000 l2mtu=9216
```

If RouterOS rejects `l2mtu=9216`, keep the maximum accepted value and record it.
If the links flap, wait for all four to return to `200G-baseCR4` before testing.

Post-change pass/fail gate:

```bash
cd "/path/to/dgx-cluster"
scripts/verify-roce-underlay.sh
```

Success is not queue movement alone. The first expected improvement is TCP
retransmits collapsing and `ib_write_bw` leaving the single-digit Gbps class.

## Second Test If FEC/MTU Does Not Move It

Mirror NVIDIA's official dual-logical-interface shape persistently on all four
Sparks:

- Keep `enp1s0f0np0` / `rocep1s0f0` on `192.0.2.10/24`.
- Add `enP2p1s0f0np0` / `roceP2p1s0f0` on `192.0.2.10/24`.
- Add the same DCB/PFC/DSCP policy to both Linux netdevs.
- Allow `192.0.2.10/24` in UFW.
- Run one RDMA test per rail and then an aggregate test.

This checks the official Spark networking model without changing the physical
cabling or assuming NCCL can hide an underlay problem.
