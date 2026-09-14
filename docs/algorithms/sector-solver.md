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
> solves within 2 attempts, and since voids stay open (#180) every sampled
> real stratum sector of seeds 0 to 4 solves at the first attempt. With the
> passages in rock of #182 (118 tiles, two bitset words, a real sector about
> 1.07 s) every sampled solid sector solves too, and with the catwalk
> platforms of #187 (127 tiles) every sampled shaft sector, with no railing
> across a walk.

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

`SectorDomains.build(library, size, type, records, faces)` turns one
sector's inputs into the `domains` words:

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
   A headroom record ([[edge-rasteriser#8. Headroom records]]) takes every
   tile, of any family, whose `TileLibrary.Tile.headroom` is set: no mesh,
   or a mesh whose bounds start at least `HEADROOM_CLEAR` = 1.8 m above
   the cell bottom. A floor or bridge record then drops every tile that
   blocks a side face (`TileLibrary.Tile.blocked_faces`: a parapet in the
   walker's strip to that face) towards a record a walker steps to: any
   record but headroom in the face neighbour, or a stair under it climbing
   into the cell (#173). A tunnel record does the same for its walls
   (#182), but its closed sides are rock, so it only opens towards a tunnel,
   a side portal opening whose passage runs along that face, a stair
   climbing away from it or a stair one lower climbing into it
   (`SectorDomains.steps_to`). A side portal opening drops the tiles that
   block either face along its passage: the walk leaves the sector there
   and enters from the door cell, even where that holds a stairwell over a
   stair climbing into the portal. These records are unoriented (or, for a
   portal, turned by the passage only), so this is how a parapet or tunnel
   wall ends up beside a walk and not across it. A catwalk record drops the
   tiles that block a face its walk crosses as a floor does (#187), then
   keeps only the tiles that close every other side face, where any of
   them do: a face is closed when the tile blocks it (a railing, a
   platform's backing plate) or allows no fill there but a free tile (the
   rock a `backing` closes). A `4`/`4f` run face allows neither and counts
   as open. So a straight run takes a catwalk, a turn, branch or cross a
   platform, and a dead end, which no tile closes, keeps every tile left.
3. **Record pairs.** For every two records that are face neighbours, some
   tile of the first must allow some tile of the second in that direction
   (the byte union of step 6 below, done once per pair). Otherwise the
   `error` names both records and the direction: the records are
   inconsistent whatever the seed.
4. **Sector default** for every other cell: the fill tile alone, solid in a
   solid sector and air in a stratum, shaft, cavity or chasm, so
   walk-family tiles stand only in record cells
   ([[0018-walk-tiles-only-in-record-cells]], #179, #180). Stratum
   interiors stay open until their slabs, columns and walls get an issue of
   their own.
5. **Support cells.** A cell beside a record, across face `d`, that holds no
   record itself also admits the free tiles (tiles of no family) that some
   tile `t` of the record needs there: for each `t` whose `allowed(d, t)`
   holds no fill tile, the free tiles of `allowed(d, t)`. A record with a
   tile that allows fill across all six faces stands in fill alone and
   gets no support cells (#182); without that rule `stair_tunnel`, whose
   rock sides allow no air, would bring backing plates beside every stratum
   stair. The cell keeps the
   fill tile too, and the solver's propagation decides. On the placeholder
   tileset the rock socket `1s` admits solid or a `backing` plate beside a
   catwalk, a ladder or a stair's high end and solid under a floor, slab
   edge or stair; the wall ends `3s` of a wall doorway in a headroom cell
   admit a wall or doorway beside it (before #182; stairs, floors and
   headroom now have an open tile and get none). Propagation removes solid, walls and
   doorways again (solid cannot touch air sideways, a wall stack has to run
   to the grid top), and the open stair and open floor need nothing, so
   only **catwalks and ladders** end up with support: a `backing` behind
   them. No family needs a slab under it, as every walk tile that may stand
   over open space carries its own deck (open floor, open stair, bridge,
   portal frame, short catwalk). Measured on three solved sectors each at
   seed 0, the cells outside records hold only air in strata and only air
   and 61 backings in shafts. The full-height support columns of decision
   #158 are dropped: they let the solver place floors, stairs, catwalks and
   ladders around every record.
6. **Fixed faces** (optional): six arrays in face order +x, −x, +y, −y, +z,
   −z, each empty (free) or one entry per boundary cell, indexed `u +
   size_u * v` with u and v the other two axes in xyz order, holding the
   tile of the neighbour sector's cell across the face or −1. A boundary
   cell with neighbour tile `n` across face `d` keeps `allowed(d ^ 1, n)`:
   the tiles `n` accepts from the opposite side. A cell left empty is an
   `error`.

Starting domains that pass these checks can still be inconsistent across a
few cells (a tunnel needs rock below, a bridge two cells below needs open
space above it, and the only tile with open space below and rock above is
the stairwell of #182, whose rock sides do not fit among open cells). The
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

**Tiles.** The placeholder library numbers its 61 tiles air 0, solid 1,
floor 2, slab_edge 3 to 6, column 7, wall 8 and 9, wall_doorway 10 and 11,
stair 12 to 15, bridge 16 and 17, catwalk 18 to 21, ladder 22 to 25, tunnel
26 and 27, portal_opening 28 and 29, floor_open 30, slab_edge_end 31 to 34,
slab_edge_end_f 35 to 38, stair_open 39 to 42, catwalk_end 43 to 46,
catwalk_end_f 47 to 50, portal_frame 51 and 52, catwalk_short 53 to 56,
backing 57 to 60. The 57 tiles of #182 follow in word 1 from bit 61 on:
tunnel_corner 61 to 64, tunnel_t 65 to 68, tunnel_cross 69, tunnel_end 70
to 73, vault 74 and 75, vault_corner 76 to 79, vault_t 80 to 83,
vault_cross 84, vault_end 85 to 88, bridge_corner 89 to 92, bridge_t 93 to
96, bridge_cross 97, bridge_end 98 to 101, stair_tunnel 102 to 105,
stairwell 106 and 107, stairwell_end 108 to 111, portal_tunnel 112 and 113,
portal_tunnel_end 114 to 117. The 9 tiles of #187 end word 1:
catwalk_corner 118 to 121, catwalk_t 122 to 125, catwalk_cross 126. Tile `t` sits in word `t >> 6` at bit
`t & 63`, so tile 64 is bit 0 of word 1.

**Record masks.** A stair record with yaw 1 (climbing −z) matches
`stair@1` and `stair_open@1`, bits 13 and 40: `(1 − (1 − 0)) mod 4 = 0`. A
portal opening on the +x face has yaw 0: `(r − (0 − 3)) mod 2 = (r + 3) mod
2 = 0` holds for `r = 1`, so it matches `portal_opening@1` and
`portal_frame@1`, bits 29 and 52, with their passage along x. On the −z
face (yaw 1) it matches bits 28 and 51. A floor record matches bits 2 to 6
and 30 to 38: floor, open floor and every slab edge and slab edge end. A
headroom record matches bits 0, 10 and 11: air and both rotations of the
wall doorway, whose lintel starts 1.8 m up.

**Support cells.** A catwalk record at (5, 3, 5) in a shaft matches bits
18 to 21, 43 to 50, 53 to 56 and 118 to 126. `catwalk_short@0` (bit 53) has `1s` on
`+z`, and air shows `0s` there, so it accepts no air at (5, 3, 6); what it
does accept there is solid, the rock faces of other catwalks, ladders,
stairs and tunnels, and `backing@0` (bit 57, its plate and `1s` on `−z`,
facing the catwalk). Of those, solid and `backing@0` have no family, so
(5, 3, 6) starts as air, solid or `backing@0`; the rotations with rock on
`+x`, `−z` and `−x` add `backing@1`, `backing@2` and `backing@3` to the
cells there.
Propagation drops solid (it needs rock beside it), and the observation of
the catwalk picks one rotation and so one backing.

**Floor faces a walk crosses.** A floor record at (5, 3, 5) with a floor
record at (5, 3, 6) drops every tile whose `blocked_faces` has `+z` (bit 4):
`slab_edge@0`, `slab_edge_end@0` and `slab_edge_end_f@0`, bits 3, 31 and 35,
whose parapet runs along `+z`. Floor and open floor block no face, so the
mask is never empty.

**Catwalk faces (#187).** A catwalk record at (5, 3, 5) with catwalk
records at (4, 3, 5) and (5, 3, 6) turns there, so its walk crosses `-x`
and `+z`. Dropping the tiles that block either leaves the twelve with no
railing or plate there: `catwalk@0` and `@3`, the same rotations of
`catwalk_end`, `catwalk_end_f` and `catwalk_short`, `catwalk_corner@3`,
`catwalk_t@0` and `@3` and `catwalk_cross`, bits 18, 21, 43, 46, 47, 50,
53, 56, 121, 122, 125 and 126. The closing step keeps the tiles that close
`+x` and `-z` as well. `catwalk@3` blocks `+x` with its railing but shows
`4f` on `-z`, an open run face; `catwalk@0` shows `4` on `+x`; the T pieces
and the cross have a gate on one of them. Only `catwalk_corner@3`, whose
plates block both faces, is left, so the turn takes the corner platform
and the two catwalks beside it meet it with an open end.

**Record pair.** A bridge at (2, 2, 2) under a tunnel at (2, 3, 2): the
bridge tiles' `+y` sockets are `0i`, so their union in `+y` holds only
tiles with `0i` below, and both tunnels have `1i` below. The intersection
is empty, so `build` returns `Record((2, 2, 2) bridge 0 …) and
Record((2, 3, 2) tunnel 0 …) cannot touch across +y` without touching the
solver.

**Inconsistent across cells.** A bridge at (4, 2, 4) and a tunnel at
(4, 4, 4) are not neighbours, so the pair check passes. Propagating them
narrows (4, 3, 4) to tiles with open space below (for the bridge) and rock
on top (for the tunnel): only the stairwell, which the air around it
removes. The solve returns `FAILED` with `attempts 0` and `inconsistent
starting domains: cell (4, 4, 4) is left empty by propagating them` in a
few milliseconds.

**Restarts.** An unconstrained 8³ grid at seed 2135: attempt 0 uses `s =
hash3_u(2135, (0, 0, 0), 9100)` and contradicts after 425 observations;
attempt 1 (salt 9101) solves. With the default 8 attempts the result is
`SOLVED`, `attempts 2`, `restarts 1`, and `steps` (933) counts the
observations of both. With `max_attempts = 1` it is `DEGRADED`: 512 cells
of tile 1, `attempts 1`, `restarts 1`. Seed 2135 is the first seed that
solves at its second attempt on the 127-tile set of #187 (seed 1502 was on
the 118-tile set of #182, seed 374 on the 61-tile set, seed 36 on the
53-tile set before #180).

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
| the same with headroom and walkable floor faces (#173) | 17 | 3 | 0 | mean 3.25 over the 20 searched |
| the same with open voids, 61 tiles (#180) | 20 | 0 | 0 | all at the first |

**Real sectors (#161).** On the 30-tile set, 14 of the 20 real sectors of
seed 0, and 71 of the 100 of seeds 0 to 4, failed before an attempt. `mise
run solver-real` classifies each by the record pair `SectorDomains` rejects
or a minimal record set whose propagation empties a cell:

| Cause | Seed 0 | Seeds 0–4 | Fix |
| --- | ---: | ---: | --- |
| Two side portal openings, or a portal and a floor, in crossing wall planes: a portal opening pulls a wall stack to the grid top and wall ends along the face to the grid edge | 9 | 39 | `portal_frame` |
| A floor or stair beside a portal opening's wall side (the walk reaches the portal along the face) | 3 | 15 | `portal_frame` |
| A floor directly over or under a stair cell, or beside a stair's high end, which is the cell under the next step | 1 | 8 | stair rule in the rasteriser |
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

**Headroom and walkable floors (#173).** `mise run solver-real` over seeds
0 to 4, 20 sectors each, every sector reaching an attempt in every run:

| Records and domains | Solved | At the first attempt | Mean attempts |
| --- | ---: | ---: | ---: |
| before #173 | 95 | 58 | 2.15 |
| headroom records only | 97 | 55 | – |
| headroom, door cells, walkable routings first, floor faces (this) | 90 | 37 | 2.97 |
| the same without the floor face filter | 97 | 56 | – |
| floor faces free of parapets entirely, no headroom | 77 | 41 | – |
| open voids: air outside records and support cells (#180) | 100 | 100 | 1.00 |

Headroom does not cost solves: air above a walk is easy to tile. What does
is keeping parapets off the faces a walk crosses, since a parapet line
along a walk has to run on and end with end pieces. It is also what makes
the sectors walkable: `mise run walk-check --all-solving` at seed 0 walks
66 of 66 solving sectors with it and 37 of 78 without ([[placement]]).

**Open voids (#180).** With air outside record and support cells the same
`mise run solver-real` run solves all 100 sectors at the first attempt,
against 90 solved and 37 at the first attempt before; no sector degrades.
`mise run walk-check --all-solving` at seed 0 finds 84 candidate sectors
both times: before, 66 solved (23 at the first attempt) and all 66 walked;
now all 84 solve at the first attempt and all 84 walk portal to portal.
A 24³ stratum attempt takes about 0.54 s in `solver-check`, most cells
collapsing to air in propagation. The void types, sampled the same way
(the first 10 sectors of each type with records at seeds 0 and 1, 20 per
type):

| Type | Before: solved / at the first attempt / walk tiles outside records | Open voids with support cells | Air only, no support |
| --- | --- | --- | --- |
| shaft | 20 / 15 / 34 455 | 20 / 15 / 0 | 0, all 20 empty a cell |
| cavity | 20 / 18 / 29 207 | 20 / 20 / 0 | 20 / 20 / 0 |
| chasm | 20 / 19 / 26 243 | 20 / 20 / 0 | 4, 16 empty a cell |
| solid | 0, all 20 rejected by the record checks | the same (20 / 20 / 0 with the rock pieces of #182) | the same |

Without support cells a catwalk or ladder has nothing to hang on, and a
single catwalk cell (a door cell or the foot of a ladder) has no catwalk
tile open at both ends: the old support columns filled both gaps with
catwalk, ladder and stair tiles outside the records, which is where the
tens of thousands of stray walk tiles came from. `backing` and
`catwalk_short` close them. Restricting the support columns to air and
solid does not help (the same 0 and 4 solved), because solid cannot touch
air sideways. Solid sectors failed as before: a tunnel turning or opening
into headroom had no tile ([[edge-rasteriser]]), fixed by #182 below.
`tiles-check` on the placeholder tileset, which places unconstrained 6³
grids, now contradicts in 42 of 142 attempts (0.296, from 0.259) with the
two new prototypes.

**Tunnels through rock (#182).** `mise run solver-real --solid 20` runs the
20 stratum sectors and then the first 20 solid sectors with records of the
same sample per world seed 0 to 4:

| Tileset and domains | Strata solved / at the first attempt | Solid solved / at the first attempt | Solid failing before an attempt |
| --- | ---: | ---: | ---: |
| before (61 tiles) | 100 / 100 | 0 / 0 | 100, every one rejected: a tunnel under its headroom |
| rock pieces, tunnel and portal face filter (118 tiles) | 100 / 100 | 100 / 99 | 0 |

Every stratum line (sector, records, outcome, attempts) is identical to
before, and `walk-check --all-solving` still walks 84 of 84 at seed 0. The
solid sector (-835, -870, -607) of seed 3 solves at its second attempt.
Without `stairwell_end` 40 of the 100 still emptied a cell (a floor portal
reserves no head room, so the first stairwell beside it had no closed low
side); without the face filter on side portals a walk from a stair into a
portal could meet `portal_tunnel_end`'s wall. No solved sector of either
type blocks a walk face (`count_blocked_walk_faces`). Bridges, measured on
the first 10 cavity and chasm sectors with records at seeds 0 and 1: all 20
of each solve before and after, and the parapets that stood across a walk
drop from 24 (cavity) and 7 (chasm) to 0.

**Catwalk turns (#187).** `mise run solver-real --seeds 0,1 --count 0
--shaft 10` runs the first 10 shaft sectors with records at seeds 0 and 1;
blocked faces count catwalk records too (`count_blocked_walk_faces`, which
follows `FACE_FILTERED`):

| Tileset and domains | Shaft solved / at the first attempt | Failing before an attempt | Blocked walk faces |
| --- | ---: | ---: | ---: |
| before (118 tiles, 1 m catwalk deck, no catwalk face filter) | 20 / 15 | 0 | 1 427 |
| platforms on backing cells (`1s` closed sides), face filter only | 20 / 20 | 0 | 0 |
| platforms on backing cells, face and close filters | 17 / 16 | 3 | 0 |
| platforms with their own plates, face and close filters (127 tiles, committed) | 20 / 19 | 0 | 0 |

Most of the 1 427 faces were straight runs: the catwalk railing stood on the
walk line of its cell. The record shapes of the sample are 752 straight
cells, 164 T (a branch, a ladder or portal beside a run, or two runs side
by side), 82 corners, 4 crosses and 2 dead ends. With the plates in
backing cells, corners of a zigzag walk that touch diagonally ask for two
plates in one cell and empty it. Without the close filter every sector
solves, but a platform fits any catwalk record and fills straight runs.
Over seeds 0 to 4, 20 sectors of each type (`mise run solver-real --solid
20 --shaft 20`): strata 100 solved, 100 at the first attempt; solid 100,
99; shafts 100, 99 (seed 1 (-786, -702, -33) at its third attempt), no
sector failing before an attempt and no blocked walk face.
`walk-check --all-solving` still walks 84 of 84 at seed 0, and
`walk-check --catwalk` walks shaft sector (2, -1, 0) from its portal over
two corner platforms to its hub. A real stratum sector takes about 1.11 s
in `solver-check`, the 24³ unconstrained solve about 10.0 s, both within
noise of the 118-tile set. Which corner look to keep is decision #190.

The two-word tables cost time: a real stratum sector takes about 1.07 s in
`solver-check` against 0.55 s with 61 tiles (1.49 s before the solver's
two-word propagation was unrolled; results are byte-identical), an 8³ grid
about 0.30 s against 0.14 s. Whether to keep one library for every sector
type is decision #188.

`mise run
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
- **Default domains** of solid and void sectors (#158): settled by
  [[0018-walk-tiles-only-in-record-cells]]; stratum interiors (slabs,
  columns, walls) are the next question.
- **One library past 64 tiles** (#188): the rock pieces of #182 double the
  solve time; per-type libraries would keep one word.
- **Catwalk turns** (#190): platforms on their own backing plates with
  open catwalk ends (#187), or `4`/`4f` corners at about 60 tiles and a
  third bitset word.
- **Parapets over open space** (#185): with air under every walk, a floor
  record can only take the open floor, so stratum walks have no parapets.
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
