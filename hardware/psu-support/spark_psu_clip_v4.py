"""
DGX Spark 240W PSU clip-on cradle for 1U blank panel (19" rack, rear mount)
Coordinate system: X = across rack, Y = front(-)/rear(+), Z = up. Z=0 at floor bottom.
Brick: 99.0 x 99.05 x 35.17 mm, hangs vertically (35mm across rack), AC inlet UP, DC cable DOWN.
Print: floor-down, ABS, supports only under the two clip hook features.
"""
from pathlib import Path

import numpy as np
import trimesh

# ---------------- Parameters (mm) ----------------
T          = 4.0     # main wall thickness
BRICK_X    = 35.17   # brick thickness (across rack)
BRICK_Y    = 99.05   # brick depth (front-back)
BRICK_Z    = 99.0    # brick height
CLR_X      = 1.3
CLR_Y      = 1.6
IX         = BRICK_X + CLR_X          # 36.47 interior across
IY         = BRICK_Y + CLR_Y          # 100.65 interior deep
OX         = IX + 2*T                 # outer width  = 44.47
OY         = IY + 2*T                 # outer depth  = 108.65
WALL_H     = 58.0                     # basket side wall height (above Z=0)
FLOOR_T    = 4.0

PANEL_H    = 44.45                    # 1U blank panel height
PANEL_SPAN = PANEL_H + 0.35           # vertical interior between hooks
JAW        = 11.5   # V3: winner A geometry opened up 0.5mm per fit test
PLUG_GAP   = 40.0                     # clearance above brick top for C5 plug
HOOK_DROP  = 20.0   # deep leg: sole retention feature in V2
LIP_RISE   = 6.0                      # bottom lip rise up panel rear face
HOOK_T     = 5.0                      # hook arm / lip thickness

# Derived heights
BRICK_TOP   = FLOOR_T + BRICK_Z               # 103.0
PANEL_BOT   = BRICK_TOP + PLUG_GAP            # 143.0  (bottom edge of panel)
PANEL_TOP   = PANEL_BOT + PANEL_SPAN          # 187.8
BP_Y0       = T + IY                          # backplate front face y = 104.65
BP_Y1       = BP_Y0 + T                       # backplate rear face  y = 108.65 (panel front rests here)
LEG_Y0      = BP_Y1 + JAW                     # hook leg front face
LEG_Y1      = LEG_Y0 + T

def box(x0,x1,y0,y1,z0,z1):
    b = trimesh.creation.box(extents=[x1-x0, y1-y0, z1-z0])
    b.apply_translation([(x0+x1)/2, (y0+y1)/2, (z0+z1)/2])
    return b

solids, cuts = [], []

# ---------------- Basket ----------------
# Floor
solids.append(box(0, OX, 0, OY, 0, FLOOR_T))
# Floor openings (cable pass-through + ventilation), 8mm perimeter, 8mm center rib
rib_w = 8.0
open_y0, open_y1 = 8.0, OY - 8.0
mid = (open_y0 + open_y1)/2
cuts.append(box(8, OX-8, open_y0, mid - rib_w/2, -1, FLOOR_T+1))
cuts.append(box(8, OX-8, mid + rib_w/2, open_y1, -1, FLOOR_T+1))

# Side walls (solid, then windows cut for airflow across the 99x99 faces)
for x0 in (0.0, OX - T):
    solids.append(box(x0, x0+T, 0, OY, FLOOR_T, WALL_H))
post = 8.0
win_z0, win_z1 = 16.0, WALL_H - 8.0
wy = (OY - 3*post)/2
cuts.append(box(-1, OX+1, post,          post + wy,      win_z0, win_z1))
cuts.append(box(-1, OX+1, 2*post + wy,   2*post + 2*wy,  win_z0, win_z1))

# Front end wall (-Y) with vent window
solids.append(box(0, OX, 0, T, FLOOR_T, WALL_H))
cuts.append(box(10, OX-10, -1, T+1, 20, WALL_H-10))

# ---------------- Backplate (rear end wall, rises to the clip) ----------------
solids.append(box(0, OX, BP_Y0, BP_Y1, 0, PANEL_TOP))
# Stiffening ribs on backplate front face (outer edges, become C-channel)
for x0 in (0.0, OX - T):
    solids.append(box(x0, x0+T, BP_Y0 - T, BP_Y0, WALL_H, PANEL_TOP))

# ---------------- Clip ----------------
# Top hook: arm over panel top, leg down rear face
solids.append(box(0, OX, BP_Y0 - T, LEG_Y1, PANEL_TOP, PANEL_TOP + HOOK_T))   # arm: solid across ribs+jaw, no notch
solids.append(box(0, OX, LEG_Y0, LEG_Y1, PANEL_TOP - HOOK_DROP, PANEL_TOP))   # leg
# V2: no bottom lip -- single drop-on hook. Flared lead-in on leg bottom (outward 45)
ch2 = trimesh.creation.box(extents=[OX+2, 5.0, 5.0])
ch2.apply_transform(trimesh.transformations.rotation_matrix(np.radians(-45), [1,0,0]))
ch2.apply_translation([OX/2, LEG_Y0, PANEL_TOP - HOOK_DROP])
cuts.append(ch2)

# ---------------- Cable management (front wall exterior) ----------------
# Two L-bracket prongs rising from the bed -> fully self-supporting
for px0 in (10.0, 23.5):
    solids.append(box(px0, px0+5, -14, 0, 0, 18))          # vertical support wall
    solids.append(box(px0, px0+5, -14, 0, 18, 24))         # prong body
    solids.append(box(px0, px0+5, -14, -11, 24, 30))       # retention tip (keeps cable in)
# Zip-tie slots through front wall
cuts.append(box(31, 35, -15, T+1, 26, 29))
cuts.append(box(3.5, 7.5, -15, T+1, 26, 29))

# ---------------- Build ----------------
body = trimesh.boolean.union(solids, engine='manifold')
cutter = trimesh.boolean.union(cuts, engine='manifold')
result = trimesh.boolean.difference([body, cutter], engine='manifold')
result.merge_vertices()
result.fix_normals()

print("watertight:", result.is_watertight)
print("bbox (mm):", np.round(result.bounds, 1).tolist())
ext = result.bounds[1] - result.bounds[0]
print(f"size: {ext[0]:.1f} x {ext[1]:.1f} x {ext[2]:.1f} mm")
vol = result.volume / 1000.0
print(f"volume: {vol:.0f} cm^3 solid; ~{vol*1.04*0.55:.0f} g ABS at ~55% effective (4 walls/40% infill) per clip")
output_path = Path(__file__).with_suffix(".stl")
result.export(output_path)
print(f"exported {output_path}")
