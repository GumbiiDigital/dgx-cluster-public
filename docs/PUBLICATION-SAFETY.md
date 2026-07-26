# Publication Safety

## What this repository preserves

This is a sanitized adaptation of real DGX Cluster engineering work. Non-identifying measurements, software versions, failure modes, decisions, rollback logic, and acceptance results are retained. They are not invented examples and they are not rewritten as generic portfolio claims.

## What is replaced

- Live IP addresses and subnets are mapped consistently into RFC 5737 documentation ranges.
- Private hostnames are mapped to `spark-a.example` through `spark-h.example` and other `.example` aliases.
- Physical switch-port labels are replaced by role relationships rather than live numbering.
- Exact power outlet and controller maps are omitted.
- Usernames, email addresses, account identifiers, hardware identifiers, serial values, and local paths are omitted.
- Private endpoints, overlay addresses, raw captures, credentials, keys, tokens, and secrets are omitted.

## What is intentionally not generalized

The repository retains technical facts that make the work defensible, including:

- software and firmware versions;
- interface and transport names;
- switch model and operating-system version;
- measured throughput and correctness results;
- failed hypotheses and negative tests;
- acceptance and stop conditions; and
- the commissioning conclusion when automation remained disabled.

## Alias convention

The public aliases are internally consistent but non-operational:

| Role | Public convention |
| --- | --- |
| Management plane | `192.0.2.0/24` |
| RoCE rail 0 | `198.51.100.0/24` |
| RoCE rail 1 | `203.0.113.0/24` |
| Compute systems | `spark-a.example` through `spark-h.example` |
| Fabric switch | `fabric-switch.example` |

The addresses are reserved for documentation and do not identify the live environment.

## Reviewed visual evidence

Unreviewed screenshots, rack photos, and equipment maps remain excluded. An
image may be published under `media/review/` only when its metadata has
been removed, its pixels have been manually inspected, and its placement and
review status are documented in [MEDIA-REVIEW.md](MEDIA-REVIEW.md). The reviewed
set records the PSU-support design and rack thermal work. I approved the visible
Spark names, power-unit names, model markings, rack labels, and cabling.
The photos contain no visible IP addresses, MAC addresses, credentials, account
data, or private controller identifiers.

The reviewed chart publishes aggregate workload and thermal measurements while
omitting hostnames, addresses, controller identities, outlet mappings, and raw
operational logs. Hatched chart regions represent unavailable controller data;
they are not interpolated values.

## Automated gate

The publication checker rejects common secret patterns, private and CGNAT addresses, multicast-local hostnames, email addresses, hardware-address formats, UUIDs, personal home paths, raw controller-map fields, and links to private source repositories. It also validates JSON, relative Markdown links, the Mermaid-only architecture file, and required repository structure.

The checker is a backstop, not a substitute for reviewing whether a technically valid detail would expose a live control relationship.
