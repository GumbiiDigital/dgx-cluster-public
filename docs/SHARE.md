# Share Copy

## Short post

I rebuilt my DGX Cluster public repo around the work itself: the slow underlay, the switch forwarding root cause, the dual-rail repair, NCCL tuning, rack recabling, custom-printed PSU supports, and a bounded AC Infinity fan test. The measurements and build photographs are real. The live identities and topology are not published.

## X thread

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

### 9

The rack work was mechanical as well as computational. I designed PSU supports to lift eight warm power bricks off the rack surfaces, tested four clip dimensions instead of reprinting the full part four times, and placed the fan below the resulting open path.

### 10

A bounded fan test recorded `82.4 F` with the fan on, `82.8 F` after two minutes off, and `82.5 F` after restoration and independent readback. That proves the control path and local temperature response, not maximum thermal capacity or measured CFM.

### 11

The public record includes the print iterations, completed rack photographs, and engineering sequence. Image metadata is removed; the visible equipment labels and cabling were reviewed before publication.
