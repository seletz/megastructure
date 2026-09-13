---
tags:
  - algorithm
  - skeleton
  - graph
  - milestone/0.2.0
  - implemented
  - planned
status: draft
---

# Sector Skeleton and Walkable Graph

> [!summary]
> Before any tile is placed, the world is laid out at two coarse levels. The
> **skeleton** divides space into 48 m sectors and gives each a type (stratum,
> shaft, cavity, solid or chasm) from a hash of its coordinates, with rules
> that make shafts run vertically and voids cluster. The **walkable graph**
> then connects the open sectors: a portal on each shared face, a spanning
> tree so everything is reachable, and a few extra edges so there are loops.
> The graph is the only thing the tile solver must obey; it guarantees the
> world can be walked by construction instead of by luck.

> [!warning] Partly planned
> The hashed sector grammar is implemented (issue #76,
> [[0015-hashed-multi-scale-sector-grammar]]) and drawn by the skeleton
> viewer (#77, `mise run run-skeleton`, see [[skeleton]]); its parameters are
> defaults still to be tuned there (#78). The walkable graph is
> not implemented or decided yet. It collects the design from
> [[MEGASTRUCTURE_CONCEPT]] and [[RESEARCH_WFC]] into one place, with a
> sketch of how it could work, so the graph issues start from a shared
> picture. Expect it to change.

## Where it sits

```mermaid
flowchart LR
    S["skeleton<br/>sector_type(seed, sector)"] --> G["walkable graph<br/>portals, tree, loops"]
    G --> R["rasterised path cells<br/>domain restrictions"]
    R --> W["fill layer<br/>WFC per sector"]
    S --> W
```

Each layer reads only the layers before it, and every step is a pure function
of the seed and coordinates, drawn from the [[integer-hash]].

## The hashed sector grammar

Sectors are 48 m cubes, 24 fill cells of 2 m on a side. The concept defines
five types:

| Type | Rule of thumb | Prototype analogue |
| --- | --- | --- |
| stratum | the default; horizontal floors every 6 m | slabs and column grid |
| shaft | vertical void 4 to 16 m wide, prefers to continue up and down | shaft cells, hash < 0.42 |
| cavity | rare, enormous, spans several sectors | cavity cells, hash < 0.14 |
| solid | impassable mass that hides one region from the next | implicit |
| chasm | very rare long vertical canyon between facades | the exterior prototype |

`Skeleton.sector_type(seed, cell)` takes the seed and the sector index
`Vector3i(ix, iy, iz)` (sector `i` covers `48 i` to `48 (i + 1)` metres on
each axis) and returns one of `STRATUM`, `SHAFT`, `CAVITY`, `SOLID` or
`CHASM`. It never looks at neighbouring sectors, so any sector can be asked
in any order. Structure comes from hashing at several scales, the same way
the interior prototype [megastructure.html](../megastructure.html) does: its
shafts are decided per 48 m column in `x, z` (salt 10, size 11, offset 12 and
13), so a shaft runs the full height; its cavities per 112 m cube (salt 20,
sizes 21 to 23, offsets 24 to 26), so one void covers parts of several
sectors. In the skeleton every rule is decided on a cell **coarser than one
sector**, and the hash of that coarse cell places a run, box or plane of
sectors inside it.

### Rules

Rules are tested in order of precedence; the first rule that claims the
sector decides its type:

**chasm > cavity > shaft > solid > stratum**

1. **Chasm.** The world is cut into bands `chasm_band` = 32 sectors wide in
   `x` and `chasm_band_height` = 64 sectors tall in `y`. With probability
   `chasm_probability` = 0.02 a band holds one canyon `chasm_width` = 6
   sectors (288 m) wide, at a hashed `x` offset, with a hashed height of 16
   to 48 sectors at a hashed `y` offset. It runs without end along `z`.
   Chasms override everything because they are the rarest and largest
   feature and must cut cleanly through the rest.
2. **Cavity.** Space is cut into cubes of `cavity_cell` = 3 sectors (144 m,
   resolving the concept's 112 m cavity grid to a whole number of sectors).
   With probability `cavity_probability` = 0.14 a cube holds one box, 2 to 3
   sectors along each axis at a hashed offset. Voids cluster because one hash
   opens several sectors at once.
3. **Shaft.** Each column `(ix, iz)` is cut into vertical segments of
   `shaft_segment` = 12 sectors. With probability `shaft_probability` = 0.42
   a segment holds one run of 3 to 9 sectors at a hashed start, so shafts
   continue vertically. A shaft inside a cavity or chasm is swallowed by it.
4. **Solid.** Space is cut into blocks of `solid_grid` = 5 sectors. Every
   band of blocks along `x` has one wall plane at a hashed `x` offset shared
   by the whole band, so walls of neighbouring blocks line up; likewise along
   `z`, and a floor plane along `y`. Each block closes its `x` wall and its
   `z` wall with `solid_wall_probability` = 0.35 and its floor with
   `solid_floor_probability` = 0.15. Solid therefore comes in 5 × 5 sector
   slabs that separate the world into blocks; shafts, cavities and chasms
   punch through them.
5. **Stratum** otherwise: the default, horizontal habitable layers.

Integer choices (lengths, sizes, offsets) take the 32-bit `hash3_u` modulo
the range; chances compare `hash3` with the probability. Coarse cells use
floor division, so negative sectors fall into the cell below zero instead of
sharing cell 0. Parameters out of range (a minimum above its maximum, a box
larger than its cell, a zero cell size) are clamped when read, so the
function is total for every parameter set.

### Salts

Salts 100 to 139 belong to the skeleton; they do not overlap the prototype
and shader salts (below 100).

| Salt | Key | Decides |
| ---: | --- | --- |
| 100 | `(ix, floor(iy / shaft_segment), iz)` | segment holds a shaft run |
| 101 | same | shaft run length |
| 102 | same | shaft run start in the segment |
| 110 | `floor(cell / cavity_cell)` | cube holds a cavity |
| 111, 112, 113 | same | cavity size in x, y, z |
| 114, 115, 116 | same | cavity offset in x, y, z |
| 120 | `(floor(ix / solid_grid), 0, 0)` | x wall plane offset of the band |
| 121 | `(floor(iz / solid_grid), 0, 0)` | z wall plane offset of the band |
| 122 | `(floor(iy / solid_grid), 0, 0)` | floor plane offset of the band |
| 123 | `floor(cell / solid_grid)` | block closes its x wall |
| 124 | same | block closes its z wall |
| 125 | same | block closes its floor |
| 130 | `(floor(ix / chasm_band), floor(iy / chasm_band_height), 0)` | band holds a chasm |
| 131 | same | chasm x offset |
| 132 | same | chasm height |
| 133 | same | chasm y offset |

Salt 900 is used only by the histogram test to pick random cells.

### Parameters

The parameters live in a `SectorGrammar` resource with `@export` fields, so
they can be edited in the inspector, saved as `.tres` and changed live in the
skeleton viewer's tweak panel, which generates its sliders from those
exports. `Skeleton.new()` uses the defaults above; `Skeleton.new(grammar)`
takes a tuned one.

### Worked example

Seed 0, the 9 × 9 × 9 sectors centred on the origin: 459 stratum, 99 shaft,
46 cavity, 125 solid and no chasm (chasms are too rare to appear in so small
a window). The full table, per layer, is [[skeleton_histogram_seed0]]. Over a
larger window of 200 × 80 × 40 sectors about 61 % are stratum, 19 % shaft,
8 % cavity, 12 % solid and 0.7 % chasm, and a vertical shaft run is 4.7 sectors
long on average.

## The walkable graph

### Nodes and portals

- One **portal** on each face shared by two adjacent non-solid sectors. Its
  position on the face is hashed, snapped to the 2 m cell grid and, on
  vertical faces, to a floor height so corridors meet floors.
- One **interior node** per stratum sector.
- The portal between sector `s` and `s + axis` is keyed by `s` and the axis,
  so both sectors compute the same point without talking to each other, as
  the faces in [[model-synthesis-and-sectors]] do.

### Spanning tree plus loops

Every pair of adjacent open sectors is a candidate edge with a hashed weight.
Kruskal's algorithm takes the edges from lightest to heaviest and keeps an
edge only if it joins two groups that are not yet connected (tracked with
union-find). The result is a **spanning tree**: every open sector reachable from
every other one it touches through open sectors, and no cycles. A second hash then adds a few of the rejected edges back, which
gives **loops**, so the player is not always walking a dead-end tree.

**Worked example.** A 3 × 3 slice of sectors with a solid one in the middle:

```
 A  B  C
 D  #  E
 F  G  H
```

The candidate edges form a ring: A–B, B–C, C–E, E–H, H–G, G–F, F–D, D–A.
Say the hashed weights put C–E last. Kruskal accepts the first seven edges,
each joining new sectors, and rejects C–E because C and E are already
connected the long way round. The loop hash then decides whether C–E comes
back as an extra edge.

```mermaid
graph LR
    A --- B
    B --- C
    E --- H
    H --- G
    G --- F
    F --- D
    D --- A
    C -.-|loop if hashed in| E
```

Vertical edges (stairs, ladders) should be rare and long: give them heavier
weights so the tree prefers horizontal edges, and a low loop probability. The
edge type (corridor, stair, ramp, ladder, bridge across a shaft or cavity,
catwalk along a shaft wall) follows from the two sector types and the axis.

### Output: the fill contract

Each sector gets a short list of edges with endpoints in local coordinates.
A rasteriser turns it into per-cell domain restrictions for the solver:
corridor cells may only be floor-like tiles, stair cells a specific oriented
stair. These restrictions are the only hard constraint the fill layer takes
from the graph ([[wave-function-collapse]]). Restricting a cell to a family
instead of a single tile leaves the solver room to place walls and columns
around the path.

## How it is checked

- `mise run skeleton-histogram` (part of `mise run check`) prints the seed 0
  histogram, checks that `sector_type` returns a type for 2 000 random cells
  and the int32 extremes, also under an out-of-range grammar, that two
  evaluations of 2 000 random cells agree, and that the histogram matches
  [[skeleton_histogram_seed0]].

Planned for the graph:

- A union-find pass over every 5³ window for seeds 0 to 9 reports the number
  of connected components of open sectors.
- Portal positions are compared from both sectors of a face over many random
  pairs.
- The rasterised records of one sector never conflict (the same cell with two
  disjoint restrictions).
- A debug view draws the graph as coloured lines around the free-fly camera.

## Open questions

- **Region boundaries.** The concept builds the tree per region of 3³
  sectors. Inside a region that guarantees connectivity; between regions,
  some edges across the region border must be kept too, and which ones must
  be decided from both sides identically. A single global minimum spanning
  tree is unique for distinct hashed weights but cannot be computed locally.
- **Solid that separates.** The grammar wants solid mass to split regions,
  while the connectivity check wants one component per window. Either
  corridors may tunnel through solid sectors, or the check counts components
  per window only where they touch the window's open boundary.
- **Per sector or per region.** The concept leaves open whether the graph is
  built per sector (fast, local) or per region (better long paths), and
  suggests starting with 3³ regions.
- **Vertical travel.** Stairs, ramps or ladders: what reads best and what the
  capsule controller handles.
- **Hashed or cellular grammar.** Whether the pure hash version looks
  structured enough, to be judged in the skeleton viewer (#77, #78). The
  first version is hashed ([[0015-hashed-multi-scale-sector-grammar]]).

## References

Sources:

- Kruskal 1956, On the Shortest Spanning Subtree of a Graph and the
  Traveling Salesman Problem

Related notes: [[MEGASTRUCTURE_CONCEPT]] (skeleton and walkable graph),
[[RESEARCH_WFC]] (epics A and B), [[model-synthesis-and-sectors]],
[[wave-function-collapse]], [[integer-hash]].

Code: [[skeleton]] describes `SectorGrammar` and `Skeleton`; the graph has
no code yet. The interior prototype
[megastructure.html](../megastructure.html) shows the multi-scale hashed
shafts and cavities the grammar starts from.
