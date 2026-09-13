---
tags:
  - plan
  - milestone/0.2.0
status: current
---

# Plan for milestone 0.2.0: cells and WFC with simplified geometry

> [!summary]
> The second milestone builds the generative world for real, in Godot's own
> scene machinery rather than the throwaway ray-marcher. It follows the three
> layers of the concept: a hashed **skeleton** that gives every 48 m sector a
> type, a **walkable graph** that guarantees you can get from sector to
> sector, and a **fill** that places tiles inside each sector with a Wave
> Function Collapse solver. Geometry stays deliberately crude: box-only
> placeholder tiles, one walkable sector first, then streaming around the
> player. Every random choice still comes from the shared integer hash, so a
> seed reproduces the world exactly.

The research behind this milestone is in [[RESEARCH_WFC]]; its section 7 is
the origin of the epics below. The terms are in the [[GLOSSARY]], the
algorithms in [[algorithms/README|Algorithm notes]].

## Scope

- **In:** sector grammar and viewer, walkable graph with a connectivity
  guarantee, a tile resource format with socket-based adjacency, a typed
  GDScript solver with seeded restarts, GridMap then MultiMesh placement with
  collision, a capsule you can walk with, worker-thread generation and
  streaming with hysteresis.
- **Out:** real tile art, lighting and look beyond what the placeholder
  needs, the interior prototype's decoration passes (pipes, cables), the
  chasm sector type in tiles. Those come after the world is walkable.

## Approach

**Skeleton first, as a pure function.** `sector_type(seed, cell)` is
neighbour-independent so any sector can be generated alone and in parallel,
yet reads as structured because each decision is keyed on a coarser cell than
the sector (columns for shafts, 3-sector blocks for cavities, panels for solid
mass). See [[0015-hashed-multi-scale-sector-grammar]] and
[[0016-tuned-sector-grammar-solid-before-voids]].

**Connectivity by construction.** Per 3-sector region, a spanning tree over
non-solid sectors plus hashed extra edges; portals on shared faces are chosen
by hash so both sides agree. The graph is rasterised into per-cell domain
restrictions, which is the only input the solver accepts from it.

**Sockets, not pair rules.** Tiles carry a socket id per face with symmetry
and rotation tags; adjacency bitsets are derived and validated by a task.

**Solver as model synthesis blocks.** Simple-tiled WFC per sector with a
near-universal solid tile, seeded restarts instead of backtracking, and
face-first boundary solving so sectors are order-independent. Typed GDScript
first; a native extension only if a benchmark says so
([[0009-face-first-order-independent-sector-boundaries]],
[[0010-near-universal-solid-tile-with-seeded-restarts]],
[[0011-typed-gdscript-solver-first]]).

**Godot-native placement.** GridMap for the first walkable sector, then one
MultiMeshInstance3D per tile mesh per sector plus one merged collision shape,
built from worker-thread output ([[0008-godot-native-rendering-for-the-generative-world]]).

## Epics

Each sub-issue is one branch and one pull request, with a changelog line and
the wiki notes it touches.

### [#75 Skeleton viewer](https://github.com/seletz/megastructure/issues/75) (done)

- [#76](https://github.com/seletz/megastructure/issues/76) `sector_type` and grammar parameters
- [#77](https://github.com/seletz/megastructure/issues/77) Sector box debug renderer
- [#78](https://github.com/seletz/megastructure/issues/78) Grammar tuning pass

### [#79 Walkable graph](https://github.com/seletz/megastructure/issues/79)

- [#80](https://github.com/seletz/megastructure/issues/80) Portals and interior nodes
- [#81](https://github.com/seletz/megastructure/issues/81) Spanning tree plus hashed loops
- [#82](https://github.com/seletz/megastructure/issues/82) Graph debug lines
- [#83](https://github.com/seletz/megastructure/issues/83) Edge rasteriser (the fill contract)

### [#84 Tileset and adjacency](https://github.com/seletz/megastructure/issues/84)

- [#85](https://github.com/seletz/megastructure/issues/85) Tile resource format
- [#86](https://github.com/seletz/megastructure/issues/86) Rotation expansion and adjacency derivation
- [#87](https://github.com/seletz/megastructure/issues/87) Tileset validation task
- [#88](https://github.com/seletz/megastructure/issues/88) Box-only placeholder tileset

### [#89 Solver](https://github.com/seletz/megastructure/issues/89)

- [#90](https://github.com/seletz/megastructure/issues/90) Solver core
- [#91](https://github.com/seletz/megastructure/issues/91) Pre-collapse and restart policy
- [#92](https://github.com/seletz/megastructure/issues/92) Face-first boundary solve
- [#93](https://github.com/seletz/megastructure/issues/93) Benchmark task

### [#94 Placement, walking and streaming](https://github.com/seletz/megastructure/issues/94)

- [#95](https://github.com/seletz/megastructure/issues/95) GridMap placement
- [#96](https://github.com/seletz/megastructure/issues/96) MultiMesh placement and merged collision
- [#97](https://github.com/seletz/megastructure/issues/97) Worker-thread sector jobs
- [#98](https://github.com/seletz/megastructure/issues/98) Streaming with hysteresis and LRU

Alongside the epics, the milestone also carries the design wiki
([#55](https://github.com/seletz/megastructure/issues/55), done) and tooling
such as the maintainer tasks and the offscreen screenshot task.

## Done when

- A capsule walks from portal to portal through a stratum sector at seed 0
  along the generated path, without falling through or getting stuck.
- Walking ten sectors in a line never shows a hole at a boundary, and memory
  returns to baseline on the way back.
- `mise run check` runs the histogram, stats, tileset validation, solver
  determinism and preset checks in CI, and `mise run wfc-bench` reports the
  per-sector solve time that decides whether a native solver is needed.
