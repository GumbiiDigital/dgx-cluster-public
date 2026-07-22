# LAN Baseline
Date: 2026-06-28

Command:

```bash
./scripts/verify-lan.sh
```

## CRS804 Management

```text
PING 192.0.2.10: 3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 0.333/0.386/0.435/0.042 ms
```

## CRS804 Services

```text
21 ftp      closed
22 ssh      open
23 telnet   closed
80 www      closed
443 https   closed
8291 winbox open
8728 api    closed
8729 api-ssl closed
```

## Host Resolution

```text
workstation-a.example          192.0.2.10
workstation-b.example
spark-b.example
compute-gateway.example
```

## SSH Listeners

```text
192.0.2.10
192.0.2.10
192.0.2.10
192.0.2.10
192.0.2.10
192.0.2.10
192.0.2.10
192.0.2.10
```
