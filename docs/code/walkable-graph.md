---
tags:
  - code-map
  - graph
status: current
---

# Walkable Graph

> [!summary]
> The second generator layer: its points and the edges between them. Wherever two open
> (non-solid) sectors touch, there is one **portal**: a point on the face
> between them where a corridor, stair or ladder will cross. Every open
> sector also gets one **interior node** inside it. Both are computed from
> the seed and the sector coordinates alone, and a portal is keyed on the
> lower sector of its pair, so the two sectors always agree on where their
> portal is. All points sit on the 2 m cell grid the tiles will use, and
> heights sit on the 6 m floor pitch. **Edges** join adjacent sectors:
> corridors, stairs, ladders, bridges, catwalks, and tunnels through solid
> where nothing else connects. They are chosen per 3³ region so that every
> open sector is reachable. The skeleton viewer draws the edges as coloured
> **debug lines**, node to portal to node. The rasteriser (#83) comes next.

## Files

- [walkable_graph.gd](../../scripts/world/walkable_graph.gd) (`class_name
  WalkableGraph`, a `RefCounted`): the grid and edge constants, the salts,
  the `EdgeKind` enum, the inner classes `Portal`, `InteriorNode` and `Edge`
  and the functions below.
- [graph_lines.gd](../../scripts/world/graph_lines.gd) (`class_name
  GraphLines`, a `Node3D`): draws the edges of a box of regions as lines,
  one mesh per edge kind; used by the skeleton viewer.
- `scripts/tools/graph_check.gd`: the check behind `mise run graph-check`,
  listed in [[tools-and-tasks]].
- `scripts/tools/graph_connectivity_check.gd`: the check behind `mise run graph-connectivity`, listed in
  [[tools-and-tasks]].

## Using it

```gdscript
var graph := WalkableGraph.new(WorldState.seed)       # default Skeleton
var p := graph.portal(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
if p != null:
	print(p.position, p.axis, p.face_cell)            # metres, 0, cells on the face
var node := graph.interior_node(Vector3i(0, 0, 0))    # null if solid
var nodes := graph.nodes_in_region(Vector3i(-1, -1, -1), Vector3i(1, 1, 1))
for edge in graph.edges_for_sector(Vector3i(0, 0, 0)):
	print(edge.a, edge.b, WalkableGraph.edge_kind_name(edge.kind), edge.portal.position)
var region_edges := graph.edges_in_region(WalkableGraph.region_of(Vector3i(0, 0, 0)))
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
| `edges_in_region(region)` | The `Edge`s inside a 3³ region: the pruned Kruskal tree and hashed loops, ordered by `a`, then axis. Connects every open sector of the region and every sector a boundary edge lands on. |
| `boundary_edges(region, axis)` | The `Edge`s across the face between `region` and the region above it along `axis`, keyed on `region`: the lightest pair plus hashed loops, never empty. |
| `edges_for_sector(cell)` | Every edge touching the sector: its region's edges and the boundary edges of that region's faces that land on it. |
| `region_of(cell)` (static) | The region of a sector, `floor(cell / 3)`. |
| `edge_kind(type_a, type_b, axis)` (static) | The `EdgeKind` for two sector types and an axis. |
| `edge_kind_name(kind)` (static) | `"corridor"`, `"stair"`, `"ladder"`, `"bridge"`, `"catwalk"` or `"tunnel"`. |

| `Portal` field | Meaning |
| --- | --- |
| `a`, `b` | The two sectors, always ordered: `b` is `a` plus one along `axis`, whichever order `portal` was called with. |
| `axis` | `Vector3i.AXIS_X`, `AXIS_Y` or `AXIS_Z`: the axis the face is normal to. |
| `face_cell` | The point in cells from the face's lower corner, along the other two axes in xyz order: `(y, z)` on an x face, `(x, z)` on a y face, `(x, y)` on a z face. |
| `position` | World position in metres. |

`Portal.equals(other)` compares every field exactly.

| `Edge` field | Meaning |
| --- | --- |
| `a`, `b` | The two sectors, ordered: `b` is `a` plus one along `axis`. |
| `axis` | The axis between them. |
| `kind` | `EdgeKind`: `CORRIDOR`, `STAIR`, `LADDER`, `BRIDGE`, `CATWALK` or `TUNNEL`. |
| `portal` | The `Portal` on their face. Tunnel edges get the point from the same salts, although `portal(a, b)` returns null for them. |

`Edge.equals(other)` compares every field, the portal included.

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

Edges read nothing but sector types, from the region and the sector layers
across its six faces, and hashes, so a region's edges never depend on
another region's edges or on call order. Nothing is cached: a caller that
streams sectors should keep `edges_in_region` per region. The algorithm,
weights, salts 153 to 158 and the connectivity argument are in
[[walkable-graph-connectivity]].

## Debug lines

`GraphLines` is a child of the `SkeletonViewer` in
the viewer scene ([[skeleton#Viewer]]).
`rebuild(skeleton, seed, min_cell, max_cell)` draws every edge of the regions
overlapping the box: `edges_in_region` of each, and `boundary_edges` of every
face with an overlapped region on either side. Each edge is two segments,
from the node of `a` to its portal and from the portal to the node of `b`, so
a path reads node → portal → node. Solid sectors have no interior node, so a
tunnel bends at the sector centre instead.

| Kind | Colour |
| --- | --- |
| corridor | white |
| stair, ladder | yellow |
| bridge | cyan |
| catwalk | green |
| tunnel | magenta |

Each kind is one `MeshInstance3D` with an `ArrayMesh` holding one
`PRIMITIVE_LINES` surface built from a `PackedVector3Array`, which is cheaper
to rebuild than an `ImmediateMesh` fed vertex by vertex. A kind's mesh also
holds a cross of three axis-aligned segments (`marker_size` metres) at each
of its portals; the tunnel mesh holds the crosses at solid sector centres. A
further `Nodes` mesh holds grey crosses at the interior nodes. The
materials are unshaded, alpha-blended at full alpha, write no depth and have
render priority 10, above the viewer's boxes. Hiding a kind hides its mesh.

Nothing in `WalkableGraph` is cached, and `edges_in_region` reads the
boundary layers of all six neighbours, so `GraphLines` keeps three caches:
edges per region, boundary edges per face, and node points per sector, each
trimmed to what the last rebuild used; and it builds its graph on a
`CachedSkeleton`, an inner `Skeleton` subclass that remembers `sector_type`
per cell (dropped past 200 000 cells). `invalidate()` clears all of them; the
viewer calls it on a seed or grammar change. Rebuild times are in
[[skeleton#Viewer]].

## How to run or check it

- `mise run run-skeleton` shows the debug lines; the panel's `graph` section
  toggles them.

- `mise run graph-check` (part of `mise run check`) tests portal symmetry,
  faces, margin, grid and floor levels, null results for solid and
  non-adjacent pairs, and the interior nodes, for seeds 0 to 4.
- `mise run graph-connectivity` (part of `mise run check`, about 25 s)
  tests edge kinds, portals, determinism and `edges_for_sector` over a 15³
  sample for seeds 0 to 9, and fails unless every region-aligned 3³ and 6³
  window has one component of open sectors. It prints the strict 5³ window
  counts, the tunnel fraction, the edge kinds and the mean vertical run.

## References

- [[sector-skeleton-and-walkable-graph]]: portals, nodes and their salts.
- [[walkable-graph-connectivity]]: how the edges are chosen;
  [[0017-region-spanning-trees-with-tunnels]]: why.
- [[skeleton]]: `sector_type`, which decides which sectors are open.
- [[hash]]: the integer hash every point draws from.
- [[MEGASTRUCTURE_CONCEPT]], section 2.2: the walkable graph.
