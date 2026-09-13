---
tags: [glossary]
status: current
---

# Glossary

Plain-language definitions of the jargon used in this vault and in the code:
world structure, procedural generation, rendering, Godot and our workflow.
Entries are alphabetical and short on purpose. Where a term has a specific
meaning here, an "In this project" line says where it shows up; "See also"
points to the note that goes deeper. Names in plain text (not links) are notes
that are planned but not written yet. The main sources are
[[MEGASTRUCTURE_CONCEPT]], [[PLAN_0.1.0]], [[RESEARCH_WFC]] and
[[hash_vectors]].

## A

### AC-3

A classic way to enforce arc consistency: whenever a cell's domain shrinks,
recheck its neighbours and remove options they can no longer support, repeating
until nothing changes. It needs no bookkeeping beyond the domains themselves.

In this project: the recommended propagator for the WFC solver, with domains
stored as bitsets.

See also: [[RESEARCH_WFC]], Propagation, AC-4.

### AC-4

A faster variant of AC-3 that keeps a count of how many supporting options
each option has in each direction, so a removal only touches the affected
counters. It is quicker per step but needs a large table of counters.

In this project: considered and set aside for GDScript because of memory; a
candidate for a native port.

See also: [[RESEARCH_WFC]], AC-3.

### Adjacency table

A precomputed lookup that says, for each tile and each of the six directions,
which tiles may sit next to it. It is derived from socket matching once when
the tileset loads.

In this project: planned as `allowed[dir][tile]`, a bitset per entry stored in
a `PackedInt64Array`.

See also: [[RESEARCH_WFC]], Socket.

### ADR

Architecture Decision Record: a short, dated note that records one design
decision, the options considered and why one was picked. A series of them forms
a decision log.

In this project: the vault's planned Decisions log uses this format; the
shared integer hash decision in [[PLAN_0.1.0]] is an early example.

See also: Decisions log (planned).

### Air tile

The tile that means "empty space". It is an ordinary tile whose sockets all
match other empty faces.

In this project: one of the two base tiles, with solid, of the planned tileset.

See also: [[RESEARCH_WFC]], Solid tile.

### Albedo

The base colour of a surface: the fraction of light it reflects, before any
lighting is applied.

In this project: concrete (~0.52) and dark metal (~0.32) are the two
materials; see `concrete_albedo` and `metal_albedo` in
[surface.gdshaderinc](../shaders/include/surface.gdshaderinc).

See also: [[MEGASTRUCTURE_CONCEPT]].

### Ambient occlusion

A darkening of creases, corners and crevices, where surrounding geometry
blocks light arriving from most directions. It adds a strong sense of form at
low cost.

In this project: the ray marcher samples the distance field a few times along
the surface normal (`ao_taps`, `ao_step`); see
[surface.gdshaderinc](../shaders/include/surface.gdshaderinc).

See also: [[PLAN_0.1.0]].

### Arc consistency

A property of a constraint problem: every remaining option in every cell has
at least one compatible option in each neighbouring cell. Enforcing it removes
options that can never be part of a solution.

See also: AC-3, AC-4, Propagation.

### Autoload

A Godot script or scene that the engine creates at startup and keeps alive
globally, reachable by name from anywhere.

In this project: deliberately avoided for the world seed, because autoloads do
not exist in headless `--script` runs; `WorldState` uses static members
instead ([world_state.gd](../scripts/world_state.gd)).

## B

### Backtracking

When a solver hits a dead end, undoing recent choices and trying different
ones instead of starting over. It is more robust but costs time and memory.

In this project: explicitly not used; the solver restarts with a new sub-seed
instead.

See also: [[RESEARCH_WFC]], Restart.

### Bitset

A row of bits where each bit stands for one item, stored in plain integers.
Set operations become fast bitwise AND and OR on whole words.

In this project: a cell's domain is a bitset over tiles, two 64-bit ints for
up to ~128 tiles.

See also: [[RESEARCH_WFC]].

### Branch workflow

The rule that every issue is worked on in its own branch named
`<number>-<slug>`, merged into `develop` by pull request after a rebase.

In this project: enforced by GitHub branch protection (issue #25).

See also: [[PLAN_0.1.0]], Worktree.

### Bridge

A span crossing a void. In the chasm, a slab or tube reaching from one facade
to the other, some broken in the middle; in the walkable graph, an edge type
across shafts and cavities.

In this project: `chasm_bridges` in
[chasm.gdshaderinc](../shaders/include/chasm.gdshaderinc).

See also: [[MEGASTRUCTURE_CONCEPT]].

## C

### Cable

A thin hanging cylinder, usually drawn as a separate decorative layer rather
than a structural element.

In this project: vertical cables in the chasm shader. Whether cables become
tiles later is open; [[RESEARCH_WFC]] suggests a separate decoration pass.

See also: [[MEGASTRUCTURE_CONCEPT]], Decay pass.

### CanvasLayer

A Godot node that draws 2D content (UI) on its own layer above or below the 3D
view.

In this project: the HUD and the tweak panel are CanvasLayers, hidden while a
screenshot is captured ([hud.gd](../scripts/ui/hud.gd)).

### Catwalk

A narrow walkway running along a shaft wall.

In this project: an edge type in the walkable graph and a planned tile.

See also: [[MEGASTRUCTURE_CONCEPT]].

### Cavity

A rare, enormous void spanning several sectors, walled by stratified cliff
faces.

In this project: one of the five sector types.

See also: [[MEGASTRUCTURE_CONCEPT]], Sector.

### Cell

One box of a regular grid. The word is used at several scales: a 2 m voxel in
the fill layer, and larger hashing cells (for example one bridge per bridge
cell) in the shaders.

See also: [[hash_vectors]], Voxel.

### Chasm

A very rare sector type: a long vertical canyon, about 280 m wide, with
stratified facades on both sides.

In this project: the subject of milestone 0.1.0, ported from
`megastructure-chasm.html` into
[chasm.gdshaderinc](../shaders/include/chasm.gdshaderinc).

See also: [[MEGASTRUCTURE_CONCEPT]], [[PLAN_0.1.0]].

### Chebyshev distance

Distance measured as the largest difference along any one axis, so the set of
points within distance R forms a cube rather than a sphere.

In this project: used to decide which sectors are within streaming radius R.

See also: [[RESEARCH_WFC]].

### CI

Continuous Integration: automated checks run on every pull request before it
can merge.

In this project: GitHub Actions runs `mise run check`.

See also: [[PLAN_0.1.0]], mise task.

### ConcavePolygonShape3D

A Godot collision shape made of arbitrary triangles (a "trimesh"). Slow to test
against, but fine for static geometry.

In this project: planned as one merged collision shape per sector, built on a
worker thread.

See also: [[RESEARCH_WFC]], [[MEGASTRUCTURE_CONCEPT]].

### Contradiction

The state where some cell has no tile left that fits its neighbours, so the
current attempt cannot finish.

In this project: handled by restarting the sector with a new sub-seed, then by
all-solid degradation.

See also: [[RESEARCH_WFC]], Restart.

## D

### Debug view

An alternate shader output that shows internal data (step counts, depth,
normals, material ids) instead of the lit image.

In this project: the `debug_view` uniform in
[raymarch_world.gdshader](../shaders/raymarch_world.gdshader).

### Decay pass

A step after tile placement that removes a hashed share of columns and wall
segments and adds cables, giving "repetition with decay".

See also: [[MEGASTRUCTURE_CONCEPT]].

### Depth buffer

A per-pixel record of how far away the nearest drawn surface is, used so that
nearer objects hide farther ones.

In this project: the ray-march shader writes `DEPTH`, so ordinary Godot meshes
intersect correctly with the ray-marched world.

See also: [[PLAN_0.1.0]], Reversed-Z.

### Determinism

Getting exactly the same result every time from the same inputs, on every
machine. It lets the world be regenerated instead of stored.

In this project: every decision is a pure function of (seed, cell
coordinates); randomness comes only from the shared integer hash, never from
`RandomNumberGenerator`.

See also: [[MEGASTRUCTURE_CONCEPT]], [[RESEARCH_WFC]], Hash.

### Domain

The set of tiles still possible for one cell. Solving shrinks domains until
each holds exactly one tile.

See also: [[RESEARCH_WFC]], Wave.

### Domain restriction

Narrowing a cell's domain to a family of tiles before solving, rather than
fixing it to one tile. The solver can still choose within the family.

In this project: how walkable-graph cells will be pre-collapsed, for example
`{floor, floor+column, doorway}` for corridor cells.

See also: [[RESEARCH_WFC]], Pre-collapsed cell.

## E

### Edge rasteriser

The planned step that turns walkable-graph edges into per-cell domain
restrictions, the only input the fill solver takes from the graph.

See also: [[RESEARCH_WFC]] (Epic B, B4).

### Emissive

A material that gives off its own light, visible even in darkness.

In this project: the rare warm-lit facade openings.

See also: [[MEGASTRUCTURE_CONCEPT]].

### Entropy

In WFC, a measure of how undecided a cell is, based on how many tiles remain
and their weights (Shannon entropy). Picking the lowest-entropy cell first is
Gumin's original heuristic.

In this project: replaced by minimum remaining values, with Shannon kept
behind a flag.

See also: [[RESEARCH_WFC]], Minimum remaining values.

### Epic

A large GitHub issue that groups related smaller issues, its sub-issues, into
one piece of work.

In this project: epics for 0.1.0 are listed in [[PLAN_0.1.0]]; the design
wiki is epic #55.

See also: Milestone.

### Epsilon

A small tolerance value. In ray marching, how close a ray must get to a
surface to count as a hit, or how far apart to sample when estimating a
normal.

In this project: `hit_epsilon` and `normal_epsilon` in
[raymarch_world.gdshader](../shaders/raymarch_world.gdshader).

### Exposure

A brightness multiplier applied before tone mapping, like a camera's exposure
setting.

In this project: the `exposure` uniform in
[post.gdshaderinc](../shaders/include/post.gdshaderinc).

## F

### Facade
The stratified wall face of a chasm: a ledge at every 6 m stratum, a heavy
deck every 30 m, buttresses (vertical ribs) every 40 m, recessed terraces and
punched openings.

In this project: `ledge_*`, `deck_*`, `buttress_*` and `terrace_*` uniforms in
[chasm.gdshaderinc](../shaders/include/chasm.gdshaderinc).

See also: [[MEGASTRUCTURE_CONCEPT]], Chasm.

### Face-first boundary solve

The planned scheme for sector borders: solve shared edges first, then shared
faces, then each sector's interior. Both neighbours compute the same face
independently, so sectors can be generated in any order.

See also: [[RESEARCH_WFC]].

### Fill

The third and finest generation layer: placing tiles inside each sector with
WFC, constrained by the walkable graph.

See also: [[MEGASTRUCTURE_CONCEPT]], Skeleton, Walkable graph.

### Film grain

Subtle random noise added to each frame to mimic photographic film and break
up smooth gradients.

In this project: `grain_amount` and `grain_fps` in
[post.gdshaderinc](../shaders/include/post.gdshaderinc), off by default
because it flickers at half render resolution
([[0013-film-grain-off-by-default]]).

### Fog

Blending distant surfaces towards a fog colour, so depth and scale read and far
geometry can be cheap. Exponential fog thickens smoothly with distance.

In this project: the shader fog is exponential and graded by view direction,
brighter looking up than looking down (`fog_color_up`, `fog_color_down`).

See also: [[MEGASTRUCTURE_CONCEPT]].

### Forward+

One of Godot 4's renderers, needed for volumetric fog and SDFGI.

In this project: the renderer the project uses.

See also: [[MEGASTRUCTURE_CONCEPT]].

### Free-fly camera

A camera that moves freely through space, ignoring gravity and collision.

In this project: mouse look plus WASD and Q/E, matching the prototype's
controls ([free_fly_camera.gd](../scripts/free_fly_camera.gd)).

See also: [[PLAN_0.1.0]].

### Fullscreen quad

A single rectangle covering the whole screen, used as a canvas for a shader
that computes every pixel itself.

In this project: a `QuadMesh` pinned to the near plane carries the ray-march
shader.

See also: [[PLAN_0.1.0]].

## G

### GDExtension

Godot's mechanism for adding native code (C++, Rust) to a project without
rebuilding the engine.

In this project: the planned escape hatch if the GDScript solver takes more
than about 1 s per sector.

See also: [[RESEARCH_WFC]].

### Grammar

A set of rules for choosing sector types, with biases such as "shafts continue
vertically" and "strata spread horizontally".

In this project: a pure hashed function `Skeleton.sector_type(seed, cell)`
whose rules are decided on cells coarser than a sector, with parameters in a
`SectorGrammar` resource ([skeleton.gd](../scripts/world/skeleton.gd)).

See also: [[MEGASTRUCTURE_CONCEPT]], [[sector-skeleton-and-walkable-graph]].

### GridMap

A Godot node that places meshes from a library on a 3D grid, with built-in
collision. Quick to set up, but it does not scale well to large tilesets.

In this project: planned for the first walkable sector, then replaced by
MultiMeshInstance3D.

See also: [[RESEARCH_WFC]], MeshLibrary.

### Grime

Hashed variation that darkens and dirties surfaces at fine and coarse scales.

In this project: `grime_*` uniforms in
[surface.gdshaderinc](../shaders/include/surface.gdshaderinc).

## H

### Hash

A function that scrambles its input into a number that looks random but is
always the same for the same input.

In this project: one integer hash of (seed, cell, salt), implemented
bit-identically in [hash.gdshaderinc](../shaders/include/hash.gdshaderinc),
[hash.gd](../scripts/hash.gd) and the HTML prototypes. `hash3_u` returns the
32-bit value, `hash3` a float in [0, 1).

See also: [[hash_vectors]], PCG, Salt, Seed.

### Hash vectors

A table of known inputs and expected hash outputs that every implementation
must reproduce exactly.

In this project: produced by `mise run hash-vectors`.

See also: [[hash_vectors]].

### Headlight

A light attached to the camera, lighting what the player looks at.

In this project: a warm point light with inverse-square falloff
(`headlight_*` in [lighting.gdshaderinc](../shaders/include/lighting.gdshaderinc)).

See also: [[MEGASTRUCTURE_CONCEPT]].

### HUD

Heads-up display: an on-screen overlay of status information.

In this project: shown on start with FPS, frame time, camera pose, seed and a
controls line; H (or F1) toggles it, leaving a dimmed "H: HUD   Tab: panel"
hint, and P (or F12) saves a screenshot without it
([hud.gd](../scripts/ui/hud.gd)).

See also: [[PLAN_0.1.0]].

### Hysteresis

Using different thresholds for switching on and off, so a value hovering near
the limit does not flicker between states.

In this project: sectors load within radius R and unload only beyond R+1.

See also: [[MEGASTRUCTURE_CONCEPT]], Streaming.

## I

### Impostor

A cheap stand-in shown instead of detailed geometry at a distance, such as a
box with the rough silhouette of a sector.

See also: [[MEGASTRUCTURE_CONCEPT]], LOD.

## K

### Key light

The main light in a scene, setting the dominant direction of shadows.

In this project: a directional light with soft shadows in the chasm shader
(`key_*` in [lighting.gdshaderinc](../shaders/include/lighting.gdshaderinc)).

### Kruskal's algorithm

A method for building a spanning tree: sort candidate edges by weight and add
each one unless it would close a loop.

In this project: planned for the walkable graph, with hashed edge weights.

See also: [[RESEARCH_WFC]], Spanning tree, Union-find.

## L

### LOD

Level of detail: showing simpler versions of objects as they get farther away.

In this project: planned as full tiles near the player, a sector impostor
beyond ~2 sectors and nothing beyond ~5, using visibility ranges.

See also: [[MEGASTRUCTURE_CONCEPT]], [[RESEARCH_WFC]], Impostor.

### Lower bound

For a distance field, a value that may underestimate but never overestimates
the true distance to the nearest surface. Ray marching stays safe only if the
field is a lower bound, otherwise rays step through walls.

In this project: the reason cut-outs such as openings are built carefully in
[chasm.gdshaderinc](../shaders/include/chasm.gdshaderinc), and why
`step_scale` exists.

See also: Signed distance field.

## M

### MeshLibrary

A Godot resource holding the meshes (and collision) a GridMap can place.

See also: [[RESEARCH_WFC]], GridMap.

### Milestone

A GitHub grouping of issues that together form one release step, such as
0.1.0 or 0.2.0.

See also: [[PLAN_0.1.0]], Epic.

### Minimum remaining values

A heuristic that solves next the cell with the fewest options left (MRV).
It needs only integer counts, so it is exactly reproducible everywhere.

In this project: the recommended cell choice, with a hashed tie-break. A fixed
row-by-row (scanline) order is the simpler alternative.

See also: [[RESEARCH_WFC]], Entropy.

### mise task

A named command defined in `mise.toml` and run with `mise run <name>`.

In this project: all build, run, check and export automation lives in mise
tasks, for example `check`, `run`, `hash-vectors` and `preset-check`.

See also: [[PLAN_0.1.0]].

### Model synthesis

Paul Merrell's procedural method, closely related to WFC. It starts from a
trivially valid world and modifies it one small block at a time with fixed
borders, which scales to large outputs.

In this project: the sector is treated as one such block.

See also: [[RESEARCH_WFC]], Wave Function Collapse.

### MultiMesh

A Godot resource that draws many copies of one mesh in a single draw call, each
with its own transform.

See also: [[RESEARCH_WFC]], MultiMeshInstance3D.

### MultiMeshInstance3D

The Godot node that puts a MultiMesh into the scene.

In this project: planned as one per (tile mesh, sector), filled from a buffer
built on a worker thread.

See also: [[MEGASTRUCTURE_CONCEPT]], [[RESEARCH_WFC]].

## N

### Near and far plane

The closest and farthest distances a camera renders. Anything outside that
range is clipped.

In this project: the ray march starts at the near plane; misses are written at
the far plane ([raymarch.gdshaderinc](../shaders/include/raymarch.gdshaderinc)).

See also: Reversed-Z.

### Normal

The direction pointing straight out of a surface at a point. Lighting depends
on it.

In this project: estimated from the distance field's gradient using
`normal_epsilon`.

## O

### Observation

The WFC step that picks one cell and collapses it to a single tile, before
propagation spreads the consequences.

See also: [[RESEARCH_WFC]], Propagation.

### Occlusion culling

Skipping objects hidden behind other objects so they are not drawn at all.

In this project: a candidate for interiors, using an `ArrayOccluder3D` per
sector.

See also: [[RESEARCH_WFC]].

### Opening

A window-like hole punched into a facade, about half present and a few percent
lit.

In this project: `opening_*` uniforms in
[chasm.gdshaderinc](../shaders/include/chasm.gdshaderinc).

### Overlapping model

The WFC variant that learns small patterns from an example image or volume and
reproduces them. It produces per-pixel labels, not tile placements.

In this project: rejected in favour of the simple-tiled model.

See also: [[RESEARCH_WFC]].

## P

### Parameter registry

The code that discovers every shader uniform at runtime and describes it (name,
group, range, default) so the tweak panel can be built automatically.

In this project: [param_registry.gd](../scripts/ui/param_registry.gd).

See also: [[PLAN_0.1.0]].

### Parapet

A low wall around a floor opening or edge that keeps people from falling.

In this project: 1.1 m tall around every shaft opening.

See also: [[MEGASTRUCTURE_CONCEPT]].

### PCG

A family of small, fast pseudo-random functions. We use a single PCG-style
permutation of a 32-bit word as the building block of the hash.

See also: [[hash_vectors]], Hash.

### Pillar

A free-standing column in the chasm, radius 4 to 12 m, with a ring at every
deck level.

### Pixel parity

Getting the same image, pixel for pixel as far as practical, as a reference
renderer for the same inputs.

In this project: the 0.1.0 goal against the chasm HTML prototype for the same
seed and camera pose.

See also: [[PLAN_0.1.0]].

### Portal

A point on the shared face between two adjacent non-solid sectors where the
walkable graph crosses from one to the other.

See also: [[MEGASTRUCTURE_CONCEPT]], [[RESEARCH_WFC]].

### Pre-collapsed cell

A cell whose options are fixed or narrowed before the solver runs, for example
along a path or at a sector boundary.

See also: [[MEGASTRUCTURE_CONCEPT]], Domain restriction.

### Preset

A saved snapshot of every tweakable parameter, the seed and the camera pose.

In this project: JSON files under `user://presets`, with a built-in
"Prototype defaults" preset ([preset_store.gd](../scripts/ui/preset_store.gd)).

See also: [[PLAN_0.1.0]].

### Propagation

After a cell's options shrink, removing now-impossible options from its
neighbours, then theirs, until the grid is consistent again.

See also: [[RESEARCH_WFC]], AC-3.

### Prototype

In this project, one of the two HTML pages (`megastructure.html` interior,
`megastructure-chasm.html` exterior) that define the look. In the tileset
sense, a hand-authored tile before its rotations are generated.

See also: [[MEGASTRUCTURE_CONCEPT]], [[RESEARCH_WFC]].

## R

### Ray marching

Rendering by stepping along the ray through each pixel and asking a distance
function how far the nearest surface is, until a surface is hit.

In this project: the throwaway 0.1.0 renderer
([raymarch_world.gdshader](../shaders/raymarch_world.gdshader)).

See also: [[PLAN_0.1.0]], Sphere tracing.

### Render scale

Rendering the 3D view at a fraction of the window resolution, then upscaling.

In this project: 0.5 by default (`rendering/scaling_3d/scale`).

See also: [[PLAN_0.1.0]].

### Restart

Discarding a failed solve and starting again with a different sub-seed.

In this project: capped at a few attempts per sector, then all-solid
degradation fills the rest.

See also: [[RESEARCH_WFC]], Contradiction.

### Reversed-Z

A depth convention where 1 means the near plane and 0 the far plane, which
gives better depth precision at a distance.

In this project: Godot 4.3+ uses it, so the shader writes 0 for misses.

See also: [[PLAN_0.1.0]], Depth buffer.

### Rotation expansion

Generating the rotated copies of each hand-authored tile automatically,
turning its sockets along with it.

See also: [[RESEARCH_WFC]], Symmetry tag.

## S

### Salt

An extra number mixed into a hash so that different decisions about the same
cell get independent values.

In this project: for example salt 31 for "is there a bridge here" and 32 for
its offset.

See also: [[hash_vectors]].

### SDFGI and VoxelGI

Two Godot global illumination techniques that simulate light bouncing between
surfaces. SDFGI works with geometry created at runtime but is expensive;
VoxelGI must be baked and leaks through thin walls.

In this project: no GI at first; SDFGI is to be evaluated in the look pass.

See also: [[RESEARCH_WFC]].

### Sector

The coarse building block of the world, a 48 m cube with one type: stratum,
shaft, cavity, solid or chasm.

In this project: indexed by `Vector3i`; the type comes from
`Skeleton.sector_type`.

See also: [[MEGASTRUCTURE_CONCEPT]], Skeleton.

### Seed

The one number that determines the entire world. Change it and everything
regenerates differently.

In this project: a uint32 held by `WorldState.seed`, pushed into the shader by
[seed_uniform.gd](../scripts/seed_uniform.gd).

See also: [[hash_vectors]], Determinism.

### Shader include

A file of shader code pulled into another shader with `#include`, so shared
functions are written once.

In this project: `.gdshaderinc` files under
[shaders/include](../shaders/include/).

### Shaft

A vertical void 4 to 16 m wide that tends to continue up and down through
several sectors.

See also: [[MEGASTRUCTURE_CONCEPT]], Sector.

### Signed distance field

A function that returns, for any point, the distance to the nearest surface:
positive outside, negative inside (SDF). Shapes are combined with simple
operations like min and max.

In this project: primitives in
[sdf.gdshaderinc](../shaders/include/sdf.gdshaderinc), the chasm in
[chasm.gdshaderinc](../shaders/include/chasm.gdshaderinc).

See also: [[PLAN_0.1.0]], Lower bound, Ray marching.

### Simple-tiled model

The WFC variant that works with hand-made tiles and rules about which tiles may
be neighbours.

In this project: the chosen model for the fill layer.

See also: [[RESEARCH_WFC]], Overlapping model.

### Skeleton

The first and coarsest generation layer: assigning a type to every sector.

See also: [[MEGASTRUCTURE_CONCEPT]], Fill, Walkable graph.

### Socket

A label on each face of a tile. Two tiles may be neighbours when the sockets on
their touching faces match, so no pair rules are written by hand.

See also: [[MEGASTRUCTURE_CONCEPT]], [[RESEARCH_WFC]], Symmetry tag.

### Soft shadow

A shadow with a gradual edge (penumbra) instead of a hard one.

In this project: estimated by marching towards the light and tracking how
closely the ray grazes geometry (`shadow_softness`).

See also: [[PLAN_0.1.0]].

### Solid tile

The tile that means "impassable mass". A universal solid tile fits next to
anything, so a solve can always fall back to it.

In this project: one of the five sector types is also called solid.

See also: [[RESEARCH_WFC]], Universal tile.

### Spanning tree

A set of edges that connects every node of a graph with no loops.

In this project: guarantees all non-solid sectors in a region are connected;
extra hashed edges then add loops.

See also: [[MEGASTRUCTURE_CONCEPT]], Kruskal's algorithm.

### Sphere tracing

The standard form of ray marching: step forward by exactly the distance the
field reports, since nothing can be closer than that.

In this project: steps are shortened by `step_scale` for safety.

See also: Ray marching, Lower bound.

### Stratum

A horizontal habitable layer with a 6 m pitch; also the default sector type
made of such layers. Plural: strata.

See also: [[MEGASTRUCTURE_CONCEPT]].

### Streaming

Loading world pieces near the player and unloading distant ones while moving.
Because generation is deterministic, unloading loses nothing; a small cache of
solved sectors avoids re-solving when walking back.

See also: [[MEGASTRUCTURE_CONCEPT]], [[RESEARCH_WFC]], Hysteresis.

### Sub-seed

A seed derived from the main seed plus an attempt counter, so a restart gets
different yet still reproducible random choices.

See also: [[MEGASTRUCTURE_CONCEPT]], Restart.

### Symmetry tag

A marker on a socket saying whether its face profile is mirror-symmetric (`s`)
or a flipped counterpart (`f`), plus a rotation index on vertical sockets.

See also: [[RESEARCH_WFC]], Socket.

## T

### Tile

One hand-authored building module (floor slab, wall, stair) that fills one
voxel cell.

See also: [[MEGASTRUCTURE_CONCEPT]], Tileset.

### Tile vocabulary

The set of structural elements and their proportions taken from the prototypes,
which defines the look.

See also: [[MEGASTRUCTURE_CONCEPT]].

### Tile weight

How strongly the solver prefers a tile when choosing. Heavy weights on boring
tiles keep the world mostly regular.

See also: [[MEGASTRUCTURE_CONCEPT]], [[RESEARCH_WFC]].

### Tileset

The complete collection of tiles, with their sockets, weights and rotations.

In this project: planned as a Godot `Resource`, checked by a
`tiles-check` mise task (validation of sockets, reachability and placement
counts).

See also: [[RESEARCH_WFC]].

### Tone mapping

Squeezing the wide range of computed light values into the range a screen can
show.

In this project: an exposure tone map with highlights allowed to clip
([post.gdshaderinc](../shaders/include/post.gdshaderinc)).

See also: [[MEGASTRUCTURE_CONCEPT]].

### Tweak panel

The in-app panel for adjusting every shader constant live, with seed control,
presets and screenshots.

In this project: [tweak_panel.gd](../scripts/ui/tweak_panel.gd), built from
the parameter registry.

See also: [[PLAN_0.1.0]].

## U

### Uniform

A shader input that stays the same for every pixel in a frame and can be
changed from outside the shader.

In this project: every prototype constant is a uniform whose default is the
prototype value.

See also: [[PLAN_0.1.0]].

### Union-find

A data structure that tracks which items belong to the same group and merges
groups quickly. It answers "are these two connected?".

In this project: planned to verify that the walkable graph connects every
non-solid sector.

See also: [[MEGASTRUCTURE_CONCEPT]], Spanning tree.

### Universal tile

A tile compatible with every neighbour, acting as a pressure valve so the
solver can always complete.

See also: [[MEGASTRUCTURE_CONCEPT]], Solid tile.

## V

### Vignette

Darkening towards the edges of the image, like an old lens.

In this project: the `vignette` uniform in
[post.gdshaderinc](../shaders/include/post.gdshaderinc).

### Visibility range

A Godot node setting that shows a node only within a distance band, with
optional fade margins. It is the basis for manual LOD.

See also: [[RESEARCH_WFC]], LOD.

### Voxel

A cell of a 3D grid, the volume equivalent of a pixel.

In this project: 2 m voxels, 24³ per sector, in the fill layer.

See also: [[MEGASTRUCTURE_CONCEPT]].

## W

### Walkable graph

The second generation layer: a network of nodes and edges (corridors, stairs,
ladders, bridges, catwalks) that guarantees the world can be crossed on foot.
Also called the path graph.

See also: [[MEGASTRUCTURE_CONCEPT]], Portal.

### Wave

In WFC, the full state of the grid: the domain of every cell at once.

In this project: planned as one `PackedInt64Array` of bitsets.

See also: [[RESEARCH_WFC]], Domain.

### Wave Function Collapse

A procedural generation algorithm by Maxim Gumin (WFC). It fills a grid by
repeatedly fixing the most constrained cell and propagating what that rules
out for its neighbours.

In this project: the fill layer's solver, in the simple-tiled form.

See also: [[RESEARCH_WFC]], Model synthesis.

### WorkerThreadPool

Godot's shared pool of background threads for running tasks off the main
thread.

In this project: one task per sector, producing plain data that the main
thread turns into nodes.

See also: [[MEGASTRUCTURE_CONCEPT]], [[RESEARCH_WFC]].

### Worktree

A git feature that checks out another branch in a separate folder, so several
branches can be worked on side by side.

In this project: each issue branch lives in its own worktree.

See also: Branch workflow.
