# Spark Fleet Parity

Date: 2026-06-29

Goal: make the first four DGX Sparks match on baseline management, NVIDIA driver/kernel, firmware, dashboard, persistence, and Prometheus exporter state.

## Changes Applied

- `spark-a.example` was upgraded from kernel `6.17.0-1014-nvidia` and NVIDIA driver `580.142` to kernel `6.17.0-1021-nvidia` and NVIDIA driver `580.159.03`.
- `spark-a.example` completed high-urgency DGX Spark firmware updates through `fwupdmgr`, including EC, SoC, and USB-C PD controller updates.
- `spark-b.example` had a broken post-reboot NVIDIA driver stack because the matching `6.17.0-1021` NVIDIA module package was missing. Installed the matching open NVIDIA module package and upgraded the driver to `580.159.03`.
- `spark-c.example` was already current for the baseline kernel, NVIDIA driver, services, apt state, and firmware state.
- `spark-d.example` was already current for packages and firmware. Its failed one-time `nvidia-spark-remove-once.service` was reset and rerun successfully, removing `nvidia-fs-loader`; the unit is now inactive instead of failed.

## Final Summary

```text
spark-a.example|6.17.0-1021-nvidia|580.159.03|active,active,active,active,active,active|failed=0|prom=ok|reboot=no|apt=0|fw=current
spark-b.example|6.17.0-1021-nvidia|580.159.03|active,active,active,active,active,active|failed=0|prom=ok|reboot=no|apt=0|fw=current
spark-c.example|6.17.0-1021-nvidia|580.159.03|active,active,active,active,active,active|failed=0|prom=ok|reboot=no|apt=0|fw=current
spark-d.example|6.17.0-1021-nvidia|580.159.03|active,active,active,active,active,active|failed=0|prom=ok|reboot=no|apt=0|fw=current
```

Service order in the compact summary:

```text
ssh,tailscaled,nvidia-persistenced,dgx-dashboard,dgx-dashboard-public-admin,dgx-spark-prometheus
```

## Package Baseline

All four Sparks reported these package versions after the update/reboot pass:

```text
linux-nvidia-hwe-24.04=6.17.0-1021.21
linux-image-nvidia-hwe-24.04=6.17.0-1021.21
linux-modules-nvidia-580-open-nvidia-hwe-24.04=6.17.0-1021.21
nvidia-driver-580-open=580.159.03-0ubuntu192.0.2.10
dgx-dashboard=0.29.0
dgx-oobe=0.25.1
fwupd=2.0.20-1ubuntu2~24.04.1
tailscale=1.98.4
```

## LAN Addresses

```text
spark-a.example   192.0.2.10  tailscale 192.0.2.10
spark-b.example   192.0.2.10    tailscale 192.0.2.10
spark-c.example   192.0.2.10  tailscale 192.0.2.10
spark-d.example   192.0.2.10  tailscale 192.0.2.10
```

## Verification Checks

- SSH access over the CRS804 LAN succeeded on all four Sparks.
- `nvidia-smi` reported `NVIDIA GB10, 580.159.03` on all four Sparks.
- `systemctl --failed` returned zero failed units on all four Sparks.
- `curl http://192.0.2.10:9835/metrics` succeeded on all four Sparks.
- `/var/run/reboot-required` was absent on all four Sparks.
- `apt list --upgradable` returned zero upgradable packages on all four Sparks after `apt-get update` and `dist-upgrade` where privileged access was available.
- `fwupdmgr get-upgrades` showed no available firmware updates and current firmware on all four Sparks.
