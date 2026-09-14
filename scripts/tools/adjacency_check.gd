extends SceneTree
## Checks rotation expansion and the adjacency table of `TileLibrary`. The
## socket matching rules pair by pair; a hand-computed quarter and half turn
## of one prototype, and the face permutation against Godot's own
## `Basis(Vector3.UP, PI / 2)`; the worked example of
## docs/algorithms/socket-adjacency.md; exclusions in every direction and
## rotation; the fixture tileset's tile count and full table; the bitset word
## layout of a 66-tile set; and, for every table built here, that it agrees
## with a direct pairwise comparison and is symmetric. Prints the build times
## and the fixture's dump. With `-- --dump <res path>` it only dumps that
## tileset. Run headless with `mise run adjacency-check`.

const FIXTURE := "res://tests/fixtures/tilesets/fixture_tileset.tres"

## Socket pairs on opposite faces (horizontal, then vertical) and whether they match.
const HORIZONTAL_MATCHES := [
	["3s", "3s", true], ["3", "3f", true], ["3f", "3", true],
	["3s", "3", false], ["3s", "3f", false], ["3", "3", false], ["3f", "3f", false],
	["3s", "4s", false], ["3", "4f", false], ["0s", "0s", true],
]
const VERTICAL_MATCHES := [
	["5_1", "5_1", true], ["5i", "5i", true], ["5_1", "5_2", false], ["5_0", "5_3", false],
	["5i", "5_0", false], ["5_0", "5i", false], ["5_1", "6_1", false], ["5i", "6i", false],
]

## A prototype with every face different, and its sockets after one and two
## quarter turns, worked out by hand: +x goes to -z, -z to -x, -x to +z, +z
## to +x, vertical indices advance by one per turn.
const TURN_PROTOTYPE: Array[String] = ["1", "2s", "5_0", "6_3", "3f", "4"]
const TURN_ONCE: Array[String] = ["3f", "4", "5_1", "6_0", "2s", "1"]
const TURN_TWICE: Array[String] = ["2s", "1", "5_2", "6_1", "4", "3f"]

## Fixture tiles and, per direction +x, -x, +y, -y, +z, -z, the allowed
## tile indices of each tile.
const FIXTURE_LABELS: Array[String] = ["solid@0", "air@0", "floor@0", "wall@0", "wall@1"]
const FIXTURE_ALLOWED := [
	[[0], [1, 3], [2], [1, 3], [4]],
	[[0], [1, 3], [2], [1, 3], [4]],
	[[0, 2], [1], [1], [3], [4]],
	[[0], [1, 2], [0], [3], [4]],
	[[0], [1, 4], [2], [3], [1, 4]],
	[[0], [1, 4], [2], [3], [1, 4]],
]

var _failures := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dump_at := args.find("--dump")
	if dump_at != -1:
		quit(_dump(args[dump_at + 1] if dump_at + 1 < args.size() else ""))
		return
	_check_matching()
	_check_rotation()
	_check_worked_example()
	_check_exclusions()
	_check_fixture()
	_check_word_layout()
	print("adjacency check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _dump(path: String) -> int:
	var tileset: TileSet3D = null
	if ResourceLoader.exists(path):
		tileset = load(path) as TileSet3D
	if tileset == null:
		printerr("adjacency dump: %s is not a TileSet3D" % path)
		return 1
	var library := TileLibrary.build(tileset)
	for error in library.errors:
		printerr(error)
	print(library.dump())
	return 0 if library.errors.is_empty() else 1


func _check_matching() -> void:
	var cases := 0
	for pair in [[TilePrototype.FACE_POS_X, HORIZONTAL_MATCHES], [TilePrototype.FACE_POS_Z, HORIZONTAL_MATCHES], [TilePrototype.FACE_POS_Y, VERTICAL_MATCHES]]:
		var face: int = pair[0]
		for case in pair[1]:
			cases += 1
			var a := TilePrototype.parse_socket(case[0], face)
			var b := TilePrototype.parse_socket(case[1], face ^ 1)
			if TileLibrary.sockets_match(a, b) != case[2] or TileLibrary.sockets_match(b, a) != case[2]:
				_fail("%s %s against %s %s should %smatch" % [TilePrototype.FACE_NAMES[face], case[0], TilePrototype.FACE_NAMES[face ^ 1], case[1], "" if case[2] else "not "])
			if (TileLibrary.partner_key(a) == TileLibrary.socket_key(b)) != case[2]:
				_fail("partner key of %s disagrees with matching %s" % [case[0], case[1]])
	print("  matching: %d socket pairs" % cases)


func _check_rotation() -> void:
	var prototype := PackedStringArray(TURN_PROTOTYPE)
	var once := TileLibrary.rotate_sockets(prototype, 1)
	var twice := TileLibrary.rotate_sockets(prototype, 2)
	if once != PackedStringArray(TURN_ONCE):
		_fail("one quarter turn gave %s, expected %s" % [once, TURN_ONCE])
	if twice != PackedStringArray(TURN_TWICE) or TileLibrary.rotate_sockets(once, 1) != twice:
		_fail("two quarter turns gave %s, expected %s" % [twice, TURN_TWICE])
	if TileLibrary.rotate_sockets(prototype, 4) != prototype or TileLibrary.rotate_sockets(once, -1) != prototype:
		_fail("four turns, or a turn back, do not restore the prototype")

	# The permutation is Godot's: turning each face normal by +90 degrees about +y.
	var normals: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var turn := Basis(Vector3.UP, PI / 2.0)
	for face in TilePrototype.FACE_COUNT:
		var turned := (turn * normals[face]).round()
		if turned != normals[TileLibrary.rotate_face(face, 1)]:
			_fail("face %s turns to %s in Godot, not %s" % [TilePrototype.FACE_NAMES[face], turned, TilePrototype.FACE_NAMES[TileLibrary.rotate_face(face, 1)]])

	var tileset := _tileset([_prototype("turned", TURN_PROTOTYPE, 4)])
	var library := _build(tileset, "rotation set")
	if library.tile_count() != 6:
		_fail("rotation set: %d tiles, expected 6" % library.tile_count())
	else:
		var turned := library.tiles[3]
		if turned.label() != "turned@1" or turned.sockets != PackedStringArray(TURN_ONCE) or turned.prototype_index != 2:
			_fail("rotation set: tile 3 is %s %s" % [turned.label(), turned.sockets])
		if library.tiles[2].sockets[TilePrototype.FACE_NEG_Z] != "4" or library.tiles[5].sockets[TilePrototype.FACE_POS_X] != "4":
			_fail("rotation set: turned@0 -z or turned@3 +x is not 4")
	_check_table(library, "rotation set")
	print("  rotation: quarter and half turn of %s" % " ".join(TURN_PROTOTYPE))


func _check_worked_example() -> void:
	# The three tiles along x of the worked example; everything else open.
	var tileset := _tileset([
		_prototype("a", ["0s", "0s", "0i", "0i", "0s", "0s"], 1),
		_prototype("b", ["2", "0s", "0i", "0i", "0s", "0s"], 1),
		_prototype("c", ["0s", "2f", "0i", "0i", "0s", "0s"], 1),
	])
	var library := _build(tileset, "worked example")
	# Tiles 0 and 1 are solid and air; a, b, c are 2, 3, 4, so shift the example's bits by 2.
	var expected := {
		TilePrototype.FACE_POS_X: [0b011, 0b100, 0b011],
		TilePrototype.FACE_NEG_X: [0b101, 0b101, 0b010],
	}
	for dir: int in expected:
		for i in 3:
			var bits := library.allowed(dir, 2 + i)
			var got := (bits[0] >> 2) & 0b111 if bits.size() == 1 else -1
			if got != expected[dir][i]:
				_fail("worked example: allowed %s of %s is %s, expected %s" % [TilePrototype.FACE_NAMES[dir], "abc"[i], _bits(got), _bits(expected[dir][i])])
	_check_table(library, "worked example")
	print("  worked example: A, B, C along x")


func _check_exclusions() -> void:
	var open: Array[String] = ["0s", "0s", "0i", "0i", "0s", "0s"]
	var a := _prototype("a", open, 1)
	var b := _prototype("b", open, 4)
	a.exclusions = PackedStringArray(["b"])
	var library := _build(_tileset([a, b]), "exclusion set")
	var pairs := 0
	# Every open tile touches every other in every direction, except a with any rotation of b.
	for dir in TilePrototype.FACE_COUNT:
		for x in library.tiles:
			for y in library.tiles:
				if x.prototype.name == "solid" or y.prototype.name == "solid":
					continue
				var names := x.prototype.name + y.prototype.name
				var forbidden := names == "ab" or names == "ba"
				if forbidden:
					pairs += 1
				if library.is_allowed(dir, x.index, y.index) == forbidden:
					_fail("exclusion set: %s %s %s is %s" % [x.label(), TilePrototype.FACE_NAMES[dir], y.label(), "allowed" if forbidden else "forbidden"])
	_check_table(library, "exclusion set")
	print("  exclusions: %d excluded tile pairs, both ways" % pairs)


func _check_fixture() -> void:
	var tileset := load(FIXTURE) as TileSet3D
	if tileset == null:
		_fail("%s did not load as a TileSet3D" % FIXTURE)
		return
	var start := Time.get_ticks_usec()
	var library := TileLibrary.build(tileset)
	var usec := Time.get_ticks_usec() - start
	if not library.errors.is_empty():
		_fail("%s: %s" % [FIXTURE, library.errors])
		return
	var labels := PackedStringArray()
	for tile in library.tiles:
		labels.append(tile.label())
	if labels != PackedStringArray(FIXTURE_LABELS) or library.word_count != 1:
		_fail("fixture: tiles %s, %d word(s)" % [labels, library.word_count])
		return
	if library.tiles[2].weight != 4.0 or library.tiles[4].sockets != PackedStringArray(["3s", "3s", "3_1", "3_1", "0s", "0s"]):
		_fail("fixture: floor weight or wall@1 sockets are wrong")
	for dir in TilePrototype.FACE_COUNT:
		for a in library.tile_count():
			var expected := 0
			for b: int in FIXTURE_ALLOWED[dir][a]:
				expected |= 1 << b
			if library.allowed(dir, a) != PackedInt64Array([expected]):
				_fail("fixture: allowed %s of %s is %s, expected %s" % [TilePrototype.FACE_NAMES[dir], labels[a], library.allowed(dir, a), _bits(expected)])
	_check_table(library, "fixture")
	print("  fixture: %d prototypes, %d tiles, %d word(s), built in %.3f ms" % [tileset.prototypes.size(), library.tile_count(), library.word_count, usec / 1000.0])
	for line in library.dump().split("\n"):
		print("    %s" % line)


func _check_word_layout() -> void:
	var prototypes: Array[TilePrototype] = []
	for i in 64:
		prototypes.append(_prototype("p%d" % i, ["0s", "0s", "0i", "0i", "0s", "0s"], 1))
	var tileset := _tileset(prototypes)
	var start := Time.get_ticks_usec()
	var library := _build(tileset, "layout set")
	var usec := Time.get_ticks_usec() - start
	# solid is tile 0, air tile 1, p0..p63 tiles 2..65: bit 63 is p61, bit 64 p62.
	if library.tile_count() != 66 or library.word_count != 2:
		_fail("layout set: %d tiles, %d words" % [library.tile_count(), library.word_count])
		return
	if TileLibrary.build(_tileset([])).word_count != 1 or TileLibrary.new().word_count != 0:
		_fail("layout set: word count of 2 tiles or of no tiles is wrong")
	var open := library.allowed(TilePrototype.FACE_POS_X, 1)
	var rock := library.allowed(TilePrototype.FACE_POS_X, 0)
	# From air: every tile but solid (bit 0); bits 64 and 65 in word 1, nothing above.
	if open != PackedInt64Array([~1, 0b11]):
		_fail("layout set: allowed +x of air is %s, expected [%d, 3]" % [open, ~1])
	if rock != PackedInt64Array([1, 0]):
		_fail("layout set: allowed +x of solid is %s, expected [1, 0]" % rock)
	if not library.is_allowed(TilePrototype.FACE_POS_X, 65, 63) or not library.is_allowed(TilePrototype.FACE_POS_X, 63, 64) or library.is_allowed(TilePrototype.FACE_POS_X, 64, 0):
		_fail("layout set: is_allowed disagrees at the word boundary")
	if not library.allowed(6, 0).is_empty() or not library.allowed(0, 66).is_empty() or library.is_allowed(0, 0, 66) or library.is_allowed(-1, 0, 0):
		_fail("layout set: out of range arguments were accepted")
	for dir in TilePrototype.FACE_COUNT:
		for a in library.tile_count():
			var words := library.allowed(dir, a)
			for b in library.tile_count():
				var word := floori(b / 64.0)
				var bit := b - 64 * word
				if ((words[word] >> bit) & 1 == 1) != library.is_allowed(dir, a, b):
					_fail("layout set: bit %d of allowed %s of %d is not in word %d at %d" % [b, TilePrototype.FACE_NAMES[dir], a, word, bit])
					return
	_check_table(library, "layout set")
	print("  word layout: %d tiles, %d words per bitset, built in %.3f ms" % [library.tile_count(), library.word_count, usec / 1000.0])


## The table agrees with comparing every pair's sockets directly and is symmetric.
func _check_table(library: TileLibrary, what: String) -> void:
	for dir in TilePrototype.FACE_COUNT:
		for x in library.tiles:
			for y in library.tiles:
				var direct := TileLibrary.sockets_match(
					TilePrototype.parse_socket(x.sockets[dir], dir),
					TilePrototype.parse_socket(y.sockets[dir ^ 1], dir ^ 1)
				) and not (y.prototype.name in x.prototype.exclusions) and not (x.prototype.name in y.prototype.exclusions)
				if library.is_allowed(dir, x.index, y.index) != direct:
					_fail("%s: %s %s %s is %s, sockets say %s" % [what, x.label(), TilePrototype.FACE_NAMES[dir], y.label(), library.is_allowed(dir, x.index, y.index), direct])
					return
				if library.is_allowed(dir, x.index, y.index) != library.is_allowed(dir ^ 1, y.index, x.index):
					_fail("%s: %s %s %s is not symmetric" % [what, x.label(), TilePrototype.FACE_NAMES[dir], y.label()])
					return


func _build(tileset: TileSet3D, what: String) -> TileLibrary:
	var library := TileLibrary.build(tileset)
	if not library.errors.is_empty():
		_fail("%s: %s" % [what, library.errors])
	return library


## A valid tileset of solid, air and the given prototypes.
func _tileset(extra: Array[TilePrototype]) -> TileSet3D:
	var tileset := TileSet3D.new()
	tileset.prototypes.append(_prototype("solid", ["1s", "1s", "1i", "1i", "1s", "1s"], 1))
	tileset.prototypes.append(_prototype("air", ["0s", "0s", "0i", "0i", "0s", "0s"], 1))
	tileset.prototypes.append_array(extra)
	return tileset


func _prototype(prototype_name: String, sockets: Array[String], rotations: int) -> TilePrototype:
	var prototype := TilePrototype.new()
	prototype.name = prototype_name
	prototype.mesh = BoxMesh.new()
	prototype.sockets = PackedStringArray(sockets)
	prototype.rotations = rotations
	return prototype


func _bits(value: int) -> String:
	return String.num_int64(value, 2)


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  %s" % message)
