# First Spark Bring-Up

This checklist is for connecting the first DGX Spark without mixing up management networking and high-speed cluster fabric.

## Baseline Before Plug-In

Known management LAN:

- Gateway: `192.0.2.10`
- CRS804 management: `192.0.2.10`
- Mac Studio: `192.0.2.10`
- Spark node under test: `spark-a.example` at `192.0.2.10`
- workstation-a: `192.0.2.10`
- workstation-b: `192.0.2.10`

The newly connected Spark for this session was detected as `spark-a.example` at `192.0.2.10`.

## First Connection

1. Plug the Spark into the normal management LAN first.
2. Wait 60-120 seconds for DHCP and mDNS.
3. Run the verifier:

```bash
./scripts/verify-lan.sh
```

4. Look for a new host with SSH open, a Spark hostname, or a new DHCP lease in the router UI.
5. Label the cable and port before moving to QSFP cabling.

## High-Speed Fabric Notes

The CRS804-4DDQ can support a six-Spark fabric when each Spark uses one high-speed link through 400G breakout lanes.

Do not connect the full QSFP fabric until:

- Management SSH is stable.
- The Spark hostname and IP are recorded.
- The CRS804 port map is written down.
- The intended link mode and breakout cable plan are confirmed.

## Evidence To Capture Per Spark

For each Spark, add a row to the cluster inventory with:

- Hostname
- Management IP
- MAC address
- Switch port
- Cable label
- SSH verification result
- High-speed port assignment
