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
> (`TilePrototype`, `TileSet3D`); matching, rotation expansion and the table
> come next. The convention follows [[RESEARCH_WFC]], which takes it from
> Marian42's infinite city, and is proposed for approval in issue #140.

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
generated rotation turns the tile 90° about `y`:

- the four horizontal sockets move round one face (the convention to pin in
  code is counter-clockwise seen from above, as Godot rotates about `+y`:
  `+x` goes to `-z`, `-z` to `-x`, `-x` to `+z`, `+z` to `+x`);
- the horizontal labels themselves do not change, because a rotation does not
  mirror anything;
- both vertical sockets increment their rotation index modulo 4, and `i`
  stays `i`.

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

Unit tests cover the matching rules (`s` with `s`, `n` with `nf`, vertical
rotation indices), a 90° rotation permuting sockets correctly, and the
two-way consistency of the derived table.

## Open questions

- **Rotation direction.** The face permutation above has to match how the
  placement code builds the instance basis (GridMap orthogonal indices, then
  MultiMesh transforms). One test that places a rotated asymmetric tile next
  to its partner settles it.
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
[[RESEARCH_WFC]], [[MEGASTRUCTURE_CONCEPT]] (tile vocabulary).

Code: [[tileset]] (the resource format and socket parser); the matching
and the table are not written yet.
