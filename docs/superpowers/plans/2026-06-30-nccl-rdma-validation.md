# NCCL RDMA Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate the four connected DGX Sparks over the CRS804 using NCCL/RDMA instead of treating TCP `iperf3` as the final fabric grade.

**Architecture:** Keep the existing uniform four-node baseline and use `public-user` as the cluster user. Prove RoCE/RDMA verbs capability first, then build one shared `nccl-tests` checkout on each node, then run two-node and four-node NCCL tests over `enp1s0f0np0` while confirming NCCL selected `NET/IB` instead of `NET/Socket`.

**Tech Stack:** Ubuntu 24.04.4, NVIDIA driver 580.159.03, CUDA 13.0, Open MPI 4.1.6, NCCL, ConnectX-7, CRS804 200G Ethernet fabric.

---

## Source-Backed Constraints

- NVIDIA's DGX Spark NCCL playbook uses `ibdev2netdev`, cluster SSH, `UCX_NET_DEVICES`, `NCCL_SOCKET_IFNAME`, `OMPI_MCA_btl_tcp_if_include`, Open MPI, and `nccl-tests` as the validation path: <https://build.nvidia.com/spark/nccl/stacked-sparks>
- NVIDIA's multi-Spark switch playbook validates common usernames, passwordless SSH, and a 200 Gbps-capable switch fabric before cluster tests: <https://build.nvidia.com/spark/multi-sparks-through-switch>
- NVIDIA NCCL troubleshooting says to validate low-level RDMA with tools such as `ib_write_bw` before blaming NCCL: <https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/troubleshooting.html>
- NVIDIA's DGX Spark / GB10 FAQ says GPUDirect RDMA is not supported on DGX Spark, so this plan validates RoCE/RDMA and NCCL transport selection but does not chase `nvidia-peermem`, `dma-buf`, or `GDRCopy` as required Spark fixes: <https://forums.developer.nvidia.com/t/dgx-spark-gb10-faq/347344>

### Task 1: Capture RDMA Capability Baseline

**Files:**
- Modify: `/path/to/dgx-cluster/docs/four-spark-cluster-baseline-2026-06-29.md`

- [x] **Step 1: Check RDMA-related tools and devices on all four nodes**

Run from the Mac:

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
for host in spark-a.example spark-b.example spark-c.example spark-d.example; do
  echo "===== $host rdma inventory ====="
  "$TS" ssh public-root@"$host" '
    hostname
    command -v ibv_devinfo || true
    command -v rdma || true
    command -v ibstat || true
    command -v ibdev2netdev || true
    command -v ib_write_bw || true
    ip -br addr show enp1s0f0np0 || true
    ls -l /dev/infiniband 2>/dev/null || true
    find /sys/class/infiniband -maxdepth 2 -type l -o -type d 2>/dev/null | sort | sed -n "1,80p"
    ibdev2netdev 2>/dev/null || true
    ibv_devinfo 2>/dev/null | sed -n "1,120p" || true
    rdma link show 2>/dev/null || true
  '
done
```

Expected:

```text
Each node shows an RDMA-capable mlx5 device, usually under /sys/class/infiniband.
`ibdev2netdev` maps the active mlx5 port to `enp1s0f0np0`.
If `NCCL_IB_HCA=mlx5_0` is wrong for these nodes, update the env block uniformly before NCCL.
If ibv_devinfo is missing but devices exist, install rdma-core/libibverbs-utils/perftest uniformly.
If no /sys/class/infiniband entries exist, stop and investigate driver/module state before NCCL.
```

- [x] **Step 2: Install missing RDMA inspection tools uniformly if needed**

Only run if Task 1 shows missing `ibv_devinfo` or `rdma` commands while RDMA devices exist:

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
for host in spark-a.example spark-b.example spark-c.example spark-d.example; do
  echo "===== $host rdma tools ====="
  "$TS" ssh public-root@"$host" '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y rdma-core ibverbs-utils perftest
    command -v ibv_devinfo
    command -v rdma
    command -v ibdev2netdev
    command -v ib_write_bw || true
  '
done
```

Expected:

```text
ibv_devinfo and rdma are present on all four nodes.
```

Result: skipped package install because all four nodes already had
`ibv_devinfo`, `rdma`, `ibdev2netdev`, and `ib_write_bw`.

- [x] **Step 3: Run a two-node RDMA verbs smoke test**

Run only after `ibdev2netdev` shows the active HCA and port for `enp1s0f0np0`.
Replace `mlx5_0` if Task 1 discovered a different HCA.

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
"$TS" ssh public-root@spark-b.example 'timeout 45 ib_write_bw -d mlx5_0 -F --report_gbits' &
server_pid=$!
sleep 3
"$TS" ssh public-root@spark-a.example 'ib_write_bw -d mlx5_0 -F --report_gbits spark-b.example'
wait "$server_pid" || true
```

Expected:

```text
The client and server print bandwidth rows without RDMA connection errors.
If the command requires a GID index on this RoCE setup, rerun with the correct `-x <gid-index>` discovered from `show_gids` or `ibv_devinfo -v`.
If verbs fail entirely, stop before NCCL and classify the failure as RDMA device, GID, firewall, or routing.
```

Result: verbs connectivity passed from `spark-a.example` to `spark-b.example` over
`rocep1s0f0` with IPv4 RoCEv2 GID index `3`, but throughput was only
`0.096469-0.23 Gbits/sec` average depending on test shape. NCCL testing is
blocked until the switch-side counters and RoCE path are checked.

- [x] **Step 4: Append RDMA baseline results to the cluster baseline doc**

Add a short section under `Current Stop Point` in `/path/to/dgx-cluster/docs/four-spark-cluster-baseline-2026-06-29.md`:

```markdown
## RDMA Inventory

RDMA inventory was checked before NCCL testing.

| Node | RDMA device | `ibv_devinfo` | Notes |
| --- | --- | --- | --- |
| `spark-a.example` | `<device>` | `<present/missing>` | `<short note>` |
| `spark-b.example` | `<device>` | `<present/missing>` | `<short note>` |
| `spark-c.example` | `<device>` | `<present/missing>` | `<short note>` |
| `spark-d.example` | `<device>` | `<present/missing>` | `<short note>` |
```

Result: documented in
`/path/to/dgx-cluster/docs/four-spark-cluster-baseline-2026-06-29.md`.

### Execution Stop: RDMA Verbs Underperform

Stop here before Task 2. The low-level RDMA path connects and selects the
correct fabric GID, but it is slower than the previous TCP `iperf3` result.
Run CRS804 switch-side counters for `fabric-port-a` and `fabric-port-b`, then
decide whether to investigate RoCE/PFC/FEC/cable/switch counters, PCIe power
messages, or NVIDIA firmware guidance before building and running NCCL tests.

Updated stop-point evidence:

- CRS804 switch counters for Spark 1 and Spark 2 stayed clean during the slow
  RDMA tests: no FEC uncorrected errors, no transmit drops, no pause frames,
  and no `rx-too-long` increments during the measured window.
- Rebooting Spark 1 and Spark 2 with final cabling left connected did not clear
  the issue. `ib_write_bw -R -q 4 -D 30` stayed near `5.33-5.35 Gbits/sec`.
- NVIDIA's official benchmarking shape was tested with temporary
  non-persistent `192.0.2.10/24` addresses on `enP2p1s0f0np0` /
  `roceP2p1s0f0`. That second function reached only `5.21 Gbits/sec` by
  `ib_write_bw`, and a simultaneous dual-function run produced only
  `7.47 Gbits/sec` aggregate.
- TCP control tests over both functions were similarly low:
  `7.71 Gbits/sec` over `192.0.2.10/24` and `8.12 Gbits/sec` over the temporary
  `192.0.2.10/24`, both with large TCP retransmit counts while host and switch
  physical counters stayed clean.
- The temporary `192.0.2.10/24` addresses and temporary runtime UFW allow rule
  were removed after testing.
- CRS804 QoS inspection now points at missing RoCE/DCB policy, not a dead port:
  `switch1` is `Marvell-98DX7335` with `qos-hw-offloading=yes`, but all four
  Spark ports are `profile=default map=default trust-l2=ignore trust-l3=ignore`
  and `pfc=disabled`.
- The only switch QoS profile is `default pcp=0 dscp=0 traffic-class=1`; DSCP
  and VLAN/PCP maps are empty; TC3 is inactive and `ecn=no`; Spark 1/2 queue
  stats show queue0/queue1 traffic only with zero queue3-queue7 packets.
- Host-side Mellanox DCB matches the switch default state: `mlnx_qos` reports
  `DCBX mode: OS controlled`, priority trust `pcp`, and PFC disabled for
  priorities `0-7`; `dcb pfc show` reports all priorities off.
- Host `dcb app show` returns no application-priority entries; jumbo
  `ping -s 8972 -M do` succeeds both directions, so MTU is not the current
  explanation.
- LLDP is active and CRS804 neighbors are visible on the Spark fabric
  interfaces, but the DCBX-like TLVs observed from the switch are default/no-PFC
  rather than a usable lossless RoCE policy.
- A bounded Spark 1 / Spark 2 write test applied the documented MikroTik RoCE
  QoS objects and matching host DCB/PFC/TOS state, then rolled them back when it
  failed. RouterOS accepted the core profiles/maps/PFC profile and queue
  changes, but rejected `egress-rate-queue3=200.0Gbps` with
  `failure: max bit rate is 100G`; `100.0Gbps` was accepted.
- The test did not improve throughput: `ib_write_bw -R --tos=106` stayed near
  `5.5 Gbits/sec`.
- More importantly, CRS804 queue counters still showed queue0 increments and
  queue3 stayed `0`, even for `iperf3 --tos 0x68` and even when both test ports
  were briefly forced to `profile=roce trust-l3=ignore`.
- The test changes were rolled back. The switch returned to default profiles,
  empty maps, `pfc=disabled`, and baseline tx-manager queues. Spark 1 and
  Spark 2 returned to PFC off, `cma_roce_tos=0`, no DSCP app entries, and the
  original receive-buffer mapping.
- Follow-up source check changed the stop condition: MikroTik's RouterOS
  `7.23` stable release notes explicitly add `qos-hw - added ECN and PFC support
  on CRS8xx switches`. Because this CRS804 is
  still on `7.21.4 (long-term)`, the failed queue3 classification test is now
  best explained as a RouterOS CRS8xx support-version blocker, not an NCCL issue.

Do not move to NCCL throughput conclusions. Do not retry the generic RoCE QoS
recipe on RouterOS `7.21.4`. The next conservative action is a CRS804 backup,
stable-channel upgrade to `7.23+`, RouterBOARD firmware upgrade/reboot, and then
the same Spark 1 / Spark 2 two-port classification test. Require CRS804 queue3,
host priority-3, PFC, and ECN counters to move before rerunning NCCL.

### 2026-06-30 Goal 1/2/3 Update

CRS804 was upgraded from RouterOS `7.21.4 (long-term)` to `7.23.1 (stable)`,
and RouterBOOT firmware was upgraded to `7.23.1`. The post-upgrade RoCE QoS
test succeeded at the classification layer: profiles `roce` and `cnp` are
hardware offloaded, TC3 is hardware offloaded with `ecn-actual=yes`, PFC profile
`pfc-tc3` is hardware offloaded, and all four Spark ports now place traffic into
queue3 with zero per-queue drops.

All four Sparks were made uniform with persistent
`dgx-roce-qos.service`, active SSH, DSCP AF31 -> priority 3, DSCP CS6 ->
priority 6, and `cma_roce_tos=106` on `rocep1s0f0`.

The remaining blocker is no longer CRS804 queue classification. After reboot,
persistent host QoS, and final cabling, raw RDMA still caps at
`6.70 Gbits/sec` for:

```text
ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12 spark-b.example
```

Do not run NCCL as a throughput conclusion yet. The current validated stop point
is documented in
`/path/to/dgx-cluster/docs/four-spark-roce-7-23-1-validation-2026-06-30.md`.

Additional evidence after this stop point: Spark 3 -> Spark 4 was retested over
LAN SSH with the same RDMA-CM command shape and returned only
`6.64-6.67 Gbits/sec`; Spark 1 -> Spark 2 retested through the verifier at
`6.62 Gbits/sec`. A cold-drain runbook, NVIDIA escalation draft, and repeatable
post-boot verifier were added in
`/path/to/dgx-cluster/docs/roce-cold-drain-runbook-2026-06-30.md`
and
`/path/to/dgx-cluster/docs/nvidia-support-escalation-draft-2026-06-30.md`
and `/path/to/dgx-cluster/scripts/verify-roce-underlay.sh`.
The support bundle wrapper
`/path/to/dgx-cluster/scripts/capture-roce-evidence.sh`
was also added and shakedown-tested with a diagnostic threshold, producing
repeatable failing RDMA evidence: Spark 1 -> Spark 2 at `6.67 Gbits/sec` and
Spark 3 -> Spark 4 at `6.63 Gbits/sec`.

Post-cold-drain and Perplexity-assisted follow-up testing changed the next
branch. The failure is not just an `ib_write_bw` artifact: TCP over the same
fabric also caps around `8.8-9.1 Gbits/sec` with about `50k-60k` retransmits
per 20-second test, including cross-cage Spark 1 -> Spark 3. Explicit RoCEv2
GID index `3` is correct, jumbo ping passes, host PCIe link width/speed is
healthy, and the CRS804 shows no drops, pause frames, FCS errors, or
`rx-error-events`.

A bounded CRS804 Spark 1 / Spark 2 bypass test temporarily moved only those two
ports from `trust-l3=trust pfc=pfc-tc3` to `trust-l3=ignore pfc=disabled`.
TCP remained capped at `9.13 Gbits/sec` with `55,020` retransmits, and RDMA
failed immediately with `Failed status 12: wr_id 7 syndrom 0x81`. The switch
ports were restored to `trust-l3=trust pfc=pfc-tc3` and verified.

Do not move to NCCL yet. The direct Spark 1 <-> Spark 2 cable test has now
completed with the NVIDIA-supplied Spark-to-Spark cable:

1. both hosts detected the direct cable and re-enumerated ConnectX-7;
2. `ethtool` reported `200000Mb/s`, `Lanes: 2`, and link detected on the
   primary direct interfaces;
3. jumbo `ping -s 8972 -M do 192.0.2.10` passed from Spark 1 to Spark 2;
4. direct TCP improved to `12.8 Gbits/sec` with `0` retransmits;
5. direct RDMA improved to only `12.71 Gbits/sec` with
   `ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12`.

This changes the branch: the CRS804 path worsens the symptom, but it is not the
primary limiter. With the switch removed, the same host pair still caps near
the NVIDIA-forum `~13 Gbits/sec` failure family.

Perplexity was used as a research sidekick after the direct cable result. It
pointed to the same host/NIC diagnostic lane: PCIe slot power capability,
driver/kernel state, NIC firmware, and mlx5 health logs. Spark 1 and Spark 2
then both reported:

```text
SlotPowerLimit 0W
LnkSta: Speed 32GT/s, Width x4
PCIe slot power capability was not advertised
Detected insufficient power on the PCIe slot (27W)
```

The current next valid actions are:

1. prepare/update the NVIDIA support bundle with direct-cable evidence,
   `lspci -vv`, `dmesg`, `nvidia-smi topo -m`, firmware, driver, kernel, and
   MFT output;
2. check whether NVIDIA has a DGX Spark OS / kernel / mlx5 / firmware update
   that specifically addresses the `~13 Gbits/sec` direct-cable cap;
3. only after a direct Spark-to-Spark TCP/RDMA path leaves the `~13 Gbits/sec`
   failure mode, return to CRS804 path tuning and then NCCL.

MFT helper scripts were added for this branch:

- `/path/to/dgx-cluster/scripts/install-mft-tools.sh`
- `/path/to/dgx-cluster/scripts/capture-mft-evidence.sh`

The installer is dry-run by default and verifies passwordless sudo before making
changes. After Spark 3 and Spark 4 passwordless sudo was fixed, the installer
was run with `APPLY_MFT_INSTALL=1`. MFT `192.0.2.10-1` is now installed on all
four Sparks. `mlxstat` is not present in this ARM64 package and was made
optional in the helper scripts.

```bash
APPLY_MFT_INSTALL=1 scripts/install-mft-tools.sh
scripts/capture-mft-evidence.sh
```

Current MFT evidence bundle:

```text
evidence/mft-20260630-100025/
```

`mst_pci` / `mst_pciconf` kernel modules are absent on
`6.17.0-1021-nvidia`, but `mlxlink -d <PCI-BDF>` works. All active ConnectX-7
functions on all four Sparks report `Active`, `200G`, `4x`,
`Standard_RS-FEC - (544,514)`, status opcode `0`, and
`Recommendation: No issue was observed`. This clears the MFT physical-link
gate and advances the plan to direct-cable bypass testing. A post-MFT verifier
rerun still failed at `6.71 Gbits/sec` for both Spark 1 -> Spark 2 and Spark 3
-> Spark 4, so NCCL remains gated.

### Task 2: Confirm NCCL and CUDA Build Paths

**Files:**
- Modify: `/path/to/dgx-cluster/docs/four-spark-cluster-baseline-2026-06-29.md`

- [ ] **Step 1: Check CUDA and NCCL locations**

Run:

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
for host in spark-a.example spark-b.example spark-c.example spark-d.example; do
  echo "===== $host cuda nccl paths ====="
  "$TS" ssh public-root@"$host" '
    hostname
    readlink -f /usr/local/cuda 2>/dev/null || true
    ls -d /usr/local/cuda* 2>/dev/null || true
    find /usr -name "libnccl.so*" 2>/dev/null | sort | sed -n "1,40p"
    find /usr -name "nccl.h" 2>/dev/null | sort | sed -n "1,40p"
    dpkg -l | egrep "nccl|cuda-toolkit|cuda-compiler|openmpi|libopenmpi-dev" || true
  '
done
```

Expected:

```text
CUDA exists under /usr/local/cuda or another consistent CUDA path.
NCCL runtime and headers are present.
If nccl.h is missing, stop and install the matching NCCL dev package uniformly.
```

Result update: read-only inventory on all four Sparks showed CUDA `13.0`
available at `/usr/local/cuda-13.0`, `/usr/local/cuda/bin/nvcc` reporting
`V13.0.88`, and OpenMPI `4.1.6` present. `libnccl.so` and `nccl.h` were missing
on all four. `apt-cache policy` showed `libnccl2` and `libnccl-dev` candidates
available from the NVIDIA CUDA repository. The apt default candidate was
`2.30.7-1+cuda13.3`, while the CUDA `13.0` matching candidate was
`2.28.9-1+cuda13.0`. NCCL is therefore not ready to build or run yet.

Prepared scripts:

- `/path/to/dgx-cluster/scripts/check-nccl-readiness.sh`
- `/path/to/dgx-cluster/scripts/run-nccl-after-roce.sh`
- `/path/to/dgx-cluster/scripts/install-nccl-prereqs.sh`
- `/path/to/dgx-cluster/scripts/build-nccl-tests.sh`

The runner gates NCCL behind `scripts/verify-roce-underlay.sh` and refuses to run
NCCL by default unless `RUN_NCCL=1` is explicitly set after RoCE and readiness
checks pass.

Verification update: `scripts/check-nccl-readiness.sh` was run and failed as
expected on all four Sparks with `MISSING: libnccl.so`, while confirming CUDA
`13.0` and OpenMPI `4.1.6`. `SKIP_ROCE_GATE=1 scripts/run-nccl-after-roce.sh`
also stopped at the readiness gate and did not run NCCL.

Follow-up update: readiness now reports all missing NCCL pieces per host:
`libnccl.so`, `nccl.h`, `all_reduce_perf`, and `all_gather_perf`. The dry-run
NCCL package helper confirmed `libnccl2=2.28.9-1+cuda13.0` and
`libnccl-dev=2.28.9-1+cuda13.0` are available on all four Sparks and did not
install anything.

- [ ] **Step 2: Install missing NCCL development package only if headers are absent**

Run only if Step 1 shows `libnccl.so` exists but `nccl.h` is missing:

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
for host in spark-a.example spark-b.example spark-c.example spark-d.example; do
  echo "===== $host nccl dev package ====="
  "$TS" ssh public-root@"$host" '
    export DEBIAN_FRONTEND=noninteractive
    apt-cache policy libnccl-dev || true
    apt-get install -y libnccl-dev
    find /usr -name "nccl.h" 2>/dev/null | sort | sed -n "1,20p"
  '
done
```

Expected:

```text
nccl.h exists on all four nodes.
```

### Task 3: Build `nccl-tests` Uniformly

**Files:**
- Modify: `/path/to/dgx-cluster/docs/four-spark-cluster-baseline-2026-06-29.md`

- [ ] **Step 1: Clone or update `nccl-tests` on all four nodes**

Run:

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
for host in spark-a.example spark-b.example spark-c.example spark-d.example; do
  echo "===== $host nccl-tests checkout ====="
  "$TS" ssh public-root@"$host" '
    sudo -u public-user bash -lc "
      set -euo pipefail
      cd ~
      if [ -d nccl-tests/.git ]; then
        cd nccl-tests
        git fetch --tags --prune
        git status --short
      else
        git clone https://github.com/NVIDIA/nccl-tests.git
      fi
    "
  '
done
```

Expected:

```text
Each node has /opt/public-cluster/nccl-tests.
Existing dirty checkouts should be inspected before building.
```

- [ ] **Step 2: Build `nccl-tests` with MPI**

Run:

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
for host in spark-a.example spark-b.example spark-c.example spark-d.example; do
  echo "===== $host nccl-tests build ====="
  "$TS" ssh public-root@"$host" '
    sudo -u public-user bash -lc "
      set -euo pipefail
      source /opt/public-user/.bashrc
      cd /opt/public-user/nccl-tests
      make MPI=1 CUDA_HOME=/usr/local/cuda -j\$(nproc)
      test -x build/all_gather_perf
      test -x build/all_reduce_perf
    "
  '
done
```

Expected:

```text
build/all_gather_perf and build/all_reduce_perf exist on all four nodes.
If CUDA_HOME is not /usr/local/cuda, rerun with the CUDA path discovered in Task 2.
```

### Task 4: Run Minimal Two-Node NCCL Sanity Test

**Files:**
- Modify: `/path/to/dgx-cluster/docs/four-spark-cluster-baseline-2026-06-29.md`

- [ ] **Step 1: Run a small all-gather test from spark-a.example to spark-b.example**

Run:

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
"$TS" ssh public-root@spark-a.example '
  sudo -u public-user bash -lc "
    set -euo pipefail
    source /opt/public-user/.bashrc
    cd /opt/public-user/nccl-tests
    mpirun -np 2 \
      -H spark-a.example:1,spark-b.example:1 \
      --mca plm_rsh_agent \"ssh -o StrictHostKeyChecking=no\" \
      -x UCX_NET_DEVICES \
      -x NCCL_SOCKET_IFNAME \
      -x NCCL_IB_DISABLE \
      -x NCCL_IB_HCA \
      -x NCCL_NET_GDR_LEVEL \
      -x NCCL_DEBUG=INFO \
      -x NCCL_DEBUG_SUBSYS=INIT,NET \
      -x LD_LIBRARY_PATH \
      ./build/all_gather_perf -b 64M -e 1G -f 2 -g 1 2>&1 | tee /opt/public-user/nccl-two-node-spark-a.example-spark-b.example.log
  "
'
```

Expected:

```text
The command completes and prints NCCL performance rows.
No SSH timeout, NCCL internal error, missing library error, or device selection error appears.
The log contains `NET/IB` and does not use `NET/Socket` as the selected data path.
```

- [ ] **Step 2: If two-node NCCL fails, stop and classify the failure**

Classify into one of these buckets:

```text
SSH launch failure: cluster SSH or host aliases regressed.
Library/build failure: CUDA/NCCL/OpenMPI path issue.
RDMA device failure: mlx5/NCCL_IB_HCA or RoCE selection issue.
Runtime transport fallback: NCCL used sockets instead of RDMA.
```

Do not tune TCP if the failure is NCCL/RDMA-specific.

### Task 5: Run Four-Node NCCL Test

**Files:**
- Modify: `/path/to/dgx-cluster/docs/four-spark-cluster-baseline-2026-06-29.md`

- [ ] **Step 1: Run four-node all-reduce**

Run only after Task 4 passes:

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
"$TS" ssh public-root@spark-a.example '
  sudo -u public-user bash -lc "
    set -euo pipefail
    source /opt/public-user/.bashrc
    cd /opt/public-user/nccl-tests
    mpirun -np 4 \
      -H spark-a.example:1,spark-b.example:1,spark-c.example:1,spark-d.example:1 \
      --mca plm_rsh_agent \"ssh -o StrictHostKeyChecking=no\" \
      -x UCX_NET_DEVICES \
      -x NCCL_SOCKET_IFNAME \
      -x NCCL_IB_DISABLE \
      -x NCCL_IB_HCA \
      -x NCCL_NET_GDR_LEVEL \
      -x NCCL_DEBUG=INFO \
      -x NCCL_DEBUG_SUBSYS=INIT,NET \
      -x LD_LIBRARY_PATH \
      ./build/all_reduce_perf -b 64M -e 1G -f 2 -g 1 2>&1 | tee /opt/public-user/nccl-four-node-all-reduce.log
  "
'
```

Expected:

```text
The command completes across spark-a.example-spark-d.example and prints bus bandwidth.
If it passes, increase -e to 4G in a separate run.
```

- [ ] **Step 2: Run four-node all-gather**

Run:

```bash
TS=/opt/public-tools/tailscale/Contents/MacOS/Tailscale
"$TS" ssh public-root@spark-a.example '
  sudo -u public-user bash -lc "
    set -euo pipefail
    source /opt/public-user/.bashrc
    cd /opt/public-user/nccl-tests
    mpirun -np 4 \
      -H spark-a.example:1,spark-b.example:1,spark-c.example:1,spark-d.example:1 \
      --mca plm_rsh_agent \"ssh -o StrictHostKeyChecking=no\" \
      -x UCX_NET_DEVICES \
      -x NCCL_SOCKET_IFNAME \
      -x NCCL_IB_DISABLE \
      -x NCCL_IB_HCA \
      -x NCCL_NET_GDR_LEVEL \
      -x NCCL_DEBUG=INFO \
      -x NCCL_DEBUG_SUBSYS=INIT,NET \
      -x LD_LIBRARY_PATH \
      ./build/all_gather_perf -b 64M -e 1G -f 2 -g 1 2>&1 | tee /opt/public-user/nccl-four-node-all-gather.log
  "
'
```

Expected:

```text
The command completes across spark-a.example-spark-d.example and prints bandwidth rows.
```

### Task 6: Document Results and Decide Whether to Tune

**Files:**
- Modify: `/path/to/dgx-cluster/docs/four-spark-cluster-baseline-2026-06-29.md`

- [ ] **Step 1: Add NCCL result table**

Append:

```markdown
## NCCL/RDMA Results

| Test | Nodes | Size range | Result | Notes |
| --- | ---: | --- | --- | --- |
| `all_gather_perf` | 2 | `64M-1G` | `<result>` | `<transport/log note>` |
| `all_reduce_perf` | 4 | `64M-1G` | `<result>` | `<transport/log note>` |
| `all_gather_perf` | 4 | `64M-1G` | `<result>` | `<transport/log note>` |
```

- [ ] **Step 2: Commit the baseline doc update**

Run:

```bash
git add README.md docs/four-spark-cluster-baseline-2026-06-29.md docs/superpowers/plans/2026-06-30-nccl-rdma-validation.md
git commit -m "Document four Spark NCCL RDMA validation plan"
```

Expected:

```text
Commit succeeds with the baseline, stop point, and NCCL/RDMA plan recorded.
```

---

## Self-Review

- Spec coverage: The plan avoids TCP as the main validation path and moves to RDMA/NCCL, while preserving the uniform `public-user` cluster baseline.
- Placeholder scan: Commands are explicit. Result fields in documentation steps are intentionally filled from live command output during execution.
- Type consistency: Host aliases, user, environment variables, and paths match the current four-Spark baseline.
