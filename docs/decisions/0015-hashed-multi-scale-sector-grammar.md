---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/76
  - "[[sector-skeleton-and-walkable-graph]]"
  - "[[MEGASTRUCTURE_CONCEPT]]"
---

# Hashed Multi-Scale Sector Grammar

> [!summary]
> Every sector's type is a pure function of the seed and its coordinates,
> with no look at its neighbours. It still looks structured rather than like
> noise, because each rule is decided once for a group of sectors (a column
> segment, a 3 × 3 × 3 cube, a 5-sector block, a wide band) and then marks a
> whole run, box or wall of sectors inside that group.

## Context

The concept (section 2.1) asks for five sector types with biases: shafts
continue vertically, strata spread, voids cluster, solid mass separates
regions. It suggests starting with a hashed `sector_type(seed, ix, iy, iz)`
and moving to a cellular pass only if that looks random. A pass that reads
neighbours makes a type depend on evaluation order, which breaks streaming.

## Decision

- 48 m sectors indexed by `Vector3i`; `Skeleton.sector_type(seed, cell)`.
- Decisions keyed on coarser cells: shafts per `(ix, iz)` column segment
  with a hashed start and length; cavities per 3³-sector cube (144 m,
  replacing the prototype's 112 m) with a hashed box inside; solid walls and
  floors per 5³-sector block on band-aligned planes; chasms per wide `x`/`y`
  band with a long vertical extent.
- Fixed precedence: chasm > cavity > shaft > solid > stratum.
- One salt per decision, 100 to 133, documented in
  [[sector-skeleton-and-walkable-graph]].
- Parameters in a `SectorGrammar` resource with `@export` defaults.

## Consequences

- Any sector is computed alone, in any order, on any thread.
- Structure is limited to what coarse cells can express; the tuning pass
  (#78) decides whether a cellular pass is needed.
- Changing a default or a salt changes the world; the seed 0 histogram task
  ([[skeleton_histogram_seed0]]) makes that visible in review.

## Links

- Issue #76; epic #75; [[RESEARCH_WFC]], section 7, A1.
- Code: [[skeleton]]. Related: [[0004-shared-integer-hash-replaces-float-hash]].
