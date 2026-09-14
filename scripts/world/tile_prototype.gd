@tool
class_name TilePrototype
extends Resource
## One hand-authored tile of a `TileSet3D`, before its rotations are generated.
##
##     var floor := TilePrototype.new()
##     floor.name = "floor"
##     floor.mesh = BoxMesh.new()
##     floor.family = EdgeRasteriser.TileFamily.FLOOR
##     floor.sockets = PackedStringArray(["2s", "2s", "0i", "1i", "2s", "2s"])
##     print(TilePrototype.socket_error(floor.sockets[TilePrototype.FACE_POS_Y], TilePrototype.FACE_POS_Y))  # ""
##
## A tile fills one 2 m cell. Each of its six faces carries a socket string in
## the order +x, -x, +y, -y, +z, -z, so a face's opposite is `face ^ 1`.
## Horizontal faces (+x, -x, +z, -z) take `N`, `Ns` or `Nf`: profile N,
## asymmetric, mirror-symmetric or flipped. Vertical faces (+y, -y) take
## `N_R` with a rotation index R in 0..3, or `Ni` for a rotation-invariant
## profile. N is a decimal id without leading zeros. The grammar, matching
## rules and a worked example are in docs/algorithms/socket-adjacency.md;
## this resource only stores and parses the strings, it does not match them.

## Face indices into `sockets`.
const FACE_POS_X := 0
const FACE_NEG_X := 1
const FACE_POS_Y := 2
const FACE_NEG_Y := 3
const FACE_POS_Z := 4
const FACE_NEG_Z := 5
const FACE_COUNT := 6
const FACE_NAMES: Array[String] = ["+x", "-x", "+y", "-y", "+z", "-z"]

## `family` of a free tile, one no graph record asks for (solid, air, wall).
const FAMILY_NONE := -1

## Allowed values of `rotations`.
const ROTATION_COUNTS: Array[int] = [1, 2, 4]

## `Socket.rotation` of a rotation-invariant vertical socket (`Ni`).
const ROTATION_INVARIANT := -1

const _HORIZONTAL_PATTERN := "^(0|[1-9][0-9]*)(s|f)?$"
const _VERTICAL_PATTERN := "^(0|[1-9][0-9]*)(?:_([0-3])|(i))$"

static var _horizontal_re: RegEx
static var _vertical_re: RegEx


## A parsed socket string.
class Socket:
	extends RefCounted
	## The profile id N.
	var id: int
	## Whether the face is vertical (+y or -y).
	var vertical: bool
	## Horizontal only: `Ns`.
	var symmetric := false
	## Horizontal only: `Nf`.
	var flipped := false
	## Vertical only: R of `N_R`, or ROTATION_INVARIANT for `Ni`.
	var rotation := ROTATION_INVARIANT

	func _to_string() -> String:
		if vertical:
			return "%d%s" % [id, "i" if rotation == ROTATION_INVARIANT else "_%d" % rotation]
		return "%d%s" % [id, "s" if symmetric else "f" if flipped else ""]


## Unique name inside the tileset; exclusions and the solid and air names
## refer to it.
@export var name := ""
## Geometry of the unrotated tile, centred on the cell. May be null only for
## the tileset's air tile.
@export var mesh: Mesh
## How strongly the solver prefers the tile; greater than 0.
@export_range(0.001, 100.0, 0.001, "or_greater") var weight := 1.0
## `EdgeRasteriser.TileFamily` the tile belongs to, or FAMILY_NONE.
@export var family := FAMILY_NONE
## Socket strings in face order +x, -x, +y, -y, +z, -z.
@export var sockets := PackedStringArray(["0s", "0s", "0i", "0i", "0s", "0s"])
## Yaw rotations generated from the tile: 1, 2 or 4 quarter-turn steps.
@export_enum("1:1", "2:2", "4:4") var rotations := 1
## Names of prototypes that may not sit next to this one in any direction,
## even when their sockets match.
@export var exclusions := PackedStringArray()


func _validate_property(property: Dictionary) -> void:
	if property.name == "family":
		var names := PackedStringArray(["None:%d" % FAMILY_NONE])
		for i in EdgeRasteriser.FAMILY_NAMES.size():
			names.append("%s:%d" % [EdgeRasteriser.FAMILY_NAMES[i].capitalize(), i])
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(names)


## Whether a face index is +y or -y.
static func is_vertical(face: int) -> bool:
	return face == FACE_POS_Y or face == FACE_NEG_Y


## The parsed socket, or null when `text` is not a valid socket for the face.
static func parse_socket(text: String, face: int) -> Socket:
	if face < 0 or face >= FACE_COUNT:
		return null
	if _horizontal_re == null:
		_horizontal_re = RegEx.create_from_string(_HORIZONTAL_PATTERN)
		_vertical_re = RegEx.create_from_string(_VERTICAL_PATTERN)
	var socket := Socket.new()
	socket.vertical = is_vertical(face)
	if socket.vertical:
		var match_v := _vertical_re.search(text)
		if match_v == null:
			return null
		socket.id = match_v.get_string(1).to_int()
		if match_v.get_string(3).is_empty():
			socket.rotation = match_v.get_string(2).to_int()
	else:
		var match_h := _horizontal_re.search(text)
		if match_h == null:
			return null
		socket.id = match_h.get_string(1).to_int()
		socket.symmetric = match_h.get_string(2) == "s"
		socket.flipped = match_h.get_string(2) == "f"
	return socket


## "" when `text` is a valid socket for the face, otherwise why it is not.
static func socket_error(text: String, face: int) -> String:
	if parse_socket(text, face) != null:
		return ""
	if is_vertical(face):
		return "socket %s \"%s\" is not N_0..N_3 or Ni" % [FACE_NAMES[face], text]
	return "socket %s \"%s\" is not N, Ns or Nf" % [FACE_NAMES[face], text]


## The parsed socket of a face; null when the string is invalid.
func socket(face: int) -> Socket:
	if face < 0 or face >= sockets.size():
		return null
	return parse_socket(sockets[face], face)


## Problems with this prototype alone, each prefixed with its name. Names of
## other prototypes (exclusions, solid, air) are checked by `TileSet3D`.
func validate() -> Array[String]:
	var errors: Array[String] = []
	var label := "prototype \"%s\"" % name
	if name.is_empty():
		errors.append("%s: empty name" % label)
	if weight <= 0.0:
		errors.append("%s: weight %s is not greater than 0" % [label, weight])
	if family != FAMILY_NONE and (family < 0 or family >= EdgeRasteriser.TileFamily.size()):
		errors.append("%s: family %d is not FAMILY_NONE or an EdgeRasteriser.TileFamily" % [label, family])
	if rotations not in ROTATION_COUNTS:
		errors.append("%s: rotations %d is not 1, 2 or 4" % [label, rotations])
	if sockets.size() != FACE_COUNT:
		errors.append("%s: %d sockets, expected 6" % [label, sockets.size()])
	for face in mini(sockets.size(), FACE_COUNT):
		var problem := socket_error(sockets[face], face)
		if not problem.is_empty():
			errors.append("%s: %s" % [label, problem])
	return errors
