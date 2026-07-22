# Sparks 5-8 Switchless Direct Mesh

Date: 2026-07-01

Raw local evidence:

- `evidence/sparks58-switchless-mesh-*`
- `evidence/sparks58-novel-20260701-194237/`
- final no-stale postcheck: `evidence/sparks58-novel-20260701-194237-finalcheck/`
- final readiness/no-stale postcheck after all novel experiments:
  `evidence/sparks58-novel-20260701-194237-finalcheck2/`

Status: PASS for the switchless underlay, concurrent edge RDMA, two-node NCCL
edge proof, concurrent two-node NCCL phases, explicit-edge custom TCP
ring all-reduce, and pinned per-edge UCX/RDMA transport. STOP for stock/env-
driven four-node NCCL collectives on this square mesh: NCCL attempted
non-neighbor RoCE GID pairs and failed before data movement. This lane is
host-side only and intentionally excludes CRS804 commands.

## Dedicated Scope

This note covers only the switchless Sparks 5-8 lane:

| Spark | Hostname | Management name | Role |
| --- | --- | --- | --- |
| Spark 5 | `spark-e.example` | `spark-e.example` | Ring node 1 |
| Spark 6 | `spark-f.example` | `spark-f.example` | Ring node 2 |
| Spark 8 | `spark-g.example` | `spark-h.example` | Ring node 3 |
| Spark 7 | `spark-h.example` | `spark-g.example` | Ring node 4 |

Expected NCCL ring order:

```text
Spark 5 -> Spark 6 -> Spark 8 -> Spark 7 -> Spark 5
```

The parent CRS804/switch-tuning lane remains separate. Existing CRS804 evidence
is useful as background, but it is not proof for this topology.

## Canonical Wiring

| Direct cable | Physical port assumption | Primary logical half | Secondary logical half |
| --- | --- | --- | --- |
| Spark 5 <-> Spark 6 | closest to Cat5 | `enp1s0f0np0` / `rocep1s0f0` | `enP2p1s0f0np0` / `roceP2p1s0f0` |
| Spark 7 <-> Spark 8 | closest to Cat5 | `enp1s0f0np0` / `rocep1s0f0` | `enP2p1s0f0np0` / `roceP2p1s0f0` |
| Spark 5 <-> Spark 7 | outermost | `enp1s0f1np1` / `rocep1s0f1` | `enP2p1s0f1np1` / `roceP2p1s0f1` |
| Spark 6 <-> Spark 8 | outermost | `enp1s0f1np1` / `rocep1s0f1` | `enP2p1s0f1np1` / `roceP2p1s0f1` |

The port mapping must be verified live with `ibdev2netdev`, `ethtool`,
`ip -br link/addr`, `rdma link`, and `show_gids` before assigning IPs.

Perplexity cabling check: the tested square/ring wiring is physically valid for
two-port switchless Sparks and matches the natural "each node has two
neighbors" graph. The external check did not identify a better no-switch cable
arrangement that would make stock NCCL's same-NIC-index behavior valid. It
instead classified this as a physically sound but non-standard four-node
switchless mesh: NVIDIA's documented four-node story expects a RoCE switch,
while direct switchless examples are documented/community-visible for two-node
and some three-node ring cases.

## Temporary Point-to-Point IP Plan

The harness assigns only non-persistent host-side IPs. Rebooting the Sparks or
running cleanup removes the test addresses.

| Link | Primary half | Secondary half |
| --- | --- | --- |
| Spark 5 <-> Spark 6 | `192.0.2.10/30` <-> `192.0.2.10/30` | `192.0.2.10/30` <-> `192.0.2.10/30` |
| Spark 7 <-> Spark 8 | `192.0.2.10/30` <-> `192.0.2.10/30` | `192.0.2.10/30` <-> `192.0.2.10/30` |
| Spark 5 <-> Spark 7 | `192.0.2.10/30` <-> `192.0.2.10/30` | `192.0.2.10/30` <-> `192.0.2.10/30` |
| Spark 6 <-> Spark 8 | `192.0.2.10/30` <-> `192.0.2.10/30` | `192.0.2.10/30` <-> `192.0.2.10/30` |

## Validation Ladder

Use the switchless harness:

```bash
bash scripts/run-sparks58-switchless-mesh.sh
```

Useful modes:

```bash
MODE=snapshot bash scripts/run-sparks58-switchless-mesh.sh
MODE=underlay bash scripts/run-sparks58-switchless-mesh.sh
MODE=cleanup bash scripts/run-sparks58-switchless-mesh.sh
RUN_NCCL=1 MODE=nccl-pairs bash scripts/run-sparks58-switchless-mesh.sh
RUN_NCCL=1 MODE=nccl-ring bash scripts/run-sparks58-switchless-mesh.sh
```

Required proof order:

1. Management reachability and stale-job scan for all four nodes.
2. Live mapping snapshot before IP assignment.
3. Temporary point-to-point IP assignment on all direct links.
4. Jumbo ping both directions on every direct pair and both logical halves.
5. `ib_write_bw -R` both directions on every direct pair and both logical halves.
6. Two-node NCCL on each direct pair, with logs showing `NET/IB` and no socket
   fallback.
7. Four-node `all_reduce_perf` with `NCCL_ALGO=Ring` and host order
   Spark 5, Spark 6, Spark 8, Spark 7.
8. Only after the basic ring passes, sweep channels and QPs.

Stop and document the boundary if NCCL attempts non-neighbor paths, falls back
to sockets, or needs explicit routing/topology-file experiments.

## Live Findings

Initial reachability gate:

- `spark-e.example`, `spark-f.example`, `spark-h.example`, and `spark-g.example` were visible as
  online Tailscale peers.
- Tailscale SSH worked through `spark-e.example` through
  `spark-h.example`.
- LAN aliases answered ping, but LAN SSH with the NVIDIA Sync key was
  denied during the first gate, so management control used Tailscale SSH.
- A corrected stale-job scan found no lingering `mpirun`, `orted`,
  `all_reduce_perf`, `all_gather_perf`, `nccl-tests`, `ib_write_bw`, or
  `iperf3` processes.
- All four nodes had very fresh uptime after the physical cabling/power window.

Initial link mapping gate:

- All four expected Ethernet functions existed and were `UP,LOWER_UP`.
- `ibdev2netdev` mapped all four expected RoCE devices to the expected netdevs.
- `rdma link` reported `ACTIVE` / `LINK_UP` for all four RoCE devices on all
  four Sparks.
- `ethtool` reported `200000Mb/s`, full duplex, and link detected on all four
  logical functions.
- Before temporary IP assignment, the high-speed functions had only IPv6
  link-local addresses and `show_gids` found no IPv4 RoCE GIDs.

## Underlay Result

Raw evidence: `evidence/sparks58-switchless-mesh-20260701-135808/`

The direct host-side underlay passed on all four physical edges, both logical
halves, and both directions. Every `ib_write_bw -R` client result reported
`111.94 Gbits/sec` with exit code `0`:

| Direct edge | Logical half | Forward | Reverse |
| --- | --- | ---: | ---: |
| Spark 5 <-> Spark 6 | `rocep1s0f0` | `111.94 Gbits/sec` | `111.94 Gbits/sec` |
| Spark 5 <-> Spark 6 | `roceP2p1s0f0` | `111.94 Gbits/sec` | `111.94 Gbits/sec` |
| Spark 7 <-> Spark 8 | `rocep1s0f0` | `111.94 Gbits/sec` | `111.94 Gbits/sec` |
| Spark 7 <-> Spark 8 | `roceP2p1s0f0` | `111.94 Gbits/sec` | `111.94 Gbits/sec` |
| Spark 5 <-> Spark 7 | `rocep1s0f1` | `111.94 Gbits/sec` | `111.94 Gbits/sec` |
| Spark 5 <-> Spark 7 | `roceP2p1s0f1` | `111.94 Gbits/sec` | `111.94 Gbits/sec` |
| Spark 6 <-> Spark 8 | `rocep1s0f1` | `111.94 Gbits/sec` | `111.94 Gbits/sec` |
| Spark 6 <-> Spark 8 | `roceP2p1s0f1` | `111.94 Gbits/sec` | `111.94 Gbits/sec` |

Interpretation: the no-switch QSFP mesh is physically healthy. This matches the
earlier direct Spark-to-Spark bypass class and is not the CRS804-limited
throughput class.

## Two-Node NCCL Edge Result

The first NCCL attempts exposed two management/launcher details:

- Tailscale SSH as `public-user` had `memlock=8192`, causing
  `ibv_reg_mr_iova2 failed with error Cannot allocate memory`.
- LAN OpenSSH sessions as `public-user` had `memlock=unlimited`, so the
  successful NCCL harness enters Spark 5 as public-root over Tailscale, then starts a
  login shell as `public-user` and uses the existing on-node MPI key for LAN
  fanout.

The final two-node edge proof used 1MiB `all_gather_perf` as a path validation
target. Every direct edge selected `NET/IB`, kept OOB on `tailscale0`, reported
wrong/out-of-bounds `0`, and exited `0`:

| Direct edge | NCCL HCA set | Avg bus bandwidth |
| --- | --- | ---: |
| Spark 5 <-> Spark 6 | `rocep1s0f0,roceP2p1s0f0` | `4.93592 GB/s` |
| Spark 7 <-> Spark 8 | `rocep1s0f0,roceP2p1s0f0` | `4.06987 GB/s` |
| Spark 5 <-> Spark 7 | `rocep1s0f1,roceP2p1s0f1` | `5.06308 GB/s` |
| Spark 6 <-> Spark 8 | `rocep1s0f1,roceP2p1s0f1` | `5.32968 GB/s` |

These small-message values are path proof, not a tuned bandwidth claim.

## Four-Node NCCL Boundary

Command shape:

```text
all_reduce_perf, 1MiB, NCCL_ALGO=Ring
rank order: Spark 5, Spark 6, Spark 8, Spark 7
```

Result: STOP. System NCCL `2.28.9+cuda13.0` selected `NET/IB` devices on all
four nodes, but built connections across physically impossible non-neighbor
RoCE GID pairs:

```text
spark-e.example rocep1s0f0 local GID 192.0.2.10 -> remote GID 192.0.2.10
spark-g.example rocep1s0f0 local GID 192.0.2.10 -> remote GID 192.0.2.10
```

Those endpoints live on different direct point-to-point subnets and are not
cabled to each other. The run failed with:

```text
Call to ibv_modify_qp failed with 110 Connection timed out
```

This is the planned stop condition. Do not treat this as underlay failure. The
next NCCL step is a deliberate topology-aware experiment or hardware/topology
change, not more switch tuning.

## Software-Only Follow-Up Attempts

Per the "only stop for hardware configs" instruction, the run continued through
bounded software-only experiments after the first stock failure.

Built and synced NCCL `v2.30u1` from NVIDIA source under:

```text
/opt/public-cluster/src/nccl-v2.30u1/build
```

Build evidence:

```text
evidence/sparks58-switchless-nccl-build-20260701-142434/
```

The build linked `libnccl.so.2.30.7` and synced to Sparks 6, 8, and 7. The
runner was updated so `REMOTE_NCCL_HOME=/opt/public-cluster/src/nccl-v2.30u1/build`
can test that user-home NCCL without replacing the system package.

Four-node all-reduce attempts:

| Attempt | NCCL runtime | Extra env | Result |
| --- | --- | --- | --- |
| Baseline ring | `2.28.9+cuda13.0` | default harness env | FAIL, non-neighbor f0 GIDs |
| Cross-NIC | `2.28.9+cuda13.0` | `NCCL_CROSS_NIC=1` | FAIL, non-neighbor f0 GIDs |
| Cross-NIC one-channel | `2.28.9+cuda13.0` | `NCCL_CROSS_NIC=1`, `NCCL_MIN_NCHANNELS=1`, `NCCL_MAX_NCHANNELS=1` | FAIL, non-neighbor f0 GIDs |
| Newer NCCL one-channel | `2.30.7+cuda13.0` | `NCCL_CROSS_NIC=1`, one channel | FAIL, non-neighbor f0 GIDs |
| Newer NCCL all netdevs | `2.30.7+cuda13.0` | `NCCL_CROSS_NIC=1`, `NCCL_NETDEVS_POLICY=ALL`, one channel | FAIL, non-neighbor f0 GIDs |
| NCCL suggested confirmation | `2.30.7+cuda13.0` | `NCCL_CROSS_NIC=0`, one channel | FAIL, non-neighbor f0 GIDs |

Representative saved logs:

```text
evidence/sparks58-switchless-mesh-20260701-135808/s5-s6-s8-s7-ring.stock-baseline-fail.nccl.log
evidence/sparks58-switchless-mesh-20260701-135808/s5-s6-s8-s7-ring.cross-nic-fail.nccl.log
evidence/sparks58-switchless-mesh-20260701-135808/s5-s6-s8-s7-ring.cross-nic-one-channel-fail.nccl.log
evidence/sparks58-switchless-mesh-20260701-135808/s5-s6-s8-s7-ring.v230u1-loaded-fail.nccl.log
evidence/sparks58-switchless-mesh-20260701-135808/s5-s6-s8-s7-ring.v230u1-netdevs-all-fail.nccl.log
evidence/sparks58-switchless-mesh-20260701-135808/s5-s6-s8-s7-ring.v230u1-cross-nic0-confirm-fail.nccl.log
```

The final NCCL `2.30.7` logs confirmed the runtime was actually loaded:

```text
nccl-tests version 2.19.1 nccl-headers=22809 nccl-library=23007
NCCL version 2.30.7+cuda13.0
```

They still selected `NET/IB/0` for both receive and send on each rank, so
Spark 5 tried to receive from Spark 7 over f0 and Spark 8 tried to send to
Spark 7 over f0:

```text
spark-e.example rocep1s0f0 local GID 192.0.2.10 -> remote GID 192.0.2.10
spark-g.example rocep1s0f0 local GID 192.0.2.10 -> remote GID 192.0.2.10
```

NCCL `2.30.7` also emitted the relevant hint:

```text
In many cases this error occurs when NICs are not cross-rail connected.
To confirm, you can set NCCL_CROSS_NIC=0 to disable cross-rail communication.
```

That confirmation run with `NCCL_CROSS_NIC=0` failed the same way. The current
software conclusion is therefore stronger than the initial stop point: this
specific four-node square is not solved by `NCCL_CROSS_NIC`,
`NCCL_NETDEVS_POLICY=ALL`, one-channel forcing, or the tested NCCL `v2.30u1`
runtime. A passing four-node collective now requires a true topology-aware
rank-to-NIC mechanism, a custom collective/launcher that can choose NICs per
edge, or a hardware/topology change.

## Novel Software Experiments

Raw evidence:

```text
evidence/sparks58-novel-20260701-194237/
```

The novel runner is host-side only:

```bash
scripts/run-sparks58-novel-experiments.sh
```

It adds software-only experiments above the first proof ladder without touching
the CRS804 or changing switch state.

### Concurrent RDMA Ring Saturation

All four ring edges ran `ib_write_bw -R` at the same time. Both logical rails
passed with every row at `111.85 Gbits/sec` and `rc=0`:

| Edge | Rail | RDMA device | Avg |
| --- | --- | --- | ---: |
| Spark 5 -> Spark 6 | rail0 | `rocep1s0f0` | `111.85 Gbits/sec` |
| Spark 6 -> Spark 8 | rail0 | `rocep1s0f1` | `111.85 Gbits/sec` |
| Spark 8 -> Spark 7 | rail0 | `rocep1s0f0` | `111.85 Gbits/sec` |
| Spark 7 -> Spark 5 | rail0 | `rocep1s0f1` | `111.85 Gbits/sec` |
| Spark 5 -> Spark 6 | rail1 | `roceP2p1s0f0` | `111.85 Gbits/sec` |
| Spark 6 -> Spark 8 | rail1 | `roceP2p1s0f1` | `111.85 Gbits/sec` |
| Spark 8 -> Spark 7 | rail1 | `roceP2p1s0f0` | `111.85 Gbits/sec` |
| Spark 7 -> Spark 5 | rail1 | `roceP2p1s0f1` | `111.85 Gbits/sec` |

Interpretation: the direct square can carry simultaneous load on every edge.
This is stronger than single-edge RDMA proof and makes a physical-link
explanation for the four-node NCCL failure unlikely.

### Concurrent Two-Node NCCL Phases

Two disjoint NCCL phases passed:

| Phase | Edge pair | Result |
| --- | --- | --- |
| A | Spark 5 <-> Spark 6 and Spark 8 <-> Spark 7 | both `rc=0`, `NET/IB=1`, socket fallback `0`, wrong/out-of-bounds `0` |
| B | Spark 6 <-> Spark 8 and Spark 7 <-> Spark 5 | both `rc=0`, `NET/IB=1`, socket fallback `0`, wrong/out-of-bounds `0` |

Interpretation: NCCL's IB transport is healthy on every direct edge even when
two independent edge collectives run concurrently.

### Four-Rank HCA / Env Probes

All four-rank probes used NCCL `2.30.7+cuda13.0` and failed with the same
non-neighbor GID class:

| Probe | Result |
| --- | --- |
| `f0-first` | `rc=3`, NCCL `2.30.7`, non-neighbor GIDs present |
| `f1-first` | `rc=3`, NCCL `2.30.7`, non-neighbor GIDs present |
| `all-policy` | `rc=3`, NCCL `2.30.7`, non-neighbor GIDs present |
| `crossnic0` | `rc=3`, NCCL `2.30.7`, non-neighbor GIDs present |
| `appctx-ring-neighbor-biased` | `rc=3`, NCCL `2.30.7`, non-neighbor GIDs present |

The `crossnic0` row is the final Perplexity-recommended env sanity check:
`NCCL_CROSS_NIC=0` with `NCCL_IB_MERGE_NICS=0`,
`NCCL_IB_SUBNET_AWARE_ROUTING=1`, one channel, and all direct HCAs visible.
It still selected impossible f0 GID pairs.

The per-rank app-context probe tried to bias each rank toward the HCA pair
needed for its two physical neighbors. It still failed before data movement,
which means ordinary `mpirun` app-context HCA ordering is not enough to express
per-edge NIC selection to stock NCCL.

The compact classifier reduced all accumulated NCCL failures to two impossible
non-neighbor GID pairs:

| Count | Local IP | Remote IP | Classification |
| ---: | --- | --- | --- |
| 245 | `192.0.2.10` | `192.0.2.10` | non-neighbor, missing direct edge |
| 245 | `192.0.2.10` | `192.0.2.10` | non-neighbor, missing direct edge |

### NCCL Topology Dump

Spark 5 produced:

```text
topo-dump.spark-e.example.collect.log
hca-probe.topo-dump.log
```

The dump showed all four local RoCE devices as 200G network devices and the
graph recorded `crossnic=1`. NCCL selected `NET/IB` and kept OOB on
`tailscale0`, but still constructed non-neighbor GID pairs:

```text
spark-e.example local GID 192.0.2.10 -> remote GID 192.0.2.10
spark-g.example local GID 192.0.2.10 -> remote GID 192.0.2.10
```

The other hosts did not leave separate `/var/tmp/public-run/sparks58-topo.xml` files, but the
combined NCCL log confirms every rank enumerated all four RoCE devices and used
the same NCCL runtime.

### NCCL Topology-File Read Probe

The topology-file probe extracted Spark 5's dumped NCCL topology XML, copied it
to all four nodes as `/var/tmp/public-run/sparks58-topo-file.xml`, and reran the four-rank
ring with:

```text
NCCL_TOPO_FILE=/var/tmp/public-run/sparks58-topo-file.xml
NCCL_TOPO_DUMP_FILE=/var/tmp/public-run/sparks58-topo-file-after.xml
NCCL_GRAPH_DUMP_FILE=/var/tmp/public-run/sparks58-graph-topofile.xml
```

The log confirmed NCCL read the file:

```text
NCCL INFO Loading topology file /var/tmp/public-run/sparks58-topo-file.xml
```

It still failed with the same impossible f0 non-neighbor pairs. Interpretation:
a normal local NCCL topology XML is useful for PCI/NIC inventory, but it did
not encode the sparse inter-host direct-link graph needed by this four-node
square.

### Explicit-Edge Custom Ring

The custom harness copied `scripts/sparks58_custom_ring.py` to the Sparks and
ran a small TCP ring all-reduce over only the valid direct-neighbor IPs:

```text
Spark 5 192.0.2.10 -> Spark 6 192.0.2.10
Spark 6 192.0.2.10 -> Spark 8 192.0.2.10
Spark 8 192.0.2.10 -> Spark 7 192.0.2.10
Spark 7 192.0.2.10 -> Spark 5 192.0.2.10
```

With `CUSTOM_RING_ELEMENTS=1048576`, each rank sent 4 MiB messages around the
ring, accumulated all four ranks, and verified the expected sum. All ranks
exited `0` with `ok=1`:

| Rank | Spark | Send source | Next IP | Receive IP | Result |
| --- | --- | --- | --- | --- | --- |
| 0 | Spark 5 | `192.0.2.10` | `192.0.2.10` | `192.0.2.10` | `ok=1` |
| 1 | Spark 6 | `192.0.2.10` | `192.0.2.10` | `192.0.2.10` | `ok=1` |
| 2 | Spark 8 | `192.0.2.10` | `192.0.2.10` | `192.0.2.10` | `ok=1` |
| 3 | Spark 7 | `192.0.2.10` | `192.0.2.10` | `192.0.2.10` | `ok=1` |

This is not a production RDMA/NCCL implementation. It is a topology proof: when
the software explicitly chooses the physical neighbor edges, the four-node ring
can complete a global collective.

### Pinned UCX/RDMA Direct Ring

The UCX experiment first failed when `UCX_NET_DEVICES=all` let UCX choose
non-neighbor devices. After pinning each edge to the correct local RoCE device,
all four concurrent direct-edge UCX `tag_bw` probes exited `0`:

| Edge | Source IP | Destination IP | RDMA device | Result |
| --- | --- | --- | --- | --- |
| Spark 5 -> Spark 6 | `192.0.2.10` | `192.0.2.10` | `rocep1s0f0` | `rc=0` |
| Spark 6 -> Spark 8 | `192.0.2.10` | `192.0.2.10` | `rocep1s0f1` | `rc=0` |
| Spark 8 -> Spark 7 | `192.0.2.10` | `192.0.2.10` | `rocep1s0f0` | `rc=0` |
| Spark 7 -> Spark 5 | `192.0.2.10` | `192.0.2.10` | `rocep1s0f1` | `rc=0` |

This is the strongest software-only separation so far: UCX can use the square
when each edge is explicitly pinned, while stock NCCL's automatic graph still
selects non-neighbor GIDs.

### Final Postcheck

The final readiness postcheck passed and found no lingering benchmark jobs:

```text
evidence/sparks58-novel-20260701-194237-finalcheck/stale-jobs.txt
evidence/sparks58-novel-20260701-194237-finalcheck2/stale-jobs.txt
```

## Cabling Verification Conclusion

The live data and Perplexity reference check now agree:

1. The cables are not the failure. All direct edges are up at 200GbE link speed,
   jumbo ping passed, `ib_write_bw -R` passed both directions on both logical
   halves, and two-node NCCL selected `NET/IB` on every direct edge.
2. There is no obvious recabling of the same four physical edges that makes
   stock NCCL's "use the same NIC index for a channel on all ranks" assumption
   valid for every edge of this square. Each node must use f0 for one neighbor
   and f1 for the other neighbor.
3. The novelty is the four-node switchless collective topology, not the cabling
   or the raw RoCE underlay. The explicit-edge custom ring proves a global
   collective can complete when software uses only valid neighbors.
4. The next production-grade experiments should be topology-aware NCCL,
   topology-file/graph override work, or custom rank-to-NIC control, not cable
   swapping unless a new physical topology is intentionally being tested.

## Perplexity / External Reference Check

Per the user request, Perplexity was used as a reference check for the
switchless settings and for the novel experiment interpretation. The useful
guidance was to keep `NCCL_SOCKET_IFNAME` on a management/TCP fallback
interface, prove data movement with `NET/IB`, include all direct RoCE HCAs, and
stop if stock NCCL tries non-neighbor paths. The follow-up Perplexity pass
agreed with the live interpretation and suggested only a narrow final env check:
`NCCL_CROSS_NIC=0` with NIC merge disabled and subnet-aware routing enabled.
That check is now captured as the failing `crossnic0` HCA probe.

Primary sources checked from that Perplexity pass:

- NVIDIA NCCL networking troubleshooting recommends verifying RDMA state and
  using `ib_write_bw` between compute nodes before blaming NCCL.
- NVIDIA NCCL environment documentation says `NCCL_TOPO_FILE` loads an XML
  topology file, `NCCL_CROSS_NIC` controls whether a ring/tree may use
  different NICs across rails, `NCCL_IB_HCA` constrains the RDMA interfaces
  used by NCCL, and `NCCL_NET_MERGE_POLICY` is for rail-optimized HCA merging
  rather than per-edge rank-to-NIC mapping.
- NVIDIA's DGX Spark playbooks document direct two-node, direct three-node
  ring, and four-node/multi-node operation through a QSFP switch. I found no
  official stock-NCCL four-node direct square recipe.
- An NVIDIA Developer Forums DGX Spark thread shows the same class of
  switchless-mesh failure: NCCL tries RoCE GID pairs that are not physically or
  logically reachable, and the suggested resolution is a mesh-aware NCCL path
  rather than ordinary stock-NCCL routing.

Links:

- Perplexity validation query:
  <https://example.invalid/reference/UUID-PLACEHOLDER-01>
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
