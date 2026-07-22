# Spark 3 Verification

Date: 2026-06-29

## Identity

```text
hostname: spark-c.example
user: public-user
kernel: Linux 6.17.0-1021-nvidia
```

## Network

```text
enP7s7      192.0.2.10/24
wlP9s9      192.0.2.10/24
tailscale0  192.0.2.10/32
docker0     192.0.2.10/16, down
```

Observed from the Mac:

```text
192.0.2.10 -> spark-c.example, MAC AA:BB:CC:xx:xx:01
192.0.2.10 -> same SSH host key, MAC AA:BB:CC:xx:xx:01
```

Ping checks:

```text
192.0.2.10: 3 packets transmitted, 3 received, 0.0% loss
192.0.2.10: 3 packets transmitted, 3 received, 0.0% loss
```

## SSH

Verified SSH access from the Mac using the NVIDIA Sync key:

```bash
ssh -i "$HOME/Library/Application Support/NVIDIA/Sync/config/nvsync.key" \
  -o IdentitiesOnly=yes \
  public-user@192.0.2.10
```

## Storage

```text
/dev/nvme0n1p2 ext4 3.7T total, 48G used, 3.5T available, 2% used
```

## GPU

```text
NVIDIA GB10, driver 580.159.03
```

## Services

Verified active:

```text
ssh
tailscaled
nvidia-persistenced
dgx-dashboard
dgx-dashboard-public-admin
dgx-spark-prometheus
```

Prometheus exporter verification:

```text
LISTEN *:9835
http://192.0.2.10:9835/metrics returned Prometheus metrics
http://192.0.2.10:9835/metrics returned Prometheus metrics
http://192.0.2.10:9835/metrics returned Prometheus metrics
```

Note: `/var/run/reboot-required` existed at verification time, so use a clean reboot or shutdown before moving the unit.
