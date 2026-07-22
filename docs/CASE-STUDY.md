# Case Study: Turning Cluster Ambiguity Into Reviewable Evidence

## Context

Local AI infrastructure crosses several layers at once: physical links, addressing, host identity, transport, collective communication, storage, services, and workloads. When one layer fails, the visible symptom can point in the wrong direction.

I wanted a method that reduced guesswork without turning every incident into a broad reconfiguration.

## Problem

The common failure pattern is premature action:

- a host responds, so the workload path is assumed healthy;
- one benchmark passes, so repeatability is assumed;
- a configuration looks correct, so the physical path is assumed; and
- a recovery works once, so it is treated as automation-ready.

Those shortcuts hide mismatches and make rollback harder.

## What I built

I organized the work around a compact evidence loop:

1. State the intended role and acceptance condition.
2. Resolve a synthetic target such as compute-a.example.
3. Collect read-only evidence from the smallest relevant layer.
4. Classify the result as observed, measured, failed, planned, or unknown.
5. Propose one bounded change with a rollback condition.
6. Re-run the same acceptance check.
7. Store a structured receipt.

The companion JSON example shows how the receipt can stay machine-readable without containing a real inventory.

## Engineering decisions

- Identity is explicit and never inferred from a label alone.
- Network reachability, authorization, transport readiness, and workload health are separate gates.
- Experiments have stop conditions before they have actions.
- A failed check remains failed until the targeted rerun passes.
- Synthetic public records preserve the method while private evidence remains private.

## Representative artifact

The synthetic cluster observation example uses a documentation-only host and address. It records intent, evidence class, gates, and an acceptance decision. The values are illustrative and were not collected from a live system.

## Evidence available here

The public evidence is structural:

- the example parses as JSON;
- the architecture is explicitly synthetic;
- the repository checker rejects common private-data patterns;
- CI runs the same checker on every change; and
- the documentation states what is not proven.

## Lessons

The most valuable cluster tool is not a single command. It is a disciplined boundary between what I know, what I infer, what I am allowed to change, and what must be verified afterward.

That boundary makes experiments easier to repeat and failures easier to explain.

## Limitations

This case study does not disclose or recreate a live topology. It contains no operational inventory, benchmark, host count, equipment map, or current status. It is a public description of the engineering method only.
