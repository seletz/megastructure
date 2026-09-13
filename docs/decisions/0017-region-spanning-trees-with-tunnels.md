---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/81
  - "[[walkable-graph-connectivity]]"
  - "[[0016-tuned-sector-grammar-solid-before-voids]]"
---

# Region Spanning Trees with Tunnels

> [!summary]
> Walkable graph edges are decided per 3³ region: a Kruskal tree over all
> sectors with hashed weights, plus boundary edges between regions. Edges may
> tunnel through solid, but only where no open path exists inside the region.
> Every window made of whole regions is provably connected. Windows that cut
> regions are not, and the check says so with numbers.

## Context

[[0016-tuned-sector-grammar-solid-before-voids]] makes solid split space
into 2.4 blocks per 5³ window, while the concept promises that every open
sector is reachable. Issue #81 asked for one component per 5³ window, with
edges decided locally and deterministically.

## Decision

- **Tunnels.** A pair with a solid sector is a candidate edge of kind
  `tunnel`, weighted above every open-open pair, so Kruskal tunnels only when
  no open path in the region joins the groups. Counting components per open
  boundary was rejected: it keeps the separation but breaks the promise.
- **Regions.** Kruskal over all 27 sectors of a region, pruned to the
  terminals: open sectors and the ends of boundary edges.
- **Boundaries.** Each face between two regions gets its lightest pair,
  keyed on the lower region, plus hashed open-open loops.
- **Guarantee.** Windows aligned to regions (3³, 6³ sectors) must have one
  component; `mise run graph-connectivity` fails otherwise.
- **Strict 5³ windows** are reported, not enforced. With seeds 0 to 9 only
  481 of 13 310 (3.6 %) are one component. Even every open-open adjacency
  without tunnels reaches only 25.9 %, so any sparse local graph falls short.

## Consequences

- 13 % of edges are tunnels. The rasteriser (#83) must carve them.
- A region reads the sector types of its neighbours' face layers, never
  their edges.
- Vertical runs average 2 sectors. The column-keyed weights could be tuned
  later.

## Links

- Issue #81; epic #79. How: [[walkable-graph-connectivity]]. Code:
  [[walkable-graph]].
