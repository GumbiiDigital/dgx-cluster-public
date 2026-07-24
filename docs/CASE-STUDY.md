# Case Study: From Link-Up to a Defensible Eight-System Fabric

## The problem I was actually solving

The hardware could report healthy links while the useful data path remained slow. That distinction shaped the entire build. I needed to know whether management identity, physical link, Ethernet forwarding, RDMA, MPI launch, and NCCL collectives all worked independently and together.

I did not want a cluster that looked complete because the LEDs were green. I wanted a sequence of gates that would fail at the layer that was actually broken.

## Recorded timeline

| Date | Engineering milestone |
| --- | --- |
| 2026-06-28 | First-system identity and management bring-up |
| 2026-06-29 | Four-system parity and underlay baseline |
| 2026-06-30 | RoCE isolation, topology correction, and switch forwarding repair |
| 2026-07-01 | Four-system NCCL validation and profile work |
| 2026-07-03 | Eight-system recable repair and NCCL tuning |
| 2026-07-17 | Raspberry Pi BLE commissioning and fail-closed correction |
| 2026-07-21 | Post-rack topology rerun and thermal-management documentation |

## Phase 1: identity before fabric

The first systems came online through ordinary management Ethernet. Each one had to pass hostname, address, SSH, GPU, software, service, and firmware checks before I treated the cable label as trustworthy or attached the high-speed fabric.

That caught an early naming problem: a newly detected system and an existing synchronization target could have been mistaken for the same machine. The operating rule became explicit: detect first, prove host identity, then label the physical system.

The first four systems were normalized to:

- Ubuntu `24.04.4`;
- NVIDIA kernel `6.17.0-1021-nvidia`;
- NVIDIA driver `580.159.03`;
- CUDA `13.0` in the recorded baseline;
- no failed services;
- no reboot-required marker; and
- current firmware status at the time of the check.

One system required the matching open NVIDIA kernel module. Another had a failed one-time service that was reset and rerun. Those corrections stayed in the record because parity is a measured state, not a visual assumption.

## Phase 2: the first performance result was a stop sign

The initial fabric had `200000 Mb/s` links and MTU `9000`, but the application path did not match that physical state:

- TCP was roughly `9.3-9.43 Gbit/s`, with retransmits;
- raw RDMA varied from roughly `0.1-7 Gbit/s`; and
- a reboot did not repair either logical function.

I stopped before treating NCCL as a fabric benchmark. A collective benchmark on a broken underlay would have produced a number, but not a useful conclusion.

## Phase 3: eliminate the easy explanations

The switch was upgraded to RouterOS `7.23.1` after backup and export. The recorded configuration work included:

- `200G-baseCR4` links;
- MTU `9000`;
- source-backed RoCE QoS using DSCP `26` for traffic class 3;
- CNP `48` for traffic class 6;
- ECN on traffic class 3;
- PFC on traffic class 3; and
- a `100 Gbit/s` egress rate because that was the platform limit for the setting.

Queue 3 counters moved with zero drops, but raw RDMA remained roughly `5-7 Gbit/s`, and TCP remained roughly `8-9 Gbit/s` with retransmits. Cold-drain tests and a bounded PFC bypass did not fix it.

MFT `4.35.0.159-1` reported both active functions at `200G x4`, Standard RS-FEC, and no observed issue. A direct system-to-system cable then produced `12.8 Gbit/s` TCP without retransmits and `12.71 Gbit/s` RDMA. That proved the switch made the symptom worse, but it also showed the host path was not yet near the intended per-rail gate.

## Phase 4: align the physical and logical shape

The source-backed known-good layout used the second ConnectX-7 port on every system, exposing two logical functions on separate subnets. The public aliases retain that relationship:

- rail 0: `enp1s0f1np1` / `rocep1s0f1`;
- rail 1: `enP2p1s0f1np1` / `roceP2p1s0f1`; and
- one subnet per rail.

Putting both logical functions on one subnet was rejected because it created route ambiguity and invalid NCCL behavior. The physical move was followed by read-only link checks before any performance claim.

## Phase 5: find the switch forwarding failure

The decisive symptom was switch CPU traffic. High-rate fabric frames were reaching the switch CPU path and being dropped even though the bridge host table and ARP state looked correct.

Before the repair:

- TCP was roughly `9 Gbit/s` per half, with retransmits;
- UDP receive was roughly `9.9 Gbit/s` with about `87%` loss; and
- the switch CPU queue added roughly `16.9 million` dropped packets and about `152 GB` of dropped traffic.

Explicit destination forwarding rules moved the learned fabric destinations back to the Marvell Prestera ASIC path. The rules used live-learned relationships, were backed up first, and had a comment-based rollback.

After the repair:

- one repaired path reached `111.07 Gbit/s` with one retransmit;
- dual TCP pair results were `197.62`, `198.00`, and `196.61 Gbit/s`, all with zero retransmits; and
- sequential RDMA on both logical rails reached `97.98 Gbit/s`.

The root cause was not FEC, MTU, cable link-up, or host RDMA device absence. It was a forwarding-path error that ordinary link health did not expose.

## Phase 6: recable, break the mapping, and prove the repair

A later rack recable left stale static forwarding destinations on four systems. The links were still physically healthy, but the old logical-to-physical relationship stranded those nodes.

Before the correction, the small-packet matrix passed only `24/112` directed paths. I captured switch backup/export state, changed only the stale forwarding destinations, and reran the same acceptance program.

After the correction:

- small ping passed `112/112`;
- jumbo ping passed `112/112`;
- directed RDMA passed `112/112`;
- RDMA ranged from `109.06-109.30 Gbit/s`, mean `109.20 Gbit/s`;
- MPI fanout passed `8/8`;
- the all-eight NCCL canary passed over `NET/IB`; and
- the fixed `256 MiB` collective completed with wrong `0` and average bus bandwidth `20.1189 GB/s`.

That final NCCL number was recorded as the repair baseline, not a peak.

## Phase 7: tune only after the fabric was valid

The frozen all-eight profile used two QPs per connection, no split across QPs, and twelve channels. Three longer `256 MiB` repeats produced `22.9494`, `23.0400`, and `23.0002 GB/s`, for a mean of `22.9965 GB/s` and wrong `0`.

That was about `5.7%` above the pre-tuning all-eight baseline of `21.7487 GB/s`. A single quick run reached higher, but I did not freeze the one-off peak because the longer head-to-head set favored the twelve-channel profile for stability.

The full result is in [NCCL-TUNING-RECORD.md](NCCL-TUNING-RECORD.md).

## Phase 8: revalidate after the rack changed again

The physical result is documented in the [rack overview](../media/review/gumbii-dgx-spark-rack-overview.jpg). The public image is evidence of the build, not an operational topology diagram.

After another teardown and reassembly, the full validation ran again rather than relying on the old success:

- all eight management SSH checks passed;
- all sixteen fabric interfaces were up at `200000 Mb/s`, MTU `9000`;
- jumbo ping passed `112/112`;
- `105/112` directed RDMA paths passed under the concurrent sweep;
- the seven outliers passed a bounded serial retry at `111.85 Gbit/s`;
- the secondary-rail mean was `111.94 Gbit/s` across `56/56` directed paths;
- NCCL completed with wrong `0` and `23.8196 GB/s` average bus bandwidth; and
- the debug canary recorded `824` `NET/IB` lines and zero `NET/Socket` lines.

The concurrent outliers were classified as test-load contention only because the same paths passed the bounded serial rerun. They were not silently discarded.

## Phase 9: remove the PSU heat pocket and prove the fan path

The middle of the rack concentrated eight power supplies, cable loops, and warm
air in one narrow area. I designed a printed support that moved each PSU off the
rack surface and opened a vertical path below the bricks.

![Original PSU heat pocket](../media/review/01-rack-heat-pocket-before.jpg)

The first orange print fit the PSU, but its rack-retention clip did not fit the
shelf correctly. Reprinting the entire support for every dimensional change
would have wasted time and material, so I printed four small clip coupons with
four measurements, selected the one that fit, and transferred that dimension
back into the full model.

![Four dimensional clip tests](../media/review/05-dimensional-test-clips.jpg)

The final green supports were printed in production pairs, installed across the
rack, and positioned above a dedicated fan.

![Fan below the raised PSU supports](../media/review/11-fan-below-psu-standoffs.jpg)

The bounded control test started at `82.4 F` with the fan running. After a
two-minute fan-OFF interval, the same rack probe read `82.8 F`. The fan was
restored through the Raspberry Pi; the immediate reading was `82.9 F`, so I did
not claim recovery yet. A later independent readback showed the fan ON and the
probe at `82.5 F`. Every protected outlet remained ON.

That test proves the selected fan relay, independent readback, and an observable
short-window temperature response. It does not establish rack CFM, long-term
thermal capacity, or a maximum safe workload temperature. The full print and
test record is in [THERMAL-MANAGEMENT.md](THERMAL-MANAGEMENT.md).

## What this work demonstrates

The defensible result is not a single benchmark. It is the chain of evidence:

1. prove identity;
2. prove link and MTU;
3. prove every directed rail path;
4. prove RDMA transport;
5. prove MPI launch;
6. prove NCCL transport and correctness;
7. repeat enough runs to freeze a profile; and
8. rerun the chain after physical change.

That is the engineering record preserved here.
