# No-Switch Four-Spark Direct Mesh Guide

This guide describes a four-node DGX Spark layout that uses direct QSFP cables
instead of a switch. It uses neutral Node A/B/C/D names so the pattern can be
reused outside this lab.

## Topology

Wire four nodes as a direct ring:

```text
Node A -> Node B -> Node D -> Node C -> Node A
```

Use one physical QSFP port for each ring edge:

| Cable | Suggested role |
| --- | --- |
| Node A <-> Node B | first physical port, primary edge |
| Node C <-> Node D | first physical port, opposite edge |
| Node A <-> Node C | second physical port, return edge |
| Node B <-> Node D | second physical port, forward edge |

On DGX Spark, each physical QSFP connection can expose two logical Ethernet/RDMA
halves. Verify your actual mapping before assigning addresses; do not assume the
names below are universal.

This square/ring is physically valid for two-port nodes: each node has exactly
two direct neighbors. If all direct edges pass jumbo ping, `ib_write_bw`, and
two-node NCCL, the cables are doing their job. A later four-node NCCL failure
that references non-neighbor GID pairs is a topology/modeling problem, not by
itself a recabling instruction.

Support boundary: this is a switchless direct-mesh experiment. NVIDIA documents
direct two-node Spark cabling, direct three-node ring cabling, and four-node or
larger Spark clusters through a QSFP switch. As of the evidence captured for
this guide, there is no official stock-NCCL recipe that makes a four-node
two-port switchless square behave like a switched fabric.

Typical mapping:

| Physical port | Ethernet halves | RDMA halves |
| --- | --- | --- |
| first port | `enp1s0f0np0`, `enP2p1s0f0np0` | `rocep1s0f0`, `roceP2p1s0f0` |
| second port | `enp1s0f1np1`, `enP2p1s0f1np1` | `rocep1s0f1`, `roceP2p1s0f1` |

## Preflight

Before assigning IPs, verify every node over management networking:

```bash
hostname
uptime
pgrep -af "[m]pirun|[o]rted|[a]ll_reduce_perf|[a]ll_gather_perf|[n]ccl-tests|[i]b_write_bw|[i]perf3" || true
ibdev2netdev
ip -br link show
ip -br addr show
rdma link show
show_gids
ethtool <each-high-speed-netdev>
```

Expected pre-IP state:

- all expected high-speed netdevs are `UP` with `LOWER_UP`;
- all expected RDMA devices are `ACTIVE` / `LINK_UP`;
- `ethtool` reports the expected link speed and `Link detected: yes`;
- IPv4 GIDs appear only after IPv4 addresses are assigned.

## Temporary IP Plan

Use /30 point-to-point subnets. The 198.51.100 range is the first logical half and
203.0.113 mirrors the second logical half.

| Link | First half | Second half |
| --- | --- | --- |
| Node A <-> Node B | `192.0.2.10/30` <-> `192.0.2.10/30` | `192.0.2.10/30` <-> `192.0.2.10/30` |
| Node C <-> Node D | `192.0.2.10/30` <-> `192.0.2.10/30` | `192.0.2.10/30` <-> `192.0.2.10/30` |
| Node A <-> Node C | `192.0.2.10/30` <-> `192.0.2.10/30` | `192.0.2.10/30` <-> `192.0.2.10/30` |
| Node B <-> Node D | `192.0.2.10/30` <-> `192.0.2.10/30` | `192.0.2.10/30` <-> `192.0.2.10/30` |

Assign addresses non-persistently while testing:

```bash
sudo ip link set dev <netdev> mtu 9000
sudo ip addr replace <ip>/30 dev <netdev>
sudo ip link set dev <netdev> up
```

Use persistent network configuration only after the temporary layout passes.

## Underlay Validation

Validate every direct edge, both directions, and both logical halves.

Jumbo ping:

```bash
ping -I <netdev> -c 3 -s 8972 -M do <peer-ip>
```

RDMA bandwidth:

```bash
# On the receiver
sudo bash -lc 'ulimit -l unlimited; ib_write_bw -R -d <rdma-dev> -F --report_gbits -q 8 -s 8388608 -D 8'

# On the sender
sudo bash -lc 'ulimit -l unlimited; ib_write_bw -R -d <rdma-dev> -F --report_gbits -q 8 -s 8388608 -D 8 <peer-ip>'
```

A direct Spark-to-Spark link should be in the 100 Gbit/sec class per logical
half when the physical state is healthy. If jumbo ping passes but RDMA is
single-digit Gbit/sec, fix the underlay before running NCCL.

## NCCL Validation

Keep MPI launch and OpenMPI OOB on management networking. Use the direct RoCE
devices only for NCCL data.

Two-node edge test:

```bash
NCCL_DEBUG=INFO \
NCCL_DEBUG_SUBSYS=INIT,NET,GRAPH \
NCCL_IB_DISABLE=0 \
NCCL_IB_HCA=<rdma-half-0>,<rdma-half-1> \
NCCL_SOCKET_IFNAME=<management-iface> \
NCCL_ALGO=Ring \
mpirun -np 2 -H <spark-a.example-mgmt>:1,<spark-b.example-mgmt>:1 \
  --mca oob_tcp_if_include <management-iface> \
  --mca btl_tcp_if_include <management-iface> \
  -x NCCL_DEBUG -x NCCL_DEBUG_SUBSYS -x NCCL_IB_DISABLE -x NCCL_IB_HCA \
  -x NCCL_SOCKET_IFNAME -x NCCL_ALGO \
  /opt/public-user/nccl-tests/build/all_gather_perf -b 16G -e 16G -f 2 -g 1 -n 20 -w 5 -c 1
```

Four-node ring test:

```bash
NCCL_ALGO=Ring \
mpirun -np 4 -H <spark-a.example-mgmt>:1,<spark-b.example-mgmt>:1,<spark-d.example-mgmt>:1,<spark-c.example-mgmt>:1 \
  /opt/public-user/nccl-tests/build/all_reduce_perf -b 256M -e 256M -f 2 -g 1 -n 20 -w 5 -c 1
```

Proof requirements:

- NCCL logs show `NET/IB` on the intended direct RoCE devices.
- NCCL logs do not show socket fallback as the data path.
- The four-node ring uses the physical neighbor order.
- Wrong/out-of-bounds values stay at `0`.

Stop before tuning if NCCL needs routes between non-neighbor subnets, attempts
traffic across missing edges, or requires a custom topology file. Document that
boundary separately from successful underlay proof.

The helper scripts used in the Sparks 5-8 lab provide a reusable pattern:

```bash
# Host-side switchless validation harness.
scripts/run-sparks58-switchless-mesh.sh

# Host-side novel experiment harness for sparse direct rings.
scripts/run-sparks58-novel-experiments.sh

# Optional user-home NCCL build/sync helper for reversible runtime trials.
scripts/build-sparks58-switchless-nccl.sh
```

The build helper is intentionally non-installing: it builds NCCL under a user
home directory and the runner can prefer it with `REMOTE_NCCL_HOME=...` through
`LD_LIBRARY_PATH`. Removing that environment variable returns the job to the
system NCCL package.

## Stock NCCL Boundary

A switchless direct mesh is not a normal fully connected Ethernet fabric. Pair
tests can pass while a four-node collective still fails if NCCL builds a graph
that connects RoCE GIDs on non-neighbor point-to-point subnets.

This failure is recognizable in NCCL logs:

```text
Call to ibv_modify_qp failed with 110 Connection timed out
local GID <one direct-link subnet>, remote GID <different direct-link subnet>
```

When that happens, stop. Do not add L3 routes just to make the timeout
disappear; that no longer proves a direct ring and can create a slow or
misleading multi-hop path.

Environment-only NCCL tuning may not be sufficient for the square topology. In
the lab, all of the following still selected non-neighbor f0 GIDs and failed:

- stock NCCL `2.28.9`;
- `NCCL_CROSS_NIC=1`;
- one-channel forcing with `NCCL_MIN_NCHANNELS=1` and `NCCL_MAX_NCHANNELS=1`;
- a user-home NVIDIA NCCL `v2.30u1` / `2.30.7` runtime;
- `NCCL_NETDEVS_POLICY=ALL`;
- NCCL's own `NCCL_CROSS_NIC=0` confirmation hint;
- HCA order permutations with NCCL `2.30.7`;
- `NCCL_CROSS_NIC=0` with `NCCL_IB_MERGE_NICS=0`,
  `NCCL_IB_SUBNET_AWARE_ROUTING=1`, and one channel.
- per-rank app-context HCA ordering intended to bias each rank toward its two
  physical neighbors;
- `NCCL_TOPO_FILE` using a topology XML dumped from the same Spark layout.

NCCL `2.30.7` reported:

```text
In many cases this error occurs when NICs are not cross-rail connected.
```

Treat that as a topology signal, not as proof that the direct links are bad. The
next step is a topology-aware NCCL experiment or a physical topology change:

- an explicit NCCL topology file;
- a mesh-aware/patched NCCL build if one is required for the target node count;
- or a framework/launcher that can constrain rank-to-NIC selection per edge.

Do not expect a simple recable of the same four direct edges to make stock NCCL
behave like a switched fabric. In a two-port four-node ring, each node must use
one port for one neighbor and the other port for the second neighbor. If the
collective stack assumes the same NIC index reaches every rank neighbor, the
stack needs a better topology model.

Use external guidance as a check, but trust live logs first. NVIDIA's NCCL
troubleshooting guidance supports pairwise `ib_write_bw` before higher-level
NCCL conclusions, and NVIDIA forum reports for switchless DGX Spark meshes show
the same non-reachable-GID failure pattern with stock NCCL.

## Optional Sparse-Ring Experiments

After the basic underlay and two-node NCCL proof, use software-only experiments
to separate hardware health from collective topology selection:

1. Run concurrent `ib_write_bw -R` on all four ring edges. Passing all edges at
   the expected direct-link rate proves the square can carry simultaneous load.
2. Run concurrent disjoint two-node NCCL phases: Node A <-> Node B plus
   Node D <-> Node C, then Node B <-> Node D plus Node C <-> Node A. Passing
   `NET/IB` on both phases proves edge NCCL remains healthy under concurrency.
3. Run bounded four-rank HCA/env probes with full NCCL `INIT,NET,GRAPH` logs.
   If every HCA order still selects non-neighbor GIDs, treat env tuning as
   exhausted.
4. Dump NCCL topology and graph files. Use them to explain what NCCL thinks the
   NIC graph looks like before attempting a topology override.
5. Try `NCCL_TOPO_FILE` only as an experiment and require logs to prove the file
   was loaded. A normal local topology XML may not describe sparse inter-host
   neighbor constraints.
6. Run a pinned UCX control with one RDMA device per direct edge. If
   `UCX_NET_DEVICES=all` fails, pin each edge explicitly, for example
   `UCX_NET_DEVICES=rocep1s0f0:1` or `UCX_NET_DEVICES=rocep1s0f1:1`.
7. Optionally run a tiny explicit-edge custom collective. This does not replace
   NCCL, but it can prove the direct ring can complete a global operation when
   software uses only valid neighbors.

The Sparks 5-8 lab used this explicit neighbor order:

```text
Node A -> Node B -> Node D -> Node C -> Node A
```

The proof harness bound each send socket to the correct source IP for the next
direct edge:

| Rank | Logical node | Send edge | Receive edge |
| --- | --- | --- | --- |
| 0 | Node A | Node A -> Node B | Node C -> Node A |
| 1 | Node B | Node B -> Node D | Node A -> Node B |
| 2 | Node D | Node D -> Node C | Node B -> Node D |
| 3 | Node C | Node C -> Node A | Node D -> Node C |

In that lab, 4 MiB messages completed with all ranks `ok=1`. That proves the
logical direct ring can carry a global collective when neighbor selection is
explicit. It does not prove stock NCCL can infer the same sparse topology.

The same lab also ran concurrent pinned UCX/RDMA `tag_bw` probes on all four
neighbor edges. All four exited `0` when each edge was pinned to the correct
RoCE device. This is a useful control: explicit-edge transports can obey the
square; the unresolved gap is stock NCCL automatic graph construction.

## Tuning After Proof

Only after the basic ring passes:

1. Sweep `NCCL_MIN_NCHANNELS` and `NCCL_MAX_NCHANNELS`.
2. Sweep `NCCL_IB_QPS_PER_CONNECTION`.
3. Sweep `NCCL_IB_SPLIT_DATA_ON_QPS`.
4. Compare single-half and dual-half behavior.
5. Repeat a median set for the best large-message configuration.

On DGX Spark, `GPU Direct RDMA Disabled` in NCCL logs is expected and is not a
failure by itself.

## References

- NVIDIA NCCL networking troubleshooting:
  <https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/troubleshooting/networking_troubleshooting.html>
- NVIDIA NCCL environment variables:
  <https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html>
- NVIDIA DGX Spark, connect three in a ring:
  <https://build.nvidia.com/spark/connect-three-sparks>
- NVIDIA DGX Spark, connect multiple through a switch:
  <https://build.nvidia.com/spark/multi-sparks-through-switch>
- NVIDIA Developer Forums, switchless DGX Spark mesh:
  <https://forums.developer.nvidia.com/t/is-training-on-3-dgx-spark-nodes-without-a-switch-supported/369404>
