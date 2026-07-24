# Source Adaptation Map

## Purpose

This file records how the public repository was rebuilt from the private DGX Cluster engineering record. It is a coverage and privacy check, not a link to private material.

## Preserved source categories

| Source category | Public destination | Preserved substance |
| --- | --- | --- |
| First-system bring-up and connection record | [COMMISSIONING.md](COMMISSIONING.md) | management-first order, identity ambiguity, parity gates, recorded versions |
| Four-system baseline and RoCE validation | [FABRIC-TROUBLESHOOTING.md](FABRIC-TROUBLESHOOTING.md) | failed throughput, QoS and FEC tests, direct-cable isolation, stop conditions |
| Known-good topology delta and physical correction | [CASE-STUDY.md](CASE-STUDY.md), [FABRIC-TROUBLESHOOTING.md](FABRIC-TROUBLESHOOTING.md) | second-port dual-function shape, separate rail subnets, physical-action gate |
| CRS804 forwarding repair | [FABRIC-TROUBLESHOOTING.md](FABRIC-TROUBLESHOOTING.md) | CPU-drop diagnosis, ASIC-forwarding correction, rollback design, measured repair results |
| Four-system and eight-system NCCL campaigns | [NCCL-TUNING-RECORD.md](NCCL-TUNING-RECORD.md) | frozen profiles, harness correction, repeat statistics, size contour, transport proof |
| Rack recable repair and later full rerun | [RACK-RECABLE-REVALIDATION.md](RACK-RECABLE-REVALIDATION.md) | stale forwarding relationship, complete directed matrices, bounded retry classification, NCCL proof |
| Guarded recovery design | [RECOVERY-POLICY.md](RECOVERY-POLICY.md) | multi-signal eligibility, refusal logic, cooldown, single-use decision, recovery journal |
| Raspberry Pi BLE commissioning | [POWER-BLE-COMMISSIONING.md](POWER-BLE-COMMISSIONING.md) | clean-room method, acknowledgement failure, decoder correction, fail-closed result |
| Open-rack thermal walkthrough | [THERMAL-MANAGEMENT.md](THERMAL-MANAGEMENT.md) | PSU-support iterations, installation, fan placement, and bounded measured test |

## Sanitized categories

The adaptation consistently replaces or omits:

- live management, rail, and overlay addresses;
- live hostnames and private service names;
- usernames, emails, personal names beyond the public brand, and local paths;
- hardware addresses, serials, device identifiers, and account identifiers;
- credentials, keys, tokens, and secrets;
- private URLs and endpoints;
- raw BLE addresses, UUIDs, frames, payload bytes, and controller fingerprints;
- exact physical switch-port labels; and
- exact controller, outlet, and load mappings.

## Stable public relationships

The public record uses one stable alias set throughout:

- compute: `spark-a.example` through `spark-h.example`;
- management: `192.0.2.21` through `192.0.2.28`;
- rail 0: `198.51.100.21` through `198.51.100.28`;
- rail 1: `203.0.113.21` through `203.0.113.28`; and
- switch: `fabric-switch.example`.

These names and addresses are explicitly sanitized public aliases. The measurements, versions, decisions, and troubleshooting outcomes around them are the recorded engineering work.

## Excluded source categories

The public cluster record does not import:

- raw evidence directories or logs;
- private inventory and topology manifests;
- unreviewed screenshots or rack photos; fourteen reviewed JPEGs are published
  under `media/review/` with metadata removal and documented visual
  review;
- controller captures or live power maps;
- unrelated training corpora and model artifacts;
- active monitoring state; or
- current operational status.

Those exclusions reduce exposure without replacing the engineering narrative with generic prose.
