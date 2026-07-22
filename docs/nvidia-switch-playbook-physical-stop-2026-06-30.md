# NVIDIA Switch Playbook Physical Stop - 2026-06-30

## Finding

The obvious source-of-truth gap is now physical and procedural, not another
CRS804 QoS knob.

NVIDIA's official multi-Spark switch playbook says to connect one QSFP cable per
Spark, use the same CX7 physical port on all Sparks, and in the playbook use the
second CX7 port: the one farther from the Ethernet port. Its example shows the
`f1` logical pair up:

```text
rocep1s0f1  -> enp1s0f1np1  (Up)
roceP2p1s0f1 -> enP2p1s0f1np1 (Up)
```

It also notes that each physical port has two logical interfaces and says, for
that second-port topology, to disregard the `f0` interfaces and use the `f1`
pair only.

Our current live topology is the inverse:

```text
rocep1s0f0   -> enp1s0f0np0   (Up)
roceP2p1s0f0 -> enP2p1s0f0np0 (Up)
rocep1s0f1   -> enp1s0f1np1   (Down)
roceP2p1s0f1 -> enP2p1s0f1np1 (Down)
```

So the next source-backed step requires physically moving the QSFP cable on each
Spark to the second CX7 port, then configuring the `f1` logical pair.

## Sources

- NVIDIA official switch playbook:
  <https://build.nvidia.com/spark/multi-sparks-through-switch>
- NVIDIA playbook README source:
  <https://raw.githubusercontent.com/NVIDIA/dgx-spark-playbooks/main/nvidia/multi-sparks-through-switch/README.md>
- NVIDIA cluster setup script source:
  <https://raw.githubusercontent.com/NVIDIA/dgx-spark-playbooks/main/nvidia/multi-sparks-through-switch/assets/spark_cluster_setup/node_scripts/detect_and_configure_cluster_networking.py>
- NVIDIA performance benchmarking guide:
  <https://raw.githubusercontent.com/NVIDIA/dgx-spark-playbooks/main/nvidia/connect-two-sparks/assets/performance_benchmarking_guide.md>

Important source-backed details:

- The playbook requires at least 200 Gbps QSFP ports, one cable per Spark, and
  says 400 Gbps switch ports can use breakout cables.
- It recommends the same CX7 port on every Spark to avoid NCCL failures.
- Its physical setup uses the second CX7 port, farther from Ethernet.
- It expects the switch ports to be in a single L2 bridge/domain; some switches
  can hardware-offload only one bridge.
- Manual static addressing must put the two logical interfaces on different
  subnets. NVIDIA explicitly warns that putting two distinct interfaces on the
  same subnet causes routing ambiguity and NCCL failures.
- NVIDIA's direct two-Spark benchmark drives both logical halves concurrently and
  shows about `92.57 Gbits/sec` plus `97.28 Gbits/sec`, or `189.85 Gbits/sec`
  aggregate.

## Live State After Cleanup

After the failed flat-QoS and temporary dual-logical tests, the current fabric
state was restored to the intended CRS804 RoCE profile:

```text
CRS804 ports:
  fabric-port-a, fabric-port-b, fabric-port-c, fabric-port-d
  speed=200G-baseCR4
  mtu=9000
  l2mtu=9216
  fec-mode=fec91
  trust-l3=keep
  pfc=pfc-tc3
  egress-rate-queue3=100.0Gbps

Spark hosts:
  enp1s0f0np0 has 192.0.2.10-14/24
  enP2p1s0f0np0 has no temporary 198.51.100.x address
  cma_roce_tos is back to 106 on both f0 logical halves
  PFC priority 3 is on for both f0 logical netdevs
```

## Non-Physical Test Already Tried

To avoid prematurely asking for cable movement, we temporarily mirrored the
NVIDIA dual-logical model on the currently connected `f0` pair:

```text
enp1s0f0np0    -> 192.0.2.10-14/24
enP2p1s0f0np0  -> 192.0.2.10-14/24
```

Evidence:

```text
evidence/nvidia-playbook-dual-logical-20260630-123850/
evidence/nvidia-playbook-dual-logical-mtu9000-20260630-124001/
```

Result:

- Both logical halves connected when tested with small default messages, proving
  the `192.0.2.10/24` secondary subnet can work on the current f0 cabling.
- With the larger `-q 8 -s 8388608` shape, both non-RDMA-CM streams failed with
  `status 12` / `syndrome 0x81`.
- Switch counters still showed `rx-error-events=0`, `tx-drop-packet=0`, per-queue
  drops all zero, stable `rs-fec-uncorrected`, and 200 Gbps link rate.

This means the remaining difference from NVIDIA's exact switch playbook is the
physical CX7 port choice and the resulting `f1` interface pair.

## Required Physical Action

Move each Spark QSFP cable from the currently active CX7 port to the other CX7
port: the second port, farther from the Ethernet port, matching NVIDIA's
playbook.

Keep the CRS804 side in the same logical switch ports for now unless the public-user
has a better documented port map:

| Spark | Current CRS804 port | Current host pair | NVIDIA target host pair |
| --- | --- | --- | --- |
| Spark 1 / `spark-a.example` | `fabric-port-a` | `f0` up | `f1` up |
| Spark 2 / `spark-b.example` | `fabric-port-b` | `f0` up | `f1` up |
| Spark 3 / `spark-c.example` | `fabric-port-c` | `f0` up | `f1` up |
| Spark 4 / `spark-d.example` | `fabric-port-d` | `f0` up | `f1` up |

Expected post-move `ibdev2netdev` shape on every Spark:

```text
rocep1s0f0 port 1 ==> enp1s0f0np0 (Down)
rocep1s0f1 port 1 ==> enp1s0f1np1 (Up)
roceP2p1s0f0 port 1 ==> enP2p1s0f0np0 (Down)
roceP2p1s0f1 port 1 ==> enP2p1s0f1np1 (Up)
```

## Post-Move Read-Only Gate

Run this immediately after moving cables:

```bash
cd "/path/to/dgx-cluster"
KEY="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
for h in spark-a.example spark-b.example spark-c.example spark-d.example; do
  echo "### $h"
  ssh -i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "public-user@$h" \
    'hostname; ibdev2netdev; sudo ethtool enp1s0f1np1 | egrep "Speed|Lanes|Link detected"; sudo ethtool enP2p1s0f1np1 | egrep "Speed|Lanes|Link detected"'
done
```

And on the CRS804:

```routeros
/interface ethernet monitor fabric-port-a,fabric-port-b,fabric-port-c,fabric-port-d once
/interface bridge port print detail where interface="fabric-port-a" or interface="fabric-port-b" or interface="fabric-port-c" or interface="fabric-port-d"
/interface ethernet print stats where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
```

Pass criteria:

- All four Sparks show `enp1s0f1np1` and `enP2p1s0f1np1` up.
- Both `f1` netdevs report `Speed: 200000Mb/s`.
- CRS804 ports remain `200Gbps`, `fec91`, and bridge `hw=yes`.
- CRS804 drops/errors do not start increasing.

## Post-Move Temporary NVIDIA-Shape Test

Only after the read-only gate passes, assign temporary test IPs to the `f1` pair:

```bash
KEY="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"

ssh -i "$KEY" public-user@spark-a.example 'sudo ip addr replace 192.0.2.10/24 dev enp1s0f1np1; sudo ip addr replace 192.0.2.10/24 dev enP2p1s0f1np1; sudo ip link set enp1s0f1np1 mtu 9000 up; sudo ip link set enP2p1s0f1np1 mtu 9000 up'
ssh -i "$KEY" public-user@spark-b.example 'sudo ip addr replace 192.0.2.10/24 dev enp1s0f1np1; sudo ip addr replace 192.0.2.10/24 dev enP2p1s0f1np1; sudo ip link set enp1s0f1np1 mtu 9000 up; sudo ip link set enP2p1s0f1np1 mtu 9000 up'
ssh -i "$KEY" public-user@spark-c.example 'sudo ip addr replace 192.0.2.10/24 dev enp1s0f1np1; sudo ip addr replace 192.0.2.10/24 dev enP2p1s0f1np1; sudo ip link set enp1s0f1np1 mtu 9000 up; sudo ip link set enP2p1s0f1np1 mtu 9000 up'
ssh -i "$KEY" public-user@spark-d.example 'sudo ip addr replace 192.0.2.10/24 dev enp1s0f1np1; sudo ip addr replace 192.0.2.10/24 dev enP2p1s0f1np1; sudo ip link set enp1s0f1np1 mtu 9000 up; sudo ip link set enP2p1s0f1np1 mtu 9000 up'
```

Then run the dual-rail verifier against the `f1` pair:

```bash
PRIMARY_NETDEV=enp1s0f1np1 \
PRIMARY_RDMA=rocep1s0f1 \
PRIMARY_SRC_IP=192.0.2.10 \
PRIMARY_DST_IP=192.0.2.10 \
SECONDARY_NETDEV=enP2p1s0f1np1 \
SECONDARY_RDMA=roceP2p1s0f1 \
SECONDARY_SRC_IP=192.0.2.10 \
SECONDARY_DST_IP=192.0.2.10 \
scripts/verify-dual-rail-underlay.sh
```

Pass criteria:

- Each single logical half is in the `90+ Gbits/sec` class.
- Concurrent aggregate is in the `180+ Gbits/sec` class.

If this still fails, the evidence bundle becomes vendor-grade because it has
eliminated the exact NVIDIA switch playbook delta: correct physical CX7 port,
both logical interfaces, separate subnets, 200 Gbps switch links, FEC91, jumbo
MTU, and clean CRS804 counters.
