---
tags:
  - algorithm
  - graph
  - milestone/0.2.0
  - implemented
status: current
sources:
  - "[[merrell-2007-example-based-model-synthesis]]"
---

# Edge Rasteriser

> [!summary]
> The [[GLOSSARY#Walkable graph|walkable graph]] says *which* sectors are
> joined and where the joins cross the faces. The fill solver needs to know
> *which cells* the path runs through. The
> [[GLOSSARY#Edge rasteriser|edge rasteriser]] draws each edge of a sector
> into its 24³ cell grid as a walk: flat at the floor level of the sector's
> [[GLOSSARY#Hub|hub]], an explicit stair run (or a ladder in shafts and
> chasms) where the height changes, flat again, and an opening at the
> portal. No flat cell ever changes level, so nothing is drawn as a slope.
> Each cell becomes a record with a [[GLOSSARY#Tile family|tile family]]
> (floor, stair, bridge, catwalk, ladder, tunnel, portal opening) and an
> orientation, and the cell above every walking surface becomes a
> [[GLOSSARY#Headroom record|headroom record]] so no slab, column or lintel
> lands on the walker's head. Where two walks share a cell a fixed
> [[GLOSSARY#Merge rule|merge rule]] decides, and a walk that would clash
> tries another shape. The records are the whole contract between graph and
> solver, and they depend only on the seed and the sector.

This is milestone 0.2.0 item B4 of [[RESEARCH_WFC]] section 7. The solver
(D2) turns each record into a [[GLOSSARY#Domain restriction|domain
restriction]]; section 3 of [[RESEARCH_WFC]] explains why contradictions
can only come from inconsistent pre-collapsed cells, which is why the
records must never conflict. The edges themselves come from
[[walkable-graph-connectivity]].

## The contract

`EdgeRasteriser.new(graph).records_for_sector(sector)` returns records
sorted by cell:

| Field | Meaning |
| --- | --- |
| `cell` | Local cell, 0 to 23 on each axis (sector 48 m, cell 2 m). |
| `family` | `FLOOR`, `STAIR`, `BRIDGE`, `CATWALK`, `LADDER`, `TUNNEL`, `PORTAL_OPENING` or `HEADROOM`. |
| `orientation` | 0 to 3: yaw quarter turns of the forward direction, +x turned about +y (0 +x, 1 −z, 2 −x, 3 +z); 4 up, 5 down; 0 for unoriented families. |
| `edge_ref` | `Vector4i(a.x, a.y, a.z, axis)` of the edge, the same key in both sectors. |

| Family | Orientation |
| --- | --- |
| floor, bridge, catwalk, tunnel, headroom | unoriented (0): the solver picks the rotation |
| stair | yaw of the way up |
| ladder | always up (4) |
| portal opening, on a side face | yaw pointing out of the sector |
| portal opening, on the top or bottom face | up (4) in the lower sector, down (5) in the upper |

A **stair** cell at height `h` ramps from the floor of cell `h` to the floor
of cell `h + 1`, so a stair climbs one cell per cell of run: one stratum
(3 cells, 6 m) in 3 cells. A **ladder** fills one column from the lower floor
level to the upper one, both ends included; the climber steps on and off
sideways.

## The level rule

Interior nodes draw their floor levels from independent hashes. A portal on
an x or z face sits at the hub level of the lower sector of its pair
([[sector-skeleton-and-walkable-graph#Nodes and portals]]), so the walk in
the lower sector is level and only the upper sector's walk may change
height; on a y face the portal is at the top or bottom of the sector, so
both halves climb. The rasteriser never interpolates. For every edge kind
the walk is:

1. **flat** at the start level (the hub's), in the sector's surface family;
2. a **stair run**, oriented, 3 cells of run per stratum, or a **ladder** in
   shaft and chasm sectors, from the start level to the other level;
3. **flat** again at the other level (at least the portal cell).

A flat cell has the height of the flat cell before it, and a stair run turns
only at a flat landing. `mise run raster-check` steps through every walk
cell by cell, fails on any step a walker could not take, and counts the
stair, ladder and landing cells the level changes produce.

## The algorithm step by step

Let `n = 24` cells per sector.

### 1. Hub and surface family

- The **hub** is the sector's interior node. A solid sector has none, so a
  tunnel uses the centre cell `(12, 12, 12)` (the floor level at or below
  the centre, the point the debug lines bend at).
- The **surface family** is the family of every flat cell in the sector,
  chosen by sector type: stratum → floor, shaft → catwalk, cavity and chasm
  → bridge, solid → tunnel.

So a bridge edge from a stratum into a cavity is floor on the stratum side
and bridge in the cavity; a tunnel is tunnel only inside the rock. All
walkways of one sector share a family and all meet at the hub, which is what
keeps them from conflicting with each other.

### 2. Portal cells first

For every edge of `edges_for_sector(sector)`, the portal cell is the portal's
`face_cell` on the two face axes and `n − 1` (sector is `a`) or `0` (sector
is `b`) along the edge axis. All portal cells are placed before any walk,
because the graph fixes them; a walk that would run through one must go
elsewhere. The headroom of the side portal cells (step 8) goes in next,
where it fits.

### 3. Edge order

Vertical edges first (they have the fewest possible shapes), then horizontal
edges, each group ordered by `edge_ref`. Every edge takes the first of its
**routings** (steps 5 and 6) whose records merge with everything placed so
far. If none does, the edge keeps only its portal cell and is listed as
rejected.

### 4. Stair runs

A stair run joins a flat end cell `E` (a portal) to the hub's level. It is
built backwards from `E`, leaving it in a given direction:

1. Split the height difference into **flights** that end on floor levels:
   from a floor level a flight has 3 steps; the first flight below the top
   portal cell (`y = 23`) has 2.
2. After each flight choose, in this order: straight on, turn at a flat
   **landing** in the next cell towards the sector centre, turn the other
   way, turn back. Take the first choice whose flight and the cell after it
   fit in the sector and whose cells are free (empty, or holding the same
   family and orientation; the portal cells, their headroom and the walks
   of earlier edges are already placed), keep the stair rule (step 7) and
   whose headroom (step 8) is free, against the records placed so far and
   the run's own earlier flights. If later flights find no free choice, undo and try
   the next choice: a depth-first search, capped at `RUN_SEARCH_LIMIT` = 64
   flights per run.
3. Each stair cell faces the way up. The flat cell after the last flight, at
   the hub's level, is where the walk from the hub joins. The walk goes
   along the stair line first when the hub lies between that landing and
   `E`, so it does not pass under the stair, and across the line first
   otherwise.

A run that meets a wall or another edge's stair turns, so a stair run
almost always fits, and it never takes over a cell another stair, ladder or
portal already holds.

### 5. Horizontal edges

The walk reaches the portal `P` either across the face (along the edge axis)
or along the face wall. Corridors, bridges and tunnels try across first,
catwalks along the wall first. The last step always enters `P` across the
face, from the **door cell** `D` one cell inwards, because a portal's jambs
close its sides (#173): along the wall the walk runs to `D`, then into `P`.
Along the wall the stair leaves `D` towards the hub first, then away from
it.

1. Same level: an L from the hub to `D` at the hub's level, along the face
   axis first (across) or along the edge axis first (along the wall), then
   `P`. A hub on the face row would reach `P` along the wall across first;
   that route runs through `P` itself, conflicts with the portal and falls
   back to the other L.
2. Different levels, outside shafts and chasms: the L to the landing, then
   a stair run leaving `P` inwards (across), or leaving `D` along the wall
   followed by `D` and `P`.
3. Different levels, in a shaft or chasm: the L to the cell before `P` (or
   beside `D`), a ladder there from the hub's level to `P.y`, then `D`
   along the wall, then `P`.
4. Same level, last: **detours**. Along the edge axis from the hub to the
   line `d` cells in from the face, along the face to `P`'s column, then
   across to `P`, for `d = 1` to 23 in turn. A level walk whose L would pass
   directly under another edge's stair steps around its column this way.

### 6. Vertical edges

The portal column `C` holds the portal cell at the top (`y = 23`, lower
sector) or bottom (`y = 0`, upper sector).

- Outside shafts and chasms, whatever the edge kind (a stair edge, the
  stratum half of a stair edge into a shaft, a vertical tunnel in rock): a
  stair run leaving `C` in each of the four directions +x, −z, −x, +z in
  turn.
- In a shaft or chasm: a ladder in `C` from the hub's level to 22 (lower)
  or 1 (upper), then in each of the four columns beside `C`, reaching the
  portal's height (23 or 0) so the climber steps across into the opening.
  The L to the ladder foot is tried x first, then z.

The two portal cells of a vertical edge are stacked in one world column, one
cell apart in height (23 in the lower sector, 0 in the upper). The tiles of
the up and down opening span that step.

### 7. Merge rule

Records are merged cell by cell with `EdgeRasteriser.merge`:

| Records at one cell | Result |
| --- | --- |
| same family and orientation | one record, the smaller `edge_ref` |
| floor, bridge, catwalk or tunnel with a ladder | the ladder |
| floor, bridge, catwalk or tunnel with a stair or portal opening | conflict |
| two portal openings with yaws | a corner opening with the smaller yaw |
| two different surface families | conflict |
| stairs of different orientation, stair and ladder | conflict |
| portal opening and stair or ladder, up or down opening and any other opening | conflict |
| headroom with headroom | one record, the smaller `edge_ref` |
| headroom with any other family | conflict |

**Stair rule** (the headroom rule of #161). No record but headroom lies
directly above or below a stair cell. A floor directly under a stair has
1.4 m of clearance, so a flat cell over or under a stair (or two stacked
stair cells) describes geometry no tile pair can hold. A routing whose
merged records break the rule at one of its cells is dropped like a
conflict, and stair runs check the rule as they search (step 4).

Headroom conflicts with every walk family because a cell one walker needs
for its head is no cell another may stand in: a floor of a second walk
directly over a first walk's floor puts its 0.6 m slab 1.4 m above the
lower walking surface. Neither side can win without breaking one walk, so
the later routing is dropped and the edge tries its next shape (step 3),
exactly as for two surface families.

### 8. Headroom records

Every walking surface of a kept routing reserves the cells above it
(`headroom_for`), each as a `HEADROOM` record with the routing's `edge_ref`
and orientation 0:

| Record | Headroom cells above it |
| --- | --- |
| floor, bridge, catwalk, tunnel | `headroom_cells` (default 1) |
| stair | `headroom_cells + 1`: the tread rises to the top of its cell, the floor of the cell above |
| portal opening on a side face | `headroom_cells` |
| ladder, portal opening up or down | none: a passage, not a surface |

Cells above the grid top are skipped. The routing's records and its
headroom merge into the placed records together (step 3), so a routing
whose headroom lands on another walk's cell, or whose cells land on
another walk's headroom, is dropped like any conflict; stair runs test
both while they search. Decision #171 set one cell as the conservative
default and keeps the count a parameter: `EdgeRasteriser.new(graph,
headroom)`, 0 turning headroom records off.

The solver turns a headroom record into a domain of every tile whose mesh
leaves the lowest 1.8 m of the cell empty (`TileLibrary.HEADROOM_CLEAR`,
[[sector-solver#Starting domains]]): a 1.8 m walker on a floor reaches
0.4 m into the cell above and on the top tread of a stair 1.8 m. On the
placeholder tileset that is air and the wall doorway under its lintel. An
open floor, a portal frame and a column are not: their slab or jambs start
at the cell bottom. Tunnels need rock above (`1i`) and no headroom tile has
it, so a tunnel with headroom cannot build its domains; on the placeholder
tileset tunnels through rock failed before an attempt already.

**Portal cells.** A portal opening's own cell needs a walking surface. Its
record takes `portal_opening` (two jambs in a wall, no slab) and
`portal_frame` (a slab and two jambs). The headroom above a side portal
removes `portal_opening`, whose `3_0` top needs a wall stack, when the
domains propagate, so the portal cell is always the frame's slab at the
walk's level. The frame has no lintel: one cell over a 0.6 m slab leaves
1.4 m, and the lintel belongs to the cell above if anything does.

**Worked example.** The sector below (seed 0, `(3, 0, 59)`, hub
`(22, 15, 14)`) has 27 floor cells at `y = 15`, three stair cells and two
portal openings. With `headroom_cells = 1`:

| Records | Headroom cells |
| --- | --- |
| 27 floor cells at `y = 15` | the 27 cells above them at `y = 16` |
| stair `(7, 15, 3)` | `(7, 16, 3)`, `(7, 17, 3)` |
| stair `(7, 16, 2)` | `(7, 17, 2)`, `(7, 18, 2)` |
| stair `(7, 17, 1)` | `(7, 18, 1)`, `(7, 19, 1)` |
| portal `(7, 18, 0)`, yaw 1 | `(7, 19, 0)` |
| portal `(23, 15, 13)`, yaw 0 | `(23, 16, 13)` |

No cell is above two records, so the sector gets 35 headroom records and
67 records in all. The stair
rule already kept every cell above a stair empty; the headroom now fills
it and the cell above that, and the solver keeps air or a doorway in all
35.

The rules are commutative, so the result does not depend on which record came
first. A ladder wins over a flat cell where a walkway crosses the foot of
another edge's ladder, whose rungs stand off one face. Until #173 a stair
and a portal opening won too, but a flat walk across a stair's slope or
between a portal's jambs is not walkable, so those routings now take their
next shape; stair runs themselves only take free cells (step 4). A conflict never enters the output: the routing that caused it is
dropped and the next one tried (step 3). Each edge's own walk is kept as it
was routed, so the check can step through it even where the merged output
shows another edge's cell.

## Worked example

Seed 0, stratum sector `(3, 0, 59)`, hub `(22, 15, 14)`, two edges:

| Edge | `edge_ref` | Portal cell | Portal level − hub level |
| --- | --- | --- | ---: |
| corridor from `(3, 0, 58)` | `(3, 0, 58, 2)` | `(7, 18, 0)` | +3 |
| corridor to `(4, 0, 59)` | `(3, 0, 59, 0)` | `(23, 15, 13)` | 0 |

The first edge's lower sector is `(3, 0, 58)`, so its portal has that
sector's hub level, 18, and the stair is on this side. This sector is the
lower one of the second edge, so that portal has the hub's level, 15.

1. Portal openings at `(7, 18, 0)` with yaw 1 (−z out) and
   `(23, 15, 13)` with yaw 0 (+x out).
2. The z edge goes first (smaller `edge_ref`). The portal is 3 cells above
   the hub, so a stair run leaves it inwards along +z: one flight of 3 steps
   facing −z (yaw 1, the way up) at `(7, 17, 1)`, `(7, 16, 2)`, `(7, 15, 3)`,
   landing at `(7, 15, 4)`. The hub is not between that landing and the
   portal, so the walk goes across the stair line first: floor
   `(22…7, 15, 14)`, then `(7, 15, 13…4)`. Walking it: flat at 15, up three
   steps, flat into the portal at 18.
3. The x edge is level: an L across the face, along z first, `(22, 15, 14)`,
   `(22, 15, 13)`, then the portal. Its floor at the hub merges with the
   first edge's, keeping `edge_ref (3, 0, 58, 2)`.

```
plan view (x right, z up): H hub, # floor at y = 15, S stair, P portal
z=14  # # # # # # # # # # # # # # # H .
z=13  # . . . . . . . . . . . . . . # P
z=12  # . . . . . . . . . . . . . . . .
z=11  # . . . . . . . . . . . . . . . .
z=10  # . . . . . . . . . . . . . . . .
z=9   # . . . . . . . . . . . . . . . .
z=8   # . . . . . . . . . . . . . . . .
z=7   # . . . . . . . . . . . . . . . .
z=6   # . . . . . . . . . . . . . . . .
z=5   # . . . . . . . . . . . . . . . .
z=4   # . . . . . . . . . . . . . . . .
z=3   S . . . . . . . . . . . . . . . .
z=2   S . . . . . . . . . . . . . . . .
z=1   S . . . . . . . . . . . . . . . .
z=0   P . . . . . . . . . . . . . . . .
     x=7                             x=23
```

The sector gets 32 walk records: 2 portal openings, 3 stair cells and 27
floor cells, one 26-connected group, and 35 headroom records above them
(step 8). In `(3, 0, 58)` the same corridor reaches its
portal at `(7, 18, 23)` without a stair.

A turning run: a vertical stair edge whose hub is at `y = 3` in the lower
sector needs 20 steps to the top portal, a flight of 2 and six of 3. From a
portal column at `x = 11` a straight run needs 20 cells of run plus a
landing and fits in neither direction, so the run heads for the wall and
turns at a landing after the last flight that fits.

## Determinism

The records read only `edges_for_sector`, `interior_node` and `sector_type`,
each a pure function of `(seed, sector)`. Edges are sorted by a total order
(vertical first, then `edge_ref`), routings and turns are tried in a fixed
order, the merge rule is commutative, and the output is sorted by cell. No
hash is drawn, so there are no new salts. `mise run raster-check` compares
every sample sector against a rasteriser on a fresh graph.

## Parameters and salts

| Constant | Value | Where | Meaning |
| --- | ---: | --- | --- |
| `CELL_SIZE` | 2 m | `WalkableGraph` | cell edge |
| `cells_per_sector()` | 24 | `WalkableGraph` | cells per sector edge |
| `STRATUM_PITCH_CELLS` | 3 | `WalkableGraph` | floor levels; steps per stair flight |
| `ORIENTATION_UP`, `ORIENTATION_DOWN` | 4, 5 | `EdgeRasteriser` | vertical orientations |
| `RUN_SEARCH_LIMIT` | 64 | `EdgeRasteriser` | flights a stair run search lays before it gives up on one start |
| `HEADROOM_CELLS`, `headroom_cells` | 1 | `EdgeRasteriser` | headroom cells above a flat cell or side portal, one more above a stair (decision #171) |
| `HEADROOM_CLEAR` | 1.8 m | `TileLibrary` | empty height above the cell bottom a tile needs to count as headroom |

| Salt | Used by | Decides |
| ---: | --- | --- |
| 904 | `raster_check.gd` only | the sample sectors |

## Measured shape

`mise run raster-check`, 1 000 random sectors within ±100 000 sectors, 200
per seed 0 to 4: 698 have edges (1 606 edges), 47.0 records per sector with
edges (0.34 % of its cells), 32.8 over all sampled sectors. 37 edges take a
fallback routing, none is rejected, no record lies directly above or below
a stair cell, every walk passes the level rule and every sector's records
are one 26-connected group.

| Family | Records |
| --- | ---: |
| floor | 17 245 |
| stair | 6 154 |
| bridge | 2 278 |
| catwalk | 2 486 |
| tunnel | 1 898 |
| portal opening | 1 601 |
| ladder | 1 134 |

Level changes: 576 horizontal edge ends change level. They produce 3 957
stair cells; vertical edges add 2 197 stair cells, ladders 1 134 cells
(counted along the walks, before merging) and turning runs 112 landing
cells.

**Headroom rule (#161).** Without it the same sample had 52 record pairs
directly above or below a stair cell (4, 12, 13, 11 and 12 for seeds 0 to
4), 1 fallback routing and 100 landings. The rule moves 36 more edges to a
later routing (a turned stair run or a detour) and adds 12 landings; floor,
bridge and tunnel cells change by under 2 % and stair cells not at all.

**Portal level rule (#132).** Before portals on x and z faces took the lower
sector's hub level, their heights were hashed on their own and both ends of
a horizontal edge usually climbed. The same 1 000 sectors then had 1 148
horizontal edge ends changing level and 8 313 stair cells on them:

| Mean stair cells | Per sector | Per sector with edges |
| --- | ---: | ---: |
| hashed portal heights | 10.53 | 15.28 |
| lower sector's hub level | 6.19 | 8.99 |

Vertical edges are unchanged (2 213 stair cells), so the saving is all on
horizontal edges, which now climb on one side only: 52 % fewer stair cells
there. Biasing the node levels further is an open decision (#143).

A scratch run over 10 000 sectors (2 000 per seed) passed every check too:
16 396 edges, 11 on a fallback routing, none rejected, 62 299 stair cells
(40 713 on horizontal edges changing level, 6.23 per sector) and 971
landings; with hashed portal heights it had 105 327 stair cells.

## Open questions

- Walks are one cell wide. Headroom reserves the cells above them, but not
  the cells beside them; a walker brushing a column in the next cell is
  possible.
- Bridge and catwalk records still take tiles with a parapet or railing on
  one side, which blocks a walk turning in that cell; floor records drop
  tiles that block a face their walk crosses (#173). `walk-check` covers
  stratum sectors only.
- Tunnels need a headroom tile with rock above (a tunnel vault) before a
  solid sector with records can build its domains.
- A stair next to a portal can make the walkway pass beside or under the
  stair and double back (a switchback). It is walkable but not the shortest
  path.
- A stair edge's two halves are not aligned across the face; the vertical
  opening pair bridges them.
- Node levels are still independent hashes, so a horizontal edge between
  two open sectors climbs in its upper sector unless both nodes drew the
  same of the 7 levels. Whether to correlate node
  levels to cut stairs further is decision #143; biasing a node towards its
  neighbours' portal levels would make it read their node levels and break
  the rule that every point is a function of its own sector.
- Rejected edges keep only their portal cell and would break walking. None
  appears in the samples; if one does, the check fails.

## References

- [[RESEARCH_WFC]], section 1 (pre-collapsed cells as domain restrictions),
  section 3 (contradictions only between inconsistent pre-collapsed cells)
  and section 7, B4.
- [[MEGASTRUCTURE_CONCEPT]], sections 2.2 and 2.3 (edges are the fill
  layer's only hard constraint; path cells pre-collapsed to floor, stair and
  bridge tiles) and 3 (stair: one stratum per tile).
- [[walkable-graph-connectivity]] and
  [[sector-skeleton-and-walkable-graph#Nodes and portals]]: the edges,
  portals and interior nodes drawn here.
- [[merrell-2007-example-based-model-synthesis]]: fixed cells as the
  constraints of a block solve.
- Glossary: [[GLOSSARY#Edge rasteriser]], [[GLOSSARY#Tile family]],
  [[GLOSSARY#Merge rule]], [[GLOSSARY#Hub]], [[GLOSSARY#Domain restriction]],
  [[GLOSSARY#Pre-collapsed cell]], [[GLOSSARY#Portal]].
- Code: [[walkable-graph]].
