# DGX Spark PSU Support

This directory contains the production revision of the custom support used to
mount the eight DGX Spark power supplies to a 1U rack blank. The design retains
each PSU vertically, preserves access to both cable ends, and keeps the airflow
path below the power supplies open.

## Files

- `spark_psu_clip_v4.stl`: ready-to-print production mesh.
- `spark_psu_clip_v4.py`: parametric source used to generate the mesh with
  `trimesh`, `numpy`, and the Manifold boolean engine.

## Print Record

The installed production set was printed in ABS, floor-down, with supports only
under the two hook features. The source records the measured PSU envelope,
clearances, 1U panel span, winning clip geometry, cable retention, and airflow
openings in millimeters.

Fit was established through physical iteration. The first full orange support
held the PSU correctly but did not seat on the rack panel. Four small clip
coupons were then printed with different dimensions. The best fit was returned
to this full V4 model before the eight green production parts were printed.

The complete engineering and temperature record is in
[Open-Rack Thermal Management](../../docs/THERMAL-MANAGEMENT.md).

## Regenerating The STL

Install the required geometry packages in an isolated Python environment, then
run:

```bash
python spark_psu_clip_v4.py
```

The script writes `spark_psu_clip_v4.stl` beside itself and reports whether the
resulting mesh is watertight, its bounding box, and an estimated ABS mass.
