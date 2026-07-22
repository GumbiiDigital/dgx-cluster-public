# Publication Safety

## Purpose

I use this repository to publish the cluster engineering method, not the cluster. Every example must remain synthetic and non-operational.

## Allowed

- Fictional names under the example namespaces.
- Documentation-only address ranges.
- General validation and reliability patterns.
- Synthetic JSON with clearly labeled illustrative outcomes.
- Limitations and failed assumptions that do not identify a live environment.

## Excluded

- Live network or hardware identity.
- Accounts, credentials, keys, tokens, and local paths.
- Raw logs, telemetry, inventories, service listings, and equipment maps.
- Exact system counts, operational measurements, and current status.
- Screenshots, photos, or copied private artifacts.
- Commands aimed at real systems.

## Project-specific review

Cluster material must not reveal how private roles connect, how many systems exist, or which services share a dependency. Architecture examples describe a validation pattern only.

## Gate

The standard-library checker validates required files, JSON syntax, Mermaid-only architecture, and common private-data patterns. CI runs the same gate. A passing scan reduces publication risk but does not replace human review.
