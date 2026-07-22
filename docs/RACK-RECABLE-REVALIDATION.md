# Rack Recable and Full Fabric Revalidation

## Why this record exists

A known-good fabric was physically torn down and rebuilt. The old benchmark results could not prove the new physical state. The acceptance program was rerun from management identity through NCCL transport.

Public aliases replace live hostnames, addresses, and port numbers. The measured results are retained.

## First recable repair

The first rack recable left four static switch forwarding destinations pointed at their former physical egresses. All eight physical links were up at `200G-baseCR4` with `fec91`, and all sixteen logical fabric destinations were learned. The stale static rules still stranded four systems.

Pre-fix evidence:

| Gate | Result |
| --- | ---: |
| Small directed ping matrix | `24/112` pass |
| Reachable clique | four systems |
| Affected systems | four systems |

The switch was backed up and exported. Only the stale destination relationships were changed; already-correct rules stayed untouched.

Post-fix evidence:

| Gate | Result |
| --- | ---: |
| Small ping, both rails, every ordered pair | `112/112` |
| Jumbo ping with `8972` byte payload and do-not-fragment | `112/112` |
| Directed RDMA, both rails, every ordered pair | `112/112` |
| RDMA bandwidth range | `109.06-109.30 Gbit/s` |
| RDMA mean | `109.20 Gbit/s` |
| MPI fanout | `8/8` |
| NCCL `1 MiB` canary | pass |
| NCCL fixed `256 MiB` | pass |

The fixed-size collective completed with:

- out-of-bounds values `0 OK`;
- out-of-place bus bandwidth `18.53 GB/s`;
- in-place bus bandwidth `21.71 GB/s`; and
- average bus bandwidth `20.1189 GB/s`.

That was a repair baseline, not a peak claim.

## Later topology rerun

After another rack teardown and reassembly, the full observed topology was checked again.

### Management and interface state

- management SSH passed on all eight systems;
- all sixteen f1 interfaces were up;
- each reported `200000 Mb/s`; and
- MTU was `9000`.

### Packet and RDMA gates

| Gate | Result |
| --- | ---: |
| Jumbo directed ping | `112/112` |
| Concurrent directed RDMA | `105/112` above the `90 Gbit/s` gate |
| Bounded serial retry of seven outliers | all passed at `111.85 Gbit/s` |
| Secondary rail | `56/56`, mean `111.94 Gbit/s` |

The seven concurrent outliers were classified as test-load contention only after each exact path passed the bounded serial rerun. The first result was not overwritten or described as a full concurrent pass.

### NCCL gate

| Check | Result |
| --- | ---: |
| Fixed `256 MiB` run | exit `0` |
| Wrong | `0` |
| Average bus bandwidth | `23.8196 GB/s` |
| Debug `NET/IB` lines | `824` |
| Debug `NET/Socket` lines | `0` |

The process sweep found no lingering benchmark or RDMA test jobs.

## Acceptance logic

The topology was accepted because:

1. identity and management access passed across the complete cohort;
2. both logical rails were present at the expected speed and MTU;
3. every jumbo directed path passed;
4. every RDMA outlier from the concurrent sweep passed a bounded same-path retry;
5. NCCL completed with correct results over `NET/IB` and no socket fallback; and
6. the test environment was left clean.

The acceptance does not mean every simultaneous all-to-all RDMA path exceeded the gate in one concurrent pass. That distinction remains explicit.
