# Guarded Spark Recovery Policy

## Separation of duties

Triage decides whether a failure is isolated and eligible. Actuation performs one bounded recovery. They are separate operations with separate receipts.

The public aliases describe the policy without exposing the live power map. Infrastructure roles are never eligible for recovery.

## Historical eligibility gate

A Spark was eligible for a recovery decision only when all of the following were true:

- LAN ping failed;
- LAN SSH and hostname proof failed;
- overlay reachability failed;
- the same isolated failure appeared in three consecutive five-minute observations;
- exactly one Spark was fully failed;
- at least six peers were healthy;
- maintenance pause was clear;
- controller alarm state was clear;
- the temperature safety gate was clear;
- the node was outside its six-hour recovery cooldown; and
- the private identity-to-outlet mapping digest matched the current decision.

Any unknown, stale, mismatched, or shared failure produced a refusal.

## Decision receipt

An eligible plan produced a single-use decision valid for `60` seconds. The receipt bound:

- the sanitized logical node role;
- private controller and outlet identity by digest, not by public label;
- the observation set;
- every policy reason;
- the cooldown state;
- a unique operation identifier; and
- the mapping version.

Stale, replayed, or mapping-mismatched decisions were rejected.

## Bounded actuation design

The intended operation was:

1. acquire per-node and global locks;
2. take a fresh controller snapshot;
3. rerun the fleet probes;
4. journal the intent before relay OFF;
5. switch the proved compute outlet OFF;
6. verify OFF;
7. wait `20` seconds;
8. restore continuous ON;
9. verify ON; and
10. allow up to eight minutes for the system to return before closing the receipt.

There was no retry loop. If the outlet was already unexpectedly OFF, the design restored ON without adding another OFF interval.

After a daemon restart during an interrupted operation, only the journaled, identity-verified compute outlet could be restored to continuous ON. The daemon could not initiate a second cycle during recovery.

## Hard refusals

The policy refused recovery for:

- infrastructure roles;
- more than one failed Spark;
- shared network or power symptoms;
- hostname or mapping mismatch;
- active maintenance;
- high or unknown temperature;
- controller alarm or unknown alarm state;
- cooldown;
- stale evidence;
- replayed decisions; and
- ambiguous physical relay state.

Overload remained a physical-reset condition because software control is unavailable during controller overload.

## Current conclusion

The policy engine and refusal logic remain useful engineering artifacts. Unattended relay recovery is not claimed as enabled because BLE physical relay-state verification did not pass commissioning. The correct runtime state is fail-closed.
