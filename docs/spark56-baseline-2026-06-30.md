# Spark 5 and Spark 6 Baseline - 2026-06-30

This note records the onboarding and parity check for the fifth and sixth DGX
Sparks while the first two-node QSFP/RDMA transport issue is still being
investigated separately.

## Scope

| Alias | Hostname | Tailscale name | Tailscale IP | LAN IP | Wi-Fi IP |
| --- | --- | --- | --- | --- | --- |
| `spark-e.example` | `spark-e.example` | `spark-e.example` | `192.0.2.10` | `192.0.2.10` | `192.0.2.10` |
| `spark-f.example` | `spark-f.example` | `spark-f.example` | `192.0.2.10` | `192.0.2.10` | `192.0.2.10` |

## Changes Applied

- Enabled passwordless sudo for `public-user` on both nodes.
- Installed and enabled OpenSSH service parity.
- Copied the known-good Prometheus exporter and systemd unit from `spark-c.example`.
- Copied the known-good RoCE QoS helper and systemd unit from `spark-c.example`.
- Installed NVIDIA MFT tools from the NVIDIA Ubuntu 24.04 SBSA repository.
- Applied all pending apt upgrades, including the HP printer-stack security
  packages that were pending on both fresh nodes.
- Cleaned up one-time NVIDIA removal units that had been left failed by apt
  locks during first boot package maintenance.
- Applied the available high-urgency DGX Spark USB-C PD firmware update on
  `spark-f.example`, then rebooted and rechecked firmware state.

## Final Summary

```text
spark-e.example|6.17.0-1021-nvidia|580.159.03|active,active,active,active,active,active,active,active,active|failed=0|prom=ok|reboot=no|apt=0|fw=current|lan=192.0.2.10@1000Mb/s
spark-f.example|6.17.0-1021-nvidia|580.159.03|active,active,active,active,active,active,active,active,active|failed=0|prom=ok|reboot=no|apt=0|fw=current|lan=192.0.2.10@10Mb/s
```

Service order in the compact summary:

```text
tailscaled,ssh,ssh.socket,nvidia-persistenced,dgx-dashboard,dgx-dashboard-public-admin,dgx-spark-prometheus,dgx-roce-qos.service,docker
```

## Package And Tool Baseline

Both nodes reported:

```text
Ubuntu 24.04.4 LTS
kernel=6.17.0-1021-nvidia
NVIDIA driver=580.159.03
GPU=NVIDIA GB10
mft=192.0.2.10-1
mstflint=4.26.0+1-2ubuntu3
```

MFT command availability:

```text
mst: yes
mlxlink: yes
mlxfwmanager: yes
mlxconfig: yes
mstflint: yes
```

## Verification Checks

- Tailscale showed both nodes online.
- SSH access with the NVIDIA Sync key succeeded on both nodes.
- Passwordless sudo returned `passwordless-ok` on both nodes.
- `nvidia-smi` reported `NVIDIA GB10` with driver `580.159.03` on both nodes.
- `systemctl --failed` returned zero failed units on both nodes.
- `curl http://192.0.2.10:9835/metrics` returned
  `cpu_frequency_mhz` from each Prometheus exporter.
- `/var/run/reboot-required` was absent on both nodes after the final reboot.
- `apt list --upgradable` returned zero upgradable packages on both nodes.
- `fwupdmgr get-upgrades` reported devices with no available firmware updates
  on both nodes.

## Current Caveats

- Spark 5 and Spark 6 are not yet connected to the CRS804 high-speed QSFP
  fabric. The RoCE QoS service is installed and enabled, but RDMA links and
  `192.0.2.10/24` fabric IPs still need to be configured after cabling.
- Spark 6 LAN Ethernet was linked during verification, but only at `10Mb/s`.
  Tailscale and Wi-Fi were healthy. Reseat or swap the management Ethernet cable
  or switch port before relying on this wired LAN path.
