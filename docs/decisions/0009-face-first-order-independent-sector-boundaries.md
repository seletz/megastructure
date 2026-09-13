---
tags:
  - decision
status: proposed
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/pull/42
  - "[[RESEARCH_WFC]]"
  - "[[0010-near-universal-solid-tile-with-seeded-restarts]]"
---

# Face-First, Order-Independent Sector Boundaries

> [!note] Proposed
> Recommended by the research, not yet decided. It must be settled before the
> solver work starts, because it shapes streaming.

> [!summary]
> The world is filled one 48 m sector at a time, and neighbouring sectors
> must fit together at their shared walls. We propose to compute each shared
> wall first, from the seed and its position alone, and only then fill the
> inside of each sector. Both neighbours then compute the same wall on their
> own, so sectors can be generated in any order, in parallel, and thrown away
> freely.

## Context

The tile solver fills a 24 × 24 × 24 grid per sector. Two ways to make
neighbours agree ([[RESEARCH_WFC]], section 1):

- **Copy from loaded neighbours:** simple, but a sector's content then
  depends on which neighbours happened to exist, breaking "every decision is
  a pure function of seed and coordinates" and making unloading costly.
- **Faces first:** solve the shared parts in a fixed order.

## Decision

Proposed: solve edges (lines shared by several sectors) first, then each 2D
face between two non-solid sectors, seeded by the shared hash and
pre-constrained at walkable-graph portals, then the interior with all six
faces fixed. This follows Merrell's model synthesis and Boris the Brave's
"infinite modifying in blocks".

## Consequences

- Load order does not matter; unloading is just freeing nodes; sectors can
  be solved on parallel workers.
- Fixing all six faces can over-constrain the interior. A universal solid
  tile guarantees a solution exists
  ([[0010-near-universal-solid-tile-with-seeded-restarts]]); faces weighted
  toward solid and air keep interesting geometry inside sectors.

## Links

- PR #42; [[RESEARCH_WFC]], "1. Algorithm choice" and "Decisions to make",
  item 1.
- Related: [[0004-shared-integer-hash-replaces-float-hash]],
  [[0008-godot-native-rendering-for-the-generative-world]].
