# Sanitization Map

This short map documents the public placeholder conventions used throughout this
copy. It contains no values from the private operational repository.

| Source category | Public convention |
| --- | --- |
| IPv4 addresses and subnets | RFC 5737 documentation ranges such as `192.0.2.10` |
| Hostnames and node aliases | Stable names under `example`, such as `spark-a.example` |
| User and role names | Generic aliases such as `public-user` and `public-admin` |
| Fabric and switch identifiers | Stable role aliases such as `fabric-port-a` |
| MAC-like hardware identifiers | `AA:BB:CC:xx:xx:01` style placeholders |
| Serial and UUID values | `SERIAL-PLACEHOLDER-01` and `UUID-PLACEHOLDER-01` |
| Local filesystem paths | Public paths such as `/opt/public-user` and `/var/tmp/public-run` |

The source tree contained no tracked image assets, so no image pixels or image
metadata required transformation. The public tree retains the source paths and
technical content while replacing identifying values consistently.
