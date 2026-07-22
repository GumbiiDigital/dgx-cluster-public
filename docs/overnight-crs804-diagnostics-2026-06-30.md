# CRS804 Cold-Drain Diagnostic Summary - 2026-06-30

## Context

- Switch: MikroTik CRS804-4DDQ, RouterOS 7.23.1, identity `switch-a`.
- Fabric ports under test:
  - `fabric-port-a` -> Spark 1, `192.0.2.10`
  - `fabric-port-b` -> Spark 2, `192.0.2.10`
  - `fabric-port-c` -> Spark 3, `192.0.2.10`
  - `fabric-port-d` -> Spark 4, `192.0.2.10`
- All four links were 200G-baseCR4 with MTU 9000.
- Raw evidence was captured locally under ignored path:
  `evidence/overnight-crs804-20260630-114412/`

## Test Sequence

1. Waited for all four Sparks after cold-drain power cycle.
2. Captured CRS804 and host baseline state.
3. Tested `flat-no-qos` on `cluster-bridge`.
4. Tested `minimal-bridge-flat` on temporary `br-overnight`.
5. Restored ports to `cluster-bridge`.
6. Tested `roce-qos` with:
   - `trust-l3=keep`
   - `pfc=pfc-tc3`
   - `egress-rate-queue3=100G`
   - host PFC priority 3 and `cma_roce_tos=106`

## Results

TCP via CRS804 stayed in the same range across all profiles and tested pairs:

- Short `iperf3 -P16` sender results: `8.79-9.75 Gbits/sec`.
- Long Spark1-to-Spark2 300s soak results:
  - `flat-no-qos`: `8.91 Gbits/sec`
  - `minimal-bridge-flat`: `9.03 Gbits/sec`
  - `roce-qos`: `9.17 Gbits/sec`

RDMA-CM `ib_write_bw -R -q8 -s 8388608` stayed in a narrow range:

- `flat-no-qos`: `6.54-6.77 Gbits/sec`
- `minimal-bridge-flat`: `6.61-6.72 Gbits/sec`
- `roce-qos`: `6.54-6.70 Gbits/sec`

Non-RDMA-CM `ib_write_bw` failed in all profiles and directions with the same pattern:

- Client-side completion error
- `Failed status 12`
- `syndrom 0x81`
- Server-side socket/RDMA exchange failure

CRS804 counters did not show obvious physical-layer or queue-drop failure:

- `rx-error-events`: `0` on all four ports at before/after snapshots.
- `tx-drop-packet`: `0` on all four ports at before/after snapshots.
- `rs-fec-uncorrected` remained stable at `29`, `28`, `36`, `24` across snapshots.

## Current Switch State After Run

The diagnostic completed cleanly and left the four fabric ports restored to `cluster-bridge`.

QoS on the four fabric ports was left in the RoCE profile:

- `trust-l2=ignore`
- `trust-l3=keep`
- `pfc=pfc-tc3`
- `egress-rate-queue3=100.0Gbps`

## Interpretation

The cold-drain, flat/no-QoS profile, minimal bridge isolation, and RoCE QoS profile all reproduced the same cap. That makes a simple stale-state or bridge-side configuration issue less likely.

The result still does not prove the CRS804 cannot do the job. The next research step is to find a known-good CRS804 plus DGX Spark setup guide or forum report and compare every boring detail: exact RouterOS version, port breakout mode, cabling type, bridge/QoS settings, ECN/PFC mapping, host interface names, RDMA GID/CM usage, and whether tests were run through the switch or direct cable.

## Open Question For Next Thread

Find the source-of-truth setup path for DGX Spark nodes on CRS804:

- NVIDIA DGX Spark documentation, forums, developer forums, or validated partner notes.
- MikroTik CRS804/CRS5xx/Prestera RouterOS reports that explicitly mention RoCE, 200G/400G DAC, PFC, ECN, or unexpected 10G-like throughput.
- Any known-good four-node or eight-node Spark deployment on this switch, including exact commands and expected benchmark numbers.
