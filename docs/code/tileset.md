---
tags:
  - code-map
  - tileset
  - wfc
status: current
---

# Tileset

> [!summary]
> The fill solver builds sectors out of tiles: 2 m cubes of geometry such as
> a floor slab, a wall or a stair. A **tile prototype** is one hand-authored
> tile: its mesh, how often the solver should pick it, which path family it
> can stand in for, the six **sockets** on its faces that decide what may sit
> next to it, how many turned copies to generate, and tiles it must never
> touch. A **tileset** is the list of prototypes plus the names of its solid
> and air tiles. Both are Godot resources, saved as `.tres` and edited in
> the inspector. A validator lists every mistake as one line of text, so a
> broken tileset fails a check before the solver ever sees it. A **tile
> library** is built from a valid tileset once at load: every prototype
> turned into its rotations, and for each tile and each of the six
> directions a bitset of the tiles allowed next to it
> ([[socket-adjacency]]).

## Files

- [tile_prototype.gd](../../scripts/world/tile_prototype.gd) (`class_name
  TilePrototype`, a `Resource`): the fields below, the face constants, the
  inner class `Socket` and the socket string parser.
- [tileset.gd](../../scripts/world/tileset.gd) (`class_name TileSet3D`, a
  `Resource`): the prototypes, `solid_name`, `air_name` and the validator.
  Named `TileSet3D` because Godot's own `TileSet` is the 2D tile map
  resource.
- [tile_library.gd](../../scripts/world/tile_library.gd) (`class_name
  TileLibrary`, a `RefCounted`): rotation expansion, socket matching and
  the adjacency bitsets, with the inner class `Tile`.
- `tests/fixtures/tilesets/fixture_tileset.tres`: solid, air, floor and wall
  as `BoxMesh` placeholders; valid.
- `tests/fixtures/tilesets/broken_tileset.tres`: a tileset with one of each
  format mistake, for the format check.
- `tests/fixtures/tilesets/dead_socket_tileset.tres`: a tileset that
  validates but cannot be placed well: solid and air plus a pipe with a dead
  `+x` socket, an island that matches only itself and a plug dead on `+x`
  and `-x`, for the validation task.
- `scripts/tools/tileset_check.gd`, `scripts/tools/adjacency_check.gd` and
  `scripts/tools/tiles_check.gd`: the checks behind `mise run
  tileset-check`, `mise run adjacency-check` (which also serves
  `adjacency-dump`) and `mise run tiles-check` (which also serves
  `tiles-check-fixtures`), listed in [[tools-and-tasks]].

Both scripts are `@tool`, so the inspector shows `family` as a drop-down of
the `EdgeRasteriser.TileFamily` names plus None.

## Using it

```gdscript
var tileset: TileSet3D = load("res://tests/fixtures/tilesets/fixture_tileset.tres")
var errors := tileset.validate()           # [] when valid
for error in errors:
	printerr(error)
var solid := tileset.find(tileset.solid_name)
var top := solid.socket(TilePrototype.FACE_POS_Y)   # TilePrototype.Socket, id 1, invariant
print(TilePrototype.socket_error("5_4", TilePrototype.FACE_NEG_Y))
# socket -y "5_4" is not N_0..N_3 or Ni
```

| `TilePrototype` field | Meaning |
| --- | --- |
| `name` | Unique inside the tileset; exclusions, `solid_name` and `air_name` refer to it. |
| `mesh` | The unrotated tile's `Mesh`, centred on the cell. Only the air tile may leave it empty. |
| `weight` | How strongly the solver prefers the tile; must be greater than 0. |
| `family` | An `EdgeRasteriser.TileFamily` (floor, stair, bridge, catwalk, ladder, tunnel, portal opening) or `FAMILY_NONE` (−1) for a free tile no graph record asks for, such as solid, air or a wall. One family per prototype; decision #142. |
| `sockets` | Six socket strings in face order `+x, -x, +y, -y, +z, -z` (`FACE_POS_X` = 0 ... `FACE_NEG_Z` = 5); the opposite face of `d` is `d ^ 1`. |
| `rotations` | 1, 2 or 4: how many quarter turns about `+y` to generate. 1 for a tile that looks the same turned (column, solid), 2 for one that repeats after a half turn (straight wall), 4 otherwise (corner, stair). |
| `exclusions` | Names of prototypes that may not sit next to this one in any direction, even when the sockets match. Usually empty. |

Socket strings are `N`, `Ns` or `Nf` on horizontal faces and `N_0` to `N_3`
or `Ni` on vertical faces, with `N` a decimal id without leading zeros. The
precise grammar, what each form matches and why the ids are numbers are in
[[socket-adjacency#Socket strings]].

| `TilePrototype` function | Returns |
| --- | --- |
| `parse_socket(text, face)` (static) | A `Socket` with `id`, `vertical`, `symmetric`, `flipped` and `rotation` (`ROTATION_INVARIANT` = −1 for `Ni`), or `null` when the string is not valid for that face or the face is outside 0..5. `str(socket)` gives the string back. |
| `socket_error(text, face)` (static) | `""` when valid, otherwise a message such as `socket +x "3x" is not N, Ns or Nf`. |
| `is_vertical(face)` (static) | Whether the face is `+y` or `-y`. |
| `socket(face)` | The parsed socket of one face, or `null`. |
| `validate()` | This prototype's own problems: empty name, weight, family out of range, rotations, socket count and each bad socket string. |

| `TileSet3D` member | Meaning |
| --- | --- |
| `prototypes` | `Array[TilePrototype]` in authoring order. |
| `solid_name` | Name of the solid tile (default `"solid"`). |
| `air_name` | Name of the air tile (default `"air"`). |
| `find(name)` | The prototype with that name, or `null`. |
| `missing_families()` | The `TileFamily` values no prototype has, ascending. |
| `validate(require_families := false)` | Every problem as one string, empty when valid: first each prototype in order (its own `validate()`, then a repeated name, then a missing mesh), then exclusions naming no prototype, a `solid_name` or `air_name` naming no prototype, the two names being equal and, with `require_families`, one line per missing family. |

Every message starts with `prototype "<name>":` when it belongs to one
prototype, so a long list still reads per tile. The order is fixed, which
lets the check compare the broken fixture's list line by line.

The resources only store and validate. `TileLibrary` does the rest:

```gdscript
var library := TileLibrary.build(tileset)
if not library.errors.is_empty():          # the tileset's validate() messages
	return
for tile in library.tiles:                 # prototype order, then quarter turns
	print(tile.index, " ", tile.label(), " ", tile.sockets)   # 4 wall@1 ["3s", "3s", "3_1", ...]
var above := library.allowed(TilePrototype.FACE_POS_Y, 0)       # PackedInt64Array, word_count words
print(library.is_allowed(TilePrototype.FACE_POS_Y, 0, 2))       # true: floor may sit on solid
print(library.dump())
```

| `TileLibrary` member | Meaning |
| --- | --- |
| `build(tileset)` (static) | The library; on an invalid or null tileset `errors` holds the messages and there are no tiles. |
| `errors` | `Array[String]`, empty for a usable library. |
| `tiles` | `Array[TileLibrary.Tile]`, index = bit position. Each has `index`, `prototype`, `prototype_index`, `rotation` (quarter turns), `sockets` (effective strings in face order), `weight` (the prototype's, unchanged; #146), `keys` and `label()` (`name@rotation`). |
| `word_count` | `ceil(tile_count / 64)` words per bitset. |
| `tile_count()` | Number of tiles. |
| `allowed(dir, tile)` | Copy of the bitset of tiles allowed next to `tile` in direction `dir` (a face index); bit `b` in word `b >> 6` at `b & 63`. Empty when an index is out of range. |
| `is_allowed(dir, a, b)` | One bit of it; `false` out of range. The table is symmetric: `is_allowed(d, a, b) == is_allowed(d ^ 1, b, a)`. |
| `dump()` | One header line and one line per tile: index, label, weight, sockets and the allowed indices per direction as ranges (`+y:0,2 -y:1-2`). |
| `QUARTER_TURN` | Face index to face index after one quarter turn: `[5, 4, 2, 3, 0, 1]`, `+x`→`-z`, `-z`→`-x`, `-x`→`+z`, `+z`→`+x`. |
| `rotate_face(face, steps)`, `rotate_socket(socket, steps)`, `rotate_sockets(sockets, steps)` (static) | The face permutation, one socket turned (vertical index + steps mod 4, horizontal unchanged) and six strings turned. |
| `sockets_match(a, b)` (static) | Whether two parsed sockets on opposite faces match: `Ns`–`Ns`, `N`–`Nf`, `N_R`–`N_R`, `Ni`–`Ni`, equal ids. |
| `socket_key(socket)`, `partner_key(socket)` (static) | Integer name of a socket and of the one socket that matches it; the table groups tiles by these. |

A tileset that validates can still be unusable: a socket nothing matches, a
tile no chain of neighbours connects to air or solid, an `Ns` face whose
mesh is lopsided, a tile the placement never picks. `mise run tiles-check`
finds those (below). The real placeholder tileset, which should pass
`validate(true)` and `tiles-check`, is #88.

## How to run or check it

- `mise run tileset-check` (part of `mise run check`) parses 112 socket
  strings, valid and invalid, on every face and compares the parsed fields;
  validates a prototype of every family and of `FAMILY_NONE` and rejects
  families out of range; loads the fixture, which must validate with no
  errors, keep its names, meshes, weights, rotations and sockets, and miss
  exactly the six families other than floor; and loads the broken fixture,
  whose errors must equal the expected 14 lines in order.
- `mise run adjacency-check` (part of `mise run check`) checks the matching
  rules on 28 socket pairs, a hand-computed quarter and half turn and the
  face permutation against `Basis(Vector3.UP, PI / 2)`, the A/B/C worked
  example, an exclusion in every direction and rotation, the fixture's 5
  tiles and full table, the word layout of a 66-tile set (bits 63 and 64,
  out-of-range arguments), and that every table it builds equals the
  pairwise rule and is symmetric. It prints the build times (fixture about
  0.6 ms, 66 tiles about 7 ms) and the fixture dump.
- `mise run adjacency-dump res://path/to/tileset.tres` prints any tileset's
  tiles and table, or its validation errors (exit 1).
- `mise run tiles-check <tileset.tres> [--max-contradiction-rate R] [--runs
  N] [--seed N]` validates any tileset, `res://` or project-relative path:
  dead sockets, directions with no allowed tile, tiles unreachable from air
  and solid, `Ns` faces whose mesh profile is not mirror-symmetric (meshes
  without vertex data are skipped with a warning), and a 100-run 6³
  placement histogram with the contradiction rate. Every finding is one
  `FAIL  <category>: <message>` line; exit 1 on any. The algorithm and both
  fixtures' output are in [[socket-adjacency#Validation]].
- `mise run tiles-check-fixtures` (part of `mise run check`) runs the tool's
  self-test: the fixture passes with contradiction rate 0; the dead socket
  fixture fails with exactly dead sockets, empty directions, an unreachable
  tile and a never-placed tile; placement repeats for a seed, changes with
  the seed and fails a threshold below its rate; and a `BoxMesh`, the same
  box as an `ArrayMesh`, that box shifted off-centre and an empty
  `ArrayMesh` pass, pass, fail on `±x` and warn.
- Open a fixture in the editor (`mise run editor`, then double-click the
  `.tres`) to see the inspector layout.

## References

- [[socket-adjacency]]: the socket grammar, the matching rules, the
  expansion and derivation algorithm with worked examples, and the
  validation checks and minimal placement.
- [[edge-rasteriser]]: where tile families come from.
- [[RESEARCH_WFC]], sections 2 and 7 (C1): the convention and the plan.
- [[MEGASTRUCTURE_CONCEPT]], section 3: the tile vocabulary the real tileset
  will cover.
