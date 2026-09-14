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
> and ends the solve; restarts and pre-collapsed cells come next (#91). On
> the placeholder tileset an 8³ grid takes about 19 ms and a 24³ sector
> about 0.63 s in typed GDScript, but only 11 of 20 unconstrained 24³
> solves finish without a contradiction.

This is milestone 0.2.0 item D1 of [[RESEARCH_WFC]] section 7, following
sections 3 and 4 of the research. Code: [[solver]].

## Interface

```gdscript
var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
var solver := SectorSolver.new(library, Vector3i(24, 24, 24))
solver.use_entropy = false                       # the default: MRV
var result := solver.solve(seed, sector)         # optional third argument: domains
# result.ok, result.cells (PackedInt32Array), result.steps, result.propagations,
# result.restarts (0), result.time_usec, result.contradiction_cell, result.error
```

- **Cells** are indexed `x + size.x * (y + size.y * z)`, the layout of
  [[RESEARCH_WFC]] section 4. `result.cells[i]` is a tile index of the
  library (rotation included), empty unless `ok`.
- **`domains`** (optional) is a `PackedInt64Array` of `cell_count *
  word_count` words ANDed into the starting wave and propagated before the
  first observation. It is the entry point for
  [[GLOSSARY#Pre-collapsed cell|pre-collapsed cells]] and fixed sector
  faces: #91 turns edge rasteriser records into it and #92 fixed faces.
- **`result.restarts`** stays 0: the attempt number is already folded into
  the per-attempt seed (below), so #91 only has to loop.

## Steps

1. **Build once per solver** (about 4 ms for the placeholder set): the
   border bits of every cell (which of the six neighbours exist), the full
   domain, integer weights `max(1, round(weight * 1000))`, and per direction
   the byte-sliced union table: for each word, each of its 8 bytes and each
   of the 256 byte values, the OR of the allowed sets of the tiles in that
   byte. The same layout holds the popcount, summed integer weight and
   summed `w log w` of each byte value.
2. **Reset.** Attempt seed `s = hash3_u(seed, sector, 9100 + attempt)`. Every
   cell gets the full domain (ANDed with `domains` if given), its tile count
   and a [[GLOSSARY#Tie-break priority|tie-break priority]]
   `hash3_u(s, cell position, 9200)`.
3. **Starting domains.** If `domains` is given, fail on any empty cell,
   queue every cell with fewer than all tiles and propagate (step 6).
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

## Propagation design: AC-3, not AC-4

[[GLOSSARY#AC-4|AC-4]] support counts are the textbook fast propagator
(Gumin's and fast-wfc's choice), and they were considered first. They lose
here because an observation removes nearly every tile of a cell at once,
and AC-4 pays per removed tile: every cell of a solved grid loses
`tiles − 1` tiles, and each removal visits the supports in six directions.
On the placeholder set (30 tiles, on average 12.2 allowed per direction)
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

## Measurements

Placeholder tileset (13 prototypes, 30 tiles, one word), `mise run
solver-check` and a 20-seed run on the development machine, Godot 4.7.2,
headless:

| Grid | Heuristic | Solved (seeds 0–19) | Mean / max time of solved | Mean steps / queue pops |
| --- | --- | --- | --- | --- |
| 8³ | MRV | 17 / 20 | 18.6 / 21.6 ms | 337 / 4 253 |
| 8³ | entropy | 20 / 20 | 22.3 / 23.9 ms | 314 / 4 221 |
| 24³ | MRV | 11 / 20 | 633 / 654 ms | 10 334 / 137 577 |
| 24³ | entropy | 16 / 20 | 760 / 1 070 ms | 8 686 / 134 545 |

Failed solves stop at the contradiction, so they are faster. The 24³
failure rate is what restarts (#91) and the solid policy (#136) must bring
down; the time is the first input to the native threshold (#138) and the
benchmark (#93).

## Determinism

- Every random value is `Hash.hash3_u`: the attempt seed from `(seed,
  sector)`, the tie-break from `(attempt seed, cell position)`, the tile
  draw from `(attempt seed, cell position, step)`. No
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
- **Entropy mode** computes `log` on doubles. Within one binary it is
  reproducible, but `log` may differ in the last bit between C libraries,
  so it is not guaranteed bit-identical across platforms or a native port.
  MRV is.

## Parameters and salts

| Name | Value | Meaning |
| --- | --- | --- |
| `size` | `Vector3i(24, 24, 24)` | Cells per axis; tests use 8³. |
| `use_entropy` | false | Shannon entropy instead of tile count as the heap key. |
| `ATTEMPT_SALT` | 9100 (+ attempt, below 100) | Attempt seed from `(seed, sector)`. |
| `TIE_SALT` | 9200 | Per-cell tie-break priority. |
| `CHOICE_SALT` | 9300 (+ step) | Weighted tile draw of the observation `step`. |
| `WEIGHT_SCALE` | 1000 | Fixed-point tile weights; weights have 0.001 steps. |
| `MAX_TOTAL_WEIGHT` | 2³¹ − 1 | Largest summed domain weight (an error beyond). |
| `ENTROPY_SCALE` | 2²⁴ | Fixed-point scale of the entropy key. |

The salts sit above every other salt in the project (the tile placement of
`tiles-check` uses 8701 to 8703), and each counter has its own range: up
to 100 attempts from 9100, the tie-break at 9200, and the step counter
counting up from 9300 into salts nothing else uses.

## Open questions

- **MRV or entropy** (#137): entropy solved 16 of 20 sectors against 11
  of 20 at 24³ on the placeholder set, at 20 % more mean time.
- **Restarts and the solid policy** (#91, #136): at this failure rate a 24³
  sector needs several attempts; a more universal solid tile would lower it.
- **Native threshold** (#138): 0.63 s mean per successful 24³ solve, before
  restarts; a failed attempt costs up to that again.

## References

- [[wave-function-collapse]]: the algorithm explained, with the sea, coast
  and land example.
- [[socket-adjacency]]: where the allowed bitsets come from.
- [[RESEARCH_WFC]], sections 1, 3, 4 and 7 (D1).
- [[0010-near-universal-solid-tile-with-seeded-restarts]],
  [[0011-typed-gdscript-solver-first]].
- Papers: [[gumin-2016-wavefunctioncollapse]],
  [[karth-2017-wfc-is-constraint-solving]],
  [[merrell-2021-comparing-model-synthesis-and-wfc]],
  [[newgas-2020-wfc-explained]], [[fehr-2018-fast-wfc]].
- Code: [[solver]], [[tools-and-tasks]].
