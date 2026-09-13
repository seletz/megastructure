---
tags:
  - code-map
  - graph
status: current
---

# Walkable Graph

> [!summary]
> The second generator layer, so far only its points. Wherever two open
> (non-solid) sectors touch, there is one **portal**: a point on the face
> between them where a corridor, stair or ladder will cross. Every open
> sector also gets one **interior node** inside it. Both are computed from
> the seed and the sector coordinates alone, and a portal is keyed on the
> lower sector of its pair, so the two sectors always agree on where their
> portal is. All points sit on the 2 m cell grid the tiles will use, and
> heights sit on the 6 m floor pitch. The edges between the points (#81),
> the debug lines (#82) and the rasteriser (#83) come next.

## Files

- [walkable_graph.gd](../../scripts/world/walkable_graph.gd) (`class_name
  WalkableGraph`, a `RefCounted`): the grid constants, the salts, the inner
  classes `Portal` and `InteriorNode` and the functions below.
- `scripts/tools/graph_check.gd`: the check behind `mise run graph-check`,
  listed in [[tools-and-tasks]].

## Using it

```gdscript
var graph := WalkableGraph.new(WorldState.seed)       # default Skeleton
var p := graph.portal(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
if p != null:
	print(p.position, p.axis, p.face_cell)            # metres, 0, cells on the face
var node := graph.interior_node(Vector3i(0, 0, 0))    # null if solid
var nodes := graph.nodes_in_region(Vector3i(-1, -1, -1), Vector3i(1, 1, 1))
```

`WalkableGraph.new(seed, skeleton)` takes a tuned `Skeleton` as the second
argument; its grammar's `sector_size` sets `cells_per_sector()` (48 m / 2 m =
24, at least 4).

| Function | Returns |
| --- | --- |
| `portal(a, b)` | The `Portal` between two face-adjacent sectors, in either order; `null` when they are not adjacent (same sector, diagonal, farther apart) or either is solid. |
| `interior_node(cell)` | The `InteriorNode` of a sector; `null` when it is solid. |
| `nodes_in_region(min_cell, max_cell)` | The interior nodes of every non-solid sector in the box, bounds inclusive, ordered by x, then y, then z. |
| `cells_per_sector()` | Fill cells along one sector edge. |

| `Portal` field | Meaning |
| --- | --- |
| `a`, `b` | The two sectors, always ordered: `b` is `a` plus one along `axis`, whichever order `portal` was called with. |
| `axis` | `Vector3i.AXIS_X`, `AXIS_Y` or `AXIS_Z`: the axis the face is normal to. |
| `face_cell` | The point in cells from the face's lower corner, along the other two axes in xyz order: `(y, z)` on an x face, `(x, z)` on a y face, `(x, y)` on a z face. |
| `position` | World position in metres. |

`Portal.equals(other)` compares every field exactly.

| `InteriorNode` field | Meaning |
| --- | --- |
| `cell` | The sector. |
| `type` | `Skeleton.SectorType`: stratum, or shaft, cavity or chasm, which the edge rules treat as vertical travel or open space. |
| `local_cell` | The point in cells from the sector's lower corner. |
| `position` | World position in metres. |

Each coordinate is one `Hash.hash3_u` draw modulo its range. A coordinate
along x or z (and both on a y face) lies in `MARGIN_CELLS` to
`n - MARGIN_CELLS` cells, so at least 2 m from the edges; a height is a
floor level, a multiple of `STRATUM_PITCH_CELLS` = 3 inside the same margin
(6 to 42 m). Positions are summed as 64-bit cell counts and multiplied by
`CELL_SIZE` = 2, so they are exact on the grid while they fit a float32
(about ±2²⁵ m, some 700 000 sectors); `face_cell` and `local_cell` are exact
everywhere. The rules and salts are in
[[sector-skeleton-and-walkable-graph]].

## How to run or check it

- `mise run graph-check` (part of `mise run check`) tests portal symmetry,
  faces, margin, grid and floor levels, null results for solid and
  non-adjacent pairs, and the interior nodes, for seeds 0 to 4.

## References

- [[sector-skeleton-and-walkable-graph]]: portals, nodes and their salts.
- [[skeleton]]: `sector_type`, which decides which sectors are open.
- [[hash]]: the integer hash every point draws from.
- [[MEGASTRUCTURE_CONCEPT]], section 2.2: the walkable graph.
