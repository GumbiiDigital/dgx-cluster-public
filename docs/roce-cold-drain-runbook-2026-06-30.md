# RoCE Cold-Drain Runbook - 2026-06-30

Use this when the CRS804 shows correct RoCE queue classification but DGX Spark
raw RDMA remains capped around single-digit Gbps.

## Why This Is The Next Step

The CRS804 side is no longer the primary suspect:

- RouterOS and RouterBOOT are both `7.23.1`.
- All four fabric ports are up at `200G-baseCR4`, MTU `9000`.
- QoS profiles, DSCP maps, TC3 ECN, and PFC are hardware offloaded.
- RoCE traffic now lands in `tx-queue3`.
- Switch tx drops are zero during the measured tests.

The remaining symptom matches NVIDIA forum reports for DGX Spark / ConnectX-7:
links negotiate correctly, but `ib_write_bw`/TCP throughput remains around
10 Gbps or lower until the Spark is fully powered off and unplugged after the
final QSFP topology is connected.

Source thread. This report is especially close to our symptom: direct DGX Spark
QSFP traffic stayed around `13-16 Gbps`, then recovered to roughly
`109 Gbits/sec` after the user powered the Spark off, unplugged it for about a
minute, and booted again:
<https://forums.developer.nvidia.com/t/dgx-spark-direct-qsfp-connection-only-getting-13-16-gbps-instead-of-expected-200g-performance/370035>

## Physical Procedure

1. Leave all CRS804 QSFP cables in the intended final positions.
2. From the Mac, shut down the four connected Sparks cleanly:

   ```bash
   KEY="$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key"
   for host in spark-a.example spark-b.example spark-c.example spark-d.example; do
     ssh -i "$KEY" -o IdentitiesOnly=yes public-user@"$host" \
       'sudo shutdown -h now'
   done
   ```

   If a node is not reachable by LAN SSH, shut it down from the local UI or
   power button after its disk activity settles.

3. Wait until all four Sparks are fully off.
4. Disconnect the power cable from each Spark.
5. Wait at least 60 seconds.
6. While each Spark is unplugged, press its power button once to discharge
   residual platform state.
7. Reconnect power and boot the four Sparks.
8. Wait for them to come back on the management LAN and/or Tailscale.

## Post-Boot Verification

Run the verifier from the repo public-root:

```bash
cd "/path/to/dgx-cluster"
scripts/verify-roce-underlay.sh
```

For a support-grade evidence bundle, run the wrapper instead:

```bash
cd "/path/to/dgx-cluster"
scripts/capture-roce-evidence.sh
```

To include switch counters in the same bundle, pass the CRS804 SSH target. Do
not put the password in the command; SSH will prompt normally:

```bash
CRS804_SSH=public-admin@192.0.2.10 scripts/capture-roce-evidence.sh
```

Bundles are written under `evidence/`, which is intentionally ignored by git.

If mDNS is not resolving after the reboot, override the management targets with
known-good LAN IPs:

```bash
SPARK1_MGMT=192.0.2.10 \
SPARK2_MGMT=<spark-b.example-lan-ip> \
SPARK3_MGMT=192.0.2.10 \
SPARK4_MGMT=192.0.2.10 \
scripts/verify-roce-underlay.sh
```

The pass condition is not "the command runs." The pass condition is:

- `dgx-roce-qos.service` active on all four;
- `ssh` active on all four;
- `enp1s0f0np0` has the expected `192.0.2.x/24` fabric IP;
- `dcb app` still shows AF31 -> priority 3 and CS6 -> priority 6;
- `cma_roce_tos` still reports `106`;
- at least one two-node `ib_write_bw` pair reaches the expected class, roughly
  `90+ Gbits/sec` per active RoCE function;
- CRS804 queue3 continues to move with zero drops during the test window.

Do not run NCCL as a throughput conclusion until this gate passes.

`cma_roce_tos` is a privileged check. The verifier reads it automatically when
the SSH user is public-root or has passwordless sudo; otherwise it prints a warning and
the final pass still needs a public-root check for that value.

The verifier exits nonzero if either tested pair is below `90 Gbits/sec`.
Override that gate only for diagnostics:

```bash
IB_PASS_GBPS=1 scripts/verify-roce-underlay.sh
```

While the verifier runs, these RouterOS commands are useful for the switch-side
counter check:

```routeros
/interface ethernet print stats where name="fabric-port-a" or name="fabric-port-b" or name="fabric-port-c" or name="fabric-port-d"
/interface ethernet switch qos tx-manager queue print detail
/interface ethernet switch qos priority-flow-control print detail
```

## If The Cold Drain Fails

If `ib_write_bw` still returns around `6-8 Gbits/sec`, use the prepared NVIDIA
support/forum draft:

```text
docs/nvidia-support-escalation-draft-2026-06-30.md
```

That draft includes this evidence:

- CRS804 model `CRS804-4DDQ`, RouterOS `7.23.1`, RouterBOOT `7.23.1`;
- CRS804 QoS offload enabled and queue3 classification proven;
- Spark host driver `580.159.03`, ConnectX firmware `28.45.4028`;
- `ibdev2netdev` mapping `rocep1s0f0 -> enp1s0f0np0 (Up)`;
- `dcb pfc` priority 3 on, `dcb app` AF31:3 CS6:6, `cma_roce_tos=106`;
- `ib_write_bw -R -d rocep1s0f0 -F --report_gbits -q 8 -s 8388608 -D 12`
  still capped around `6.6-6.7 Gbits/sec`;
- dmesg line: `Detected insufficient power on the PCIe slot (27W)`.
