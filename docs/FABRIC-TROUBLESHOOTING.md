# RoCE Fabric Troubleshooting Record

## Baseline that failed

The first four-system fabric looked healthy at the physical layer:

- link speed reported `200000 Mb/s`;
- MTU was `9000`; and
- ordinary FEC and drop checks did not identify a clear physical fault.

Useful throughput did not match:

| Test | Recorded result |
| --- | --- |
| TCP | roughly `9.3-9.43 Gbit/s`, with retransmits |
| Raw RDMA | roughly `0.1-7 Gbit/s` |
| Reboot | no material correction |

That result blocked NCCL performance conclusions. The underlay had not earned a workload benchmark yet.

## RouterOS and QoS validation

The CRS804-4DDQ was backed up and upgraded to RouterOS `7.23.1`. The source-backed RoCE shape used:

- `200G-baseCR4`;
- MTU `9000`;
- DSCP `26` mapped to traffic class 3;
- CNP `48` mapped to traffic class 6;
- ECN on traffic class 3;
- PFC on traffic class 3; and
- a `100 Gbit/s` configured egress rate, the relevant RouterOS setting limit.

Queue 3 counters increased and showed zero drops, but raw RDMA stayed near `5-7 Gbit/s` and TCP stayed near `8-9 Gbit/s` with retransmits. QoS classification was therefore functioning, but it was not the throughput root cause.

Bounded cold-drain and PFC-bypass tests also failed to correct the path. They were rolled back rather than left as unexplained configuration drift.

## Host and cable isolation

MFT `4.35.0.159-1` reported both active functions at `200G x4`, Standard RS-FEC, with no observed issue. A direct cable between two Sparks removed the switch from the data path:

| Direct test | Recorded result |
| --- | ---: |
| TCP | `12.8 Gbit/s`, no retransmits |
| RDMA | `12.71 Gbit/s` |

The direct path was better than the switched path but still below the intended per-rail gate. The conclusion was deliberately narrow: the switch worsened the symptom, while host-side limitations still required investigation.

## Physical and logical correction

The NVIDIA-aligned shape used the second ConnectX-7 port consistently on every Spark. It exposed two logical f1 functions:

```text
rail 0: enp1s0f1np1 / rocep1s0f1
rail 1: enP2p1s0f1np1 / roceP2p1s0f1
```

Each rail used its own subnet. Sharing one subnet across both functions was rejected because it created route ambiguity and unreliable NCCL behavior.

The physical change was followed by link, MTU, address, and directed-path checks before load testing.

## Forwarding root cause

The switch bridge host table and ARP state looked correct, but high-rate fabric traffic was being forwarded toward the switch CPU. The CPU queue accumulated drops instead of keeping the flow in the Marvell Prestera ASIC path.

Before the repair:

- TCP was roughly `9 Gbit/s` per half, with retransmits;
- UDP receive was roughly `9.9 Gbit/s` with about `87%` loss; and
- CPU-queue counters added roughly `16.9 million` dropped packets and about `152 GB` of dropped traffic.

The repair added explicit destination-forwarding rules based on the live-learned fabric relationships. The public record omits destination identifiers and physical port numbers. The engineering change was:

```text
for each learned fabric destination:
    match destination on the bridge data path
    forward to the proved fabric egress
    keep the flow in the switch ASIC
```

The rules were preceded by switch backup/export and carried a shared comment prefix so the complete change could be removed as one rollback.

## Repair evidence

| Test | Recorded result |
| --- | ---: |
| Repaired single path | `111.07 Gbit/s`, one retransmit |
| Dual TCP pair A | `197.62 Gbit/s`, zero retransmits |
| Dual TCP pair B | `198.00 Gbit/s`, zero retransmits |
| Cross-pair TCP | `196.61 Gbit/s`, zero retransmits |
| Sequential RDMA rail 0 | `97.98 Gbit/s` |
| Sequential RDMA rail 1 | `97.98 Gbit/s` |

This moved the failure classification away from FEC, MTU, cable link-up, and RDMA-device presence. The meaningful root cause was the forwarding path.

## Recable regression

A later physical rack recable changed which systems reached several fabric egresses. Four static forwarding destinations still pointed at the old relationship.

The links remained at `200G-baseCR4` with `fec91`, and all expected fabric destinations were learned, but the stale static rules overrode the working physical state. The pre-fix small-packet matrix passed only `24/112` directed paths.

After backup/export, only the stale forwarding destinations were corrected. The same acceptance program then passed:

- small ping `112/112`;
- jumbo ping `112/112`;
- directed RDMA `112/112`;
- RDMA range `109.06-109.30 Gbit/s`, mean `109.20 Gbit/s`;
- MPI fanout `8/8`; and
- all-eight NCCL canary and fixed-size collective.

The lesson is operational: a physical recable invalidates static forwarding assumptions even when the links themselves stay green. Revalidation must include every directed path, not one representative pair.

## Acceptance order

1. Prove host identity over management.
2. Prove both fabric interfaces, speed, FEC, and MTU.
3. Prove small-packet reachability on every directed pair.
4. Prove jumbo frames on every directed pair.
5. Prove RDMA-CM on every directed pair and both rails.
6. Prove MPI fanout.
7. Prove NCCL uses `NET/IB`, has no `NET/Socket` fallback, and reports wrong `0`.
8. Sweep for lingering test processes.

Skipping an earlier gate makes a later benchmark ambiguous.
