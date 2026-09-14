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
> broken tileset fails a check before the solver ever sees it. Matching the
> sockets and building the adjacency table come later
> ([[socket-adjacency]]).

## Files

- [tile_prototype.gd](../../scripts/world/tile_prototype.gd) (`class_name
  TilePrototype`, a `Resource`): the fields below, the face constants, the
  inner class `Socket` and the socket string parser.
- [tileset.gd](../../scripts/world/tileset.gd) (`class_name TileSet3D`, a
  `Resource`): the prototypes, `solid_name`, `air_name` and the validator.
  Named `TileSet3D` because Godot's own `TileSet` is the 2D tile map
  resource.
- `tests/fixtures/tilesets/fixture_tileset.tres`: solid, air, floor and wall
  as `BoxMesh` placeholders; valid.
- `tests/fixtures/tilesets/broken_tileset.tres`: a tileset with one of each
  mistake, for the check.
- `scripts/tools/tileset_check.gd`: the check behind `mise run
  tileset-check`, listed in [[tools-and-tasks]].

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

The resources only store and validate. Matching sockets, expanding
rotations, applying exclusions and building `allowed[dir][tile]` bitsets
are issue #86; checking reachability, dead sockets and mesh symmetry is
#87; the real placeholder tileset, which should pass
`validate(true)`, is #88.

## How to run or check it

- `mise run tileset-check` (part of `mise run check`) parses 112 socket
  strings, valid and invalid, on every face and compares the parsed fields;
  validates a prototype of every family and of `FAMILY_NONE` and rejects
  families out of range; loads the fixture, which must validate with no
  errors, keep its names, meshes, weights, rotations and sockets, and miss
  exactly the six families other than floor; and loads the broken fixture,
  whose errors must equal the expected 14 lines in order.
- Open a fixture in the editor (`mise run editor`, then double-click the
  `.tres`) to see the inspector layout.

## References

- [[socket-adjacency]]: the socket grammar, the matching rules, rotation
  expansion and the planned validation.
- [[edge-rasteriser]]: where tile families come from.
- [[RESEARCH_WFC]], sections 2 and 7 (C1): the convention and the plan.
- [[MEGASTRUCTURE_CONCEPT]], section 3: the tile vocabulary the real tileset
  will cover.
