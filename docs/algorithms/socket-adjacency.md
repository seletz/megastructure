---
tags:
  - algorithm
  - wfc
  - tileset
  - milestone/0.2.0
status: current
---

# Socket Adjacency

> [!summary]
> The WFC solver needs to know, for every tile and every direction, which
> tiles may sit next to it. Writing those pairs by hand does not scale: 20
> tiles with 4 rotations each already make 80 tiles and thousands of pairs.
> Instead, every face of a tile gets a small label, its **socket**, describing
> the shape of the geometry that touches the face. Two tiles may be neighbours
> when the sockets on their touching faces match. Rotated copies of a tile are
> generated automatically, their sockets permuted, and the full adjacency
> table is derived once at load time as bitsets. A validation task catches
> sockets that can never match and tiles that can never be placed. The tile
> format and the socket string grammar below are implemented
> (`TilePrototype`, `TileSet3D`), and so are matching,
> [[GLOSSARY#Rotation expansion|rotation expansion]], the
> [[GLOSSARY#Adjacency table|adjacency table]] (`TileLibrary`) and the
> validation task (`mise run tiles-check`), and a box-only placeholder
> tileset passes it as the worked reference below. The convention follows
> [[RESEARCH_WFC]], which takes it from Marian42's infinite city, and is
> proposed for approval in issue #140.

## Sockets

A tile is a 2 m cube of geometry with six faces: `+x`, `-x`, `+z`, `-z`
(horizontal) and `+y`, `-y` (vertical). Each face carries a socket that
describes the cross-section of whatever geometry reaches that face: nothing,
full rock, a floor slab at the bottom, a wall in the middle, a doorway. Two
faces that touch must show the same cross-section, or the meshes will not
line up.

Horizontal and vertical faces use different labels because they can go wrong
in different ways.

### Socket strings

A socket is written as one short string. This is the exact grammar the tile
resource accepts (`TilePrototype.parse_socket`); anything else is a
validation error.

```text
horizontal = id [ "s" | "f" ]            ; faces +x, -x, +z, -z
vertical   = id ( "_" rotation | "i" )   ; faces +y, -y
id         = "0" | nonzero { digit }
rotation   = "0" | "1" | "2" | "3"
nonzero    = "1" | "2" | ... | "9"
digit      = "0" | nonzero
```

- The id is a decimal profile number without sign, spaces or leading zeros,
  so `3` and `03` can never both name profile 3. It has no upper bound.
- Suffixes are lower case and at most one: `3sf`, `3S` and `3i` on a
  horizontal face are errors.
- A vertical socket always has a suffix: a bare `5` on `+y` is an error, as
  is `5_4`, `5_01` or `05_1`.
- A horizontal face never takes a vertical suffix and the other way round:
  `3_0` on `+x` and `3s` on `-y` are errors.

| string | face | id | parsed as |
| --- | --- | --- | --- |
| `0s` | horizontal | 0 | symmetric |
| `3` | horizontal | 3 | asymmetric |
| `3f` | horizontal | 3 | flipped (the mirror of `3`) |
| `5_0` ... `5_3` | vertical | 5 | rotation index 0 to 3 |
| `0i` | vertical | 0 | rotation-invariant |

A prototype stores its six socket strings in a fixed order,
`+x, -x, +y, -y, +z, -z` (face indices 0 to 5), so the opposite of face `d`
is `d ^ 1`. The ids are numbers rather than names because the suffix
letters would be ambiguous at the end of a name (is `bus` profile `bu`,
symmetric?); a table of what each number means belongs next to the tileset
that uses it. The format itself is in [[tileset]].

### Horizontal sockets: symmetric and asymmetric

Picture two tiles side by side. Tile a's `+x` face and tile b's `-x` face
touch, and each is seen from outside its own tile, so a profile that is not
mirror-symmetric appears flipped from the other side.

| socket | meaning | matches |
| --- | --- | --- |
| `3s` | profile 3, mirror-symmetric | `3s` |
| `3` | profile 3, asymmetric | `3f` only |
| `3f` | profile 3, flipped | `3` only |

The rule: two horizontal sockets match when their ids are equal and either
both are symmetric (`s`) or exactly one of them is flipped (`f`). A floor
slab edge is symmetric; a wall that hugs the left side of the face is not.

### Vertical sockets: rotation index

A top face is matched with the bottom face of the tile above. A vertical
profile has no mirror problem, but it can be rotated: a stair landing must sit
on the top of a stair facing the same way. Vertical sockets therefore carry a
rotation index `_0` to `_3`, or `i` when the profile looks the same in all
four rotations.

| socket | matches |
| --- | --- |
| `5_1` | `5_1` |
| `5i` | `5i` |
| `5_1` and `5_2` | no match |

### Rotations are generated

A tile prototype declares `rotations = 1`, `2` or `4` depending on its own
symmetry (a column needs one, a straight wall two, a corner four). Each
generated rotation turns the tile one [[GLOSSARY#Quarter turn|quarter turn]]
about `y`:

- the four horizontal sockets move round one face, counter-clockwise seen
  from above, as `Basis(Vector3.UP, PI / 2)` turns a vector: `+x` goes to
  `-z`, `-z` to `-x`, `-x` to `+z`, `+z` to `+x`. This is the order of
  `EdgeRasteriser` orientations (0 `+x`, 1 `-z`, 2 `-x`, 3 `+z`), so a stair
  record of orientation k asks for a stair tile turned k quarter turns;
- the horizontal labels themselves do not change. A turn is a proper
  rotation: the face and the viewer outside it turn together, so the profile
  is not mirrored and `3` stays `3`. The `f` flag would only flip under a
  mirror, and mirrored variants are not generated;
- both vertical sockets increment their rotation index modulo 4, and `i`
  stays `i`. Top and bottom indices are counted in the same frame (seen from
  above), so a landing turned with its stair still matches it.

Mirrored variants are left out for now: they flip mesh winding and normals,
and the first tileset has no chiral pieces that need them.

### Special tiles

- **Air**: every socket `0s` or `0i`, and the only tile allowed no mesh.
- **Solid**: every socket `1s` or `1i`, plus a wildcard so solid may sit next
  to almost anything. The format has no wildcard yet: how to spell it is
  decision issue #141, how universal solid should be is #136. Until then
  solid matches only `1s` and `1i`. This is the pressure valve that keeps contradictions
  rare (see [[wave-function-collapse#Contradictions and restarts]]). A few
  sockets, such as stair exits and bridge ends, refuse the wildcard so the
  solver cannot end a stair in rock.
- An optional **exclusion list** can forbid pairs that match by socket but
  look wrong. It should rarely be needed. It holds prototype names and
  applies in every direction and to every rotation of both tiles.

## Deriving the adjacency table

For each direction `d` and each tile `a`, `allowed[d][a]` is a bitset over
all tiles: bit `b` is set when `a`'s socket on face `d` matches `b`'s socket on
the opposite face. That is `tiles × tiles × 6` socket comparisons, done once
at load, trivial for 80 tiles.

### Worked example

Three tiles along `x`, with bit 0 for A, bit 1 for B and bit 2 for C:

| tile | `-x` socket | `+x` socket | role |
| --- | --- | --- | --- |
| A | `0s` | `0s` | open floor |
| B | `0s` | `2` | wall starts at its `+x` side |
| C | `2f` | `0s` | wall ends at its `-x` side |

Derived table:

| | allowed `+x` | bits | allowed `-x` | bits |
| --- | --- | --- | --- | --- |
| A | A, B | `011` | A, C | `101` |
| B | C | `100` | A, C | `101` |
| C | A, B | `011` | B | `010` |

Read "allowed `+x` of B is C": to the east of a wall start there must be a
wall end. The table is consistent in both directions: C is in B's `+x` set
exactly when B is in C's `-x` set.

During propagation a cell's domain is also a bitset. If a cell may still be
A or B (`011`), its eastern neighbour is intersected with
`allowed[+x][A] | allowed[+x][B]`, which is `011 | 100 = 111`: nothing is
removed yet. Once the cell is B alone (`010`), the neighbour is intersected
with `100` and must be C. With two 64-bit words per domain, this is a handful
of CPU instructions per neighbour.

## Expansion and derivation

`TileLibrary.build(tileset)` turns a validated `TileSet3D` into the list of
rotated tiles and the six-direction table. It is the code of the two
sections above; this section pins every detail the solver relies on.

### Steps

1. **Validate.** Run `TileSet3D.validate()`. If it reports anything, the
   library keeps the messages in `errors` and has no tiles; nothing below
   runs on a broken tileset.
2. **Expand.** For each prototype in authoring order, for each turn `k` from
   0 to `rotations - 1`, append one tile. Its index is its position in that
   order, its label `name@k`, its weight the prototype's full weight
   (decision #146), and its [[GLOSSARY#Effective socket|effective sockets]]
   the prototype's sockets turned `k` times:
   `turned[QUARTER_TURN[face]] = turn(prototype[face])` per turn, where
   `QUARTER_TURN = [5, 4, 2, 3, 0, 1]` (face index to face index: `+x`→`-z`,
   `-x`→`+z`, `+y` and `-y` stay, `+z`→`+x`, `-z`→`-x`) and `turn` advances
   a vertical `N_R` to `N_((R + 1) % 4)`.
3. **Key the sockets.** Give every socket an integer key, equal for equal
   sockets: horizontal `2 × (3 × id + kind)` with kind 0 for `N`, 1 for `Ns`,
   2 for `Nf`; vertical `2 × (5 × id + R + 1) + 1` with `R + 1 = 0` for `Ni`.
   The *partner key* of a socket is the key of the one socket that matches
   it: the same key for `Ns`, `N_R` and `Ni`, the key with `f` toggled for
   `N` and `Nf`. So matching is key equality, no string comparison.
4. **Exclusion masks.** For each prototype, collect the prototypes it
   excludes and the ones that exclude it (exclusions apply both ways), and
   build one bitset with the bits of all their tiles, every rotation.
5. **Table, per direction `d`.** Group the tiles by the key of their socket
   on the opposite face `d ^ 1`: key → bitset of tiles showing it. Then for
   each tile `a`, `allowed[d][a]` is the group of the partner key of `a`'s
   socket on `d`, with `a`'s exclusion mask cleared.

The table is stored as six flat `PackedInt64Array`s, one per direction,
`tile_count × word_count` words each, with
`word_count = ceil(tile_count / 64)`. Tile `a`'s entry starts at
`a × word_count`; bit `b` lives in word `b >> 6` at position `b & 63`, so
tile 63 is the sign bit of word 0 and tile 64 bit 0 of word 1.
`allowed(dir, a)` returns a copy of the entry, `is_allowed(dir, a, b)` reads
one bit.

Because matching is symmetric and exclusions apply both ways, the table is
symmetric: `b` is in `allowed[d][a]` exactly when `a` is in
`allowed[d ^ 1][b]`.

### Worked example: a quarter turn

A prototype with every face different, sockets in face order
`+x, -x, +y, -y, +z, -z`:

| | `+x` | `-x` | `+y` | `-y` | `+z` | `-z` |
| --- | --- | --- | --- | --- | --- | --- |
| prototype (`@0`) | `1` | `2s` | `5_0` | `6_3` | `3f` | `4` |
| one turn (`@1`) | `3f` | `4` | `5_1` | `6_0` | `2s` | `1` |
| two turns (`@2`) | `2s` | `1` | `5_2` | `6_1` | `4` | `3f` |

Read the first turn column by column: `+x` of `@1` shows what was on `+z`
(`3f`), because `+z` goes to `+x`; `-z` shows what was on `+x` (`1`); the
labels `1`, `2s`, `3f`, `4` are unchanged; `5_0` becomes `5_1` and `6_3`
wraps to `6_0`. Two turns swap opposite faces. `mise run adjacency-check`
checks exactly these rows, and that turning each face normal with
`Basis(Vector3.UP, PI / 2)` lands on the face `QUARTER_TURN` names.

### Worked example: the fixture tileset

`tests/fixtures/tilesets/fixture_tileset.tres` has four prototypes; the wall
declares `rotations = 2`, so there are 5 tiles and one word per entry:

| index | tile | sockets | `+x` | `+y` | `-y` | `+z` |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | solid@0 | `1s 1s 1i 1i 1s 1s` | 0 | 0, 2 | 0 | 0 |
| 1 | air@0 | `0s 0s 0i 0i 0s 0s` | 1, 3 | 1 | 1, 2 | 1, 4 |
| 2 | floor@0 | `2s 2s 0i 1i 2s 2s` | 2 | 1 | 0 | 2 |
| 3 | wall@0 | `0s 0s 3_0 3_0 3s 3s` | 1, 3 | 3 | 3 | 3 |
| 4 | wall@1 | `3s 3s 3_1 3_1 0s 0s` | 4 | 4 | 4 | 1, 4 |

Every horizontal socket here is symmetric, so `-x` equals `+x` and `-z`
equals `+z`. Floor sits on solid (`+y` of solid holds 2, `-y` of floor holds
0) and has air above. The turned wall moved its `3s` from `±z` to `±x` and
its tops to `3_1`, so `wall@0` and `wall@1` never stack on each other.
`mise run adjacency-dump res://tests/fixtures/tilesets/fixture_tileset.tres`
prints this table, one line per tile.

### Complexity

With `P` prototypes, `n ≤ 4P` tiles and `w = ceil(n / 64)` words: expansion
is `O(n)` socket parses; the table is `O(6 × n × w)` word writes plus one
dictionary insert per tile and direction, so it grows with `n² / 64`
instead of the `6 × n²` pairwise comparisons of the direct rule; exclusions
add `O(E × n)` for `E` excluded prototype pairs. Memory is `6 × n × w`
64-bit words: 80 tiles take 960 words, under 8 KB. Built in GDScript, the
5-tile fixture takes about 0.6 ms and a 66-tile set about 7 ms, once at
load.

### Determinism

No randomness and no hashing: tile order is authoring order then turn, the
dictionaries only group tiles and are never iterated for output, and the
words are plain integers. The same tileset always gives the same indices and
the same table on every platform, which the solver's seeded choices need
(see [[wave-function-collapse]]).

### Parameters

| Parameter | Where | Effect |
| --- | --- | --- |
| `rotations` | `TilePrototype` | 1, 2 or 4 tiles per prototype, turns 0 to `rotations - 1`. |
| `sockets` | `TilePrototype` | The six strings turned and matched. |
| `exclusions` | `TilePrototype` | Prototype names whose tiles are cleared from every entry, both ways. |
| `weight` | `TilePrototype` | Copied to every rotation unchanged (#146). |
| `QUARTER_TURN` | `TileLibrary` | The face permutation of one turn; fixed, matches Godot's basis. |
| `WORD_BITS` | `TileLibrary` | 64, the bits per `PackedInt64Array` word. |

## Validation

Two tasks check a tileset before any solver sees it. `mise run
tileset-check` checks the format: the socket grammar, unique names,
weights, rotations, families, meshes and the names that exclusions, solid
and air refer to (see [[tileset]]). `mise run tiles-check <tileset.tres>`
checks whether the tiles can actually be placed. It builds the
`TileLibrary`, prints every finding as one `FAIL` line with its category,
and exits 1 when there is any; a tileset that does not validate stops at
its format errors. `mise run check` runs it on the fixtures through
`mise run tiles-check-fixtures`: the real fixture must pass, and
`tests/fixtures/tilesets/dead_socket_tileset.tres` must fail with exactly
the categories below that it was built to trip.

### The checks

1. **Dead sockets.** For each direction `d`, collect the socket keys shown
   on face `d ^ 1` by any tile, every rotation included. A socket on face
   `d` whose partner key is not among them is dead: no tile, not even the
   tile itself, can ever sit on that side. It is reported once per socket
   string and direction with the tiles showing it, for example
   `+x "7" on pipe@0 has no -x partner "7f"`. Exclusions are ignored here;
   they are the next check's business.
2. **Empty directions.** A tile whose `allowed(d, tile)` bitset is all zero
   in some direction, the same failure seen per tile and after exclusions.
   A tile with a dead socket lists one line here per affected rotation and
   face; a tile whose only partners it excludes appears here alone.
3. **Unreachable tiles.** A breadth-first search over the adjacency graph,
   starting from every rotation of the air and the solid tile at once. An
   edge joins `a` and `b` when `b` is allowed next to `a` in any direction;
   the table is symmetric, so the graph is undirected. Sector faces start as
   air and solid, so a tile the search never reaches cannot grow out of
   them, however often it could fill a grid on its own.
4. **False symmetry.** For each prototype and each horizontal face with an
   `Ns` socket, take the mesh vertices within `SLAB` = 0.01 m of the face
   plane (at ±1 m, half a cell, from the centre). Each gives a profile point
   (tangent, y), where the tangent is z on `±x` faces and x on `±z` faces.
   Mirror every point across the face's vertical centre line to
   (−tangent, y) and look for an original point within `TOLERANCE` =
   0.001 m, using a hash grid of that cell size and its 3 × 3 neighbourhood.
   Any point without a mirror image fails the socket. Only the unrotated
   prototype is checked: a quarter turn moves the profile with its socket.
   Vertices come from `PrimitiveMesh.get_mesh_arrays()` for a `BoxMesh` and
   the other primitives, and from `surface_get_arrays` for an `ArrayMesh`;
   both work under `--headless`. A mesh with no vertex data is skipped with
   a warning, not a failure. A face no vertex touches has an empty profile
   and passes, which is right for a thin wall that stops short of it.
5. **Placement histogram.** Fill a 6 × 6 × 6 grid 100 times with a minimal
   placement (next section) and print, per tile, how many cells held it and
   its share. A tile never placed in 100 runs fails, and so does a
   contradiction rate above `--max-contradiction-rate` (default 0.5,
   decision #149).

### Minimal placement

Not the solver of [[wave-function-collapse]], only enough of one to see
which tiles come out. For run `r` and attempt `k`:

1. The attempt seed is `hash3_u(seed, (r, k, 0), 8701)`, `seed` from
   `--seed` (default 0).
2. Every cell's domain is the full bitset, `word_count` words per cell. The
   grid has no boundary constraints: outside cells are simply not there.
3. The cells are sorted by `hash3_u(attempt seed, cell, 8702) >> 1`, ties by
   index, and visited in that order. A cell whose domain still has more
   than one tile picks one: `hash3(attempt seed, cell, 8703)` times the
   summed weights of the remaining tiles, walked through in index order.
4. After each pick, bitset AC-3 propagation: pop a changed cell, and for each
   of its six neighbours AND the union of `allowed(d, t)` over the cell's
   remaining tiles `t` into the neighbour's domain; push the neighbour if it
   shrank. An empty domain is a contradiction.
5. On a contradiction the run starts again with attempt `k + 1`, up to
   `--max-restarts` = 8 restarts; a run that fails every attempt counts as
   failed and places nothing.

The contradiction rate is contradictions divided by attempts. Everything is
integer hashing and bit operations except the weighted draw, so a seed
always gives the same histogram; the self-test checks that, and that seed 1
gives a different one.

### Worked example: the two fixtures

The fixture tileset passes. Its sockets allow only a few whole-grid
patterns: a floor forces its entire layer to floor, solid below and air
above; a wall forces a full vertical plane. The propagation never
contradicts:

| tile | cells | share |
| --- | --- | --- |
| solid@0 | 7 416 | 34.3 % |
| air@0 | 7 776 | 36.0 % |
| floor@0 | 2 412 | 11.2 % |
| wall@0 | 1 728 | 8.0 % |
| wall@1 | 2 268 | 10.5 % |

100 runs, 100 attempts, contradiction rate 0.000.

The dead socket fixture adds three tiles to solid and air:

| tile | sockets | mistake |
| --- | --- | --- |
| pipe | `7 0s 0i 0i 0s 0s` | `+x` is `7` and nothing shows `7f` on `-x` |
| island | `9s 9s 9i 9i 9s 9s` | matches only itself |
| plug | `8 8 0i 0i 0s 0s` | `+x` and `-x` both `8`, nothing shows `8f` |

It fails with three dead sockets (pipe `+x`, plug `+x` and `-x`), three
empty directions (the same faces), island unreachable, and plug never
placed; contradiction rate 0.320 (47 of 147 attempts). The histogram shows
why checks 1 to 3 are needed next to it: pipe is still placed (3.1 %),
because a cell on the grid's `+x` boundary has no neighbour there, and
island fills whole grids (27.0 %), because an unconstrained grid is not a
sector. Only plug, dead on two opposite sides of a 6-wide grid, never
appears.

### Worked example: the placeholder tileset

`resources/tilesets/placeholder.tres` ([[tileset#The placeholder tileset]]
has every prototype, its geometry and the meaning of each socket id) is the
reference a real tileset is checked against. 13 prototypes expand to 30 tiles:

| prototype | sockets `+x -x +y -y +z -z` | rotations | family |
| --- | --- | --- | --- |
| air | `0s 0s 0i 0i 0s 0s` | 1 | none |
| solid | `1s 1s 1i 1i 1s 1s` | 1 | none |
| floor | `0s 0s 0i 1i 0s 0s` | 1 | floor |
| slab_edge | `2 2f 0i 1i 0s 0s` | 4 | floor |
| column | `0s 0s 0i 0i 0s 0s` | 1 | none |
| wall | `3s 3s 3_0 3_0 0s 0s` | 2 | none |
| wall_doorway | `3s 3s 3_0 0i 0s 0s` | 2 | none |
| stair | `1s 0s 0i 1i 0s 0s` | 4 | stair |
| bridge | `0s 0s 0i 0i 0s 0s` | 2 | bridge |
| catwalk | `4 4f 0i 0i 1s 0s` | 4 | catwalk |
| ladder | `0s 0s 0i 0i 1s 0s` | 4 | ladder |
| tunnel | `0s 0s 1i 1i 1s 1s` | 2 | tunnel |
| portal_opening | `3s 3s 3_0 0i 0s 0s` | 2 | portal opening |

**Why it is closed.** Every socket's partner is shown on the opposite face
by some tile, most often by the tile itself: `0s`, `1s`, `3s`, `0i` and `1i`
are symmetric or invariant and appear on both faces of an axis; the
asymmetric parapet and catwalk ends pair `2` with `2f` and `4` with `4f`
across the same prototype, so a run of either continues straight and a
half-turned copy, whose parapet is on the other side, cannot join it; and
`3_0`, `3_1` stay within the two wall rotations. So there are no dead
sockets, no empty directions, and every tile touches air or solid through
some open or rock face.

**Stairs.** A stair cell climbs one cell towards its `+x`. Its high end is
`1s` and its bottom `1i`: the stair is cut into rock, and the rock in front
of it carries the next flight one cell up (whose own bottom is `1i`) or the
landing floor (whose bottom is also `1i`). Its low end is `0s`, so it opens
onto a floor at the foot and onto the open cell above the previous flight.
Three stair cells turned the same way climb a stratum, exactly as
`EdgeRasteriser` lays a stair run.

**Walls** stack strictly: `wall` has `3_0` on both vertical faces, so a wall
continues upwards, and a stack ends at the bottom only in `wall_doorway` or
`portal_opening`, whose `-y` is `0i` because nothing crosses the bottom of an
opening. **Columns and ladders** are open (`0i`) at both ends instead. With
stacking ids for them too, nothing ends a column or a ladder, so every one runs
through the whole grid and collides with the rock around it. Measured with
`mise run tiles-check`, seed 0:

| variant | attempts | contradictions | rate |
| --- | --- | --- | --- |
| walls, columns and ladders stack | 249 | 150 | 0.602, fails |
| walls stack, columns and ladders open (committed) | 138 | 38 | 0.275 |
| everything open | 135 | 35 | 0.259 |
| committed, but catwalk and ladder backs open instead of `1s` | 173 | 73 | 0.422 |

The last row shows the other pressure: without its wildcard (#141) solid
only matches rock faces, so every face of a rock region needs a tile showing
`1s` or `1i`. Tiles that offer one (stair fronts, tunnel sides and tops,
catwalk and ladder backs) lower the rate; taking them away raises it. Seeds 1
and 2 give 0.213 and 0.206. Which of these approximations to keep is decision
#153; the one-cell doorway, stair and tunnel proportions are #154.

Placement histogram, 100 runs, 0 failed:

| tiles | cells | share |
| --- | --- | --- |
| air@0 | 6 903 | 32.0 % |
| solid@0 | 2 779 | 12.9 % |
| tunnel@0, @1 | 3 621 | 16.8 % |
| ladder@0 to @3 | 3 516 | 16.3 % |
| floor@0 | 1 060 | 4.9 % |
| wall@0, @1 | 758 | 3.5 % |
| stair@0 to @3 | 1 183 | 5.5 % |
| bridge@0, @1 | 680 | 3.1 % |
| slab_edge@0 to @3 | 366 | 1.7 % |
| column@0 | 202 | 0.9 % |
| portal_opening@0, @1 | 182 | 0.8 % |
| wall_doorway@0, @1 | 158 | 0.7 % |
| catwalk@0 to @3 | 192 | 0.9 % |

Tunnels and ladders are placed far more often than their weights suggest.
Below a rock cell only rock or a tunnel may sit, so propagation forces
tunnels under every solid region the unconstrained grid starts; a ladder
fits wherever air fits and also offers a rock face, so it fills the open
cells beside rock. Catwalks are rarest, because their asymmetric
ends need a straight run of catwalks along a rock face across the grid.

### Complexity

With `n` tiles, `w` words and `c = 216` cells: dead sockets and empty
directions are `O(6 × n × w)`; reachability is `O(6 × n²)` bit reads; the
symmetry check is `O(V)` per symmetric face for `V` mesh vertices. One
placement attempt sorts `c` keys and propagates each change over 6
neighbours at `O(n × w)` per neighbour. The fixtures take well under a
second each in GDScript, including 100 runs.

### Parameters

| Parameter | Where | Effect |
| --- | --- | --- |
| `--runs` | `tiles-check` | Placement runs, default 100. |
| `--grid` | tool option | Grid edge in cells, default 6. |
| `--max-restarts` | tool option | Restarts per run after a contradiction, default 8. |
| `--max-contradiction-rate` | `tiles-check` | Highest passing contradictions ÷ attempts, default 0.5 (#149). |
| `--seed` | `tiles-check` | Base seed of the placement hashes, default 0. |
| `SLAB` | `tiles_check.gd` | 0.01 m either side of a face plane counts as on the face. |
| `TOLERANCE` | `tiles_check.gd` | 0.001 m between a mirrored point and its match. |

`mise run adjacency-check` (part of `check`) covers the matching rules (`s`
with `s`, `N` with `Nf`, vertical rotation indices), the quarter and half
turn above, the A/B/C worked example, exclusions in every direction and
rotation, the fixture table, the word layout past 64 tiles, and for every
table it builds that it equals the direct pairwise rule and is symmetric.

## Open questions

- **Rotation direction.** Pinned in `TileLibrary.QUARTER_TURN` and checked
  against `Basis(Vector3.UP, PI / 2)`. The placement code must build the
  instance basis the same way (GridMap orthogonal indices, then MultiMesh
  transforms); one test that places a rotated asymmetric tile next to its
  partner will confirm it.
- **Weight of a rotation.** Every rotation carries the full prototype
  weight for now; splitting it by `rotations` is decision #146.
- **Vertical index of half-turn symmetric tiles.** A `rotations = 2` tile
  only generates indices `R` and `R + 1`, so a partner authored at `R + 2`
  never matches although the geometry would; decision #147.
- **Hand-written or derived socket ids.** Hand-written ids in a resource are
  faster for the box-only placeholder tileset; derived ids from face profiles
  remove a class of authoring bugs once real meshes arrive.
- **Contradiction threshold.** `tiles-check` fails above a rate of 0.5 by
  default; the placeholder tileset measures 0.21 to 0.28 over seeds 0 to 2,
  so a threshold of 0.1 would fail it until solid gets its wildcard;
  decision #149.
- **Floor-level variants and vertical continuation.** The placeholder keeps
  slab edges, columns and ladders open rather than adding floor-level copies
  and stacking ids; decision #153.
- **Histogram boundary.** The placement grid is unconstrained, so a tile
  with a dead socket still appears on the grid boundary and a
  self-contained group of tiles fills whole grids. The reachability and
  dead socket checks catch both; seeding the grid faces with air and solid,
  as a sector does, would make the histogram catch them too.
- **Vertical symmetry.** Only horizontal `Ns` faces are compared with their
  mirror image; an `Ni` top or bottom face is not yet checked for looking
  the same under all four quarter turns.
- **How many sockets refuse solid.** Too many and contradictions return; too
  few and stairs end in walls.
- **Tile format.** Settled as `TileSet3D` holding `TilePrototype`s
  ([[tileset]]). The socket convention awaits approval in #140; one family
  per prototype is decision #142.

## References

Sources:

- Marian42, Infinite Procedurally Generated City with the Wave Function
  Collapse Algorithm
- Gumin, WaveFunctionCollapse (repository and README, symmetry letters)
- Stålberg, Bad North talk (Everything Procedural Conference 2018)
- Mills, Notes on Wave Function Collapse for 3D

Related notes: [[wave-function-collapse]], [[model-synthesis-and-sectors]],
[[RESEARCH_WFC]] (section 2, the convention and the derivation),
[[MEGASTRUCTURE_CONCEPT]] (tile vocabulary). Terms: [[GLOSSARY#Socket]],
[[GLOSSARY#Bitset]], [[GLOSSARY#Tile library]], [[GLOSSARY#Exclusion list]],
[[GLOSSARY#Dead socket]], [[GLOSSARY#Face profile]].

Code: [[tileset]] (the resource format, the socket parser and
`TileLibrary`, the expansion and the table), [[tools-and-tasks]]
(`tiles_check.gd`, the validation).
