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
> heights sit on the 6 m floor pitch; a portal on a side face shares the
> floor level of the lower sector's node, so that side of the corridor is
> level. **Edges** join adjacent sectors:
> corridors, stairs, ladders, bridges, catwalks, and tunnels through solid
> where nothing else connects. They are chosen per 3³ region so that every
> open sector is reachable. The skeleton viewer draws the edges as coloured
> **debug lines**, node to portal to node, as level runs with a vertical
> segment where the height changes. The **edge rasteriser** turns a
> sector's edges into records on its 24³ cell grid (floor, stair, ladder,
> bridge, catwalk, tunnel and portal opening cells), the only input the fill
> solver will take from the graph.

## Files

- [walkable_graph.gd](../../scripts/world/walkable_graph.gd) (`class_name
  WalkableGraph`, a `RefCounted`): the grid and edge constants, the salts,
  the `EdgeKind` enum, the inner classes `Portal`, `InteriorNode` and `Edge`
  and the functions below.
- [graph_lines.gd](../../scripts/world/graph_lines.gd) (`class_name
  GraphLines`, a `Node3D`): draws the edges of a box of regions as lines,
  one mesh per edge kind; used by the skeleton viewer.
- [edge_rasteriser.gd](../../scripts/world/edge_rasteriser.gd) (`class_name
  EdgeRasteriser`, a `RefCounted`): the `TileFamily` enum, the inner classes
  `Record` and `SectorRaster`, and the rasteriser functions below.
- `scripts/tools/graph_check.gd`: the check behind `mise run graph-check`,
  listed in [[tools-and-tasks]].
- `scripts/tools/graph_connectivity_check.gd`: the check behind `mise run graph-connectivity`, listed in
  [[tools-and-tasks]].
- `scripts/tools/raster_check.gd`: the check behind `mise run raster-check`,
  listed in [[tools-and-tasks]].

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

`WalkableGraph.new(seed, skeleton, scheme, void_walls_last)` takes a tuned
`Skeleton` as the second argument; its grammar's `sector_size` sets
`cells_per_sector()` (48 m / 2 m = 24, at least 4). The last two set the
properties below; changing either drops the graph's face cache.

| Property | Default | Meaning |
| --- | --- | --- |
| `boundary_scheme` | `PER_FACE` | `BoundaryScheme`: which region faces get their lightest pair. `PER_REGION_PAIR` and `SKIP_SOLID_FACES` keep faces without an open pair, or solid on both sides, only where a 2³ block tree needs them ([[walkable-graph-connectivity#2. Boundary edges between regions]]). |
| `void_wall_tunnels_last` | true | Tunnels with a cavity or chasm end weigh more than every other tunnel. |

| Function | Returns |
| --- | --- |
| `portal(a, b)` | The `Portal` between two face-adjacent sectors, in either order; `null` when they are not adjacent (same sector, diagonal, farther apart) or either is solid. |
| `interior_node(cell)` | The `InteriorNode` of a sector; `null` when it is solid. |
| `hub_level(cell)` | The floor level of a sector's hub in cells: its interior node's level, or `centre_level()` when it is solid. The height of every x and z portal the sector is the lower side of. |
| `centre_level()` | The floor level at or below the sector centre in cells (12), where a solid sector's hub sits. |
| `nodes_in_region(min_cell, max_cell)` | The interior nodes of every non-solid sector in the box, bounds inclusive, ordered by x, then y, then z. |
| `cells_per_sector()` | Fill cells along one sector edge. |
| `edges_in_region(region)` | The `Edge`s inside a 3³ region: the pruned Kruskal tree and hashed loops, ordered by `a`, then axis. Connects every open sector of the region and every sector a boundary edge lands on. |
| `boundary_edges(region, axis)` | The `Edge`s across the face between `region` and the region above it along `axis`, keyed on `region`: the lightest pair when the face is kept, plus hashed loops. Empty only for a skipped face. |
| `boundary_face_kept(region, axis)` | Whether `boundary_scheme` gives that face its lightest pair; always true for `PER_FACE`. |
| `edges_for_sector(cell)` | Every edge touching the sector: its region's edges and the boundary edges of that region's faces that land on it. |
| `region_of(cell)` (static) | The region of a sector, `floor(cell / 3)`. |
| `edge_kind(type_a, type_b, axis)` (static) | The `EdgeKind` for two sector types and an axis. |
| `edge_kind_name(kind)` (static) | `"corridor"`, `"stair"`, `"ladder"`, `"bridge"`, `"catwalk"` or `"tunnel"`. |
| `is_void_wall(type)` (static) | True for cavity and chasm, whose solid neighbours are their walls. |

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
`n - MARGIN_CELLS` cells, so at least 2 m from the edges; a node's height is
a floor level, a multiple of `STRATUM_PITCH_CELLS` = 3 inside the same
margin (6 to 42 m). A portal on an x or z face draws no height of its own:
it takes `hub_level(a)` of its lower sector `a`, which reads only `a`'s type
and node hash, so the portal is still a function of `(seed, a)`. Positions are summed as 64-bit cell counts and multiplied by
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

## Edge rasteriser

```gdscript
var rasteriser := EdgeRasteriser.new(WalkableGraph.new(WorldState.seed))
for record in rasteriser.records_for_sector(Vector3i(0, 0, 0)):
	print(record.cell, EdgeRasteriser.family_name(record.family), record.orientation, record.edge_ref)
var raster := rasteriser.rasterise(Vector3i(0, 0, 0))  # records plus per-edge walks
```

| Function | Returns |
| --- | --- |
| `records_for_sector(sector)` | The merged `Record`s of the sector, one per cell, ordered by cell x, then y, then z. |
| `rasterise(sector)` | A `SectorRaster`: `records`, `edge_records` (each edge's own walk in walking order, by `edge_ref`), `rejected` (edge refs whose every routing conflicted) and `fallbacks` (edges that did not take their first routing). |
| `hub_cell(sector)` | The cell all walks of the sector meet at: the interior node, or the centre of a solid sector. |
| `merge(p, q)` (static) | The record two records at one cell merge into, or `null` for a conflict. Commutative. |
| `portal_cell(sector, edge, n)` (static) | The edge's portal cell inside the sector. |
| `surface_family(type)` (static) | The flat family of a sector type: floor, catwalk (shaft), bridge (cavity, chasm) or tunnel (solid). |
| `edge_ref(edge)` (static) | `Vector4i(a.x, a.y, a.z, axis)`, the key both sectors of an edge use. |
| `family_name(family)`, `yaw_of(dir)` (static) | `"floor"` ... `"portal_opening"`; the yaw 0..3 of a horizontal unit vector. |

| `Record` field | Meaning |
| --- | --- |
| `cell` | Local cell, 0 to `cells_per_sector() - 1` on each axis. |
| `family` | `TileFamily`: `FLOOR`, `STAIR`, `BRIDGE`, `CATWALK`, `LADDER`, `TUNNEL` or `PORTAL_OPENING`. |
| `orientation` | Yaw quarter turns 0..3 (0 +x, 1 −z, 2 −x, 3 +z), `ORIENTATION_UP` (4) or `ORIENTATION_DOWN` (5); 0 for floor, bridge, catwalk and tunnel. |
| `edge_ref` | The edge the record came from; after a merge, the smaller of the two. |

Every edge becomes a walk from the hub to its portal cell: flat at the hub's
level, an oriented stair run (3 cells of run per stratum, turning only at
landings) or, in shafts and chasms, a ladder to the portal's level, flat
into the portal. Portal cells go in first, vertical edges before horizontal
ones, and each edge takes the first routing whose records merge with what is
already placed; stair runs search their turns around occupied cells. Nothing
is cached: `rasterise` calls `edges_for_sector` once. The rules, the merge
table and a worked example are in [[edge-rasteriser]].

## Debug lines

`GraphLines` is a child of the `SkeletonViewer` in
the viewer scene ([[skeleton#Viewer]]).
`rebuild(skeleton, seed, min_cell, max_cell)` draws every edge of the regions
overlapping the box: `edges_in_region` of each, and `boundary_edges` of every
face with an overlapped region on either side. Each edge has two halves,
from the node of `a` to its portal and from the portal to the node of `b`, so
a path reads node → portal → node. Solid sectors have no interior node, so a
tunnel bends at the sector centre instead, at `centre_level()`.

No half is drawn as a slope. It is a horizontal run at the node's height to
the point straight above or below the portal, then a vertical segment on
the portal's side, in the stair colour (yellow), down or up to the portal.
The vertical segment is placed at the portal, not along the stair: the
rasteriser starts its stair run or ladder in the cell next to the portal
cell, but where the run turns depends on the other edges of the sector, and
the viewer does not rasterise. An x or z portal is at the level of `a`'s
hub, so the half in `a` is one run and only the half in `b` can have a
vertical segment; a y portal is at a sector boundary, so both halves of a
vertical edge have one.

| Kind | Colour |
| --- | --- |
| corridor | white |
| stair, ladder | yellow |
| bridge | cyan |
| catwalk | green |
| tunnel | magenta |

Each kind is one `MeshInstance3D` with an `ArrayMesh` holding one
`PRIMITIVE_LINES` surface built from a `PackedVector3Array` and a
`PackedColorArray` of vertex colours, which is cheaper to rebuild than an
`ImmediateMesh` fed vertex by vertex. The vertex colours let a kind's mesh
hold its runs in the kind's colour and its vertical segments in yellow, so
hiding a kind hides its vertical segments too. A kind's mesh also
holds a cross of three axis-aligned segments (`marker_size` metres) at each
of its portals; the tunnel mesh holds the crosses at solid sector centres. A
further `Nodes` mesh holds grey crosses at the interior nodes. The
materials are unshaded, take their albedo from the vertex colours, are alpha-blended at full alpha, write no depth and have
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
  faces, margin, grid, that x and z portals (tunnels included) sit at the
  lower sector's hub level, null results for solid and non-adjacent pairs,
  and the interior nodes, for seeds 0 to 4.
- `mise run graph-connectivity` (part of `mise run check`, about 2 min)
  tests edge kinds, portals, determinism and `edges_for_sector` for every
  boundary scheme and tunnel weight variant, over a random 15³ sample and
  one centred on a chasm wall for seeds 0 to 9, and fails unless every
  region-aligned 3³, 6³ and 9³ window has one component of open sectors. It
  prints per variant the tunnel fraction, the tunnels with a chasm or cavity
  end, the skipped faces, the strict 5³ window counts, the edge kinds and
  the mean vertical run, then a table of all variants.
  `mise run graph-connectivity --variants=per_face,void_walls_last` runs
  only those.
- `mise run raster-check` (part of `mise run check`, about 15 s) rasterises
  1 000 random sectors for seeds 0 to 4 and fails on a difference from a
  fresh graph, a record outside 0..23, a conflict, an edge without its
  portal opening in both endpoint sectors, a rejected edge, a sector whose
  records are split, or a walk that changes level anywhere but on a stair or
  ladder. It prints the family counts, the mean records and stair cells per
  sector and the stair, ladder and landing cells level changes produce.

## References

- [[sector-skeleton-and-walkable-graph]]: portals, nodes and their salts.
- [[edge-rasteriser]]: how edges become cell records.
- [[walkable-graph-connectivity]]: how the edges are chosen;
  [[0017-region-spanning-trees-with-tunnels]]: why.
- [[skeleton]]: `sector_type`, which decides which sectors are open.
- [[hash]]: the integer hash every point draws from.
- [[MEGASTRUCTURE_CONCEPT]], section 2.2: the walkable graph.
