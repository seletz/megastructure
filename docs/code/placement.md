---
tags:
  - code-map
  - placement
status: current
---

# Placement and walking

> [!summary]
> Placement turns a solved sector, one tile index per 2 m cell, into
> geometry you can see and stand on. The first version uses Godot's
> `GridMap`: every tile prototype becomes one item of a mesh library with a
> collision shape made from its own mesh, and each cell of the solver result
> becomes one grid cell holding that item, turned by the tile's rotation.
> The walk scene solves the 27 sectors around the origin on worker threads
> and places each as it arrives; a sector that fails or degrades is shown as
> a translucent red box so the hole is visible. A capsule body walks the
> result with the keyboard, climbing stair treads with a step-up, and F
> switches to the free-fly camera. Two checks pin it down: one places an
> asymmetric mesh at every rotation and looks where its geometry and
> collision end up, the other walks the capsule along a route of cells and
> fails when it falls or gets stuck.

![Inside sector (-1, 1, -1) at seed 0: floor slab, stair flights, bridges and ladders placed as GridMap cells](../images/first-sector.png)

## Files

- [sector_gridmap.gd](../../scripts/world/sector_gridmap.gd) (`class_name
  SectorGridMap`, a `GridMap`): the mesh library built from a
  `TileLibrary`, the yaw to orientation table and `place`.
- [world_walker.gd](../../scripts/world/world_walker.gd) (`class_name
  WorldWalker`, a `Node3D`): the root of the walk scene; requests the
  sectors, places results, draws failure boxes, spawns the player, the F
  and V keys, the panel params and the HUD legend.
- [player.gd](../../scripts/player.gd) (`class_name Player`, a
  `CharacterBody3D`): the capsule controller and the camera follow.
- [world_walk.tscn](../../scenes/world_walk.tscn): the walk scene:
  `WorldWalker` root, a `FreeFlyCamera` with a headlight, environment with
  fog, a `SectorJobs` node, the `Sectors` parent, the `Player` with its
  capsule shape and a visible capsule, the tweak panel and the HUD.
- `scripts/tools/gridmap_check.gd` and `scripts/tools/walk_check.gd`: the
  scripts behind `mise run gridmap-check` and `mise run walk-check`, listed
  in [[tools-and-tasks]].

## Using it

```gdscript
var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
var mesh_library := SectorGridMap.build_mesh_library(library)   # once, shared by every sector
var result := SectorJobs.solve_sector(library, SectorGrammar.new(), seed, sector)
if result.outcome == SectorSolver.Outcome.SOLVED:
	var grid := SectorGridMap.new()
	grid.mesh_library = mesh_library
	add_child(grid)
	grid.place(library, sector, result.cells)   # at sector * 48 m
```

| `SectorGridMap` member | Meaning |
| --- | --- |
| `build_mesh_library(library, family_colours := true)` (static) | One item per prototype with a mesh, item id = prototype index, named after the prototype, with one `ConcavePolygonShape3D` from `Mesh.create_trimesh_shape` at the identity transform. Air has no mesh and no item. With `family_colours` each item's mesh is a copy with a material in the contact sheet's family colour; the tileset's meshes are never changed. |
| `YAW_ORIENTATIONS`, `yaw_orientation(quarter_turns)` (static) | GridMap orientation index of 0 to 3 quarter turns about `+y` (wrapped modulo 4): `[0, 16, 10, 22]`. |
| `place(library, sector, cells)` | Clears the map, moves it to `sector_origin` and sets every non-air cell `x + n * (y + n * z)` of the result to its prototype's item and orientation; returns the cells set (also `placed_cells`). `n` is the cube root of the cell count. |
| `sector_origin(sector, n)`, `cell_centre(sector, cell, n)` (static) | World position of a sector's corner, `sector * n * 2` m, and of a local cell's centre. |
| `family_colour(family)`, `coloured_mesh(mesh, colour)` (static) | The contact sheet colour of a family (grey for free tiles) and a coloured copy of a mesh. |
| `sector`, `placed_cells` | The sector and the cell count of the last `place`. |

Cells are 2 m (`WalkableGraph.CELL_SIZE`) with `cell_center_x/y/z` on, so
local cell (i, j, k) is the box from `(i, j, k) * 2` to two metres further,
the mesh origin at its centre, the same frame the skeleton viewer and the
walkable graph use. A map holds one sector; neighbours are separate maps
side by side, 48 m apart.

### Orientation indices

A tile turned r quarter turns is drawn with `Basis(Vector3.UP, r * PI / 2)`,
the turn `TileLibrary` expands sockets with (`+x` goes to `-z`,
counter-clockwise seen from above). GridMap does not store a basis but one
of its 24 orthogonal indices; `get_orthogonal_index_from_basis` of the four
yaw bases gives

| quarter turns | 0 | 1 | 2 | 3 |
| --- | --- | --- | --- | --- |
| basis `x` axis goes to | `+x` | `-z` | `-x` | `+z` |
| orientation index | 0 | 16 | 10 | 22 |

The table is a constant rather than computed per cell because it is a hot
loop. `mise run gridmap-check` pins it: the index and its basis agree both
ways, a 0.8 × 2 × 0.4 m box in the `+x -z` corner of a cell shows up, by
`get_cell_item_basis` and by rays cast down through the map's collision, in
the corner the hand-worked turn predicts and not in the mirrored one, and
every placeholder stair rotation is high on the face `TileLibrary` gives its
`1s` socket. An earlier guess with 1 and 3 swapped failed all three.

### The walk scene

`mise run run-walk` opens [world_walk.tscn](../../scenes/world_walk.tscn)
at seed 0. `WorldWalker` configures `SectorJobs` with the placeholder
tileset and the seed and requests the (2 `block_radius` + 1)³ sectors around
sector (0, 0, 0), nearest first. Each `sector_ready` result that solved
becomes a `SectorGridMap` under `Sectors`; a failed or degraded one becomes
a translucent red unshaded box inset 0.5 m from its sector (a degraded
result is all solid and would hide the gap). A seed change clears
everything and requests the block again.

The player is frozen until the first solved sector with records arrives;
then its feet go onto that sector's hub cell (the interior node every
walk of the sector meets at, a floor record) and it walks. At seed 0 on
the current tileset 11 of the 27 sectors solve, 16 fail before an attempt
(#161).

| Key | Action |
| --- | --- |
| W / A / S / D | Walk relative to the camera's view; free fly: fly |
| Space | Jump |
| Shift | Run; free fly: fly fast |
| Mouse (captured) or right drag | Look |
| Esc | Capture or release the mouse |
| F | Free fly on or off; leaving it drops the capsule at the camera |
| V | First or third person |
| Tab, H, P, R | Panel, HUD, screenshot, random seed, as in every scene |

The panel has a `walk` group (`free_fly`, `show_failed`, `block_radius` 0 to
2) and a `player` group (`first_person`, walk and run speed, jump velocity,
step height, third person distance). The legend under the HUD label shows
the sectors placed, failed, degraded, queued and running, the mode and the
feet position.

### The player

`Player` is a `CharacterBody3D` whose origin is at the feet; the capsule
(0.3 m radius, 1.8 m tall) sits half its height above them. While
`walking`, horizontal velocity comes from WASD relative to the camera's
yaw (or `scripted_direction` for tools), gravity pulls when it is off the
floor, `move_and_slide` moves it, and the `FreeFlyCamera` is placed at the
eye (1.6 m) or `third_person_distance` behind it along the view direction,
keeping its own mouse look; the camera's flight is switched off. The
visible `Body` capsule is hidden in first person.

`move_and_slide` slides along anything steeper than `floor_max_angle` (46°),
so a stair riser would stop the body. Before sliding, `_step_up` tests the
frame's horizontal motion; when it hits a steep surface while on the floor,
it tests the motion again from `step_height` higher and 0.15 m further on,
then a move back down, and when that lands on a floor above the feet it
lifts the body by the rise. `floor_snap_length` = `step_height` keeps the
body on a flight going down. The placeholder stair rises 0.4 m per tread,
but the top tread of a flight is flush with the cell top while the landing
slab's top is 0.6 m above the cell bottom, a 0.6 m lip, so the default
`step_height` is 0.65 m.

## How to run or check it

- `mise run run-walk` opens the scene at seed 0.
- `mise run gridmap-check` (part of `check` and `check-full`) checks the
  orientation table, the asymmetric mesh at each rotation, the placeholder
  mesh library and the stair rotations, as above.
- `mise run walk-check` (part of `check` and `check-full`) walks the capsule
  one physics step per frame (`--fixed-fps 60`) along a hand-laid course of
  placeholder tiles laid the way the rasteriser lays a walk: three floor
  cells, a flight of three stairs up onto a landing, a turn, a flight of
  three down and three floor cells. It fails when the feet drop 0.5 m below
  the lower of the two cells walked between, a cell is not reached within
  240 frames, or the capsule ends more than 1 m from the last cell's walking
  point. The course passes with 15 step-ups and ends 0.24 m from the goal.
- `mise run walk-check --sector x,y,z [--seed N]` solves a real sector with
  the walk scene's pipeline and walks from the portal of its first kept
  horizontal edge back along that edge's records to the hub and out along
  the last edge's records to its portal, with the same failure rules and a
  print of the tiles around the feet when it fails.
- `mise run smoke` runs the walk scene for 60 frames.
- `mise run shot scenes/world_walk.tscn docs/images/first-sector.png --seed 0
  --pose=-23,68.2,-25,-1.57,-0.12 --frames 900 --params free_fly=true`
  renders the image above from inside sector (-1, 1, -1); `free_fly` keeps
  the spawn from moving the camera, and the frames give the worker threads
  time to solve the block under Xvfb.

### Acceptance status

The issue's acceptance, a stratum sector at seed 0 walked portal to portal,
is not met yet. At seed 0, 49 stratum sectors within three sectors of the
origin have two kept horizontal portals and records that build domains;
five solve, and none can be walked: portal openings have no slab and can
stand over a ladder, so the capsule falls (#161), and the records leave the
cell above a floor or stair free, so a bridge slab, column, lintel or jamb
there leaves 1.4 to 1.6 m of room (#171). Sector (-1, 1, -1) climbs its
first flight and stops under a bridge. Until #171 is decided the course
gates the checks, and the real-sector walk is re-run on seed 0 after #161.

## References

- [[RESEARCH_WFC]], section 5 (placement) and section 7 (E1).
- [[godot-docs-gridmap]]: the class this placement uses.
- [[solver]]: the results placed here and `SectorJobs`.
- [[tileset]]: the prototypes, their meshes and the rotation convention.
- [[edge-rasteriser]]: the records the real-sector walk follows.
- [[camera-and-scene]]: the free-fly camera the player drives.
- #139: whether GridMap stays as a debug tool once MultiMesh placement lands.
