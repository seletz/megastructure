---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/81
  - https://github.com/seletz/megastructure/issues/129
  - https://github.com/seletz/megastructure/issues/135
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
- **Void walls last** (#129). A tunnel from a chasm or cavity into solid
  weighs more than every other tunnel, so trees open a void's wall only
  where the void has no other way out.
- **Guarantee.** Windows aligned to regions (3³, 6³ sectors) must have one
  component; `mise run graph-connectivity` fails otherwise.
- **Strict 5³ windows** are reported, not enforced. With seeds 0 to 9 only
  481 of 13 310 (3.6 %) are one component. Even every open-open adjacency
  without tunnels reaches only 25.9 %, so any sparse local graph falls short.

## Measured variants (#129)

Chasm sectors collected tunnels into their walls. Four variants sit behind
`WalkableGraph.boundary_scheme` and `void_wall_tunnels_last`, measured by
`mise run graph-connectivity` over seeds 0 to 9, on the random 15³ samples
and on 15³ samples centred on a chasm wall. Every variant keeps every
region-aligned 3³, 6³ and 9³ window connected.

| Variant | Tunnels (random / chasm) | Chasm-end tunnels | Cavity-end tunnels (random / chasm) | Faces skipped (random) | Strict 5³ |
| --- | ---: | ---: | ---: | ---: | ---: |
| per face, before | 13.0 % / 6.1 % | 83 | 324 / 96 | 0 % | 3.6 % |
| per region pair: open faces always, others where a 2³ block tree needs them | 9.1 % / 4.1 % | 72 | 225 / 64 | 13.2 % | 2.6 % |
| skip solid faces: faces solid on both sides only where a block tree needs them | 12.7 % / 6.0 % | 83 | 319 / 95 | 0.4 % | 3.6 % |
| per face, void walls last (**default**) | 14.0 % / 6.6 % | 63 | 42 / 9 | 0 % | 3.5 % |
| per region pair, void walls last | 9.7 % / 4.4 % | 50 | 32 / 7 | 13.1 % | 2.6 % |

- The shipped default is the most conservative variant that reduces chasm
  tunnels: every face keeps its edge and the guarantee for any
  face-connected set of regions stands; only the order among tunnels
  changes. It costs 1 point more tunnels.
- Only 37 of 179 void-wall tunnels in the chasm samples lie on boundary
  faces; the rest join a chasm column to its own region, which the 3³
  guarantee requires under any scheme.
- The region-pair schemes guarantee connectivity only for single regions
  and boxes at least 2 regions thick on each axis.
- Which boundary scheme to keep is the owner's call in #135.

## Consequences

- 14 % of edges are tunnels. The rasteriser (#83) must carve them.
- A region reads the sector types of its neighbours' face layers, never
  their edges.
- Vertical runs average 2 sectors. The column-keyed weights could be tuned
  later.

## Links

- Issue #81; epic #79; tunnel variants #129, scheme decision #135. How: [[walkable-graph-connectivity]]. Code:
  [[walkable-graph]].
