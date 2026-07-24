# Rack-Local BLE Power Commissioning

## Objective

The goal was to remove the mobile app from normal rack-local observation and eventually support guarded recovery through a Raspberry Pi 3B+. The design avoided vendor-cloud automation and internet-facing control endpoints.

The public record preserves the commissioning method and conclusions. Bluetooth addresses, controller identifiers, UUIDs, payload bytes, raw captures, exact outlet maps, and device-to-outlet relationships remain private.

## Local service shape

The Raspberry Pi design used:

- onboard BLE;
- a dedicated service account;
- local Unix sockets rather than a TCP listener;
- append-only actuation receipts;
- a read-only commissioning mode;
- maintenance and scheduler gates; and
- remote supervision that was not required for local process continuity.

The vendor app remained break-glass tooling for firmware, pairing, and restoring a known physical state.

## Clean-room characterization

The BLE work was performed by observing local controller behavior and bounded app-generated state transitions. The vendor application was not decompiled, and vendor cloud endpoints were not used.

The work established:

- repeatable controller discovery;
- a metadata-only GATT inventory;
- a request/response message family with sequence and selector correlation;
- CRC validation; and
- an identity-verified app-free read path.

One read-only capture collected `415` observations around a `27` byte advertised payload. A later bounded capture collected `60` frames across four payload groups. Those counts helped isolate stable and varying fields, but no raw frame data is published here.

## The first failure stopped the write path

An early one-outlet test received a valid protocol acknowledgement but moved a different physical relay than the requested target. The official app restored the known baseline, the helper was quarantined, and relay writes stopped.

That event changed the acceptance rule:

> A valid protocol acknowledgement proves only that the controller accepted a message. It does not prove target identity, relay mapping, or physical state.

## The second correction was more fundamental

The first decoder treated a field in a GET response as physical relay state. A later physical observation disproved it: the controller could report a continuous-ON program while the outlet indicator was dark and the attached load was not running.

The field was reclassified as configured program mode, not relay state.

At that stage, the daemon behavior was corrected to:

- report physical relay state as unknown unless a separate correlated source proves it;
- preserve unknown sensor and alarm fields as null;
- reject production relay writes before they reach the controller;
- keep the scheduler disabled; and
- keep unattended recovery disabled.

The correction passed Ruff and `199` tests in the private implementation. The deployed verification produced zero relay writes.

## Subsequent bounded commissioning

Later work used the dedicated fan outlet as the only harmless live fixture. A
passive capture established internally consistent environmental fields across
the observed frame variants: `80.3-80.4 F`, `41.8-41.9%` humidity, and
`2.04-2.06 kPa` VPD during the retained baseline. Normal alarm and overload
indicators were also decoded without inducing a fault.

The fan then provided physical relay proof under a strict one-outlet helper:

- fan-ON baseline: `82.4 F`;
- two minutes after fan OFF: `82.8 F`;
- immediate reading after restoring ON: `82.9 F`;
- later ON recovery reading: `82.5 F`; and
- every protected outlet remained ON.

The official app independently verified the fan state and probe readings. Raw
frames, controller identities, and the exact outlet selector remain private.

## What the app-free path proved

With the app closed, the Pi could establish a local read path that validated:

- controller identity;
- framing;
- CRC;
- sequence correlation; and
- selector correlation.

That app-free read path was useful, but by itself it did not establish physical
relay state. The later bounded fan cycle added independent state verification.

## What remains deliberately unclaimed

- unattended Spark recovery;
- production temperature-driven fan switching;
- long-duration rack thermal capacity; and
- a general relay map suitable for publication.

The work is substantive because it caught the unsafe assumption before it became automation. Fail-closed is the correct commissioning outcome when software state and physical observation disagree.

## Re-entry gate for future actuator work

Any future write path must begin on an empty reserve outlet and pass all of the following under direct physical observation:

1. identity-verified controller selection;
2. known OFF physical state;
3. OFF readback correlation;
4. one bounded ON transition;
5. visible physical ON confirmation;
6. independent readback confirmation;
7. one bounded OFF transition;
8. visible physical OFF confirmation;
9. restart and persistence checks; and
10. proof that no other outlet changed.

Until those gates pass repeatedly, reads remain informational and writes remain disabled.
