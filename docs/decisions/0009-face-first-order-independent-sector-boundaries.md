---
tags:
  - decision
status: proposed
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/pull/42
  - https://github.com/seletz/megastructure/issues/92
  - "[[RESEARCH_WFC]]"
  - "[[0010-near-universal-solid-tile-with-seeded-restarts]]"
---

# Face-First, Order-Independent Sector Boundaries

> [!note] Proposed, implemented and measured
> Built in #92 as [[face-first-boundaries]]. The mechanism does what it
> promises (measurements below). It stays proposed because what it can
> produce on the current tileset depends on two open decisions, #162 (what a
> face is) and #163 (which tiles border cells may hold), and no real sector
> with records solves yet (#159).

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

## Measurements (#92)

`mise run boundary-check` on the placeholder tileset:

- **Order independence:** 100 of 100 random faces at seeds 0 to 4 (with
  real records) are identical whether computed from the sector or from its
  neighbour on a separate instance.
- **Seams:** 50 of 50 unconstrained 8³ adjacent pairs and 2 of 2 24³ pairs
  solve with no socket mismatch across the shared face or inside. Of 50
  real 24³ pairs whose records build, none solves; the solved-pair check is
  vacuous there.
- **Cost of a cold 24³ sector:** 8 corners 10 ms, 12 edges 62 ms, 6 faces
  522 ms, interior 2.55 s. On the same run a plain 24³ attempt took
  about 2.1 s, so the borders add about a fifth.
- **Over-constraint:** it is real, but it comes from the tileset, not from
  the scheme. Without a rule on border tiles, 4 of 4 unconstrained 24³
  sectors failed: wall and slab-edge chains, and rock ending at different
  heights in independently keyed top and bottom layers. The open boundary
  rule of #163 makes every unconstrained sector solvable, but it keeps rock
  off the borders. A solid tile alone does not rescue it: solid does not
  accept air.

## Consequences

- Load order does not matter; unloading is just freeing nodes; sectors can
  be solved on parallel workers.
- Fixing all six faces can over-constrain the interior. A universal solid
  tile guarantees a solution exists
  ([[0010-near-universal-solid-tile-with-seeded-restarts]]); faces weighted
  toward solid and air keep interesting geometry inside sectors. Measured,
  the solid tile is not enough on the placeholder tileset; see above and
  #163.

## Links

- PR #42; [[RESEARCH_WFC]], "1. Algorithm choice" and "Decisions to make",
  item 1.
- Implementation: #92, [[face-first-boundaries]]; open follow-ups #162,
  #163.
- Related: [[0004-shared-integer-hash-replaces-float-hash]],
  [[0008-godot-native-rendering-for-the-generative-world]].
