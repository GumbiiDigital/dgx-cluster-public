# First Spark Connection
Date: 2026-06-28

## Newly Detected Host

- Hostname: `spark-a.example`
- Management IP: `192.0.2.10`
- MAC: `AA:BB:CC:xx:xx:01`
- SSH banner: `OpenSSH_9.6p1 Ubuntu-3ubuntu13.16`
- Kernel: `Linux 6.17.0-1014-nvidia`
- Active management interface: `enP7s7`
- Tailscale IP: `192.0.2.10`

Verification:

```text
PING 192.0.2.10: 3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 0.447/0.470/0.494/0.019 ms
```

SSH read-only command:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new \
  public-user@192.0.2.10 'hostname; uname -sr; ip -br -4 addr'
```

Output:

```text
spark-a.example
Linux 6.17.0-1014-nvidia
lo               UNKNOWN        192.0.2.10/8
enP7s7           UP             192.0.2.10/24
tailscale0       UNKNOWN        192.0.2.10/32
```

## Existing NVIDIA Sync Target

The local SSH config also contains `public-sync-b.example`, which logged into a Spark named `spark-b.example`.

```text
spark-b.example
Linux 6.17.0-1014-nvidia
lo               UNKNOWN        192.0.2.10/8
enp1s0f0np0      UP             192.0.2.10/24
enP2p1s0f0np0    UP             192.0.2.10/24
tailscale0       UNKNOWN        192.0.2.10/32
```

Treat `spark-a.example` as the newly detected host from this connection session. Treat `spark-b.example` as an already configured NVIDIA Sync target until the physical labels are confirmed.
