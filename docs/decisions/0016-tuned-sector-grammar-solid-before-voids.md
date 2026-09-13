---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/78
  - "[[sector-skeleton-and-walkable-graph]]"
  - "[[0015-hashed-multi-scale-sector-grammar]]"
---

# Tuned Sector Grammar: Solid Before Voids

> [!summary]
> Solid walls and floors now win over cavities and shafts, close in large
> panels instead of block by block, and shafts run from one floor to the
> next. Measured over random 5³ regions, solid now splits space into 2.4
> separate blocks on average (was 1.05) while shafts still span about 4
> sectors, and the grammar stays a pure hash.

## Context

From outside the first grammar looked like noise. Issue #78 set measurable
targets: shafts at least 3 sectors tall on average, and at least 2 non-solid
components per 5³ region. With voids ranking above solid, and each 5-sector
block closing its own wall, no parameter set reached 2 components without
turning walls into a closed lattice.

## Decision

- Precedence chasm > solid > cavity > shaft > stratum.
- Separate wall and floor grids (6 and 4 sectors); each plane closes in
  square panels (12 and 24 sectors) with probability 0.6 and 0.85.
- Shafts fill floor layers, keyed per column and group of `shaft_layers` = 3
  layers with probability 0.12; `shaft_segment`, `shaft_min_len` and
  `shaft_max_len` are removed and salts 101, 102 retired.
- Cavities per 4³ cell, boxes 3 to 4, probability 0.15; chasms 32 to 96
  sectors tall in 96-sector bands.
- `mise run skeleton-stats` guards both targets in `check`.

## Consequences

- About 38 % of sectors are solid, and regions are separated by design, so
  the walkable graph must tunnel through solid or count connectivity per
  open boundary (open question in [[sector-skeleton-and-walkable-graph]]).
- Strata spread wider than tall; the tuning numbers and before/after
  screenshots are in [[sector-skeleton-and-walkable-graph#Tuning]].
- No cellular pass is needed for now.

## Links

- Issue #78; epic #75. Code: [[skeleton]].
