---
tags:
  - algorithm
  - wfc
  - milestone/0.2.0
  - implemented
status: current
sources:
  - "[[gumin-2016-wavefunctioncollapse]]"
  - "[[karth-2017-wfc-is-constraint-solving]]"
  - "[[merrell-2021-comparing-model-synthesis-and-wfc]]"
  - "[[newgas-2020-wfc-explained]]"
  - "[[fehr-2018-fast-wfc]]"
---

# Sector Solver

> [!summary]
> `SectorSolver` is the project's implementation of
> [[wave-function-collapse]]: it fills a grid of 2 m cells (24³ for a
> sector, any size for tests) with tiles of a [[GLOSSARY#Tile library|tile
> library]] so that every pair of face neighbours is allowed by the
> [[GLOSSARY#Adjacency table|adjacency table]]. The [[GLOSSARY#Wave|wave]]
> is one packed array of [[GLOSSARY#Bitset|bitsets]]. Each
> [[GLOSSARY#Observation|observation]] takes the open cell with the fewest
> tiles left ([[GLOSSARY#Minimum remaining values|minimum remaining
> values]]), ties broken by a hashed priority, and draws its tile by weight
> from the [[integer-hash]]. [[GLOSSARY#Propagation|Propagation]] is bitset
> [[GLOSSARY#AC-3|AC-3]], with the union of a domain's allowed sets read
> from [[GLOSSARY#Byte-sliced table|byte-sliced tables]]. An empty
> [[GLOSSARY#Domain|domain]] is a [[GLOSSARY#Contradiction|contradiction]]
> and ends the attempt. `SectorDomains` turns the edge rasteriser's records,
> the sector type and optional [[GLOSSARY#Fixed face|fixed faces]] into the
> [[GLOSSARY#Starting domains|starting domains]]; the solver propagates them
> once, fails at once if they cannot hold, and otherwise
> [[GLOSSARY#Restart|restarts]] with the next attempt seed after a
> contradiction, up to 8 attempts, before the
> [[GLOSSARY#All-solid degradation|all-solid degradation]]. On the
> placeholder tileset an 8³ grid takes about 19 ms and a 24³ attempt about
> 0.63 s in typed GDScript; every unconstrained 24³ sector of seeds 0 to 19
> solves within 2 attempts, and every real stratum sector sampled reaches an
> attempt, 18 of the 20 at seed 0 solving (#161).

This is milestone 0.2.0 items D1 (the core) and D2 (pre-collapse and the
restart policy) of [[RESEARCH_WFC]] section 7, following sections 3 and 4 of
the research. Code: [[solver]].

## Interface

```gdscript
var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed))
var built := SectorDomains.for_sector(library, rasteriser, sector)   # optional faces
if not built.error.is_empty():
	push_error(built.error)                      # records that cannot hold
var solver := SectorSolver.new(library, Vector3i(24, 24, 24))
solver.use_entropy = false                       # the default: MRV
solver.max_attempts = 8                          # the default
var result := solver.solve(seed, sector, built.words)
# result.outcome (SOLVED, DEGRADED, FAILED), result.ok, result.degraded,
# result.cells (PackedInt32Array), result.attempts, result.restarts,
# result.precollapsed, result.steps, result.propagations, result.time_usec,
# result.contradiction_cell, result.error
```

- **Cells** are indexed `x + size.x * (y + size.y * z)`, the layout of
  [[RESEARCH_WFC]] section 4. `result.cells[i]` is a tile index of the
  library (rotation included), empty unless `ok`.
- **`domains`** (optional) is a `PackedInt64Array` of `cell_count *
  word_count` words ANDed into the starting wave and propagated before the
  first attempt. It is the entry point for
  [[GLOSSARY#Pre-collapsed cell|pre-collapsed cells]] and fixed sector
  faces; `SectorDomains` builds it (below), and the face-first boundary
  solve ([[face-first-boundaries]]) feeds the faces.
- **Outcomes.** `SOLVED`: an attempt filled every cell. `DEGRADED`: all
  `max_attempts` attempts hit a contradiction and every cell holds the solid
  tile (`ok` and `degraded` are true). `FAILED`: bad arguments or starting
  domains that are empty after propagation, with `attempts` 0, no cells and
  `error` saying which cell. `ok` is true for the first two: the cells are a
  valid tiling either way.
- **`result.precollapsed`** lists, ascending, the cells whose starting
  domain `domains` narrowed (record cells, sector defaults and fixed face
  cells alike). `steps` and `propagations` add up over all attempts;
  `contradiction_cell` is the last attempt's.

## Starting domains

`SectorDomains.build(library, size, type, records, faces, support_radius)`
turns one sector's inputs into the `domains` words:

1. **Check each record.** Its cell lies inside the grid, no other record
   has the same cell, its orientation suits its family (a stair a yaw 0 to 3,
   a ladder up, a portal opening a yaw, up or down, every other family 0),
   and at least one tile matches it. The first failure is the `error`,
   naming the record.
2. **Record mask.** A tile matches a record when its prototype's family is
   the record's family and, for the families with a direction, its rotation
   turns the prototype's authored forward yaw onto the record's:
   `(rotation - (yaw - authored)) mod rotations == 0`. A stair is authored
   climbing +x (authored yaw 0), so its rotation is the record's yaw. A
   portal opening is authored as a wall along x whose passage runs along z
   (authored yaw 3), so on a side face its rotation is `yaw + 1` modulo its
   2 rotations. Floor, bridge, catwalk, ladder and tunnel records, and portal
   openings in the floor or ceiling, take every rotation of their family.
3. **Record pairs.** For every two records that are face neighbours, some
   tile of the first must allow some tile of the second in that direction
   (the byte union of step 6 below, done once per pair). Otherwise the
   `error` names both records and the direction: the records are
   inconsistent whatever the seed.
4. **Sector default** for every other cell: free in a stratum, the solid
   tile alone in a solid sector, the air tile alone in a shaft, cavity or
   chasm. Cells in a [[GLOSSARY#Support column|support column]], a full
   height column within `support_radius` (default 1, Chebyshev in x and z)
   of a record's column, stay free, because on the placeholder tileset rock
   only continues down to the grid bottom and open space only up to the top,
   so a stair's rock and headroom need whole columns (decision #158).
5. **Fixed faces** (optional): six arrays in face order +x, −x, +y, −y, +z,
   −z, each empty (free) or one entry per boundary cell, indexed `u +
   size_u * v` with u and v the other two axes in xyz order, holding the
   tile of the neighbour sector's cell across the face or −1. A boundary
   cell with neighbour tile `n` across face `d` keeps `allowed(d ^ 1, n)`:
   the tiles `n` accepts from the opposite side. A cell left empty is an
   `error`.

Starting domains that pass these checks can still be inconsistent across a
few cells (a tunnel needs rock below, a bridge two cells below needs open
space above it, and no tile has open space below and rock above). The
solver finds that when it propagates them.

## Restart policy

1. **Propagate the starting domains once.** AND `domains` into the full
   wave, record every narrowed cell in `precollapsed`, fail with `FAILED` on
   an empty cell, queue the narrowed cells and propagate. An empty domain
   here is `FAILED` too: the starting domains do not depend on the seed, so
   no restart could help, and the error says so at once.
2. **Keep the propagated wave**, counts and keys as the start of every
   attempt.
3. **Attempt `a`** (0 to `max_attempts − 1`): restore the kept wave, draw
   the attempt seed `s = hash3_u(seed, sector, 9100 + a)`, the tie-break
   priorities and the heap from it, then observe and propagate (steps 4 to 7
   below, the observation counter starting at 0). All cells filled:
   `SOLVED`, `attempts = a + 1`.
4. **Contradiction:** remember the cell, `restarts += 1`, clear the queue
   and go to the next attempt.
5. **Degrade** after the last attempt: every cell the library's solid tile
   (`TileLibrary.solid_tile`), `DEGRADED`. Records and fixed faces are not
   kept: solid next to solid is always allowed, while record cells beside
   solid would break sockets on this tileset (decision #157). The caller
   logs the sector.

`max_attempts` is clamped to 1 to 100, so the attempt salts stay below the
tie-break salt. With `max_attempts = 1` a solve behaves as before #91 except
that a contradiction degrades instead of returning no cells.

## Steps of one attempt

1. **Build once per solver** (about 4 ms for the placeholder set): the
   border bits of every cell (which of the six neighbours exist), the full
   domain, integer weights `max(1, round(weight * 1000))`, and per direction
   the byte-sliced union table: for each word, each of its 8 bytes and each
   of the 256 byte values, the OR of the allowed sets of the tiles in that
   byte. The same layout holds the popcount, summed integer weight and
   summed `w log w` of each byte value.
2. **Reset.** Attempt seed `s = hash3_u(seed, sector, 9100 + attempt)`. Every
   cell starts from the propagated starting wave (the full domain without
   `domains`) with its tile count and gets a
   [[GLOSSARY#Tie-break priority|tie-break priority]]
   `hash3_u(s, cell position, 9200)`.
3. **Starting domains** were propagated once before the first attempt
   (Restart policy, step 1).
4. **Heap.** Put every open cell (count above 1) into an
   [[GLOSSARY#Indexed heap|indexed min-heap]]
   keyed by `count << 32 | priority`, ties by cell index.
5. **Observe** the heap's top cell, removing it. Sum the integer weights of
   its domain from the byte tables (`total`), make a
   [[GLOSSARY#Weighted draw|weighted draw]]
   `r = (hash3_u(s, cell position, 9300 + step) * total) >> 32`, then walk
   the bytes and bits subtracting weights until `r` falls inside a tile.
   Set the cell to that tile alone, `step += 1`, queue the cell.
6. **Propagate** until the queue is empty. Pop a cell; for each direction
   `d` whose neighbour exists, `mask = OR over the cell's non-zero bytes of
   union[d][word][byte][value]`, `narrowed = neighbour & mask`. Empty:
   contradiction, return the neighbour. Changed: store it, recount, move the
   neighbour in the heap (or remove it at count 1) and queue it if it is not
   queued yet.
7. **Repeat** 5 and 6 while the heap is not empty, then read the one set bit
   of every cell into `result.cells`.

With `use_entropy` the heap key's upper half is the Shannon entropy
`log W - (Σ w log w) / W` of the integer weights, scaled by 2²⁴ and
truncated, instead of the count; everything else is the same.

## Worked example

The sea, coast and land tiles of [[wave-function-collapse]]: S = 0, C = 1,
L = 2, one word, weights 2, 1, 1 (integers 2000, 1000, 1000). Allowed in
`+x`: S → `011` (S, C), C → `111`, L → `110` (bits written L C S).

**Union table.** Byte 0, value `101` (S and L): the table is filled from
the value without its lowest bit, `100` (L alone, `110`), ORed with S's set
`011`, giving `111`. A cell holding `{S, L}` therefore allows every tile to
its `+x` in one lookup, where the textbook loop would OR two sets.

**Propagation.** A cell collapsed to S (`001`) looks up value `001`:
`mask = 011`. Its `+x` neighbour holds `111`, narrowed to `011`: changed,
count 2, moved up in the heap and queued. That neighbour then looks up
`011`: `mask = 011 | 111 = 111`, and its own `+x` neighbour does not change,
so the ripple stops.

**Weighted draw.** The neighbour `{S, C}` is observed: `total = 3000`. With
a hash of `0x9E3779B9` (2 654 435 769), `r = 2 654 435 769 × 3000 >> 32 =
1854`. Walking the bits: S weighs 2000 and 1854 < 2000, so S is chosen. A
hash above `2000 / 3000` of the range would have reached C.

**Heap.** Three open cells with counts 3, 2, 2 and priorities 7, 9, 4 have
keys `3·2³² + 7`, `2·2³² + 9` and `2·2³² + 4`: the third cell is observed
first (fewest tiles, lowest priority among equals).

## Worked example: records, restarts and degradation

**Tiles.** The placeholder library numbers its 53 tiles air 0, solid 1,
floor 2, slab_edge 3 to 6, column 7, wall 8 and 9, wall_doorway 10 and 11,
stair 12 to 15, bridge 16 and 17, catwalk 18 to 21, ladder 22 to 25, tunnel
26 and 27, portal_opening 28 and 29, floor_open 30, slab_edge_end 31 to 34,
slab_edge_end_f 35 to 38, stair_open 39 to 42, catwalk_end 43 to 46,
catwalk_end_f 47 to 50, portal_frame 51 and 52.

**Record masks.** A stair record with yaw 1 (climbing −z) matches
`stair@1` and `stair_open@1`, bits 13 and 40: `(1 − (1 − 0)) mod 4 = 0`. A
portal opening on the +x face has yaw 0: `(r − (0 − 3)) mod 2 = (r + 3) mod
2 = 0` holds for `r = 1`, so it matches `portal_opening@1` and
`portal_frame@1`, bits 29 and 52, with their passage along x. On the −z
face (yaw 1) it matches bits 28 and 51. A floor record matches bits 2 to 6
and 30 to 38: floor, open floor and every slab edge and slab edge end.

**Record pair.** A bridge at (2, 2, 2) under a tunnel at (2, 3, 2): the
bridge tiles' `+y` sockets are `0i`, so their union in `+y` holds only
tiles with `0i` below, and both tunnels have `1i` below. The intersection
is empty, so `build` returns `Record((2, 2, 2) bridge 0 …) and
Record((2, 3, 2) tunnel 0 …) cannot touch across +y` without touching the
solver.

**Inconsistent across cells.** A bridge at (4, 2, 4) and a tunnel at
(4, 4, 4) are not neighbours, so the pair check passes. Propagating them
narrows (4, 3, 4) to tiles with open space below (for the bridge) and rock
on top (for the tunnel): none. The solve returns `FAILED` with `attempts 0`
and `inconsistent starting domains: cell (4, 2, 4) is left empty by
propagating them` in a few milliseconds.

**Restarts.** An unconstrained 8³ grid at seed 36: attempt 0 uses `s =
hash3_u(36, (0, 0, 0), 9100)` and contradicts after 84 observations;
attempt 1 (salt 9101) solves. With the default 8 attempts the result is
`SOLVED`, `attempts 2`, `restarts 1`, and `steps` (479) counts the
observations of both. With `max_attempts = 1` it is `DEGRADED`: 512 cells
of tile 1, `attempts 1`, `restarts 1`. Seed 36 is the first seed that
restarts at all on the 53-tile set; none of seeds 0 to 2 999 needs a third
attempt.

## Propagation design: AC-3, not AC-4

[[GLOSSARY#AC-4|AC-4]] support counts are the textbook fast propagator
(Gumin's and fast-wfc's choice), and they were considered first. They lose
here because an observation removes nearly every tile of a cell at once,
and AC-4 pays per removed tile: every cell of a solved grid loses
`tiles − 1` tiles, and each removal visits the supports in six directions.
On the first placeholder set (30 tiles, on average 12.2 allowed per direction)
a 24³ sector is `13 824 × 29 × 6 × 12.2 ≈ 29 million` counter updates, each
an interpreted GDScript step, plus `13 824 × 30 × 6 ≈ 2.5 MB` of counters
to fill per solve. Bitset AC-3 pays per changed cell instead: a solved 24³
sector took 137 577 queue pops on average, each at most six directions of
four byte lookups (30 tiles fit in 4 bytes), about 3.3 million lookups. The byte tables make
the union cost independent of the domain size, which is what AC-4 would
otherwise buy. In a native port the balance may shift; the interface does
not depend on the choice.

## Cell choice

Minimum remaining values with a hashed tie-break is the default; Shannon
entropy is behind `use_entropy` until decision #137. The tie-break priority
is drawn once per cell per attempt rather than once per step: a per-step
draw would have to rehash every tied cell at every observation (thousands
of hashes per step, since most open cells share the smallest count), while
a fixed priority is a random permutation of the cells that an indexed heap
can keep ordered. The tile draw does carry the per-solve counter (the step)
in its salt, as [[RESEARCH_WFC]] sketches. The heap is indexed (each cell
knows its slot), so a shrinking domain moves its entry in place; an earlier
lazy heap that pushed a new entry per change spent 40 % of a 24³ solve
popping stale entries (1.0 s against 0.6 s for the same sector and the
same output).

## Complexity

With `C` cells, `T` tiles, `k = ceil(T / 64)` words and `b ≤ 8k` used
bytes:

- **Memory:** wave `C·k` words, counts, keys, priorities, heap slots and
  queue `O(C)`; union table `6·k·8·256·k` words (12 288 for one word, 49 152
  for two), built in `O(k²·8·256·6)`.
- **Per observation:** `O(b)` for the weight sum and draw, `O(log C)` for
  the heap.
- **Per queue pop:** six directions of `O(b·k)` lookups and a recount, plus
  `O(log C)` per changed neighbour.
- **Whole solve:** at most `C` observations and `C·T` domain changes, so
  `O(C·T·(b·k + log C))` in the worst case; measured much lower (below).
- **With restarts:** one propagation of the starting domains, then at most
  `max_attempts` attempts, each restoring `C·k` words and redrawing `C`
  priorities before the work above; a degraded sector costs every attempt.
- **Starting domains:** `O(R·T)` for `R` record masks, `O(R·6·T·k)` for the
  record pairs, `O(C·k)` to write the words and `O(F·k)` per fixed face of
  `F` cells; about 4 ms for a real 24³ sector.

## Measurements

Placeholder tileset as first measured (13 prototypes, 30 tiles, one word),
`mise run solver-check` and a 20-seed run on the development machine, Godot
4.7.2, headless:

| Grid | Heuristic | Solved (seeds 0–19) | Mean / max time of solved | Mean steps / queue pops |
| --- | --- | --- | --- | --- |
| 8³ | MRV | 17 / 20 | 18.6 / 21.6 ms | 337 / 4 253 |
| 8³ | entropy | 20 / 20 | 22.3 / 23.9 ms | 314 / 4 221 |
| 24³ | MRV | 11 / 20 | 633 / 654 ms | 10 334 / 137 577 |
| 24³ | entropy | 16 / 20 | 760 / 1 070 ms | 8 686 / 134 545 |

Failed attempts stop at the contradiction, so they are faster. The table
counts single attempts (`max_attempts = 1`); the time is the first input to
the native threshold (#138) and the benchmark (#93).

On the 20-prototype set (53 tiles, still one word, #161) the same single
attempts solve 20 / 20 at 8³ with MRV and with entropy (379 and 329 mean
steps), and 16 / 20 (MRV) and 17 / 20 (entropy) at 24³ (9 909 and 9 255
mean steps). Measured back to back with the 30-tile set on the same loaded
machine, an 8³ solve takes about 1.3 times as long (145 ms against 110 ms
there), from the longer tile loops.

With restarts (default 8 attempts, MRV):

| Run | Solved | Degraded | Failed before an attempt | Attempts |
| --- | --- | --- | --- | --- |
| 8³ unconstrained, 30 tiles, seeds 0–19 | 20 | 0 | 0 | 17 at the first, 2 at the second, 1 at the third |
| 24³ unconstrained, 30 tiles, seeds 0–19 | 20 | 0 | 0 | 11 × 1, 8 × 2, 1 × 4; mean 1.55, 793 ms mean per sector |
| 20 real stratum sectors with records, 30 tiles, seed 0 | 6 | 0 | 14 | 4, 2, 6, 8, 3, 2; mean 4.17 over the solved |
| 8³ unconstrained, 53 tiles, seeds 0–19 | 20 | 0 | 0 | all at the first |
| 24³ unconstrained, 53 tiles, seeds 0–19 | 20 | 0 | 0 | 16 × 1, 4 × 2; mean 1.2 |
| 20 real stratum sectors with records, 53 tiles, seed 0 | 18 | 2 | 0 | mean 3.10 over the 20 searched |

**Real sectors (#161).** On the 30-tile set, 14 of the 20 real sectors of
seed 0, and 71 of the 100 of seeds 0 to 4, failed before an attempt. `mise
run solver-real` classifies each by the record pair `SectorDomains` rejects
or a minimal record set whose propagation empties a cell:

| Cause | Seed 0 | Seeds 0–4 | Fix |
| --- | ---: | ---: | --- |
| Two side portal openings, or a portal and a floor, in crossing wall planes: a portal opening pulls a wall stack to the grid top and wall ends along the face to the grid edge | 9 | 39 | `portal_frame` |
| A floor or stair beside a portal opening's wall side (the walk reaches the portal along the face) | 3 | 15 | `portal_frame` |
| A floor directly over or under a stair cell, or beside a stair's high end, which is the cell under the next step | 1 | 8 | headroom rule in the rasteriser |
| A floor or stair above an open-topped record in its column: rock only rests on rock, so every floor and stair needs rock down to the grid bottom | 1 | 9 | `floor_open`, `stair_open` |

With the portal frame and a soffit tile alone, 16 of the 100 still failed:
the 8 floor over or under stair pairs and 8 stair flights whose rock under
the run cannot end against open space, fixed by the rasteriser rule and
`stair_open`. Every
sector then reached an attempt but all 100 degraded: with a soffit tile (open
below, rock above) in place of the open floor, rock blobs could float and
their edges have no closing tile; with the open floor instead, 11 of 20
solved at seed 0, and adding end pieces for parapets and catwalks raised
the single-attempt success from 12 % to 56 %
([[socket-adjacency#Worked example: the placeholder tileset]]). Over seeds 0
to 4, 18, 19, 19, 20 and 19 of the 20 sectors solve; the rest degrade.
Solid, shaft, cavity and chasm sectors are not sampled yet. `mise run
solver-check` prints the seed 0 table and checks that seeds 1 to 4 reach an
attempt; `mise run solver-sector <x> <y> <z>` reproduces one sector.

`mise run wfc-bench --boundaries` (#93) at seed 0, the first 10 stratum
sectors walking outwards from the origin, on an Intel i9-9880H shared with
four other headless Godot runs:

| Run | Searched | Mean / max time | Mean attempts | Contradictions | Degraded | Failed before an attempt |
| --- | --- | --- | --- | --- | --- | --- |
| real pipeline | 3 of 10 | 3 359 / 3 568 ms | 1.33 | 1 | 0 | 7 (5 rejected, 2 inconsistent) |
| unconstrained 24³ | 10 of 10 | 3 869 / 5 638 ms | 1.20 | 2 | 0 | 0 |
| face-first boundaries, cold | 10 of 10 | 700 / 861 ms | 10.2 pieces' attempts | 0 | 0 | 10 (every interior) |

A single 24³ attempt took about 3.4 s there against 0.63 s in the table
above, the same slowdown [[face-first-boundaries#Measurements]] saw, so the
machine and its load dominate. Both runs are above the 1 s threshold of
decision #138 as measured; scaled to the 0.63 s attempt above, 1.2 to 1.33
mean attempts would be about 0.8 s, just below it. The boundaries run is
only fast because every interior fails before an attempt. Re-run on an idle
machine before deciding #138.

## Determinism

- Every random value is `Hash.hash3_u`: the attempt seed from `(seed,
  sector, attempt)`, the tie-break from `(attempt seed, cell position)`, the
  tile draw from `(attempt seed, cell position, step)`, the step counted
  from 0 in every attempt. No
  `RandomNumberGenerator`, no `Dictionary` iteration, no floats in the
  default path: weights become integers once, and the draw is an integer
  multiply-shift (a bias below `total / 2³²`, which settles the modulo bias
  question of [[wave-function-collapse]]).
- The heap orders by key, then by cell index, so equal keys cannot depend
  on insertion order. The queue is a stack in a fixed push order.
- `mise run solver-check` solves seeds 0 to 4 on two solver instances and
  requires identical cells, and compares the seed 0 SHA-256 with
  [[solver_reference_seed0]], so a change to the hash, the tileset, the
  library or the solver that alters the output fails `check`.
- **Restarts** start every attempt from the same propagated starting wave
  and nothing of a failed attempt survives but the counters, so attempt `a`
  gives the same cells whether it runs first or after `a` failures, and the
  degradation is a constant. `SectorDomains` iterates records in their given
  order and cells in index order; its `Dictionary` lookups are by cell and
  never iterated. `solver-check` repeats a restarted and a degraded solve on
  a second instance.
- **Entropy mode** computes `log` on doubles. Within one binary it is
  reproducible, but `log` may differ in the last bit between C libraries,
  so it is not guaranteed bit-identical across platforms or a native port.
  MRV is.

## Parameters and salts

| Name | Value | Meaning |
| --- | --- | --- |
| `size` | `Vector3i(24, 24, 24)` | Cells per axis; tests use 8³. |
| `use_entropy` | false | Shannon entropy instead of tile count as the heap key. |
| `max_attempts` | `DEFAULT_MAX_ATTEMPTS` = 8 | Attempts before the all-solid degradation, clamped to 1..`ATTEMPT_LIMIT` (100). |
| `ATTEMPT_SALT` | 9100 (+ attempt, below 100) | Attempt seed from `(seed, sector)`. |
| `TIE_SALT` | 9200 | Per-cell tie-break priority. |
| `CHOICE_SALT` | 9300 (+ step) | Weighted tile draw of the observation `step`. |
| `WEIGHT_SCALE` | 1000 | Fixed-point tile weights; weights have 0.001 steps. |
| `MAX_TOTAL_WEIGHT` | 2³¹ − 1 | Largest summed domain weight (an error beyond). |
| `ENTROPY_SCALE` | 2²⁴ | Fixed-point scale of the entropy key. |
| `SectorDomains.SUPPORT_RADIUS` | 1 | Chebyshev radius in x and z of the free support columns around records in solid and void sectors. |
| `SectorDomains.AUTHORED_YAW` | stair 0, portal opening 3 | Forward yaw of the prototype at rotation 0 for the families whose rotation follows the record. |

The salts sit above every other salt in the project (the tile placement of
`tiles-check` uses 8701 to 8703), and each counter has its own range: up
to 100 attempts from 9100, the tie-break at 9200, and the step counter
counting up from 9300 into salts nothing else uses.

## Open questions

- **MRV or entropy** (#137): entropy solved 16 of 20 sectors against 11
  of 20 at 24³ on the placeholder set, at 20 % more mean time.
- **The solid policy** (#136): restarts solve every unconstrained sector
  measured; records raise the attempts to about 3 per sector.
- **Records against the tileset** (#159): every sampled real stratum sector
  reaches an attempt and 18 of 20 solve at seed 0 (#161); tunnels are the
  largest remaining source of contradictions, and the look of the added
  tiles (open floors and stairs, free-standing portal frames, weights) is
  still open.
- **What degradation keeps** and whether inconsistent sectors degrade
  instead of failing (#157).
- **Default domains** of solid and void sectors (#158).
- **Native threshold** (#138): 0.63 s mean per successful 24³ attempt,
  0.79 s per unconstrained sector with restarts.

## References

- [[wave-function-collapse]]: the algorithm explained, with the sea, coast
  and land example.
- [[socket-adjacency]]: where the allowed bitsets come from.
- [[RESEARCH_WFC]], sections 1, 3, 4 and 7 (D1, D2).
- [[edge-rasteriser]]: the records the starting domains come from.
- [[face-first-boundaries]]: corners, edges and faces solved before the
  interior, each a solve of this solver with fixed faces.
- [[0010-near-universal-solid-tile-with-seeded-restarts]],
  [[0011-typed-gdscript-solver-first]].
- Papers: [[gumin-2016-wavefunctioncollapse]],
  [[karth-2017-wfc-is-constraint-solving]],
  [[merrell-2021-comparing-model-synthesis-and-wfc]],
  [[newgas-2020-wfc-explained]], [[fehr-2018-fast-wfc]].
- Code: [[solver]], [[tools-and-tasks]].
