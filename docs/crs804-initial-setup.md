# CRS804 Initial Setup
Date: 2026-06-28

## Device

- Model: `CRS804-4DDQ`
- Serial: `SERIAL-PLACEHOLDER-01`
- MAC: `AA:BB:CC:xx:xx:01`
- SoftID: `945T-RX5N`
- Identity: `switch-a`

## Management Configuration

```routeros
/system identity set name=switch-a
/ip address add address=192.0.2.10/24 interface=bridge comment="main LAN management"
/ip route add dst-address=192.0.2.10/0 gateway=192.0.2.10 comment="main LAN gateway"
/ip dns set servers=192.0.2.10,192.0.2.10 allow-remote-requests=no
```

The active route table after setup:

```text
192.0.2.10/0        192.0.2.10  main  distance 1
192.0.2.10/24  bridge        main  connected
192.0.2.10/24  bridge        main  connected
```

## Service Hardening

```routeros
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set ssh address=192.0.2.10/24
/ip service set winbox address=192.0.2.10/24
```

Verified from the Mac Studio:

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

## Update Record

Before update:

- RouterOS: `7.20.8 long-term`
- RouterBOOT current firmware: `7.20.8`
- RouterBOOT upgrade firmware: `7.21.4`

After update and reboot:

- RouterOS: `7.21.4 long-term`
- RouterBOOT current firmware: `7.21.4`
- RouterBOOT upgrade firmware: `7.21.4`
- Board: `CRS804-4DDQ`
- CPU: `ARM64`, 4 cores at 2000 MHz
- Memory: `4096.0MiB`
- Bad blocks: `0%`

## Local Backups Created On Device

```routeros
/export file=crs804-initial-lan-mgmt
/export file=crs804-before-update
/system backup save name=crs804-before-update
```
