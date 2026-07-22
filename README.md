# DGX Cluster

Sanitized engineering notes and reusable automation patterns from a DGX Spark cluster lab.

## Privacy and operating boundary

This repository deliberately excludes the live environment's addresses, hostnames, hardware identifiers, account names, local paths, and raw inventory. References marked with `PUBLIC_*`, documentation-only addresses, or other clearly generic aliases are intentional placeholders. They are not usable targets and must not be copied into a live environment.

The original operational records remain private. The public-safe records here preserve the technical sequence, observed outcomes, and recovery lessons without publishing an actionable topology.

## Contents

- `docs/` — sanitized bring-up notes, fabric experiments, verification records, and recovery guidance.
- `scripts/` — lab automation examples retained for review. Configure your own environment before running anything; do not treat the placeholders as defaults.
- `cluster-inventory.example.csv` — a fictional schema template for a local inventory. It contains no real device or network data.

## Before using the examples

1. Build a private inventory for your own environment.
2. Replace every placeholder through local configuration rather than editing public history with real values.
3. Validate node identity and reachability before any command that changes network or compute state.
4. Keep secrets, controller identities, raw captures, and topology evidence outside the repository.

## Publication status

This public copy is kept separate from the private operational source. The current tree is sanitized, but the public repository history and any external clones or caches still require their own review. A history purge, if needed, is a separate destructive operation that requires explicit review and authorization.

See [the privacy boundary](docs/PUBLICATION-PRIVACY.md) for the scope and limitations of this sanitized edition.
