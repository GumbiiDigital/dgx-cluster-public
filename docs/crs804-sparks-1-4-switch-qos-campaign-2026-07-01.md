# CRS804 Sparks 1-4 Switch QoS Campaign

Date: 2026-07-01

Status: completed on live Sparks 1-4. Raw evidence is local and ignored under
`evidence/crs804-switch-campaign-20260701-152637/`.

## Goal

Test whether CRS804-side queue classification can improve or stabilize the
already-working four-Spark NCCL profile without breaking the frozen host/RDMA
baseline.

Target ports:

- Spark 1: `fabric-port-a`
- Spark 2: `fabric-port-b`
- Spark 3: `fabric-port-c`
- Spark 4: `fabric-port-d`

Host profile:

- Base: `scripts/sparks14-nccl-profile.env`
- Switch-classified candidate: `scripts/sparks14-crs804-switch-tc3-profile.env`
- Host marking for the candidate: `NCCL_IB_TC=104`

Switch snippets:

- Apply candidate: `scripts/crs804-sparks14-switch-tc3-candidate.rsc`
- Roll back to pre-campaign live state:
  `scripts/crs804-sparks14-switch-prestate-rollback.rsc`

## Prestate

Prestate evidence:
`evidence/crs804-switch-campaign-20260701-152637/task02-switch-prestate/`

The live switch was not plain default QoS. Before the campaign, Sparks 1-4
already had:

```text
trust-l3=keep
pfc=pfc-tc3
egress-rate-queue3=100.0Gbps
DSCP 26 -> traffic-class 3
DSCP 48 -> traffic-class 6
TC3 ecn=yes
TC3 schedule=high-priority-group weight=1
```

The prestate was captured with RouterOS export and a binary backup before any
new switch write.

## Results

Fixed `256MiB` four-node `all_reduce_perf`, average bus bandwidth:

| Step | Switch / host condition | Mean GB/s | Range GB/s | Wrong | Interpretation |
| --- | --- | ---: | --- | ---: | --- |
| Current prestate | No `NCCL_IB_TC`; live prestate switch QoS | 23.8096 | 23.7690-23.8489 | 0 | Baseline remains healthy, but traffic stays in queue1. |
| Host TC104 | Prestate TC3 capped at 100G | 11.0920 | 11.0776-11.1035 | 0 | DSCP/TC classification works, but TC3 cap halves NCCL and creates queue3 drops. |
| Host TC106 | Prestate TC3 capped at 100G | 11.0946 | 11.0776-11.1069 | 0 | ECN-capable bits do not avoid the cap. |
| TC104 + FIFO192 | Prestate TC3 capped at 100G | 11.1013 | 11.0938-11.1064 | 0 | Control traffic marking does not rescue capped TC3. |
| TC3 cap removed | Unmarked | 23.8143 | 23.7909-23.8329 | 0 | Removing the cap does not hurt baseline. |
| TC3 cap removed | `NCCL_IB_TC=104` | 23.8031 | 23.7821-23.8278 | 0 | Queue3 classification becomes safe. |
| TC3 cap removed | `NCCL_IB_TC=104 NCCL_IB_FIFO_TC=192` | 23.8170 | 23.7905-23.8383 | 0 | No meaningful gain over TC104 alone. |
| PFC disabled | TC3 uncapped, `NCCL_IB_TC=104` | 23.8021 | 23.7769-23.8195 | 0 | PFC is not needed for this four-node NCCL case. |
| TC3 ECN disabled | PFC off, TC3 uncapped, `NCCL_IB_TC=104` | 23.8158 | 23.7770-23.8414 | 0 | ECN off is neutral-to-slight-positive. |
| TC3 strict priority | PFC off, TC3 uncapped, ECN off, `NCCL_IB_TC=104` | 23.8292 | 23.7912-23.8413 | 0 | Best short marked candidate. |
| Best x10 | Same strict-priority candidate | 23.8225 | 23.7750-23.8458 | 0 | Stable enough to document as the candidate profile. |
| Trust-l3 ignore control | Candidate except `trust-l3=ignore` | 23.7895 | 23.7414-23.8223 | 0 | Marked traffic falls back to queue1; queue3 placement depends on L3 trust. |

Size spot checks on the candidate:

| Size | Repeats | Mean GB/s | Range GB/s | Wrong |
| --- | ---: | ---: | --- | ---: |
| 32MiB | 3 | 22.8745 | 22.8707-22.8784 | 0 |
| 1GiB | 3 | 24.1106 | 24.0995-24.1242 | 0 |
| 4GiB | 3 | 24.1922 | 24.1735-24.2152 | 0 |

Verbose transport proof:
`evidence/crs804-switch-campaign-20260701-152637/task14-debug-transport-proof/`

- `NCCL_IB_TC=104` exported to the run.
- NCCL logged `Using network IB`.
- NCCL used both `rocep1s0f1` and `roceP2p1s0f1`.
- No socket fallback was observed.

## Mixed Load

Evidence:
`evidence/crs804-switch-campaign-20260701-152637/task10-mixed-load/`

Background load was unmarked `iperf3` from Spark 1 to Spark 2 over
`192.0.2.10`, 16 streams, overlapping the NCCL run.

| NCCL condition | Mean GB/s | Range GB/s | Wrong | TCP sum |
| --- | ---: | --- | ---: | ---: |
| Unmarked NCCL | 10.8062 | 10.6209-11.1479 | 0 | 85.4 Gbit/s |
| `NCCL_IB_TC=104` into TC3 | 14.0841 | 13.6639-14.5054 | 0 | 85.1 Gbit/s |

Interpretation: queue classification materially protects NCCL under heavy
queue1 TCP pressure, but it does not fully isolate NCCL from a same-link fabric
load. The candidate is useful as a contention-control profile, not a pure
single-workload throughput upgrade.

## As-Left Candidate

Final switch state:
`evidence/crs804-switch-campaign-20260701-152637/task15-final-switch-state/`

The live Sparks 1-4 CRS804 ports were left as:

```text
trust-l3=keep
pfc=disabled
egress-rate-queue3=0bps
TC3 schedule=strict-priority
TC3 ecn=no
```

The physical profile stayed unchanged:

```text
mtu=9000
l2mtu=9216
speed=200G-baseCR4
fec-mode=fec91
tx-flow-control=off
rx-flow-control=off
```

Final selected counters showed no new physical error class during the candidate
runs:

- `rx-error-events`: unchanged at `0`
- `rx-fcs-error`: unchanged at `0`
- `rs-fec-uncorrected`: unchanged during run windows
- Candidate marked runs after TC3 uncapping did not increase `tx-drop-packet`

## Takeaways

1. The novel finding is the TC3 cap: `egress-rate-queue3=100.0Gbps` exactly
   explains the ~11 GB/s ceiling when host traffic is marked into DSCP 26 /
   TC3.
2. The safe classification profile is not "turn on RoCE lossless." For this
   four-Spark NCCL workload, the better candidate is DSCP/TC classification
   with TC3 uncapped, PFC disabled, ECN disabled, and TC3 strict priority.
3. The candidate does not improve idle 256MiB throughput beyond the frozen
   host-only profile in a meaningful way. Its value is under contention, where
   it improves NCCL from about `10.8` to `14.1 GB/s` against heavy queue1 TCP
   load.
4. `NCCL_IB_FIFO_TC=192` is not worth carrying in the current known profile.
5. Do not restore `egress-rate-queue3=100.0Gbps` while using
   `NCCL_IB_TC=104`; that combination is a proven regression.

## Next Tests

- Repeat this exact candidate on Sparks 5-8 when the switchless session is no
  longer using those nodes.
- Test a less aggressive TC3 scheduler, such as high-priority group with larger
  ETS weight, under mixed load to see if it preserves more TCP while keeping
  NCCL above the unmarked mixed baseline.
- If moving toward a public guide, present switch QoS as an optional
  contention-control profile, not as a required baseline for clean four-node
  NCCL performance.
