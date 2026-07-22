# Share Copy

## Short post

I rebuilt my DGX Cluster public repo around the work itself: the slow underlay, the switch forwarding root cause, the dual-rail repair, the NCCL tuning, the recable failure, and the validation that followed. The measurements are real. The live identities and topology are not published.

## Thread draft

### 1

I wanted the public DGX Cluster repo to show the actual engineering, not a generic description of a lab.

### 2

The first important result was a failure: `200G` links and MTU `9000`, but only about `9.3-9.43 Gbit/s` TCP and roughly `0.1-7 Gbit/s` RDMA. I stopped before using NCCL as a fabric conclusion.

### 3

The usual suspects did not explain it. QoS counters moved, FEC and link diagnostics were clean, and a direct cable improved the symptom without reaching the intended per-rail gate.

### 4

The root cause was the switch forwarding path. High-rate fabric traffic was being sent toward the switch CPU and dropped. Moving the learned destinations back to the ASIC path produced `111.07 Gbit/s`, then roughly `197-198 Gbit/s` across paired TCP tests.

### 5

After a rack recable, stale forwarding destinations broke four systems even though every physical link looked healthy. The rerun went from `24/112` directed pings to full small-packet, jumbo, and directed-RDMA coverage.

### 6

Only after the underlay was valid did I freeze the all-eight NCCL profile. Three longer `256 MiB` repeats averaged `22.9965 GB/s`, wrong `0`, with `NET/IB` and no socket fallback.

### 7

I also included the power/BLE commissioning failure that mattered: a valid acknowledgement moved the wrong relay, and a later physical check proved the supposed relay-state field was only program mode. Automation stayed fail-closed.

### 8

Everything public uses documentation addresses and stable aliases. The technical decisions and measurements remain; the live topology, control map, accounts, and raw captures do not.
