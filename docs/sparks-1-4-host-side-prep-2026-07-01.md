# Sparks 1-4 Host-Side NCCL Prep

Date: 2026-07-01

Raw local evidence: `evidence/sparks14-host-side-20260701-120049/`

Status: PARTIAL host-side prep complete. No CRS804 commands were run.

## Scope Boundary

The public-user requested all non-switch work while preparing to move cables in
the office. This pass deliberately avoided RouterOS SSH, CRS804 counter reads,
and switch writes. The only remote changes were on reachable Spark hosts.

## Initial Host Readiness

The first host-side gate checked management SSH, candidate f1 rail IPs,
expected f1 netdevs/RDMA devices, `nccl-tests`, and stale MPI/NCCL processes.

Evidence: `task01-host-readiness/`

| Node | SSH | `198.51.100/203.0.113` f1 IPs | f1 netdevs | f1 RDMA devices | `nccl-tests` |
| --- | --- | --- | --- | --- | --- |
| Spark 1 / `spark-a.example` | fail | missing | missing | missing | unknown |
| Spark 2 / `spark-b.example` | fail | missing | missing | missing | unknown |
| Spark 3 / `spark-c.example` | ok via `spark-c.example` | missing | missing | missing | no |
| Spark 4 / `spark-d.example` | ok via `spark-d.example` | missing | missing | missing | no |

Interpretation: four-node NCCL on Sparks 1-4 was correctly blocked before any
benchmark launch. Spark 1 and Spark 2 were not reachable over their documented
LAN or Tailscale IPs. Spark 3 and Spark 4 were reachable, but the f1 fabric
interfaces and RDMA devices were not visible.

## Software Prep Completed On Spark 3 And Spark 4

Evidence:

- `task03-spark34-nccl-package-*.log`
- `task05-spark34-nccl-install.log`
- `task06-spark34-nccl-tests-build.log`
- `task09-spark34-inspector-build/`
- `task10-spark34-tuner-channels-build/`

Completed host-side changes:

- Installed `libnccl2=2.28.9-1+cuda13.0` and
  `libnccl-dev=2.28.9-1+cuda13.0` on `spark-c.example` and `spark-d.example`.
- Built `/opt/public-user/nccl-tests` on `spark-c.example` and `spark-d.example`.
- Built NCCL Inspector from NCCL tag `v2.28.9-1` on `spark-c.example` and synced it
  to `spark-d.example`.
- Built the custom channels-only tuner on `spark-c.example` and synced it to
  `spark-d.example` at
  `/opt/public-cluster/src/sparks14-tuner-channels/libnccl-tuner-sparks58-channels.so`.

Notes:

- Spark 3 to Spark 4 management SSH worked, but `/opt/public-user/.ssh/dgx_cluster_mpi_ed25519`
  was absent on Spark 3. OpenSSH still completed the management SSH path.
- No software changes were possible on Spark 1 or Spark 2 because they were
  offline/unreachable during this pass.

## Local NCCL Smoke

Evidence:

- `task11-local-nccl-smoke-*.log`
- `task12-local-nccl-debug-*.log`
- `task13-local-nccl-management-iface-*.log`

The first single-host smoke failed because NCCL found no socket interface under
the default environment. Rerunning with a real management NIC fixed bootstrap:

```bash
NCCL_SOCKET_IFNAME=enP7s7
```

Both reachable hosts then completed local one-rank `all_gather_perf` with NCCL
`2.28.9+cuda13.0`:

| Host | Result |
| --- | --- |
| `spark-c.example` | PASS, one-rank local `all_gather_perf` completed |
| `spark-d.example` | PASS, one-rank local `all_gather_perf` completed |

The one-rank bus bandwidth is `0` by definition; this was a binary/library
bootstrap check, not a fabric benchmark.

## Post-Prep Readiness Gate

Evidence: `task07-host-readiness-after-spark34-prep/`

| Node | SSH | f1 IPs | f1 netdevs | f1 RDMA devices | `nccl-tests` |
| --- | --- | --- | --- | --- | --- |
| Spark 1 / `spark-a.example` | fail | missing | missing | missing | unknown |
| Spark 2 / `spark-b.example` | fail | missing | missing | missing | unknown |
| Spark 3 / `spark-c.example` | ok | missing | missing | missing | yes |
| Spark 4 / `spark-d.example` | ok | missing | missing | missing | yes |

Interpretation: Spark 3 and Spark 4 are now software-prepped for NCCL, but the
four-node run remains physically blocked until Spark 1 and Spark 2 are reachable
and the f1 interfaces/RDMA devices appear on all four nodes.

## New Tracked Host-Side Artifacts

- `scripts/sparks14-nccl-profile.env`: Sparks 1-4 fabric profile for
  `192.0.2.10-14` and `192.0.2.10-14`.
- `scripts/check-sparks14-host-fabric-readiness.sh`: no-switch readiness gate.
- `scripts/run-sparks14-nccl-profile.sh`: Sparks 1-4 wrapper for the validated
  NCCL profile harness.
- `scripts/run-sparks14-nccl-inspector.sh`: Sparks 1-4 Inspector wrapper.
- `scripts/run-sparks14-size-policy.sh`: Sparks 1-4 size-policy wrapper.
- `scripts/build-spark1-nccl-inspector.sh`: Sparks 1-4 Inspector build wrapper.
- `scripts/build-spark1-nccl-tuner-channels.sh`: Sparks 1-4 channels tuner build
  wrapper.

The existing 5-8 scripts were also parameterized for labels, policy prefixes,
and peer host lists so the same harness can run against either four-node set.

## After Cable Move

Run this host-side gate first:

```bash
OUT_DIR=evidence/sparks14-after-cable-readiness-$(date +%Y%m%d-%H%M%S) \
  scripts/check-sparks14-host-fabric-readiness.sh
```

Only if it passes, run:

```bash
OUT_DIR=evidence/sparks14-after-cable-profile-$(date +%Y%m%d-%H%M%S) \
  scripts/run-sparks14-nccl-profile.sh
```

Then:

```bash
OUT_DIR=evidence/sparks14-after-cable-inspector-$(date +%Y%m%d-%H%M%S) \
  scripts/run-sparks14-nccl-inspector.sh
```

And:

```bash
OUT_DIR=evidence/sparks14-after-cable-size-policy-$(date +%Y%m%d-%H%M%S) \
  REMOTE_TUNER_PLUGIN=/opt/public-cluster/src/sparks14-tuner-channels/libnccl-tuner-sparks58-channels.so \
  scripts/run-sparks14-size-policy.sh
```

If Spark 1 and Spark 2 come back without NCCL packages or `nccl-tests`, run the
subset host prep for those two before benchmarking:

```bash
HOSTS_OVERRIDE='192.0.2.10 192.0.2.10' \
SSH_KEY=$HOME/.ssh/id_ed25519 \
NCCL_VERSION='2.28.9-1+cuda13.0' \
APPLY_NCCL_INSTALL=1 \
scripts/install-nccl-prereqs.sh

HOSTS_OVERRIDE='192.0.2.10 192.0.2.10' \
SSH_KEY=$HOME/.ssh/id_ed25519 \
BUILD_NCCL_TESTS=1 \
scripts/build-nccl-tests.sh
```

Do not start switch-change tests until the host-side Sparks 1-4 readiness gate
passes and a fresh CRS804 rollback snapshot is captured.
