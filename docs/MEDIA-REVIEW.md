# Media Review: Rack and Fabric Evidence

This draft stages only media found in a user-owned DGX Spark lab repository and
manually checked before public publication. It is a review surface, not an
approval record. Nothing in this change is merged into `main`.

## Staged candidate

![Gumbii Digital DGX Spark rack overview](../media/review/gumbii-dgx-spark-rack-overview.jpg)

**Proposed placement:** the repository overview in `README.md` and the physical
implementation section of `docs/CASE-STUDY.md`.

**What it shows:** the physical rack and eight DGX Spark systems as an overview
of the build.

**Security review:** the JPEG metadata was removed. The image has no visible IP
addresses, hostnames, MAC addresses, usernames, credentials, or account data.
The rack cabling and equipment labels remain visible in this candidate so the
owner can decide whether that visual level is acceptable before merge.

**Source:** `GumbiiDigital/gumbii-ai-lab/dgx-spark/assets/gumbii-dgx-spark-validation-rack.jpg`.
The public copy is a metadata-scrubbed review asset; the private source remains
unchanged.

## Proposed media slots

| Slot | Status | Proposed placement |
| --- | --- | --- |
| Rack overview | Staged for review | `README.md` and `docs/CASE-STUDY.md` |
| PSU clip / STL detail | Pending source image | Physical implementation section |
| Print-to-install sequence | Pending source image | Physical implementation section |
| Power A / Power B views | Pending source image | Hardware evidence subsection |

The PSU-clip closeups, STL renders, and installation-flow frames were not found
as committed binaries in the connected repositories. They are not fabricated or
replaced with generic illustrations. Supply the user-owned image paths or
attachments before adding those slots.

## Review gate

- Confirm the rack overview is acceptable at this visual level.
- Confirm whether the visible cabling and equipment labels should remain.
- Provide the user-owned PSU-clip/STL photos or renders for the pending slots.
- Merge only after the media and placement are explicitly approved.
