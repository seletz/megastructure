class_name TileLibrary
extends RefCounted
## The rotated tiles of a `TileSet3D` and, for each of the six directions,
## which tiles may sit next to each tile, as bitsets.
##
##     var library := TileLibrary.build(load("res://tests/fixtures/tilesets/fixture_tileset.tres"))
##     if library.errors.is_empty():
##         print(library.tile_count())                                  # 5
##         print(library.tiles[4].label(), library.tiles[4].sockets)    # wall@1 [3s, 3s, 3_1, 3_1, 0s, 0s]
##         print(library.is_allowed(TilePrototype.FACE_POS_Y, 0, 2))    # true: floor on solid
##         print(library.dump())
##
## Expansion: prototypes in authoring order, each turned 0 to `rotations - 1`
## quarter turns about +y, so tile indices run prototype by prototype and
## rotation by rotation. One quarter turn is counter-clockwise seen from
## above, as `Basis(Vector3.UP, PI / 2)` turns: the socket on +x moves to -z,
## -z to -x, -x to +z and +z to +x (`QUARTER_TURN`; the same order as
## `EdgeRasteriser` orientations 0 +x, 1 -z, 2 -x, 3 +z). The six socket
## strings of a turned tile are therefore
##     turned[QUARTER_TURN[face]] = turn(prototype[face])
## applied once per quarter turn. A turn keeps horizontal labels as they are:
## it is a proper rotation, so a profile seen from outside its face is not
## mirrored and the `f` flag would only flip under a mirror, which is never
## generated. Vertical sockets `N_R` become `N_((R + 1) % 4)` per quarter turn
## on both +y and -y; `Ni` stays `Ni`. Every rotation carries the prototype's
## full weight.
##
## Derivation: bit b of `allowed(dir, a)` is set when a's socket on face `dir`
## matches b's socket on the opposite face `dir ^ 1` and neither prototype
## lists the other as an exclusion. Horizontal `Ns` matches `Ns`, `N` matches
## `Nf` and `Nf` matches `N`; vertical `N_R` matches `N_R` and `Ni` matches
## `Ni`; ids must be equal. The table is symmetric: b is allowed from a in
## `dir` exactly when a is allowed from b in `dir ^ 1`. Each entry holds
## `word_count` = ceil(tile_count / 64) words, bit b in word `b >> 6` at
## position `b & 63`. Steps, a worked example and complexity are in
## docs/algorithms/socket-adjacency.md.

## Face a socket moves to after one quarter turn about +y, by face index.
const QUARTER_TURN: Array[int] = [5, 4, 2, 3, 0, 1]
## Bits per bitset word.
const WORD_BITS := 64


## One rotated tile.
class Tile:
	extends RefCounted
	## Position in `TileLibrary.tiles` and bit index in the bitsets.
	var index: int
	## The prototype it was turned from.
	var prototype: TilePrototype
	## Index of `prototype` in the tileset's `prototypes`.
	var prototype_index: int
	## Quarter turns about +y, 0 to the prototype's `rotations - 1`.
	var rotation: int
	## Effective socket strings in face order +x, -x, +y, -y, +z, -z.
	var sockets: PackedStringArray
	## The prototype's weight.
	var weight: float
	## `socket_key` of each face.
	var keys: PackedInt64Array

	## "name@rotation", as the dump prints it.
	func label() -> String:
		return "%s@%d" % [prototype.name, rotation]


## Problems of the tileset; when not empty the library has no tiles.
var errors: Array[String] = []
## Tiles by index.
var tiles: Array[Tile] = []
## Words per bitset, ceil(tile_count / 64).
var word_count := 0
## Per direction, `tile_count * word_count` words: tile a's bitset starts at
## `a * word_count`.
var _allowed: Array[PackedInt64Array] = []


## The library of a tileset; `errors` lists why it is empty when the tileset
## does not validate.
static func build(tileset: TileSet3D) -> TileLibrary:
	var library := TileLibrary.new()
	if tileset == null:
		library.errors.append("no tileset")
		return library
	library.errors = tileset.validate()
	if library.errors.is_empty():
		library._expand(tileset)
		library._derive(tileset)
	return library


## The face a socket on `face` ends up on after `steps` quarter turns
## (negative turns back).
static func rotate_face(face: int, steps: int) -> int:
	for i in posmod(steps, 4):
		face = QUARTER_TURN[face]
	return face


## The socket after `steps` quarter turns: horizontal unchanged, a vertical
## rotation index advanced modulo 4, rotation-invariant unchanged.
static func rotate_socket(socket: TilePrototype.Socket, steps: int) -> TilePrototype.Socket:
	var turned := TilePrototype.Socket.new()
	turned.id = socket.id
	turned.vertical = socket.vertical
	turned.symmetric = socket.symmetric
	turned.flipped = socket.flipped
	turned.rotation = socket.rotation
	if socket.vertical and socket.rotation != TilePrototype.ROTATION_INVARIANT:
		turned.rotation = posmod(socket.rotation + steps, 4)
	return turned


## Six valid socket strings turned `steps` quarter turns.
static func rotate_sockets(sockets: PackedStringArray, steps: int) -> PackedStringArray:
	var turned := PackedStringArray()
	turned.resize(TilePrototype.FACE_COUNT)
	for face in TilePrototype.FACE_COUNT:
		var socket := TilePrototype.parse_socket(sockets[face], face)
		turned[rotate_face(face, steps)] = str(rotate_socket(socket, steps))
	return turned


## Whether socket `a` on some face may touch socket `b` on the opposite face.
static func sockets_match(a: TilePrototype.Socket, b: TilePrototype.Socket) -> bool:
	if a.id != b.id or a.vertical != b.vertical:
		return false
	if a.vertical:
		return a.rotation == b.rotation
	if a.symmetric or b.symmetric:
		return a.symmetric and b.symmetric
	return a.flipped != b.flipped


## An integer naming the socket: equal keys for equal sockets.
static func socket_key(socket: TilePrototype.Socket) -> int:
	if socket.vertical:
		return (socket.id * 5 + socket.rotation + 1) * 2 + 1
	var kind := 1 if socket.symmetric else 2 if socket.flipped else 0
	return (socket.id * 3 + kind) * 2


## The key of the one socket that matches `socket`.
static func partner_key(socket: TilePrototype.Socket) -> int:
	if socket.vertical or socket.symmetric:
		return socket_key(socket)
	var partner := rotate_socket(socket, 0)
	partner.flipped = not socket.flipped
	return socket_key(partner)


func tile_count() -> int:
	return tiles.size()


## Tile b may sit next to tile a in direction `dir` (a face index) when bit b
## of this bitset is set. A copy of `word_count` words; empty for an index out
## of range.
func allowed(dir: int, tile: int) -> PackedInt64Array:
	if dir < 0 or dir >= _allowed.size() or tile < 0 or tile >= tiles.size():
		return PackedInt64Array()
	return _allowed[dir].slice(tile * word_count, (tile + 1) * word_count)


## Whether tile b may sit next to tile a in direction `dir`.
func is_allowed(dir: int, a: int, b: int) -> bool:
	if dir < 0 or dir >= _allowed.size() or a < 0 or a >= tiles.size() or b < 0 or b >= tiles.size():
		return false
	return (_allowed[dir][a * word_count + (b >> 6)] >> (b & 63)) & 1 == 1


## One header line, then one line per tile: index, label, weight, sockets and
## the allowed tile indices per direction as ranges.
func dump() -> String:
	var lines := PackedStringArray()
	lines.append("%d tiles, %d word(s) per bitset" % [tiles.size(), word_count])
	for tile in tiles:
		var parts := PackedStringArray()
		for dir in TilePrototype.FACE_COUNT:
			parts.append("%s:%s" % [TilePrototype.FACE_NAMES[dir], _ranges(dir, tile.index)])
		lines.append("%3d %-14s w=%-5s [%s] %s" % [tile.index, tile.label(), tile.weight, " ".join(tile.sockets), " ".join(parts)])
	return "\n".join(lines)


func _expand(tileset: TileSet3D) -> void:
	for prototype_index in tileset.prototypes.size():
		var prototype := tileset.prototypes[prototype_index]
		for rotation in prototype.rotations:
			var tile := Tile.new()
			tile.index = tiles.size()
			tile.prototype = prototype
			tile.prototype_index = prototype_index
			tile.rotation = rotation
			tile.sockets = rotate_sockets(prototype.sockets, rotation)
			tile.weight = prototype.weight
			tile.keys.resize(TilePrototype.FACE_COUNT)
			for face in TilePrototype.FACE_COUNT:
				tile.keys[face] = socket_key(TilePrototype.parse_socket(tile.sockets[face], face))
			tiles.append(tile)


func _derive(tileset: TileSet3D) -> void:
	var n := tiles.size()
	word_count = (n + WORD_BITS - 1) >> 6
	var empty := PackedInt64Array()
	empty.resize(word_count)
	empty.fill(0)

	# Prototype index -> bitset of the tiles it may not touch, both ways.
	var index_of := {}
	for i in tileset.prototypes.size():
		index_of[tileset.prototypes[i].name] = i
	var excluded := {}
	for i in tileset.prototypes.size():
		for excluded_name in tileset.prototypes[i].exclusions:
			var j: int = index_of[excluded_name]
			excluded.get_or_add(i, {})[j] = true
			excluded.get_or_add(j, {})[i] = true
	var masks := {}
	for i: int in excluded:
		var mask := empty.duplicate()
		for tile in tiles:
			if excluded[i].has(tile.prototype_index):
				mask[tile.index >> 6] |= 1 << (tile.index & 63)
		masks[i] = mask

	_allowed.clear()
	for dir in TilePrototype.FACE_COUNT:
		# Socket key on the opposite face -> bitset of the tiles showing it.
		var showing := {}
		for tile in tiles:
			var key := tile.keys[dir ^ 1]
			var words: PackedInt64Array = showing[key] if showing.has(key) else empty.duplicate()
			words[tile.index >> 6] |= 1 << (tile.index & 63)
			showing[key] = words
		var table := PackedInt64Array()
		table.resize(n * word_count)
		table.fill(0)
		for tile in tiles:
			var socket := TilePrototype.parse_socket(tile.sockets[dir], dir)
			var words: PackedInt64Array = showing.get(partner_key(socket), empty)
			var mask: PackedInt64Array = masks.get(tile.prototype_index, empty)
			var base := tile.index * word_count
			for w in word_count:
				table[base + w] = words[w] & ~mask[w]
		_allowed.append(table)


func _ranges(dir: int, a: int) -> String:
	var parts := PackedStringArray()
	var b := 0
	while b < tiles.size():
		if not is_allowed(dir, a, b):
			b += 1
			continue
		var start := b
		while b + 1 < tiles.size() and is_allowed(dir, a, b + 1):
			b += 1
		parts.append(str(start) if start == b else "%d-%d" % [start, b])
		b += 1
	return ",".join(parts) if not parts.is_empty() else "-"
