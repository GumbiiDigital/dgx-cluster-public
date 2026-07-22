# Sparks 1-4 Shutdown Handoff

Date: 2026-07-01

Status: Sparks 1-4 were cleanly shut down for cable work.

Raw local evidence is ignored under:

```text
evidence/shutdown-sparks14-20260701-173210/
```

## Scope

This shutdown belongs to the CRS804 switch-based Sparks 1-4 tuning lane. The
separate switchless Sparks 5-8 session is expected to manage its own nodes.

## Pre-Shutdown Gate

Before shutdown, the host-readiness gate passed for all four nodes:

| Node | Hostname | SSH target | Fabric state |
| --- | --- | --- | --- |
| Spark 1 | `spark-a.example` | `192.0.2.10` | both f1 rails present |
| Spark 2 | `spark-b.example` | `192.0.2.10` | both f1 rails present |
| Spark 3 | `spark-c.example` | `spark-c.example` | both f1 rails present |
| Spark 4 | `spark-d.example` | `spark-d.example` | both f1 rails present |

All four had the expected RDMA devices, `nccl-tests`, and no stale MPI/NCCL
processes.

## Shutdown Result

Clean shutdown commands were sent with:

```text
sudo -n systemctl poweroff
```

Each SSH command returned `ssh_rc=0` after printing the expected hostname.

Post-shutdown reachability:

| Target | Ping | SSH |
| --- | --- | --- |
| `192.0.2.10` | down | down |
| `192.0.2.10` | down | down |
| `spark-c.example` | down | down |
| `spark-d.example` | down | down |

## Handoff Note

Use this as the clean boundary before the next physical cabling phase and any
new focused session. Do not infer switch or fabric health after the cable move
from this shutdown note; rerun link, IP, RDMA, and NCCL gates after power-up.
