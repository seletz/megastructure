---
tags:
  - decision
status: accepted
date: 2026-09-14
links:
  - https://github.com/seletz/megastructure/issues/179
  - https://github.com/seletz/megastructure/issues/180
  - https://github.com/seletz/megastructure/issues/158
  - "[[sector-solver#Starting domains]]"
---

# Walk Tiles Only in Record Cells

> [!summary]
> Walk-family tiles (floors, stairs, bridges, catwalks, ladders, tunnels,
> portal openings) stand only in the cells the edge rasteriser records.
> Every other cell of a sector is air, or solid in a solid sector, apart from
> the free tiles a record needs beside it. Voids are open space.

## Context

Stratum cells without a record started free, and the support columns of
#158 kept whole columns free around every record in void sectors. The solver
filled them with floors, stairs, catwalks and ladders nobody walks, so a
sector read as a dense pile of structure instead of a void crossed by walks
(#179).

## Decision

The owner chose option 1 of #179: bridges reach across a void from portal to
portal, catwalks run along a void's edge, stairs connect one level to the
next, and everything else in a void is empty space, to be filled later by
decoration such as cables and pillars. The refinement on #180 extends this
to strata for now: their interiors stay open until slabs, columns and walls
get their own issue.

- A cell without a record starts as the sector's fill tile: solid in a solid
  sector, air in every other.
- A cell beside a record also admits the free tiles (no family) that some
  tile of the record allows across that face where it does not allow the
  fill tile. On the placeholder tileset only catwalks and ladders need one:
  the `backing` plate they hang on.
- The support columns of #158 are dropped.

## Consequences

- Every sampled stratum, shaft, cavity and chasm sector reaches an attempt,
  and strata solve at the first attempt (#180 measurements in
  [[sector-solver#Measurements]]).
- Floor walks in strata have no parapets: slab edges need rock below
  (decision #185).
- `solver-check` fails on any walk-family tile outside a record cell.

## Links

- [[sector-solver#Starting domains]], [[tileset]].
