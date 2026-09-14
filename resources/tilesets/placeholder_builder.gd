extends SceneTree
## Builds the box-only placeholder tileset and saves it as
## `resources/tilesets/placeholder.tres`, so its geometry lives in code and
## the resource is only ever regenerated, never edited by hand.
##
##     godot --headless --path . --script res://resources/tilesets/placeholder_builder.gd
##     godot --headless --path . --script res://resources/tilesets/placeholder_builder.gd -- --check
##
## With `--check` it builds the tileset into a temporary file and exits 1
## when that differs from the committed resource or when the tileset does not
## validate with every tile family. Run with `mise run tileset-build` and
## `mise run tileset-build-check`.
##
## Every mesh is a set of axis-aligned boxes in one 2 m cell centred on the
## origin, at the proportions of docs/MEGASTRUCTURE_CONCEPT.md section 3: slab
## 0.6 thick at the bottom of the cell, column 1.1 square, wall 0.7 thick,
## parapet 1.1 tall and 0.14 thick, stair treads 0.4 by 0.4 so one stair cell
## climbs one cell and three climb a stratum. The prototypes, their sockets and
## families are tabled in docs/code/tileset.md.

const OUT := "res://resources/tilesets/placeholder.tres"

## Half a cell, in metres.
const H := 1.0
const SLAB_TOP := -0.4
const COLUMN_HALF := 0.55
const WALL_HALF := 0.35
const PARAPET_TOP := SLAB_TOP + 1.1
const PARAPET := 0.14
const PARAPET_END := 0.2
## Gap that keeps an end piece's geometry off a face whose socket is symmetric.
const INSET := 0.02
const LINTEL_BOTTOM := 0.8
const JAMB := 0.2
const TREADS := 5
const TREAD := 0.4
const STAIR_HALF := 0.9
const TREAD_PLATE := 0.1
const CATWALK_WIDTH := 1.0
const CATWALK_DECK := 0.2
const RAIL := 0.06
const CATWALK_END := 0.2
const LADDER_HALF := 0.3
const LADDER_WALL_GAP := 0.14
const RUNGS := 5
const TUNNEL_WALL := 0.3
const BACKING := 0.3
## Open side faces of each tunnel, vault and bridge shape, unrotated. The
## straight tunnel and bridge are the `tunnel` and `bridge` prototypes.
const TUNNEL_SHAPES := {
	"straight": [0, 1],
	"corner": [0, 4],
	"t": [0, 1, 4],
	"cross": [0, 1, 4, 5],
	"end": [0],
}

const FAMILY := EdgeRasteriser.TileFamily


func _init() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	var tileset := build()
	var errors := tileset.validate(true)
	for error in errors:
		printerr("tileset build: %s" % error)
	if not errors.is_empty():
		quit(1)
		return
	var target := OUT
	if check:
		target = OS.get_user_data_dir().path_join("placeholder_check.tres")
	var status := ResourceSaver.save(tileset, target)
	if status != OK:
		printerr("tileset build: could not save %s (error %d)" % [target, status])
		quit(1)
		return
	if not check:
		print("tileset build: wrote %s, %d prototypes" % [OUT, tileset.prototypes.size()])
		quit(0)
		return
	var built := _normalised(FileAccess.get_file_as_string(target))
	var committed := _normalised(FileAccess.get_file_as_string(OUT))
	DirAccess.remove_absolute(target)
	if built != committed:
		printerr("tileset build: %s is out of date, run: mise run tileset-build" % OUT)
		quit(1)
		return
	print("tileset build: %s is up to date, %d prototypes" % [OUT, tileset.prototypes.size()])
	quit(0)


## The saved text with the script ids, which Godot derives from the path the
## file is saved to, replaced by their order of appearance.
static func _normalised(text: String) -> String:
	var ids := {}
	var re := RegEx.create_from_string("\"(\\d+_[a-z0-9]+)\"")
	for found in re.search_all(text):
		ids.get_or_add(found.get_string(1), "script_%d" % ids.size())
	for id: String in ids:
		text = text.replace("\"%s\"" % id, "\"%s\"" % ids[id])
	return text


## The placeholder tileset. Sockets in face order +x, -x, +y, -y, +z, -z.
## Horizontal ids: 0 open, 1 rock, 2 parapet line, 3 wall, 4 catwalk.
## Vertical ids: 0 open, 1 rock, 3 wall stack. Slab edges are open and
## columns and ladders open at both ends (decision #153); cells clip the
## concept's doorway, stair and tunnel proportions (decision #154).
static func build() -> TileSet3D:
	var tileset := TileSet3D.new()
	var slab := _box(Vector3(-H, -H, -H), Vector3(H, SLAB_TOP, H))
	tileset.prototypes = [
		_prototype("air", null, 20.0, TilePrototype.FAMILY_NONE, ["0s", "0s", "0i", "0i", "0s", "0s"], 1),
		_prototype("solid", _box_mesh(Vector3(2 * H, 2 * H, 2 * H)), 16.0, TilePrototype.FAMILY_NONE, ["1s", "1s", "1i", "1i", "1s", "1s"], 1),
		_prototype("floor", _mesh([slab]), 10.0, FAMILY.FLOOR, ["0s", "0s", "0i", "1i", "0s", "0s"], 1),
		_prototype("slab_edge", _mesh([
			slab,
			_box(Vector3(-H, SLAB_TOP, H - PARAPET), Vector3(H, PARAPET_TOP, H)),
		]), 1.0, FAMILY.FLOOR, ["2", "2f", "0i", "1i", "0s", "0s"], 4),
		_prototype("column", _mesh([
			_box(Vector3(-COLUMN_HALF, -H, -COLUMN_HALF), Vector3(COLUMN_HALF, H, COLUMN_HALF)),
		]), 0.5, TilePrototype.FAMILY_NONE, ["0s", "0s", "0i", "0i", "0s", "0s"], 1),
		_prototype("wall", _mesh([
			_box(Vector3(-H, -H, -WALL_HALF), Vector3(H, H, WALL_HALF)),
		]), 1.0, TilePrototype.FAMILY_NONE, ["3s", "3s", "3_0", "3_0", "0s", "0s"], 2),
		_prototype("wall_doorway", _mesh([
			_box(Vector3(-H, LINTEL_BOTTOM, -WALL_HALF), Vector3(H, H, WALL_HALF)),
		]), 0.5, TilePrototype.FAMILY_NONE, ["3s", "3s", "3_0", "0i", "0s", "0s"], 2),
		_prototype("stair", _mesh(_stair_boxes()), 0.5, FAMILY.STAIR, ["1s", "0s", "0i", "1i", "0s", "0s"], 4),
		_prototype("bridge", _mesh([
			slab,
			_box(Vector3(-H, SLAB_TOP, H - PARAPET), Vector3(H, PARAPET_TOP, H)),
			_box(Vector3(-H, SLAB_TOP, -H), Vector3(H, PARAPET_TOP, -H + PARAPET)),
		]), 1.0, FAMILY.BRIDGE, ["0s", "0s", "0i", "0i", "0s", "0s"], 2),
		_prototype("catwalk", _mesh([
			_box(Vector3(-H, SLAB_TOP - CATWALK_DECK, H - CATWALK_WIDTH), Vector3(H, SLAB_TOP, H)),
			_box(Vector3(-H, SLAB_TOP, H - CATWALK_WIDTH), Vector3(H, PARAPET_TOP, H - CATWALK_WIDTH + RAIL)),
		]), 0.5, FAMILY.CATWALK, ["4", "4f", "0i", "0i", "1s", "0s"], 4),
		_prototype("ladder", _mesh(_ladder_boxes()), 0.5, FAMILY.LADDER, ["0s", "0s", "0i", "0i", "1s", "0s"], 4),
		_prototype("tunnel", _mesh([
			slab,
			_box(Vector3(-H, SLAB_TOP, H - TUNNEL_WALL), Vector3(H, H, H)),
			_box(Vector3(-H, SLAB_TOP, -H), Vector3(H, H, -H + TUNNEL_WALL)),
		]), 1.0, FAMILY.TUNNEL, ["0s", "0s", "1i", "1i", "1s", "1s"], 2),
		_prototype("portal_opening", _mesh([
			_box(Vector3(-H, -H, -WALL_HALF), Vector3(-H + JAMB, H, WALL_HALF)),
			_box(Vector3(H - JAMB, -H, -WALL_HALF), Vector3(H, H, WALL_HALF)),
		]), 0.5, FAMILY.PORTAL_OPENING, ["3s", "3s", "3_0", "0i", "0s", "0s"], 2),
		_prototype("floor_open", _mesh([slab]), 1.0, FAMILY.FLOOR, ["0s", "0s", "0i", "0i", "0s", "0s"], 1),
		_prototype("slab_edge_end", _mesh(_slab_edge_end_boxes(1.0)), 0.5, FAMILY.FLOOR, ["2", "0s", "0i", "1i", "0s", "0s"], 4),
		_prototype("slab_edge_end_f", _mesh(_slab_edge_end_boxes(-1.0)), 0.5, FAMILY.FLOOR, ["0s", "2f", "0i", "1i", "0s", "0s"], 4),
		_prototype("stair_open", _mesh(_open_stair_boxes()), 0.5, FAMILY.STAIR, ["0s", "0s", "0i", "0i", "0s", "0s"], 4),
		_prototype("catwalk_end", _mesh(_catwalk_end_boxes(1.0)), 0.25, FAMILY.CATWALK, ["4", "0s", "0i", "0i", "1s", "0s"], 4),
		_prototype("catwalk_end_f", _mesh(_catwalk_end_boxes(-1.0)), 0.25, FAMILY.CATWALK, ["0s", "4f", "0i", "0i", "1s", "0s"], 4),
		# No lintel: over the 0.6 m slab one cell leaves 1.4 m, so the frame is
		# open at the top and the headroom above it keeps the passage (#173).
		_prototype("portal_frame", _mesh([
			slab,
			_box(Vector3(-H, SLAB_TOP, -WALL_HALF), Vector3(-H + JAMB, H, WALL_HALF)),
			_box(Vector3(H - JAMB, SLAB_TOP, -WALL_HALF), Vector3(H, H, WALL_HALF)),
		]), 0.5, FAMILY.PORTAL_OPENING, ["0s", "0s", "0i", "0i", "0s", "0s"], 2),
		_prototype("catwalk_short", _mesh(_catwalk_short_boxes()), 0.25, FAMILY.CATWALK, ["0s", "0s", "0i", "0i", "1s", "0s"], 4),
		# The rock a catwalk or ladder hangs on where open space is all around,
		# kept INSET off the side faces so they show no lopsided profile (#180).
		_prototype("backing", _mesh([
			_box(Vector3(-H + INSET, -H, -H), Vector3(H - INSET, H, -H + BACKING)),
		]), 0.5, TilePrototype.FAMILY_NONE, ["0s", "0s", "0i", "0i", "0s", "1s"], 4),
	]
	# Passages through rock (#182). A tunnel's walk turns, meets others at the
	# hub and ends at stairs and portals, so the tunnel comes as a corner, a
	# T, a cross and an end besides the straight piece. Above every tunnel
	# cell the head room is a vault: nothing in the lowest 1.8 m, a ceiling
	# above, rock sockets on top and on the closed sides.
	for shape: String in TUNNEL_SHAPES:
		var open: Array = TUNNEL_SHAPES[shape]
		if shape != "straight":
			tileset.prototypes.append(_prototype("tunnel_%s" % shape, _mesh(_tunnel_boxes(open, SLAB_TOP)), 0.25, FAMILY.TUNNEL, _rock_sockets(open, "1i", "1i"), _shape_rotations(open)))
	for shape: String in TUNNEL_SHAPES:
		var open: Array = TUNNEL_SHAPES[shape]
		var suffix := "" if shape == "straight" else "_%s" % shape
		tileset.prototypes.append(_prototype("vault%s" % suffix, _mesh([
			_box(Vector3(-H, -H + TileLibrary.HEADROOM_CLEAR, -H), Vector3(H, H, H)),
		]), 0.25, TilePrototype.FAMILY_NONE, _rock_sockets(open, "1i", "1i"), _shape_rotations(open)))
	# A bridge's walk turns and meets others at the hub too; without these a
	# parapet of the straight bridge stood across the turn (#181).
	for shape: String in TUNNEL_SHAPES:
		var open: Array = TUNNEL_SHAPES[shape]
		if shape != "straight":
			tileset.prototypes.append(_prototype("bridge_%s" % shape, _mesh(_bridge_boxes(open)), 0.25, FAMILY.BRIDGE, ["0s", "0s", "0i", "0i", "0s", "0s"], _shape_rotations(open)))
	tileset.prototypes.append_array([
		# A stair between rock walls, and the cell over it: open to the vault
		# above so the top tread keeps its two cells of head room, with a
		# ledge of rock along the closed sides above the head-room band.
		_prototype("stair_tunnel", _mesh(_stair_tunnel_boxes()), 0.25, FAMILY.STAIR, ["1s", "0s", "0i", "1i", "1s", "1s"], 4),
		_prototype("stairwell", _mesh(_side_boxes([0, 1], -H + TileLibrary.HEADROOM_CLEAR, H, TUNNEL_WALL)), 0.25, TilePrototype.FAMILY_NONE, ["0s", "0s", "1i", "0i", "1s", "1s"], 2),
		# The same over the first stair from a floor or ceiling portal, which
		# reserves no head room: rock on its low side.
		_prototype("stairwell_end", _mesh(_side_boxes([0], -H + TileLibrary.HEADROOM_CLEAR, H, TUNNEL_WALL)), 0.25, TilePrototype.FAMILY_NONE, ["0s", "1s", "1i", "0i", "1s", "1s"], 4),
		# Portals in rock: a tunnel whose passage runs along z (the authored
		# portal yaw) through a side face, and a tunnel end open to +z under a
		# floor or ceiling portal, where the walk steps sideways to its stair.
		_prototype("portal_tunnel", _mesh(_tunnel_boxes([4, 5], SLAB_TOP)), 0.25, FAMILY.PORTAL_OPENING, _rock_sockets([4, 5], "1i", "1i"), 2),
		_prototype("portal_tunnel_end", _mesh(_tunnel_boxes([4], SLAB_TOP)), 0.25, FAMILY.PORTAL_OPENING, _rock_sockets([4], "1i", "1i"), 4),
	])
	return tileset


## Six socket strings for a passage in rock open on the side faces `open`
## (face indices): `0s` there, `1s` on the other side faces, `top` and
## `bottom` on +y and -y.
static func _rock_sockets(open: Array, top: String, bottom: String) -> Array:
	var sockets := []
	for face in TilePrototype.FACE_COUNT:
		if face == TilePrototype.FACE_POS_Y:
			sockets.append(top)
		elif face == TilePrototype.FACE_NEG_Y:
			sockets.append(bottom)
		else:
			sockets.append("0s" if face in open else "1s")
	return sockets


## Distinct quarter turns of a passage open on `open`: 1 for the cross, 2
## for the straight piece, 4 otherwise.
static func _shape_rotations(open: Array) -> int:
	if open.size() == 4:
		return 1
	if open.size() == 2 and open[0] ^ 1 == open[1]:
		return 2
	return 4


## A slab (unless `wall_bottom` is -H, for a stair's own treads) and a
## TUNNEL_WALL thick wall from `wall_bottom` to the top along every side face
## not in `open` (`_side_boxes`).
static func _tunnel_boxes(open: Array, wall_bottom: float) -> Array[AABB]:
	var boxes: Array[AABB] = []
	if wall_bottom > -H:
		boxes.append(_box(Vector3(-H, -H, -H), Vector3(H, SLAB_TOP, H)))
	boxes.append_array(_side_boxes(open, wall_bottom, H, TUNNEL_WALL))
	return boxes


## A slab with a parapet along every side face not in `open`.
static func _bridge_boxes(open: Array) -> Array[AABB]:
	var boxes: Array[AABB] = [_box(Vector3(-H, -H, -H), Vector3(H, SLAB_TOP, H))]
	boxes.append_array(_side_boxes(open, SLAB_TOP, PARAPET_TOP, PARAPET))
	return boxes


## A `thickness` thick box from `bottom` to `top` along every side face not
## in `open`. A box runs out to the faces beside it only where the box across
## from it does too, else it stops INSET short of them, so every face shows a
## mirror-symmetric profile.
static func _side_boxes(open: Array, bottom: float, top: float, thickness: float) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for face: int in [TilePrototype.FACE_POS_X, TilePrototype.FACE_NEG_X, TilePrototype.FACE_POS_Z, TilePrototype.FACE_NEG_Z]:
		if face in open:
			continue
		var axis := face >> 1
		var across := 2 if axis == 0 else 0
		var reach := H if (face ^ 1) not in open else H - INSET
		var from := Vector3.ZERO
		var to := Vector3.ZERO
		from.y = bottom
		to.y = top
		from[axis] = H - thickness if face & 1 == 0 else -H
		to[axis] = H if face & 1 == 0 else -H + thickness
		from[across] = -reach
		to[across] = reach
		boxes.append(_box(from, to))
	return boxes


## Five treads climbing towards +x, each 0.4 m deeper and higher than the
## last, the top tread flush with the top of the cell.
static func _stair_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for i in TREADS:
		boxes.append(_box(Vector3(-H + TREAD * i, -H, -STAIR_HALF), Vector3(H, -H + TREAD * (i + 1), STAIR_HALF)))
	return boxes


## The five treads of `_stair_boxes` between rock walls on both sides.
static func _stair_tunnel_boxes() -> Array[AABB]:
	var boxes := _stair_boxes()
	boxes.append_array(_tunnel_boxes([0, 1], -H))
	return boxes


## The same five treads as `_stair_boxes`, each a plate TREAD_PLATE thick
## under its walking surface, with open space below.
static func _open_stair_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for i in TREADS:
		var top := -H + TREAD * (i + 1)
		boxes.append(_box(Vector3(-H + TREAD * i, top - TREAD_PLATE, -STAIR_HALF), Vector3(-H + TREAD * (i + 1), top, STAIR_HALF)))
	return boxes


## A slab whose parapet runs out of the cell towards `side` (+1 +x, -1 -x)
## and stops PARAPET_END short of the other face, kept INSET off the +z face
## so the open face shows no lopsided profile.
static func _slab_edge_end_boxes(side: float) -> Array[AABB]:
	var end := -side * (H - PARAPET_END)
	return [
		_box(Vector3(-H, -H, -H), Vector3(H, SLAB_TOP, H)),
		_box(Vector3(minf(end, side * H), SLAB_TOP, H - PARAPET - INSET), Vector3(maxf(end, side * H), PARAPET_TOP, H - INSET)),
	]


## A catwalk deck that runs out of the cell towards `side` (+1 +x, -1 -x)
## and stops CATWALK_END short of the other face, with a railing on its open
## side and across its end. It keeps CATWALK_END off the +z face too, so the
## rock face it hangs on shows no lopsided profile.
static func _catwalk_end_boxes(side: float) -> Array[AABB]:
	var end := -side * (H - CATWALK_END)
	var near := minf(end, side * H)
	var far := maxf(end, side * H)
	var back := H - CATWALK_END
	var boxes: Array[AABB] = [
		_box(Vector3(near, SLAB_TOP - CATWALK_DECK, H - CATWALK_WIDTH), Vector3(far, SLAB_TOP, back)),
		_box(Vector3(near, SLAB_TOP, H - CATWALK_WIDTH), Vector3(far, PARAPET_TOP, H - CATWALK_WIDTH + RAIL)),
	]
	var post := end if side > 0 else end - RAIL
	boxes.append(_box(Vector3(post, SLAB_TOP, H - CATWALK_WIDTH + RAIL), Vector3(post + RAIL, PARAPET_TOP, back)))
	return boxes


## A catwalk deck with its railing that stops INSET short of both side faces,
## so it continues into no neighbour and stands alone in a record cell; open
## at both ends so a walk steps on and off along it. It keeps CATWALK_END off
## the +z face like the end pieces.
static func _catwalk_short_boxes() -> Array[AABB]:
	var reach := H - INSET
	return [
		_box(Vector3(-reach, SLAB_TOP - CATWALK_DECK, H - CATWALK_WIDTH), Vector3(reach, SLAB_TOP, H - CATWALK_END)),
		_box(Vector3(-reach, SLAB_TOP, H - CATWALK_WIDTH), Vector3(reach, PARAPET_TOP, H - CATWALK_WIDTH + RAIL)),
	]


## Two rails and five rungs standing off the +z face.
static func _ladder_boxes() -> Array[AABB]:
	var z_back := H - LADDER_WALL_GAP
	var boxes: Array[AABB] = [
		_box(Vector3(-LADDER_HALF, -H, z_back - RAIL), Vector3(-LADDER_HALF + RAIL, H, z_back)),
		_box(Vector3(LADDER_HALF - RAIL, -H, z_back - RAIL), Vector3(LADDER_HALF, H, z_back)),
	]
	var pitch := 2 * H / RUNGS
	for i in RUNGS:
		var y := -H + pitch * (i + 0.5)
		boxes.append(_box(Vector3(-LADDER_HALF + RAIL, y - RAIL / 2, z_back - RAIL), Vector3(LADDER_HALF - RAIL, y + RAIL / 2, z_back)))
	return boxes


static func _prototype(prototype_name: String, mesh: Mesh, weight: float, family: int, sockets: Array, rotations: int) -> TilePrototype:
	var prototype := TilePrototype.new()
	prototype.name = prototype_name
	prototype.mesh = mesh
	prototype.weight = weight
	prototype.family = family
	prototype.sockets = PackedStringArray(sockets)
	prototype.rotations = rotations
	# Fixed ids keep the saved resource identical from build to build.
	prototype.resource_scene_unique_id = "prototype_%s" % prototype_name
	if mesh != null:
		mesh.resource_scene_unique_id = "mesh_%s" % prototype_name
	return prototype


static func _box(from: Vector3, to: Vector3) -> AABB:
	return AABB(from, to - from)


static func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## One surface of all boxes, six outward quads each with flat normals.
static func _mesh(boxes: Array[AABB]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box in boxes:
		var a := box.position
		var b := box.end
		# Corners of each face counter-clockwise seen from outside.
		var faces := [
			[Vector3.RIGHT, Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z)],
			[Vector3.LEFT, Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z)],
			[Vector3.UP, Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z)],
			[Vector3.DOWN, Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)],
			[Vector3.BACK, Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)],
			[Vector3.FORWARD, Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z)],
		]
		for face in faces:
			st.set_normal(face[0])
			# Godot's front faces are clockwise, so emit the quad reversed.
			for index in [1, 3, 2, 1, 4, 3]:
				st.add_vertex(face[index])
	return st.commit()
