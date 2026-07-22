# Identity-First Commissioning

## Bring-up order

The first Spark was commissioned on the management network before the high-speed fabric was connected. The same order became the fleet rule:

1. Connect management Ethernet only.
2. Allow `60-120` seconds for boot and network initialization.
3. Identify the new lease and prove the hostname over SSH.
4. Capture GPU, kernel, driver, firmware, service, and reboot-required state.
5. Attach the physical label only after host identity is proven.
6. Record the intended fabric role.
7. Connect the high-speed fabric only after the management record is stable.

The public alias table is in [sanitized-cluster-aliases.json](../examples/sanitized-cluster-aliases.json). It preserves relationships but is not deployment inventory.

## Why the order mattered

An early discovery pass exposed two NVIDIA systems that could have been confused: the newly attached Spark and an existing synchronization target. The correction was procedural, not cosmetic. A label, a remembered address, or an existing application entry could not establish identity by itself.

For every system, the commissioning record required:

- proved hostname;
- management reachability;
- SSH authorization;
- GPU identity and driver result;
- kernel and CUDA result;
- failed-service count;
- firmware state;
- reboot-required state; and
- intended fabric role.

Hardware-address values and live switch ports are intentionally absent from this public adaptation.

## First parity baseline

The first four systems were normalized to the following recorded state:

| Check | Recorded state |
| --- | --- |
| Operating system | Ubuntu `24.04.4` |
| Kernel | `6.17.0-1021-nvidia` |
| NVIDIA driver | `580.159.03` |
| CUDA | `13.0` |
| Failed services | `0` after correction |
| Pending packages | `0` after correction |
| Reboot required | no |
| Firmware | current at the time of validation |

One system needed the matching open NVIDIA kernel module. Another had a failed one-time service that was reset and rerun. Those were treated as parity failures until the same check passed again.

## Management and fabric are separate gates

The management plane exists to establish identity and launch bounded tests. It does not prove the RoCE data plane. Conversely, a fabric link does not prove that the management identity attached to it is the intended system.

The public architecture uses:

- `spark-a.example` through `spark-h.example` on `192.0.2.0/24` for management;
- `198.51.100.0/24` for rail 0; and
- `203.0.113.0/24` for rail 1.

These are sanitized aliases. The real engineering rule is the important part: resolve a stable identity first, then verify the physical and logical fabric relationship independently.

## Commissioning acceptance

A system was ready for fabric work only when:

- management identity was unambiguous;
- SSH succeeded using the expected authorization path;
- the NVIDIA GPU and driver were visible;
- software versions matched the cohort;
- failed-service and reboot-required checks were clear; and
- the intended fabric interfaces could be tied back to that proved identity.

If any one of those fields remained ambiguous, the work stopped before a topology or switch change.
