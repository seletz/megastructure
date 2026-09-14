extends SceneTree
## Checks the tile resource format. Parses valid and invalid socket strings
## for every face and compares the parsed fields; checks a prototype of every
## `EdgeRasteriser.TileFamily` and of FAMILY_NONE validates; loads the fixture
## tileset, which must validate with no errors, keep its fields and miss
## exactly the families it has no prototype for; loads the broken fixture,
## whose errors must equal the expected list line for line.
## Run headless with `mise run tileset-check`.

const FIXTURE := "res://tests/fixtures/tilesets/fixture_tileset.tres"
const BROKEN := "res://tests/fixtures/tilesets/broken_tileset.tres"

## Valid horizontal socket strings with id, symmetric, flipped.
const HORIZONTAL_VALID := [
	["0", 0, false, false], ["0s", 0, true, false], ["3", 3, false, false],
	["3s", 3, true, false], ["3f", 3, false, true], ["120f", 120, false, true],
]
## Valid vertical socket strings with id and rotation (-1 invariant).
const VERTICAL_VALID := [
	["0i", 0, -1], ["5_0", 5, 0], ["5_1", 5, 1], ["5_2", 5, 2], ["5_3", 5, 3], ["42i", 42, -1],
]
const HORIZONTAL_INVALID: Array[String] = ["", "s", "f", "03", "3sf", "3fs", "3S", "3i", "3_0", "-3", " 3s", "3s ", "x3"]
const VERTICAL_INVALID: Array[String] = ["", "5", "5s", "5f", "5_4", "5_-1", "5_", "_1", "05_1", "5_1i", "5I", "5_01"]

const BROKEN_ERRORS: Array[String] = [
	"prototype \"solid\": weight 0.0 is not greater than 0",
	"prototype \"solid\": name used more than once",
	"prototype \"ramp\": family 9 is not FAMILY_NONE or an EdgeRasteriser.TileFamily",
	"prototype \"ramp\": rotations 3 is not 1, 2 or 4",
	"prototype \"ramp\": socket +x \"3x\" is not N, Ns or Nf",
	"prototype \"ramp\": socket -x \"03\" is not N, Ns or Nf",
	"prototype \"ramp\": socket -y \"5_4\" is not N_0..N_3 or Ni",
	"prototype \"ramp\": socket +z \"2i\" is not N, Ns or Nf",
	"prototype \"ramp\": no mesh",
	"prototype \"short\": 5 sockets, expected 6",
	"prototype \"short\": socket +y \"1\" is not N_0..N_3 or Ni",
	"prototype \"\": empty name",
	"prototype \"ramp\": exclusion \"nowhere\" is not a prototype",
	"air_name \"void\" is not a prototype",
]

var _failures := 0


func _init() -> void:
	_check_sockets()
	_check_families()
	_check_fixture()
	_check_broken()
	print("tileset check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_sockets() -> void:
	var cases := 0
	for face in TilePrototype.FACE_COUNT:
		var vertical := TilePrototype.is_vertical(face)
		for case in VERTICAL_VALID if vertical else HORIZONTAL_VALID:
			cases += 1
			var socket := TilePrototype.parse_socket(case[0], face)
			if socket == null:
				_fail("socket %s \"%s\" did not parse" % [TilePrototype.FACE_NAMES[face], case[0]])
				continue
			var fields: Array = [socket.id, socket.rotation] if vertical else [socket.id, socket.symmetric, socket.flipped]
			if socket.vertical != vertical or fields != case.slice(1) or str(socket) != case[0]:
				_fail("socket %s \"%s\" parsed as %s %s" % [TilePrototype.FACE_NAMES[face], case[0], fields, socket])
			if not TilePrototype.socket_error(case[0], face).is_empty():
				_fail("socket %s \"%s\" reported an error" % [TilePrototype.FACE_NAMES[face], case[0]])
		for text in VERTICAL_INVALID if vertical else HORIZONTAL_INVALID:
			cases += 1
			if TilePrototype.parse_socket(text, face) != null or TilePrototype.socket_error(text, face).is_empty():
				_fail("socket %s \"%s\" was accepted" % [TilePrototype.FACE_NAMES[face], text])
	if TilePrototype.parse_socket("0s", -1) != null or TilePrototype.parse_socket("0s", TilePrototype.FACE_COUNT) != null:
		_fail("parse_socket accepted a face outside 0..5")
	for face in TilePrototype.FACE_COUNT:
		if TilePrototype.FACE_NAMES[face ^ 1][1] != TilePrototype.FACE_NAMES[face][1]:
			_fail("face %s is not opposite %s" % [TilePrototype.FACE_NAMES[face], TilePrototype.FACE_NAMES[face ^ 1]])
	print("  sockets: %d cases" % cases)


func _check_families() -> void:
	var families: Array[int] = [TilePrototype.FAMILY_NONE]
	for family in EdgeRasteriser.TileFamily.size():
		families.append(family)
	for family in families:
		var prototype := TilePrototype.new()
		prototype.name = "tile"
		prototype.family = family
		prototype.mesh = BoxMesh.new()
		var errors := prototype.validate()
		if not errors.is_empty():
			_fail("a prototype of family %d does not validate: %s" % [family, errors])
	for family in [TilePrototype.FAMILY_NONE - 1, EdgeRasteriser.TileFamily.size()]:
		var prototype := TilePrototype.new()
		prototype.name = "tile"
		prototype.family = family
		if prototype.validate().size() != 1:
			_fail("family %d was accepted" % family)
	print("  families: %d expressible" % families.size())


func _check_fixture() -> void:
	var tileset := load(FIXTURE) as TileSet3D
	if tileset == null:
		_fail("%s did not load as a TileSet3D" % FIXTURE)
		return
	var errors := tileset.validate()
	if not errors.is_empty():
		_fail("%s: unexpected errors %s" % [FIXTURE, errors])
	var names := PackedStringArray()
	for prototype in tileset.prototypes:
		names.append(prototype.name)
	if names != PackedStringArray(["solid", "air", "floor", "wall"]):
		_fail("%s: prototypes %s" % [FIXTURE, names])
	var solid := tileset.find(tileset.solid_name)
	var air := tileset.find(tileset.air_name)
	var floor_tile := tileset.find("floor")
	var wall := tileset.find("wall")
	if solid == null or air == null or floor_tile == null or wall == null:
		_fail("%s: solid, air, floor or wall not found" % FIXTURE)
		return
	if not solid.mesh is BoxMesh or air.mesh != null or tileset.find("nowhere") != null:
		_fail("%s: meshes or find are wrong" % FIXTURE)
	if floor_tile.family != EdgeRasteriser.TileFamily.FLOOR or floor_tile.weight != 4.0 or wall.rotations != 2:
		_fail("%s: floor family or weight, or wall rotations, are wrong" % FIXTURE)
	var wall_top := wall.socket(TilePrototype.FACE_POS_Y)
	if wall_top == null or wall_top.id != 3 or wall_top.rotation != 0 or not wall.socket(TilePrototype.FACE_POS_Z).symmetric:
		_fail("%s: wall sockets parsed wrong" % FIXTURE)
	var missing := tileset.missing_families()
	var expected: Array[int] = []
	for family in EdgeRasteriser.TileFamily.size():
		if family != EdgeRasteriser.TileFamily.FLOOR:
			expected.append(family)
	if missing != expected or tileset.validate(true).size() != expected.size():
		_fail("%s: missing families %s, expected %s" % [FIXTURE, missing, expected])
	print("  fixture: %d prototypes, valid, %d families missing" % [names.size(), missing.size()])


func _check_broken() -> void:
	var tileset := load(BROKEN) as TileSet3D
	if tileset == null:
		_fail("%s did not load as a TileSet3D" % BROKEN)
		return
	var errors := tileset.validate()
	for i in maxi(errors.size(), BROKEN_ERRORS.size()):
		var got: String = errors[i] if i < errors.size() else "(none)"
		var want: String = BROKEN_ERRORS[i] if i < BROKEN_ERRORS.size() else "(none)"
		if got != want:
			_fail("%s: error %d is %s, expected %s" % [BROKEN, i, got, want])
	print("  broken fixture: %d errors" % errors.size())


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  %s" % message)
