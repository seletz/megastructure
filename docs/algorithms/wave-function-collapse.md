---
tags:
  - algorithm
  - wfc
  - milestone/0.2.0
  - implemented
status: current
---

# Wave Function Collapse

> [!summary]
> Wave Function Collapse (WFC) fills a grid with tiles so that every pair of
> neighbours is allowed by a set of rules. Each cell starts with every tile
> still possible. The solver repeatedly picks the most constrained cell,
> commits it to one tile, and removes from the neighbouring cells every tile
> that no longer fits, which may ripple further. If some cell runs out of
> options, the attempt failed and is restarted with a different random
> stream. The fill layer of milestone 0.2.0 uses the simple-tiled variant
> to place hand-made meshes inside each 48 m sector, with every random choice
> taken from the [[integer-hash]] so the same seed always builds the same
> world. This note explains the algorithm and the choices recommended in
> [[RESEARCH_WFC]]; the solver core is implemented in [[sector-solver]]
> (restarts and pre-collapsed cells follow).

## The idea in one paragraph

Think of a sudoku where each square can hold one of a few tiles and the rules
say which tiles may sit next to each other. A cell's set of still-possible
tiles is its **domain**; the whole grid of domains is the **wave**. The solver
alternates two moves. **Observe:** pick a cell and choose one tile from its
domain. **Propagate:** remove from the neighbours every tile that has no
allowed partner left in this cell, and repeat for any neighbour that changed.
When every domain holds exactly one tile, the grid is done. The name is a
metaphor from quantum physics; no physics is involved.

There are two flavours. The **overlapping model** learns small patterns from
an example image. The **simple-tiled model** takes an explicit tileset with
adjacency rules. The project uses the simple-tiled model, because our tiles
are hand-authored meshes and their rules come from sockets on their faces
([[socket-adjacency]]).

## Worked example

Three tiles on a 3 × 3 grid: **S** (sea), **C** (coast) and **L** (land). The
only rule: sea may never touch land. Allowed neighbours:

| tile | may sit next to |
| --- | --- |
| S | S, C |
| C | S, C, L |
| L | C, L |

**Start.** Every cell holds `SCL`. The top-left cell is pre-collapsed to sea
and the bottom-right to land, the way a sector's path cells will be.

**Propagate the constraints.** The neighbours of the sea cell lose `L`; the
neighbours of the land cell lose `S`. Their neighbours would need to lose
tiles with no partner in `SC` or `CL`, but every tile still has one, so the
ripple stops:

```
 S    SC   SCL
 SC   SCL  CL
 SCL  CL   L
```

**Observe.** Four cells share the smallest domain (two tiles). A hashed
tie-break picks the top-middle cell, and a hashed weighted draw picks `S`.
Propagating removes `L` from its right and lower neighbours:

```
 S    S    SC
 SC   SC   CL
 SCL  CL   L
```

**Observe again.** The centre cell is chosen and becomes `S`. Its right and
lower neighbours had `CL`; only `C` may touch sea, so both become `C`, and
that ripples no further:

```
 S    S    SC
 SC   S    C
 SCL  C    L
```

Three more observations finish the grid, for example:

```
 S    S    C
 S    S    C
 C    C    L
```

The coast appears on its own between sea and land. That is the whole trick:
local rules, applied consistently, produce structure nobody drew.

## Choosing the next cell

The order of observations matters a lot for how often the solver fails.
Collapsing the most constrained cell first keeps the solver from painting
itself into a corner elsewhere.

- **Shannon entropy** (Gumin's original): for a domain with tile weights
  `w_i` summing to `W`, `H = log W - (Σ w_i log w_i) / W`, plus a little noise
  to break ties. Weights influence the order.
- **Minimum remaining values (MRV)**, the classic constraint-solving name:
  pick the cell with the fewest tiles left. Karth and Smith showed WFC is
  ordinary constraint solving with this kind of heuristic.
- **Scanline:** plain row-by-row order. Merrell found it fails less on large
  outputs, at the cost of directional artefacts.

The recommendation for 24³ sectors is MRV with a hashed tie-break: integer
only, so bit-identical between GDScript and a later native port, and at this
size indistinguishable from entropy. Shannon entropy stays available behind a
flag for comparison.

## Propagation

Removing a tile from a cell can make tiles in the neighbours unsupported.
The solver keeps a queue of changed cells and, for each one and each of the
six directions, intersects the neighbour's domain with the union of what the
remaining tiles allow in that direction. A neighbour that shrank goes into the
queue. This is the textbook algorithm **AC-3**.

With domains stored as bitsets, one bit per tile, the union and intersection
are a few OR and AND operations on 64-bit words. With about 80 tiles
(prototypes times rotations) a domain is two words, so a 24³ sector's wave is
27 648 integers. The alternative, **AC-4**, keeps a support counter per cell,
tile and direction; it is faster per update but needs about 6.6 million
counters per sector, which is heavy for GDScript. The bitset tables are built
once from the sockets ([[socket-adjacency]]).

## Contradictions and restarts

A **contradiction** is a cell whose domain became empty. The smallest one:
remove the coast tile from the example tileset and pre-collapse a sea cell
and a land cell with one cell between them. That cell must touch both, and no
tile may, so its domain empties during the first propagation. Contradictions
that come from bad pre-collapsed cells are bugs and fail on every attempt.
Contradictions that come from unlucky observations are rarer: propagation
only checks neighbour pairs, so in two and three dimensions an early choice
can doom a cell several steps away around a loop.

The policy recommended in [[RESEARCH_WFC]]:

1. **Restart** the sector with the attempt number bumped into the hash salt,
   up to a cap (for example 8). No state survives between attempts.
2. After the cap, **degrade** deterministically: keep the pre-collapsed path
   cells, fill the rest from an all-solid assignment, log the sector. The
   player still gets a walkable path.
3. **No backtracking.** It works (DeBroglie implements it) but costs time and
   memory, and frequent failures at this size point to a tileset problem.

A generic `solid` tile that fits next to almost anything is the pressure
valve: as long as most cells can fall back to solid, most observations
cannot doom the sector.

## Determinism from the hash

Every choice the solver makes must be a pure function of the seed, the
sector and the attempt number:

- **Tie-break between equally constrained cells:** a priority per cell from
  `hash3_u(seed, world_cell, salt + attempt)`; the lowest priority wins.
- **Weighted tile choice:** prefix sums of integer tile weights over the
  remaining domain, indexed by a hash of the same cell with another salt.
  Each cell is observed at most once per attempt, so its coordinates plus the
  attempt number are a unique key for the draw.
- **No `RandomNumberGenerator`**, whose algorithm Godot documents as an
  implementation detail, and no floats in any comparison that affects the
  result.

Because the draws are keyed by world cell coordinates, the result does not
depend on the order sectors are generated in, or on which thread solves them.

## Implementation

`SectorSolver` ([[sector-solver]], code in [[solver]]) follows this note
with these concrete choices:

- **Wave and propagation:** one `PackedInt64Array` of bitset words, bitset
  AC-3 with the union of a domain's allowed sets read from byte-sliced
  tables; AC-4 costs more in GDScript because an observation removes almost
  every tile of a cell at once.
- **Cell choice:** minimum remaining values in an indexed heap, ties broken
  by a hashed priority per cell per attempt; Shannon entropy behind
  `use_entropy`.
- **Tile choice:** integer weights (weight × 1000) and the draw
  `hash3_u(attempt seed, cell, 9300 + step) * total >> 32`, which answers
  the modulo bias question: a multiply-shift has no modulo, and its bias is
  below `total / 2³²`. The step counter in the salt is the running counter
  [[RESEARCH_WFC]] sketches; the draws depend on the observation order, which
  is itself deterministic.
- **Contradictions:** the solve stops and reports the cell; restarts, the
  all-solid degradation and pre-collapsed cells are the next step (#91).

`mise run solver-check` solves 8³ grids with the placeholder tileset,
compares two solver instances and a recorded reference
([[solver_reference_seed0]]), and times a 24³ sector (about 0.63 s).

## Open questions

- **How universal solid is.** A fully universal solid makes contradictions
  impossible but lets stairs run into walls. The research recommends a few
  sockets that refuse solid, and accepts rare restarts.
- **Entropy or MRV.** To be decided with benchmark data from the solver epic
  (#137); first numbers are in [[sector-solver#Measurements]].

## References

Sources:

- Gumin, WaveFunctionCollapse (repository and README)
- Karth and Smith 2017, WaveFunctionCollapse is Constraint Solving in the
  Wild
- Merrell 2021, Comparing Model Synthesis and Wave Function Collapse
- Boris the Brave, Wave Function Collapse Explained
- Boris the Brave, WFC Tips and Tricks
- Marian42, Infinite Procedurally Generated City with the Wave Function
  Collapse Algorithm
- DeBroglie (repository)

Related notes: [[sector-solver]], [[model-synthesis-and-sectors]], [[socket-adjacency]],
[[sector-skeleton-and-walkable-graph]], [[integer-hash]], [[RESEARCH_WFC]],
[[MEGASTRUCTURE_CONCEPT]] (fill layer).

Code: [[solver]], built on the [[hash]].
