---
tags:
  - code-map
  - skeleton
status: current
---

# Skeleton

> [!summary]
> The first layer of the generator: it splits the world into 48 m cubes
> called sectors and gives each one a type (stratum, shaft, cavity, solid or
> chasm). The type is computed from the world seed and the sector's
> coordinates alone, so any sector can be asked about at any time and always
> gets the same answer. The tuning knobs live in one resource; a task prints
> how many sectors of each type seed 0 produces and fails if that changes.
> Another task measures how structured the result is and fails if shafts get
> too short or solid stops splitting space into blocks. A separate viewer
> scene draws the sectors around the camera as coloured see-through boxes,
> with the common stratum as faint outlines, draws the walkable graph over
> them as lines coloured by edge kind, and puts every grammar knob in the
> tweak panel, so the grammar can be judged by eye while flying through it.

## Files

- [sector_grammar.gd](../../scripts/world/sector_grammar.gd)
  (`class_name SectorGrammar`, a `Resource`): every grammar parameter as an
  `@export` field with its default, grouped Lattice, Shaft, Cavity, Solid and
  Chasm. Sizes are in sectors. Out-of-range values are clamped by the reader.
- [skeleton.gd](../../scripts/world/skeleton.gd) (`class_name Skeleton`, a
  `RefCounted`): the `SectorType` enum, the salt constants and
  `sector_type(seed, cell)`.
- [skeleton_viewer.gd](../../scripts/world/skeleton_viewer.gd) (`class_name
  SkeletonViewer`, a `Node3D`): draws the sectors around the camera, one
  `MultiMeshInstance3D` per type.
- [skeleton_viewer.tscn](../../scenes/skeleton_viewer.tscn): the viewer
  scene. The ray-marched main scene does not use the skeleton.

## Using it

```gdscript
var skeleton := Skeleton.new()                  # default grammar
var type := skeleton.sector_type(WorldState.seed, Vector3i(ix, iy, iz))
print(Skeleton.type_name(type))                 # "shaft"

var grammar := SectorGrammar.new()
grammar.shaft_probability = 0.3
var tuned := Skeleton.new(grammar)
```

`sector_type` runs one private test per rule in precedence order (chasm,
solid wall or floor, cavity, shaft, else stratum) and returns at the first
match. Each test maps the sector to its coarse cell with floor division, draws
a chance with `Hash.hash3` and integer sizes and offsets with `Hash.hash3_u`,
and checks whether the sector falls inside the box, plane panel or floor layer
placed in that cell. `_floor_plane` is shared by the floor and shaft rules, so
shafts run exactly from one floor plane to the next. The rules, their tuned
parameters and the salt table (100 to 133) are in
[[sector-skeleton-and-walkable-graph]]; why the defaults are what they are is
in [[0016-tuned-sector-grammar-solid-before-voids]].

## Viewer

`mise run run-skeleton` opens [skeleton_viewer.tscn](../../scenes/skeleton_viewer.tscn):
the free-fly camera (24 m/s, 96 m/s with Shift), a near-black background,
the `SkeletonViewer`, the tweak panel and the HUD. Its nodes:

| Node | Type | Role |
| --- | --- | --- |
| `Camera` | `Camera3D` with the free-fly script | Starts at `(24, 24, 24)`, inside sector `(0, 0, 0)`, yaw 0.9, pitch -0.28. |
| `SkeletonViewer` | `Node3D` with the viewer script | The sector cubes and the legend. |
| `SkeletonViewer/GraphLines` | `Node3D` with the `GraphLines` script | The walkable graph edges as lines ([[walkable-graph#Debug lines]]). |
| `TweakPanel` | tweak panel instance | No material and no presets; the viewer is its only param source. |
| `Hud` | HUD instance | Pose and seed, with the legend below. |

The viewer is made for flying through the world, so its defaults are:

| Setting | Default | Meaning |
| --- | --- | --- |
| `follow_camera` | on | The region is centred on the camera's sector and moves with it. |
| `radius` | 4 | Sectors drawn around the centre: 9³ = 729 (at most 6, 13³ = 2 197). |
| `fill` | on | Shaft, cavity, solid and chasm as translucent filled boxes; off draws them as wireframe cubes. |
| `stratum_wireframe` | on | Stratum as a faint wireframe cube; off draws it as a faint filled box. |
| `show_stratum` | on | Stratum is drawn, much fainter than the other types. |
| `show_graph` | on | Walkable graph edges of the regions overlapping the drawn box are drawn as lines. |
| `show_corridor` … `show_tunnel` | on | One toggle per edge kind; hides that kind's lines and portal markers without a rebuild. |
| `marker_size` | 3 m | Edge of the crosses at portals and nodes; 0 hides them. |
| `boundary_scheme` | 0 | `WalkableGraph.boundary_scheme` of the drawn graph: 0 per face, 1 per region pair, 2 skip solid faces. |
| `void_wall_tunnels_last` | on | `WalkableGraph.void_wall_tunnels_last` of the drawn graph. |

Every sector of the region is drawn as a cube 44 m on a side centred in its
48 m sector, so neighbours stay apart, except the sector the camera is in:
from inside a cube you would only see that one cube. Cubes up to half the
radius from the centre are at full strength; beyond that they fade linearly
to 20 % at the radius, so the near structure dominates.

The style is chosen per type: `fill` covers shaft, cavity, solid and chasm,
`stratum_wireframe` covers stratum. Stratum is the majority, so as filled
boxes it would hide everything else; as faint edges it only marks the grid.

| Type | Default style | Wireframe edges | Filled box | Render priority |
| --- | --- | --- | --- | ---: |
| stratum | wireframe | pale blue-grey, alpha 0.12 | pale blue-grey, alpha 0.12 | 2 |
| shaft | filled | cyan, alpha 0.95 | cyan, alpha 0.35 | 1 |
| cavity | filled | orange, alpha 0.95 | orange, alpha 0.35 | 1 |
| solid | filled | grey, alpha 0.45 | grey, alpha 0.45 | 0 |
| chasm | filled | red, alpha 0.95 | red, alpha 0.35 | 1 |

All materials are unshaded, translucent `StandardMaterial3D`s that do not
write depth and draw both faces, so the region reads through itself from
inside and from outside. Without depth, the draw order decides how types
blend: Godot draws translucent materials in ascending `render_priority`, so
solid goes first, the voids are blended over it and keep their colour, and
the stratum edges come last so they stay visible over the filled boxes.
Within one type the order does not matter, because blending one colour over
itself gives the same result in any order. Each type has one `MultiMesh`
whose mesh is a 12-edge `PRIMITIVE_LINES` cube or a unit `BoxMesh`; switching
a style only swaps mesh and material. A refresh writes all instances of a
type as one `PackedFloat32Array` into `MultiMesh.buffer`, 16 floats per cube:
a scaled basis, the centre and an instance colour whose alpha is the distance
fade.

**Outside view preset.** To judge the grammar as a whole, look at a fixed
region from outside: turn `follow_camera` off (the region stays at `center`,
default `(0, 0, 0)`), set `radius` 3, and fly to position
`(-300, 260, -300)`, yaw 0.79, pitch -0.48. That is the pose of the
before/after screenshots in [[sector-skeleton-and-walkable-graph]]; with
`show_stratum` off only the voids and solid remain.

From inside, the translucent solid boxes add up to a grey haze a few sectors
deep, and where the line of sight leaves the drawn region the background
shows through as black. Turning `fill` off gives the plain wireframe lattice.

A refresh runs only when the camera enters another sector or the radius, a
toggle, the seed or a grammar parameter changes. Sector types of the drawn
region are cached per cell, so crossing a sector boundary hashes only the
new slab; a seed or grammar change clears the cache. The camera entering
another sector also redraws when the region does not follow it. Refresh times
measured with filled boxes (issue #77) on a Coffee Lake laptop CPU with the
Vulkan renderer (median of 11 runs):

| Radius | Sectors | Cold (seed or grammar change) | Boundary crossing | Toggle only |
| ---: | ---: | ---: | ---: | ---: |
| 3 | 343 | 8.8 ms | 1.3 ms | 0.2 ms |
| 6 | 2 197 | 50 ms | 5.0 ms | 1.1 ms |

Almost all of the cold time is `sector_type` in GDScript.

**Graph lines.** At the end of every refresh, and only then, the viewer calls
`GraphLines.rebuild` with its skeleton, the seed and the drawn box; the
`show_graph`, `marker_size`, `boundary_scheme` and `void_wall_tunnels_last`
setters mark the viewer dirty (the last two after dropping the graph caches),
the per-kind toggles only hide a mesh. The lines are drawn after all boxes (render
priority 10), so they stay crisp over the filled boxes. How they are built
and cached is in [[walkable-graph#Debug lines]]. Rebuild times of the graph
alone, measured headlessly on the same laptop (median of 11 runs, seed 0):

| Radius | Edges | Cold (seed or grammar change) | Crossing inside the same regions | Entering a new slab of regions | `marker_size` change |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | ~600 | 85 ms | 1.9 ms | 27 ms | 1.8 ms |
| 4 | ~1 100 | 144 ms | 3.6 ms | 38 ms | 3.1 ms |
| 6 | ~2 900 | 380 ms | 9.3 ms | 81 ms | 9.2 ms |

The region cache means a full slab of new regions is computed only every
third sector crossing; `show_graph` off skips the graph entirely. With
`follow_camera` off the region stays where it is, so the camera can fly out
and look at it from outside.

The panel's `viewer` section holds `radius`, `show_stratum`, `fill`,
`stratum_wireframe` and `follow_camera`, the `graph` section `show_graph`,
one `show_<kind>` toggle per edge kind, `marker_size`, `boundary_scheme` and
`void_wall_tunnels_last`; below them one `grammar …` section per `@export_group` of
`SectorGrammar`, generated by `ParamRegistry.add_object_exports` ([[tweak-ui]]),
so a new grammar export shows up without touching the panel. The seed comes
from `WorldState` and the seed row (R picks a random one). The legend below
the HUD lists each type's colour and count in the region, each edge kind's
colour and number of drawn edges, the centre sector, the radius, the last
refresh time and the last graph rebuild time; H hides it with the HUD.

## How to run or check it

- `mise run run-skeleton` opens the viewer; Tab opens the panel.
- `mise run smoke` (part of `check`) runs the viewer scene headlessly for
  60 frames and fails on any script or scene error.
- `mise run skeleton-histogram` prints the seed 0 histogram and checks
  totality, determinism and the reference in [[skeleton_histogram_seed0]]
  ([[tools-and-tasks]]). It is part of `mise run check`.
- After an intended grammar change, `mise run skeleton-histogram --update`
  and commit the regenerated reference.
- `mise run skeleton-stats` (part of `check`) measures shaft runs, non-solid
  components, type fractions, cavity clusters and stratum runs over 100
  random 5³ regions and fails below the structure thresholds.
- `mise run panel-check` (part of `check`) clicks the viewer's tweak panel
  widgets and checks every setter ran.

## References

- [[sector-skeleton-and-walkable-graph]]: the grammar rules, salts and
  parameters.
- [[0015-hashed-multi-scale-sector-grammar]]: why the grammar is hashed on
  coarse cells.
- [[0016-tuned-sector-grammar-solid-before-voids]]: why solid ranks above
  the voids and the defaults are what they are.
- [[hash]]: the integer hash every decision draws from.
- [[MEGASTRUCTURE_CONCEPT]], section 2.1: the sector types.
