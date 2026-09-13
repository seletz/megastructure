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
> scene draws the sectors around the camera as coloured wireframe cubes and
> puts every grammar knob in the tweak panel, so the grammar can be judged by
> eye while flying through it.

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
| `TweakPanel` | tweak panel instance | No material and no presets; the viewer is its only param source. |
| `Hud` | HUD instance | Pose and seed, with the legend below. |

The viewer is made for flying through the world, so its defaults are:

| Setting | Default | Meaning |
| --- | --- | --- |
| `follow_camera` | on | The region is centred on the camera's sector and moves with it. |
| `radius` | 4 | Sectors drawn around the centre: 9³ = 729 (at most 6, 13³ = 2 197). |
| `fill` | off | Wireframe cubes; on draws translucent filled boxes. |
| `show_stratum` | on | Stratum is drawn, much fainter than the other types. |

Every sector of the region is drawn as a cube 44 m on a side centred in its
48 m sector, so neighbours stay apart, except the sector the camera is in:
from inside a cube you would only see that one cube. Cubes up to half the
radius from the centre are at full strength; beyond that they fade linearly
to 20 % at the radius, so the near structure dominates.

| Type | Wireframe edges | Filled box (`fill`) |
| --- | --- | --- |
| stratum | pale blue-grey, alpha 0.12 | pale blue-grey, alpha 0.12, drawn after the other types |
| shaft | cyan, alpha 0.95 | cyan, alpha 0.35 |
| cavity | orange, alpha 0.95 | orange, alpha 0.35 |
| solid | grey, alpha 0.45 | grey, opaque |
| chasm | red, alpha 0.95 | red, alpha 0.35 |

All materials are unshaded `StandardMaterial3D`s. Translucent ones do not
write depth and draw both faces; wireframe cubes are all translucent, so the
lattice reads through itself. Each type has one `MultiMesh` whose mesh is a
12-edge `PRIMITIVE_LINES` cube or, with `fill`, a unit `BoxMesh`. A refresh
writes all instances of a type as one `PackedFloat32Array` into
`MultiMesh.buffer`, 16 floats per cube: a scaled basis, the centre and an
instance colour. The instance colour fades alpha, or dims the colour of the
opaque filled solid. Stratum's material has `render_priority` 1, so in fill
mode it is blended over the voids and solid behind it instead of hiding them.

**Outside view preset.** To judge the grammar as a whole, look at a fixed
region from outside: turn `follow_camera` off (the region stays at `center`,
default `(0, 0, 0)`), set `radius` 3 and `fill` on, and fly to position
`(-300, 260, -300)`, yaw 0.79, pitch -0.48. That is the pose of the
before/after screenshots in [[sector-skeleton-and-walkable-graph]]; with
`show_stratum` off only the voids and solid remain.

With `fill` on and stratum hidden, the view from inside often shows large
black shapes framed by solid boxes. They are not faces rendered black: the
line of sight passes through hidden stratum sectors out of the drawn region,
so the background colour shows through. The wireframe default does not have
this effect.

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

Almost all of the cold time is `sector_type` in GDScript. With
`follow_camera` off the region stays where it is, so the camera can fly out
and look at it from outside.

The panel's `viewer` section holds `radius`, `show_stratum`, `fill` and
`follow_camera`; below it one `grammar …` section per `@export_group` of
`SectorGrammar`, generated by `ParamRegistry.add_object_exports` ([[tweak-ui]]),
so a new grammar export shows up without touching the panel. The seed comes
from `WorldState` and the seed row (R picks a random one). The legend below
the HUD lists each type's colour and count in the region, the centre sector,
the radius and the last refresh time; H hides it with the HUD.

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
