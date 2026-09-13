---
tags:
  - decision
status: proposed
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/pull/42
  - "[[RESEARCH_WFC]]"
  - "[[0009-face-first-order-independent-sector-boundaries]]"
---

# Near-Universal Solid Tile With Seeded Restarts, No Backtracking

> [!note] Proposed
> Recommended by the research, not yet decided.

> [!summary]
> A tile solver can paint itself into a corner where no tile fits a cell. We
> propose a "solid" tile that fits next to almost anything, so such dead ends
> are rare. When one happens, the sector is simply solved again with the next
> seed; after a few failures it falls back to solid mass around the walkable
> path. The solver never undoes individual choices.

## Context

In Wave Function Collapse a contradiction is a cell whose allowed tiles have
all been ruled out. If solid mass may border every tile, contradictions can
only arise between pre-constrained cells, and an all-solid fill is always a
valid answer ([[RESEARCH_WFC]], section 3). But a fully universal solid lets
stairs run into walls and bridges end in mass.

## Decision

Proposed:

- Solid accepts every neighbour except a handful of sockets: stair exits,
  bridge and catwalk ends, doorway floors.
- On contradiction, restart the sector with the next sub-seed (a salt bump),
  up to about 8 attempts.
- After that, keep the pre-constrained path cells, fill the rest from an
  all-solid state and log the sector.
- No backtracking. Revisit only if the fallback shows up often, which would
  point at a tileset problem.

## Consequences

- Every result stays a pure function of seed and sector.
- The player always gets a walkable path, even in a degraded sector.
- The solver stays small; a logged fallback flags tileset mistakes.

## Links

- PR #42; [[RESEARCH_WFC]], "3. Contradiction handling, entropy and
  propagation" and "Decisions to make", item 2.
- Related: [[0009-face-first-order-independent-sector-boundaries]],
  [[0011-typed-gdscript-solver-first]].
