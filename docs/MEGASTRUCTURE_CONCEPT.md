# Megastructure — concept and implementation plan

A generative, walkable rendering of a Blame!-style megastructure in Godot 4. Endless interior strata, vertical shafts, vast cavities, and open chasms between stratified facades. No gameplay for now: the deliverable is a world that generates itself, streams as you move, and can be explored on foot.

This document is the handoff from the concept phase. Two ray-marched HTML prototypes exist (`megastructure.html` interior, `megastructure-chasm.html` exterior) and define the look; their distance functions are the reference for the tile vocabulary below.

## 1. Design goals

- Interior space, not terrain. The world is solid mass with space carved out of it. Heightmaps and noise landscapes are the wrong tool.
- Verticality is the point. Shafts, drops, and strata visible as cliff faces. The player should regularly see hundreds of metres up and down.
- Repetition with decay. Nihei's texture is ~95 % identical structural modules and ~5 % anomalies: missing columns, collapsed slabs, cable growth, a single lit opening.
- Walkable by construction. Traversability is guaranteed by generation order, never by luck.
- Deterministic and unbounded. Every decision is a pure function of (seed, cell coordinates). Nothing is stored except the seed and the player's edits (none, for now).
- Scale is implied, not rendered. Fog, silhouettes, and a few human-scale anchors do most of the work; distant geometry can be cheap.

## 2. Architecture: three layers

Generation is split into layers with strictly decreasing scale. Each layer only reads the layer above it.

### 2.1 Skeleton (global structure)

A coarse 3D lattice of **sectors** (start with 48 m × 48 m × 48 m; the interior prototype used a 48 m shaft grid and 112 m cavity grid). Each sector gets a type from a hashed grammar:

| Type    | Rule of thumb                                                | Prototype analogue      |
| ------- | ------------------------------------------------------------ | ----------------------- |
| stratum | default; horizontal habitable layers, 6 m pitch              | slabs + column grid     |
| shaft   | vertical void 4–16 m wide, prefers to continue up/down       | `hs < 0.42` shaft cells |
| cavity  | rare, enormous void spanning several sectors                 | `hv < 0.14` cavities    |
| solid   | impassable mass                                              | implicit                |
| chasm   | very rare; a long vertical canyon with facades on both sides | the exterior prototype  |

Grammar bias: shafts continue vertically with high probability; strata spread horizontally; voids cluster; solid mass separates regions so you can't see everything at once. Implement as a pure function `sector_type(seed, ix, iy, iz)` first (hashed, no neighbour dependence); upgrade to a proper L-system / cellular pass only if the hashed version feels random rather than structured.

### 2.2 Walkable graph (connectivity)

Before any geometry is placed, generate a **path graph** through the sectors that are not solid:

- Nodes: sector portals (points on shared faces between adjacent non-solid sectors) plus one interior node per stratum sector.
- Edges: corridor, stair, ramp, ladder, bridge (across shafts and cavities), catwalk (along shaft walls).
- Guarantee: within any loaded region, all non-solid sectors are connected (spanning tree over sector adjacency, hashed edge selection so it's deterministic per region). Extra hashed edges add loops.
- Vertical edges are deliberately scarce and long: one stair or ladder per few strata. Blame! is about walking a long way.

Output per sector: a small list of edges with endpoints in local coordinates. This is the only thing the fill layer is allowed to treat as a hard constraint.

### 2.3 Fill (local geometry via WFC / model synthesis)

Each sector is filled on a voxel grid (start with 2 m cells → 24³ per sector; revisit if too slow) using the simple-tiled Wave Function Collapse model:

- Tiles are hand-authored meshes with a **socket ID per face** and a symmetry tag. Adjacency is socket equality, never hand-written pair rules.
- Cells on walkable-graph edges are **pre-collapsed** to floor / stair / bridge tiles. Cells in solid sectors are pre-collapsed to solid. Shared faces with an already-generated neighbour sector are pre-collapsed to that neighbour's boundary tiles.
- Tile weights heavily favour the boring tiles. A generic `solid` tile compatible with everything is the pressure valve against contradictions.
- On contradiction: restart the sector with a bumped sub-seed (deterministic). Backtracking is unnecessary at this scale.
- Decay pass after WFC: hashed deletion of columns and wall segments (≈10 % and ≈45 % respectively in the prototype), cable growth as a separate stochastic layer.

## 3. Tile vocabulary (from the prototypes)

Interior, in metres. These proportions are the look; keep them.

- Stratum pitch **6.0**, slab thickness **0.6**.
- Column grid **8.0**, square columns **1.1** wide. ~10 % removed per stratum.
- Wall grid **32.0**, walls **0.7** thick, doorways **2.2 × 3.2** every 8 m. ~45 % of 16 m wall segments removed → long corridors and half-open halls.
- Ceiling beams along one axis every **4.0**, 0.7 × 0.36.
- Pipe bundle hugging walls at 4.6 m height: radii 0.20 / 0.14 / 0.11 / 0.09.
- Shaft **4–16** m square, parapet 1.1 m tall and 0.14 thick around every floor opening.

Exterior (chasm), in metres:

- Chasm width **280**. Facades stratified at 6 m with a 1.2 m ledge, heavy deck every 30 m protruding 4.4 m, buttresses every 40 m (3.6 wide, 10 deep, ~25 % removed).
- Terrace cells of 60 m recessed 6–20 m in ~32 % of cells.
- Openings 5.2 × 3.4 punched 7 m deep on an 8 × 6 grid, 50 % present, ~4 % of those emissive warm.
- Free-standing pillars radius 4–12 with a ring every deck; bridges (slab 6 × 2.8 or tube r 3.5) every ~40 m vertically, 40 % broken; hanging cables r 0.12–0.37.

First tileset to author (~20 modules, rotations expand it): solid; floor slab; slab edge / shaft parapet; column (full stratum); wall straight; wall with doorway; wall end; beam segment; pipe run straight / corner / end; stair (one stratum, 3 m run); bridge segment; bridge broken end; catwalk along shaft wall; ladder; cavity wall (stratified cliff face); cable.

## 4. Look and lighting

- Near-black ambient. One warm point light on the player (the prototype's headlight: ~90 intensity, inverse-square). Optionally a cold, very faint top light in shafts and chasms so drops read.
- Exponential fog to near-black, coefficient ~0.018 interior, ~0.003 in chasms. Fog colour in chasms brightens slightly toward the up direction only.
- Post: mild film grain, vignette, exposure tone map with highlights allowed to clip. Low-ish internal resolution is fine and arguably better.
- Materials: two only at first — concrete (albedo ~0.52, hashed grime) and dark metal (albedo ~0.32, tight specular). Emissive warm for the rare lit opening.

## 5. Godot implementation notes

- Godot 4.x, Forward+ renderer (needed for volumetric fog and SDFGI; Mobile is a fallback).
- Generation on a `WorkerThreadPool`; never on the main thread. Sector results are handed back as tile placement lists.
- Placement: one `MultiMeshInstance3D` per tile type per sector. Do not instance thousands of nodes. `GridMap` is acceptable for the first weeks of prototyping, then replace.
- Collision: per sector, merge tile collision shapes into one `ConcavePolygonShape3D` on the worker thread; or use GridMap collision early on.
- Streaming: load sectors within radius R of the player, unload beyond R+1 (hysteresis). Because everything is deterministic, unloading is free.
- LOD: beyond ~2 sectors, replace tile geometry with a single low-poly "sector impostor" (a box with the sector's silhouette features) and rely on fog. Beyond ~5, nothing.
- Seed handling: one global `uint64` seed; every hash is `hash(seed, cell coords, salt)`. Reuse the prototype hash so the two prototypes and the Godot build produce the same sector layout for the same seed — useful for comparing the WFC output against the SDF reference.

## 6. Milestones

1. **Skeleton viewer.** `sector_type()` + a debug view that draws sector boxes colour-coded by type around a free-fly camera. Tune the grammar until it looks structured from the outside.
2. **Path graph.** Generate and draw the walkable graph as lines. Verify connectivity with a union-find check over a 5³ region. No geometry yet.
3. **WFC in one sector.** Author 8–10 tiles, run WFC with pre-collapsed path cells, place with MultiMesh, walk it with a capsule body. Iterate on tiles until one stratum sector feels like the interior prototype.
4. **Streaming.** Sector loading/unloading around the player, boundary constraints between sectors, thread pool.
5. **Shafts and cavities.** Add the vertical tiles (parapet, catwalk, ladder, bridge) and cavity cliff faces.
6. **Look pass.** Lighting, fog, post, LOD impostors. Compare against the HTML prototypes side by side.
7. **Chasm sector type.** Port the exterior prototype's facade grammar as a tileset.

## 7. Open questions

- Voxel resolution: 2 m cells keep WFC fast but limit pipe detail; pipes and cables may be a separate decoration pass rather than tiles.
- Whether the walkable graph should be generated per sector (fast, local) or per region of sectors (better long paths). Start per region of 3³.
- Stairs vs. ramps vs. ladders for vertical travel — what reads best, and what the capsule controller handles.
- Whether to keep an SDF version of each sector for cheap distant rendering (ray-marched impostors) instead of mesh LODs.
