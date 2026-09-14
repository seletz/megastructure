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
> [[GLOSSARY#Rotation expansion|rotation expansion]] and the
> [[GLOSSARY#Adjacency table|adjacency table]] (`TileLibrary`); the
> validation task comes next. The convention follows [[RESEARCH_WFC]], which
> takes it from Marian42's infinite city, and is proposed for approval in
> issue #140.

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

Today `mise run tileset-check` checks only the format: the socket grammar,
unique names, weights, rotations, families, meshes and the names that
exclusions, solid and air refer to (see [[tileset]]). A headless `mise`
task, planned as `tiles-check`, will run in CI and fail the build on:

1. **Dead sockets.** A socket used on some `+d` face that no `-d` face
   matches. The tile can never have a neighbour there and causes a
   contradiction whenever it is placed away from a fixed boundary.
2. **Empty directions.** A tile whose allowed set is empty in some direction
   (the same failure, seen per tile).
3. **Unreachable tiles.** A breadth-first search over the adjacency graph
   from air and solid. Sector faces start as mostly air and solid, so a tile
   not reachable from them will never appear.
4. **False symmetry.** For every socket tagged symmetric, quantise the mesh
   vertices lying on that face, hash the set, and compare with the hash of
   the mirrored set. The same face-profile hash could later derive socket ids
   from geometry, as Oskar Stålberg describes for Bad North.
5. **Dead tiles in practice.** Solve an unconstrained 6³ grid 100 times and
   print how often each tile was placed. A tile that never appears usually
   has a weight or socket mistake.

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
[[GLOSSARY#Bitset]], [[GLOSSARY#Tile library]], [[GLOSSARY#Exclusion list]].

Code: [[tileset]] (the resource format, the socket parser and
`TileLibrary`, the expansion and the table).
