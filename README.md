# DGX Cluster Public

I built this repository to explain the engineering discipline behind a local multi-system AI lab without publishing the lab itself. The useful work is the method: define identity before action, measure before changing, preserve rollback, and leave an evidence trail another operator can review.

## What I built

This public surface organizes reusable patterns for:

- infrastructure intent and system boundaries;
- repeatable readiness and validation checks;
- observability that separates reachability, authorization, transport, and workload health;
- controlled experiments with explicit stop conditions;
- recovery notes that preserve what failed, what changed, and what remains unknown; and
- publication checks that keep private operations out of public documentation.

## Why it matters

A cluster can appear healthy while one layer is quietly wrong. A reachable host is not proof of a usable workload path. A fast benchmark is not proof of repeatability. A successful repair is not complete until the rollback and evidence are documented.

I treat those distinctions as part of the system, not as paperwork after the fact.

## Engineering approach

1. Start with declared intent and stable logical roles.
2. Resolve each target through a private source of truth.
3. Observe the smallest surface that can answer the question.
4. Separate discovery, validation, mutation, and acceptance.
5. Make risky steps reversible and bounded.
6. Record failures and corrections instead of flattening them into a success story.
7. Publish only synthetic examples after a privacy gate.

## Synthetic public-safe architecture

The architecture diagram uses documentation-only names and addresses. It demonstrates the validation flow without reproducing a live topology.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Representative work and artifacts

- [Case study](docs/CASE-STUDY.md) - how I turn an ambiguous infrastructure symptom into a bounded validation program.
- [Synthetic observation](examples/synthetic-cluster-observation.json) - a JSON-first example with documentation-only identities.
- [Publication safety](docs/PUBLICATION-SAFETY.md) - the boundary enforced before material reaches this repository.
- [Share copy](docs/SHARE.md) - concise language for explaining the work without overstating it.
- [Safety checker](scripts/check_publication_safety.py) - a standard-library repository scan used locally and in CI.

## Evidence and lessons

The evidence in this repository is limited to the public artifacts themselves: valid JSON, reviewable diagrams, documented gates, and an automated privacy scan. No synthetic example is presented as a live test result.

The main lesson is simple: repeatability comes from preserving identity, assumptions, actions, expected outcomes, actual outcomes, and rollback conditions as separate fields.

## Repository map

| Path | Purpose |
|---|---|
| README.md | Project narrative and limits |
| docs/CASE-STUDY.md | Original portfolio case study |
| docs/ARCHITECTURE.md | Synthetic Mermaid architecture |
| docs/PUBLICATION-SAFETY.md | Publication rules |
| docs/SHARE.md | Short and thread-style share copy |
| examples/ | Synthetic JSON evidence shapes |
| scripts/check_publication_safety.py | Local privacy and structure gate |
| .github/workflows/publication-safety.yml | Continuous publication check |

## Publication boundary

This is a public project interface, not an operational deployment repository. I do not publish live addresses, hostnames, hardware identities, account details, local paths, credentials, raw telemetry, service inventories, private topology, or equipment maps. Examples are synthetic and do not reproduce a live environment.

## Limitations

This repository does not prove a specific cluster size, topology, benchmark result, operational status, or production outcome. It deliberately omits the details needed to target or reproduce a private environment. Future evidence will be added only when it is both technically defensible and safe to publish.
