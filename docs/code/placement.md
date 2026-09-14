---
tags:
  - code-map
  - placement
status: current
---

# Placement and walking

> [!summary]
> Placement turns a solved sector, one tile index per 2 m cell, into
> geometry you can see and stand on. The walk scene uses `SectorMultiMesh`:
> the worker thread that solved the sector also lists, for each tile mesh,
> where every copy of it goes (one packed array of transforms per mesh), and
> gathers the triangles of all tiles into one collision mesh. The main
> thread then only makes one `MultiMeshInstance3D` per tile mesh, which the
> GPU draws in one call, and one static body. The first version,
> `SectorGridMap`, puts each cell into a Godot `GridMap` instead; it is kept
> behind a panel toggle for debugging while #139 is open. A sector that
> fails or degrades is shown as a translucent red box. `SectorStreamer`
> keeps the sectors around the player loaded as it walks: it loads within a
> radius, frees beyond the next ring, caches solved cells, places one
> sector per frame and adds its collision in small chunks within a frame
> budget, with translucent boxes standing in for sectors not placed. A
> capsule body walks the result with the keyboard, climbing stair treads
> with a step-up, and F switches to the free-fly camera. Checks pin the buffer format by hand,
> show the two placements put every tile and every collision surface in the
> same place, and walk the capsule along a route of cells on both.

![Inside sector (-1, 1, -1) at seed 0: floor slab, stair flights, bridges and ladders placed as MultiMeshes](../images/first-sector.png)

## Files

- [sector_multimesh.gd](../../scripts/world/sector_multimesh.gd)
  (`class_name SectorMultiMesh`, a `Node3D`): the tile faces cache, the
  worker-side `build` of instance buffers and collision faces, and the
  main-thread `place`.
- [sector_gridmap.gd](../../scripts/world/sector_gridmap.gd) (`class_name
  SectorGridMap`, a `GridMap`): the mesh library built from a
  `TileLibrary`, the yaw to orientation table and `place`.
- [sector_streamer.gd](../../scripts/world/sector_streamer.gd) (`class_name
  SectorStreamer`, a `Node3D`): loads and frees sectors around a focus
  position with hysteresis, the LRU cache of solved cells, the frame budget
  for freeing, placing and adding collision chunks, failure boxes and
  impostor boxes ([[sector-streaming]]).
- [world_walker.gd](../../scripts/world/world_walker.gd) (`class_name
  WorldWalker`, a `Node3D`): the root of the walk scene; starts the
  streamer and hands it the player or camera position, spawns the player
  and holds it while the collision around it loads, the F and V keys, the
  panel params and the HUD legend.
- [player.gd](../../scripts/player.gd) (`class_name Player`, a
  `CharacterBody3D`): the capsule controller and the camera follow.
- [world_walk.tscn](../../scenes/world_walk.tscn): the walk scene:
  `WorldWalker` root, a `FreeFlyCamera` with a headlight, environment with
  fog, a `SectorJobs` node, the `Streamer` (a `SectorStreamer`, parent of
  the placed sectors and boxes), the `Player` with its
  capsule shape and a visible capsule, the tweak panel and the HUD.
- `scripts/tools/multimesh_check.gd`, `scripts/tools/gridmap_check.gd`,
  `scripts/tools/walk_check.gd`, `scripts/tools/streaming_check.gd` and
  `scripts/tools/collision_cook_bench.gd`: the scripts behind `mise run
  multimesh-check`, `multimesh-draw-calls`, `gridmap-check`, `walk-check`,
  `streaming-check` and `collision-cook-bench`, listed in
  [[tools-and-tasks]].

## Using it

### MultiMesh placement

```gdscript
var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
var jobs := SectorJobs.new()
add_child(jobs)
jobs.configure(library, seed)        # reads the tile faces on the main thread
jobs.build_placement = true          # solved tasks also run SectorMultiMesh.build
var meshes := SectorMultiMesh.build_meshes(library)   # once, shared by every sector
jobs.sector_ready.connect(func(result: Dictionary) -> void:
	if result.outcome == SectorSolver.Outcome.SOLVED:
		var node := SectorMultiMesh.new()
		add_child(node)
		node.place(meshes, result.sector, result.placement))   # at sector * 48 m
jobs.request(Vector3i(-1, 1, -1))
```

Without jobs, `SectorMultiMesh.build(library, SectorMultiMesh.prototype_faces(library), cells)`
builds the same dictionary on the calling thread.

| `SectorMultiMesh` member | Meaning |
| --- | --- |
| `prototype_faces(library)` (static, main thread) | Per prototype index, the mesh's `get_faces()` triangles sorted into seven lists: those lying on cell face `+x`, `-x`, `+y`, `-y`, `+z`, `-z` (all three corners within 1 mm of the plane) and the rest (`INTERIOR`). Empty for a prototype without a mesh. `SectorJobs.configure` calls it once. |
| `build(library, faces, cells, chunk_cells := 0)` (static, any thread) | The placement data of an n³ result, below. Reads only its arguments. With `chunk_cells` > 0 the collision stays in chunks of `chunk_cells`³ cells. |
| `place(meshes, sector, placement)` (main thread) | Frees the children and collision of an earlier call, moves the node to `sector_origin` and adds one `MultiMeshInstance3D` named `Mesh_<prototype>` per prototype with instances (`TRANSFORM_3D`, `custom_aabb` the sector box, `buffer` assigned in one call) and, for merged faces, a `StaticBody3D` named `Collision` with one `ConcavePolygonShape3D` of the faces. Chunked placement data adds no collision here. Returns the MultiMeshInstance3D count (also `multimesh_count`; `instance_count`, `triangle_count`). |
| `add_collision_chunk(index)`, `add_all_collision()` (main thread, in the tree) | Adds one chunk (or all) as a `ConcavePolygonShape3D` of one of the sector's `BODY_BLOCKS`³ = 8 static bodies, made through `PhysicsServer3D` with this node as collider (`collision_bodies`, `chunk_shapes`, `chunks_added`, `chunks_with_faces`). False for an empty or added chunk. |
| `is_chunk_ready(index)`, `is_collision_complete()` | A chunk has its shape or no faces; every chunk with faces is added (true for merged collision). |
| `release_collision()`, `free_collision()` | Frees the chunk bodies and returns the chunk shapes to free later, or frees them too. Leaving the tree frees them. |
| `chunks_per_axis(n, chunk_cells)`, `chunk_index(cell, n, chunk_cells)`, `body_of_chunk(index)` | Chunks along an axis, the chunk of a local cell (`cx + k * (cy + k * cz)`), and the body a chunk goes into. |
| `build_meshes(library, family_colours := true)` (static) | One mesh per prototype index, null for air; with `family_colours` the same coloured copies `SectorGridMap.build_mesh_library` makes. |
| `YAW_BASES`, `yaw_basis(r)`, `cell_transform(cell, r)` (static) | The exact basis of 0 to 3 quarter turns about `+y` and a tile's sector-local transform: that basis at the cell centre `(cell + 0.5) * 2` m. |
| `write_instance(buffer, i, transform)`, `read_instance(buffer, i)` (static) | Instance `i` of a `MultiMesh.buffer` written from or read back as a `Transform3D`. |
| `FLOATS_PER_INSTANCE` | 12. |

| `build` field | Type | Meaning |
| --- | --- | --- |
| `buffers` | `Array` of `PackedFloat32Array` | By prototype index: the `MultiMesh.buffer` of that prototype's cells in cell order; empty for air or an unused prototype. Rotated variants share their prototype's buffer. |
| `faces` | `PackedVector3Array` | Collision triangles of every tile, sector-local; empty with chunks. |
| `chunks`, `chunk_cells` | `Array` of `PackedVector3Array`, `int` | With `chunk_cells` > 0, the triangles per chunk by chunk index; else empty and 0. |
| `cells_per_sector` | `int` | n, the cube root of the cell count. |
| `instances`, `triangles`, `culled_triangles` | `int` | Instances written, triangles kept and triangles dropped between solid cells. |
| `build_usec` | `int` | Wall time of `build`. |

Frame: transforms and faces are sector-local metres, the frame
`SectorGridMap` uses (cell (i, j, k) is the box from `(i, j, k) * 2` m, the
mesh origin at its centre). The sector offset `sector * 48` m is not baked
in; `place` puts the node at the corner. That keeps the floats small far
from the origin, where a baked float32 origin would lose centimetres, and
the same data could be placed anywhere.

### Buffer layout

`Transform3D` in `MultiMesh.buffer` with `TRANSFORM_3D` (no colour, no
custom data) is 12 floats per instance, the three basis rows each followed
by that row's origin component, where x, y, z are the basis columns:

| offset | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| value | `x.x` | `y.x` | `z.x` | `origin.x` | `x.y` | `y.y` | `z.y` | `origin.y` | `x.z` | `y.z` | `z.z` | `origin.z` |

The class reference does not say so. `mise run multimesh-draw-calls` checks
it against what the OpenGL renderer writes for `set_instance_transform`;
the headless dummy renderer stores an assigned buffer but ignores
`set_instance_transform`, so `mise run multimesh-check` pins it by hand: a
stair turned one quarter turn (`x` to `-z`, `z` to `+x`) at local cell
(3, 5, 7), centre (7, 11, 15), must give exactly
`[0, 0, 1, 7,  0, 1, 0, 11,  -1, 0, 0, 15]`. The yaw bases come from a
table of exact 0 and ±1 values rather than sine and cosine, so the floats
are exact and match GridMap's orthogonal bases.

### Collision

Each tile's triangles are the cached faces of its prototype mesh moved by
`cell_transform`, the transform its instance uses; they are appended into
one `PackedVector3Array` for the sector. A triangle on a cell face is
dropped when the tile and its neighbour across that face are both the
tileset's solid tile: two solid boxes hide the square from both sides, and
the research plan asked for exactly this cut. Neighbours in the next sector
are unknown, so border faces stay. On the main thread `place` passes the
array to `ConcavePolygonShape3D.set_faces` in one call; the capsule walks on
exactly the triangles GridMap's per-item trimesh shapes had, minus the
hidden ones.

Jolt builds that shape on the main thread when its body enters the world,
1.5 s for a mixed sector (decision #175). For streaming, `build(..., 3)`
keeps the triangles per chunk of 3³ cells (a tile's triangles never leave
its cell, so the chunks are exactly the merged faces), and
`add_collision_chunk` adds one chunk at a time as a shape of one of the
sector's 8 bodies, about 5 ms each; `SectorStreamer` spreads them over
frames. `mise run collision-cook-bench` measures the options and checks
rays hit the same heights on each ([[sector-streaming#The collision cook strategy]]).

`multimesh-check` places a solved 8³ sector both ways at sector (1, -1, 2):
all instance transforms (GridMap's `get_meshes()` against the buffers read
back) match per mesh, and 768 rays (down, along `+x` and along `+z`) and 64
capsule casts down hit at the same distance within 1 cm. It also checks a
stair's collision against its mesh faces turned by hand and the solid face
cut on two neighbouring solid cells.

### GridMap placement

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

### Streaming

```gdscript
var streamer := SectorStreamer.new()
add_child(streamer)                                   # and a SectorJobs in the tree
streamer.start(jobs, library, seed)                   # configures the jobs
streamer.focus_position = player.global_position      # every frame
```

| `SectorStreamer` member | Meaning |
| --- | --- |
| `radius` (0 to `MAX_RADIUS` = 3, default 1) | Sectors within this Chebyshev distance of the focus sector are loaded; placed sectors beyond `radius` + 1 are freed. |
| `cache_size` (256) | Results kept in the LRU cache (outcome, cells, degraded, error). |
| `frame_budget_usec` (6000) | Main-thread work per `update` for freeing, placing and collision chunks. |
| `collision_chunk_cells` (3) | Cells per collision chunk edge; applies from the next `start`. |
| `show_impostors`, `show_failed`, `use_gridmap` | Impostor boxes, failure boxes, GridMap placement (from the next `start`). |
| `start(jobs, library, seed)`, `clear()` | Configures the jobs (`build_placement`, `collision_chunk_cells`) and streams; frees everything. |
| `update()` (from `_process`) | Refresh on a focus sector change, then free, place one, add chunks, within the budget. |
| `focus_position`, `focus_sector`, `sector_of(position)`, `distance(a, b)` (static) | The followed position, its sector at the last refresh, a position's sector, the Chebyshev distance. |
| `placed`, `outcomes`, `is_loaded(sector)` | Sector to node and outcome of every placed sector. |
| `is_collision_ready_at(position)` | The 27 chunks around a position have their shapes (or none to add). |
| `is_loading_done()`, `is_settled()` | Nothing requested, ready or queued to free within `radius`; and all collision added and freed shapes gone. |
| `requested_count()`, `ready_count()`, `unload_count()`, `cache_count()`, `impostor_count()`, `collision_pending_count()`, `shapes_to_free_count()`, `cached(sector)` | Queue sizes and a cache entry, for tools and the legend. |
| `impostor_distance()` | Beyond this camera distance a placed sector's impostor replaces its MultiMeshes. |
| `solved_count`, `cache_hits`, `placed_count`, `unloaded_count`, `chunks_added_count`, `last_*` and `max_*_usec` | Counters and timings since `start`, and what the last update did. |
| `sector_placed(sector, result)`, `sector_unloaded(sector)` | Signals after a placement and after a sector was freed. |

A cached SOLVED sector is requested with `SectorJobs.request(sector, cells)`,
whose task runs `SectorJobs.place_solved` (placement data only, `cached`
true). The rules, the cache, the collision strategy, the budget and the
impostors are in [[sector-streaming]].

### The walk scene

`mise run run-walk` opens [world_walk.tscn](../../scenes/world_walk.tscn)
at seed 0. `WorldWalker` starts the `Streamer` with the `SectorJobs`, the
placeholder tileset and the seed. Each frame it hands the streamer the
camera position (while flying or before the spawn) or the capsule's feet.
The streamer loads the sectors within `radius` (27 at radius 1) around
that, nearest first; each result that solved becomes a `SectorMultiMesh`
under `Streamer` (with `use_gridmap` a `SectorGridMap`), a failed or
degraded one a translucent red unshaded box inset 0.5 m from its sector (a
degraded result is all solid and would hide the gap), and every sector
within `radius` + 1 not placed a translucent box in its skeleton type
colour. A seed change clears everything and streams again.

The player is frozen until the first solved sector with records is placed;
then its feet go onto that sector's hub cell (the interior node every
walk of the sector meets at, a floor record) and it walks. While the
collision around its feet is not added yet, its physics process stops
(decision #178) and the legend says "holding: collision loading". At seed 0
on the current tileset 19 of the 27 sectors around the origin solve.

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

The panel has a `walk` group (`free_fly`, `show_failed`, `show_impostors`,
`use_gridmap`, `radius` 0 to 3, `cache_size`; changing `use_gridmap`
streams again) and a `player` group (`first_person`, walk and run speed,
jump velocity, step height, third person distance). The legend under the
HUD label shows the sectors placed, failed, degraded, queued, running and
cached, the radius with the results waiting to be placed, sectors waiting
to be freed, sectors with collision pending and the streamer's update time,
the placement path with the frame's draw calls and the mean worker build
time per sector, the mode and the feet position.

`use_gridmap` keeps the GridMap path for debugging, the conservative answer
while #139 (whether GridMap stays once MultiMesh placement lands) is open;
a GridMap sector builds its collision in the frame it is placed.

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

## Measurements

Draw calls per sector, from `mise run multimesh-draw-calls` (OpenGL
Compatibility renderer on llvmpipe under Xvfb, one sector at a time in
front of the camera, no lights, the empty scene draws 0). Seed 0, the 19
of the 27 sectors around the origin that solve on the current placeholder
tileset of 19 tile meshes. Build time is `SectorMultiMesh.build` in GDScript.

| sector | tiles placed | meshes used | GridMap draw calls | MultiMesh draw calls | build ms | collision triangles | dropped |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| (-1, -1, -1) | 9630 | 16 | 327 | 16 | 170 | 264 040 | 42 932 |
| (-1, -1, 1) | 8043 | 19 | 319 | 19 | 133 | 277 728 | 15 504 |
| (-1, 1, -1) | 7885 | 19 | 328 | 19 | 128 | 303 176 | 9 748 |
| (-1, 1, 1) | 2124 | 13 | 238 | 13 | 44 | 98 476 | 896 |
| (0, -1, -1) | 7646 | 19 | 328 | 19 | 129 | 285 740 | 11 404 |
| (1, -1, -1) | 8538 | 19 | 353 | 19 | 151 | 285 676 | 19 688 |
| (1, -1, 0) | 8226 | 19 | 334 | 19 | 145 | 270 836 | 19 972 |
| (1, -1, 1) | 7600 | 19 | 339 | 19 | 127 | 290 308 | 8 072 |
| (1, 1, -1) | 8962 | 18 | 316 | 18 | 145 | 261 500 | 33 316 |
| (1, 1, 0) | 9113 | 19 | 328 | 19 | 153 | 251 068 | 36 500 |
| (1, 1, 1) | 8996 | 16 | 344 | 16 | 149 | 336 616 | 18 512 |
| 8 all-solid sectors | 13 824 | 1 | 27 | 1 | 220 to 233 | 6 912 | 158 976 |

GridMap draws one call per mesh per octant (8³ cells, 27 per sector), so a
mixed sector takes 238 to 353; MultiMesh takes exactly one per mesh used,
13 to 19, the issue's bound. The all-solid sectors spend their build time
walking 13 824 cells and dropping every inner face.

The worker build is not the expensive part of the main thread's work.
`mise run multimesh-check` times sector (-1, 1, -1) headless from placing
to the end of the next process and physics frame: 1824 ms with GridMap
(its octants and shapes are built in that frame), 1510 ms with MultiMesh,
of which the MultiMesh nodes take about 4 ms and `set_faces` about 11 ms;
the rest is Jolt building the 303 176-triangle shape when the body enters
the tree. Whether to keep one merged trimesh per sector, split it, cut
more triangles or build it off the main thread is decision #175; #96
keeps the merged trimesh for `place` without chunks, and streaming (#98)
adds chunks of 3³ cells as shapes of 8 bodies per sector over frames,
4.8 to 6.1 ms each at most ([[sector-streaming#The collision cook strategy]]).

## How to run or check it

- `mise run run-walk` opens the scene at seed 0.
- `mise run multimesh-check` (part of `check` and `check-full`) checks the
  buffer layout and collision by hand, the solid face cut, GridMap and
  MultiMesh placement against each other on a solved 8³ sector and the
  worker-built placement data, as above, and prints the build and placing
  times.
- `mise run multimesh-draw-calls` (under `xvfb-run`, not part of `check`)
  checks the layout against the OpenGL renderer and prints the draw call
  table above.
- `mise run gridmap-check` (part of `check` and `check-full`) checks the
  orientation table, the asymmetric mesh at each rotation, the placeholder
  mesh library and the stair rotations, as above.
- `mise run walk-check` (part of `check` and `check-full`) walks the capsule,
  first on a `SectorMultiMesh`, then on a `SectorGridMap`
  (`--placement multimesh` or `--placement gridmap` for one), one physics
  step per frame (`--fixed-fps 60`) along a hand-laid course of
  placeholder tiles laid the way the rasteriser lays a walk: three floor
  cells, a flight of three stairs up onto a landing, a turn, a flight of
  three down and three floor cells. It fails when the feet drop 0.5 m below
  the lower of the two cells walked between, a cell is not reached within
  240 frames, or the capsule ends more than 1 m from the last cell's walking
  point. The course passes on both placements with 15 step-ups in 446
  frames and ends 0.24 m from the goal.
- `mise run walk-check --sector x,y,z [--seed N]` solves a real sector with
  the walk scene's pipeline and walks from the portal of its first kept
  horizontal edge back along that edge's records to the hub and out along
  the last edge's records to its portal, with the same failure rules and a
  print of the tiles around the feet when it fails.
- `mise run streaming-check [--quick]` (`--quick` part of `check`, the full
  walk of `check-full`) walks a frozen capsule through 10 streamed sectors
  and back (2 with `--quick`) and checks the load and unload rule, holes at
  the player, the cache on the way back, memory and node counts against a
  baseline and frame times ([[sector-streaming#Measurements]]).
- `mise run collision-cook-bench` (not part of `check`) prints the
  collision strategy table of decision #175.
- `mise run smoke` runs the walk scene for 60 frames.
- `mise run run-walk`, then Tab and `use_gridmap`, switches the scene to
  GridMap placement for comparison.
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

After #161 (#174) and with MultiMesh placement (#96), 19 of the 27 sectors
around the origin solve at seed 0. `mise run walk-check --sector -1,1,-1`
now stops before its second route cell, (1, 3, 1), with the feet 1.87 m
away, on both placements at the same position to 0.1 mm: the MultiMesh
path walks exactly as the GridMap path does, and the real-sector walk
still waits on the headroom work (#171, #173). Sectors (0, -1, -1) and
(1, 1, 0) solve but have fewer than two kept horizontal portals.

**Walk-check status after #173.** With headroom records over every walking
surface, portals entered from their door cell and floor records that keep
parapets off the faces their walk crosses
([[edge-rasteriser#8. Headroom records]]), `mise run walk-check --sector
-1,1,-1` walks portal to portal on seed 0. `mise run walk-check
--all-solving` solves the 84 stratum sectors within three sectors of the
origin that have two kept horizontal portals and records that build; 66
solve and all 66 walk portal to portal on both placements, against 0 of 74
before. Of the five
sectors listed in #171, (-1, 1, -1), (2, 1, -3) and (3, 2, 0) walk, and
(-2, -1, -3) and (-2, 1, -1) now degrade. The real-sector walk still runs on
demand only (decision #171, question 2).

## References

- [[RESEARCH_WFC]], sections 4 (threads) and 5 (placement) and section 7
  (E1, E2, E4).
- [[godot-docs-multimesh]]: the class the default placement uses and its
  buffer.
- [[godot-docs-thread-safe-apis]]: why the worker builds data and the main
  thread makes nodes.
- [[godot-docs-gridmap]]: the class the debugging placement uses.
- [[sector-jobs]]: the tasks that build the placement data.
- [[sector-streaming]]: loading, freeing, caching and chunked collision
  around the player.
- [[solver]]: the results placed here and `SectorJobs`.
- [[tileset]]: the prototypes, their meshes and the rotation convention.
- [[edge-rasteriser]]: the records the real-sector walk follows.
- [[camera-and-scene]]: the free-fly camera the player drives.
- #139: whether GridMap stays as a debug tool once MultiMesh placement lands;
  until it is decided it stays behind `use_gridmap`.
- #175: the main-thread cost of adding a sector's merged trimesh.
- #177 and #178: what the streaming cache keeps, and holding the player
  while collision loads.
