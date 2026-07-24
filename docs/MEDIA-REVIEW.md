# Media Review: Rack, PSU Supports, and Thermal Evidence

The owner supplied and approved thirteen HEIC photographs for this draft. Each
public copy was converted to JPEG, resized to a maximum long edge of `1800`
pixels, saved without EXIF or location metadata, and manually inspected. The
original attachments remain unchanged.

The existing rack overview remains part of the review set:

![Gumbii Digital DGX Spark rack overview](../media/review/gumbii-dgx-spark-rack-overview.jpg)

## Approved sequence

| Order | Public asset | Engineering role |
| ---: | --- | --- |
| 1 | `media/review/01-rack-heat-pocket-before.jpg` | Original PSU and cable concentration in the rack |
| 2 | `media/review/02-orange-prototype-body.jpg` | First full support body |
| 3 | `media/review/03-orange-prototype-psu-fit.jpg` | PSU-body fit proof |
| 4 | `media/review/04-orange-prototype-cable-clearance.jpg` | Connector and cable clearance |
| 5 | `media/review/05-dimensional-test-clips.jpg` | Four rack-clip measurements printed as small coupons |
| 6 | `media/review/06-orange-prototype-support-removal.jpg` | Full prototype and print-support strategy |
| 7 | `media/review/07-orange-prototype-rack-fit.jpg` | Corrected rack-retention fit |
| 8 | `media/review/08-final-production-prints.jpg` | Final green production parts before cleanup |
| 9 | `media/review/09-final-clips-installed-side.jpg` | Installed support geometry from the side |
| 10 | `media/review/10-final-clips-installed-rear.jpg` | Installed support set from the rear |
| 11 | `media/review/11-fan-below-psu-standoffs.jpg` | Fan position below the raised PSU bricks |
| 12 | `media/review/12-completed-rack-rear-sanitized.jpg` | Completed rear arrangement with equipment tags pixelated |
| 13 | `media/review/13-completed-rack-front-sanitized.jpg` | Completed front arrangement with exact port mapping and labels pixelated |

The complete sequence is placed in
[THERMAL-MANAGEMENT.md](THERMAL-MANAGEMENT.md). Selected frames appear in the
README and case study where they support the broader engineering timeline.

## Pixel review and redactions

The first ten new photographs contain no readable IP addresses, hostnames,
MAC addresses, credentials, account data, or exact controller map. Three images
received limited deterministic pixelation:

- `media/review/11-fan-below-psu-standoffs.jpg`: one numbered cable marker;
- `media/review/12-completed-rack-rear-sanitized.jpg`: small equipment labels
  and a serial-bearing hanging tag; and
- `media/review/13-completed-rack-front-sanitized.jpg`: host labels,
  infrastructure labels, serial-bearing PDU text, and the visible switch-port
  and patch-panel relationship.

The redactions do not alter the PSU supports, fan, rack structure, or the
mechanical relationships being documented. Power-bank names that do not expose
an actionable mapping may remain where visible.

## Publication gate

- All fourteen review JPEGs are listed in this manifest.
- Every image reference resolves locally.
- JPEG metadata markers are rejected by the publication checker.
- Exact power, controller, and network relationships remain excluded.
- This remains a draft PR until the owner separately authorizes merge.
