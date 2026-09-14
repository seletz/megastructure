---
tags:
  - algorithm
  - wfc
  - streaming
  - milestone/0.2.0
  - implemented
status: current
---

# Face-First Boundaries

> [!summary]
> Neighbouring sectors must agree at their borders, but a sector must never
> depend on which neighbours happen to be loaded. `SectorBoundaries` makes
> the border cells belong to one sector, the lower one of each pair. It
> solves them in a fixed order, each piece from its own hash key: first the
> [[GLOSSARY#Boundary piece|corner]] cell, then the three 23-cell edges, then
> the three 23 × 23 faces, and only then the 23³ interior. Each piece sees
> the pieces of lower levels next to it as [[GLOSSARY#Fixed face|fixed
> faces]], whether they lie in its own sector or across a border. Nothing a
> piece uses depends on the order of the calls, so a face computed for
> sector S is bit for bit the face computed for its neighbour: 100 of 100
> random faces matched. So far no solved pair has shown a socket mismatch.
> On the placeholder tileset, border cells may only hold tiles that accept
> air on their open sides ([[GLOSSARY#Open boundary rule|open boundary
> rule]]). A 24³ sector then always solves without records, but it holds
> only open tiles, and no real sector with records solves yet (#162, #163).

This is milestone 0.2.0 item D3 of [[RESEARCH_WFC]] section 7 and the
scheme of [[model-synthesis-and-sectors]], built on [[sector-solver]]. Code:
[[solver]].

## Interface

```gdscript
var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
var boundaries := SectorBoundaries.new(library, seed, EdgeRasteriser.new(WalkableGraph.new(seed)))
var sector := boundaries.solve_sector(seed, Vector3i(3, 0, 7))
# sector.cells (24³ tile indices), sector.solved, sector.degraded,
# sector.failed, sector.errors, sector.interior, sector.level_usec
boundaries.face(Vector3i(3, 0, 7), TilePrototype.FACE_POS_X)  # 24 × 24, u + 24 * v
boundaries.edge(Vector3i(3, 0, 7), 1)                         # 24 cells along y
boundaries.corner(Vector3i(3, 0, 7))                          # one tile
```

- Without a rasteriser (`SectorBoundaries.new(library, seed, null, n)`)
  every cell starts free and the grid has `n` cells per axis. Tests use 8.
- `face(s, dir)` for `dir` +x, +y or +z is the layer of `s` itself.
  For −x, −y or −z it is the layer of the neighbour `s + dir`. The
  indices are those of `SectorDomains` fixed faces: `u + n * v`, with u and
  v the other two axes in xyz order.
- Pieces are cached per instance. `solve_sector` with a different seed clears
  the cache; so does `clear_cache()`.

## What a boundary is

With `n` cells per axis and `m = n − 1`, every cell of a sector with at
least one coordinate at `m` is a boundary cell. The count of coordinates at
`m` gives its level:

| Level | Piece | Cells of owner `s` | Size (n = 24) | Constrained by |
| --- | --- | --- | --- | --- |
| 0 | corner | `(m, m, m)` | 1 | nothing |
| 1 | edge along `a` | coordinate `a` in `0..m−1`, the others `m` | 23 | its 2 corners |
| 2 | face across `a` | coordinate `a` at `m`, the others in `0..m−1` | 23 × 23 | its 4 edges |
| 3 | interior | every coordinate below `m` | 23³ | its 6 faces |

A sector owns one corner, three edges and three faces: 1 + 69 + 1 587 +
12 167 = 13 824 cells. The border with a sector's negative neighbours
belongs to those neighbours. To compose itself a sector uses 8 corners, 12
edges, 6 faces and its interior. These are the pieces owned by `s + d` with
`d` in `{−1, 0}³`, limited to the offsets that are zero along the axes a
piece spans.

Two cells of the same level only touch inside one piece. A face cell
`(m, y, z)` touches edges at `y = m` or `y = −1` (the neighbour's `m`), and
interior cells along x. An edge cell touches corners along its axis and
faces across it. The levels therefore form a fixed dependency tree of depth
four. Why the lower sector's layer and not a shared layer or a two-cell
slab: decision #162.

## Steps

1. **Owner domains.** With a rasteriser, `SectorDomains.for_sector` gives
   the owner's `n³` words: records, the sector type's default and support
   columns. When its records cannot hold, the error is kept for the
   interior. The boundary pieces use the type's default without records
   instead, so neighbours still get a border.
2. **Piece domains.** Copy the owner's words for the piece's cells, or the
   full domain without a rasteriser.
3. **Open boundary rule.** A cell of a corner, edge or face without a
   record keeps only the tiles that accept the air tile in each direction
   whose neighbour has a higher level. This neighbour can be in its own
   sector or across the border. With this rule, air in every higher-level
   cell is always a valid completion (decision #163).
4. **Fixed faces.** For each of the six sides of the piece's grid, each
   neighbouring cell one step outside is normalised into its owning sector.
   When its level is lower than the piece's, its tile comes from that
   sector's cached piece, which is solved first if needed. The tiles go into
   `SectorDomains.apply_faces`. A cell left empty makes the piece `FAILED`.
5. **Solve.** `SectorSolver` for the piece's grid size runs with seed
   `hash3_u(seed, owner, 9000 + kind)`, sector `owner` and the domains, with
   the usual restarts and degradation.
6. **Failure.** A `FAILED` piece, or the interior of a sector whose records
   cannot hold, is filled with the solid tile. A `DEGRADED` piece is solid
   already. Either way the sector reports `solved = false`, the counts and
   the errors.
7. **Compose.** Interior cells come from the interior piece. Boundary cells
   come from the corner, edge or face piece that owns them.

**Records on the border.** A record on a boundary cell comes from the owner
sector's rasteriser output. Its cell is exempt from the open boundary rule.
The rasteriser also puts the partner record, such as the other portal
opening of an edge, in the upper sector at coordinate 0. That cell belongs
to the upper sector's interior, faces or edges, which see the owner's layer
as fixed. When the two sides' records are compatible (two side portal
openings face to face), both hold. When they differ, the owner's layer does
not change. The upper sector's piece then starts with an empty cell or
contradicts. It fails or degrades, and that sector is not solved. This is
the case, for example, for an up opening under a down opening on this
tileset (#159). The border never depends on which side asked.

## Worked example

A 4³ grid (`n = 4`, `m = 3`) at seed 0, sector (0, 0, 0), no rasteriser.

**Seeds.** The corner solves with `hash3_u(0, (0, 0, 0), 9000) =
1906124928`, the face across x with salt 9004 (`1357551361`) and the
interior with 9007 (`3511433818`). Within each solve, attempts draw from
salts 9100 and up as usual.

**Corners.** `corner((0, 0, 0))` is `air@0`, `corner((0, −1, 0))` is
`bridge@0` and `corner((0, 0, −1))` is `air@0`. None of them has a lower
level, so each is a 1 × 1 × 1 solve. The open boundary rule leaves only
tiles that accept air on all six sides: air, column and the two bridges.

**Edges.** The edge along z of (0, 0, 0) covers cells `(3, 3, z)` for z = 0
to 2. Its +z neighbour is `(3, 3, 3)`, the corner of (0, 0, 0). Its −z
neighbour is `(3, 3, −1)`, which normalises to cell `(3, 3, 3)` of
(0, 0, −1), that sector's corner. With its corner appended,
`edge((0, 0, 0), 2)` is `air bridge@0 air air`.

**Face.** The face across x covers cells `(3, y, z)` with y, z in 0 to 2.
Its four fixed sides are the edges along z at `y = 3` (own) and `y = −1`
(owned by (0, −1, 0)), and the edges along y at `z = 3` (own) and `z = −1`
(owned by (0, 0, −1)). Its ±x neighbours are interior cells, so every free
cell keeps only tiles with an air-accepting socket on +x and −x. The solved
layer, `u = y` across and `v = z` down:

```
v=0: air air     air      air
v=1: air air     air      bridge@0   <- u = 3 is edge along z, index 1
v=2: air air     bridge@1 air
v=3: air air     air      air        <- v = 3 is edge along y
```

A second instance asked for `face((1, 0, 0), −x)` returns the same 16 tiles:
it normalises to owner (0, 0, 0) and axis x, derives the same seeds and the
same fixed neighbours, and solves the same grid.

**Interior.** The 3³ interior sees six fixed faces: the three layers of
(0, 0, 0) at coordinate 3, and the layers at coordinate 3 of (−1, 0, 0),
(0, −1, 0) and (0, 0, −1). Every face cell accepts air towards it, so an
all-air interior is valid and the solve cannot fail before an attempt.

## Determinism

- Every piece is a pure function of the seed, its owner sector and its kind.
  Its domains come from the owner's records and type. Its fixed faces come
  from pieces of lower levels, which are pure functions by induction. Its
  solve seed is `hash3_u(seed, owner, PIECE_SALT + kind)`.
- The cache only avoids repeating work. `boundary-check` computes each face
  on two instances: the second first solves another face of the neighbour
  and then asks from the neighbour's side. It also composes one sector on a
  second instance after a seed change.
- Dictionaries are only looked up by owner or cell, never iterated. Cells
  and sides are visited in index order. `SectorSolver` is deterministic on
  its own ([[sector-solver#Determinism]]).
- Timing fields vary; nothing else does.

## Parameters and salts

| Name | Value | Meaning |
| --- | --- | --- |
| `PIECE_SALT` | 9000 + kind (0 to 7) | Solve seed of a piece from `(seed, owner)`: corner 0, edges x, y, z 1 to 3, faces x, y, z 4 to 6, interior 7. Below the solver's 9100 to 9300 + step. |
| `cells_per_sector` | 24 (the graph's) | `n`. Boundary pieces are 1, 23 and 23 × 23 cells, the interior 23³. |
| open boundary rule | air | Tiles a record-free boundary cell may hold, per higher-level direction (#163). |
| `SALT_TEST_BOUNDARY` | 906 | Sectors and faces sampled by `boundary-check`. |

## Complexity

With `n` cells per axis, `C = (n − 1)³` interior cells and the solver costs
of [[sector-solver#Complexity]]:

- **Cells solved per sector** (in steady state, neighbours cached): one
  corner, `3(n − 1)` edge cells, `3(n − 1)²` face cells and `(n − 1)³`
  interior cells, exactly `n³`.
- **Cold sector** (nothing cached): 8 corners, 12 edges (276 cells at
  n = 24), 6 faces (3 174 cells) and the interior. That is at most `2n³`
  cells of work for the first sector, less for every neighbour after it.
- **Fixed-face lookup:** `O(1)` per boundary cell of a piece's grid
  (normalise, level, cached piece index).
- **Memory:** one cached `Piece` per owner and kind. With a rasteriser, also
  `n³ · words` domain words per owner (110 KB at 24³ with one word) until
  `clear_cache`.
- **Solver instances:** one per grid size, eight in all. They hold working
  arrays, so an instance must not run two solves at once.

## Measurements

Placeholder tileset (30 tiles), Godot 4.7.2 headless, `mise run
boundary-check` and three cold unconstrained 24³ sectors. The machine ran
slower than for the [[sector-solver]] table: in the same run a plain
unconstrained 24³ attempt took about 2.1 s, against 0.63 s there.

| Level | Pieces of a cold 24³ sector | Time |
| --- | --- | --- |
| corners | 8 | 10 ms |
| edges | 12 | 62 ms |
| faces | 6 | 522 ms (87 ms each) |
| interior | 1 (23³, 1 attempt) | 2.55 s |

| Check | Result |
| --- | --- |
| Faces from S and from S + dir, seeds 0 to 4, real records | 100 of 100 identical; 42 face pieces solved, 58 failed |
| 8³ unconstrained adjacent pairs | 50 of 50 solved, 0 mismatches across the face, 0 inside |
| 24³ unconstrained adjacent pairs | 2 of 2 solved, 0 mismatches |
| 24³ real pairs whose records build | 0 of 50 solved (every pair has a failed piece) |

An unconstrained 24³ sector holds air 11 362, bridge 1 172, ladder 1 026
and column 264 tiles. On the placeholder tileset rock only continues down
and open space only up (#158). Once a boundary cell must accept air, no
column can reach rock above a border, so a sector holds no rock at all. The
same limit fails every real sector: floors and stairs need rock below. The
faces that fail with real records belong to solid owners (only the solid
tile, which does not accept air) or carry floor records. Before the open
boundary rule, and with a rule of air or solid, 4 of 4 unconstrained 24³
sectors failed. Wall, slab edge and catwalk sockets on a border forced
chains through the interior, and independently keyed top and bottom layers
disagreed about where the rock ends.

## Open questions

- **What a face is** (#162): the lower sector's layer, a shared layer or a
  two-cell slab, and corners as their own level.
- **Which tiles a boundary cell may hold** (#163): open to air (current),
  open to solid, weights, or tiles with open space below rock (#153, #158).
- **Records against the tileset** (#159) and **degradation** (#157): a
  failed piece is solid, which may not fit its neighbours.
- **Seams that look like seams:** faces see no hints from the skeleton yet.
- **Cost:** the interior dominates. Faces add about 20 % to a sector, and
  edges and corners add little. The native threshold is #138, the
  benchmark #93.

## References

- [[model-synthesis-and-sectors]]: why face-first, and Merrell's block
  scheme.
- [[sector-solver]]: the solver every piece runs, and its fixed faces.
- [[edge-rasteriser]]: the records on boundary cells.
- [[0009-face-first-order-independent-sector-boundaries]].
- [[RESEARCH_WFC]], sections 1 and 7 (D3).
- Code: [[solver]], [[tools-and-tasks]].
