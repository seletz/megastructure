class_name TileContactSheet
extends Node3D
## Lays out every rotated tile of a tileset in a grid, each with its cell
## outline, a +x marker and a label, and frames it with an orthographic
## camera. Used by scenes/tile_contact_sheet.tscn to render
## docs/images/placeholder-tileset.png:
##
##     mise run shot scenes/tile_contact_sheet.tscn docs/images/placeholder-tileset.png
##
## Tiles are placed in library order, row by row, on a ground grid turned
## with the camera so rows stay level in the image while the tiles keep
## their world axes (the red line is each tile's +x). A tile turned k quarter
## turns gets `Basis(Vector3.UP, k * PI / 2)`, the turn `TileLibrary` expands
## sockets with, so the picture shows the same rotations the adjacency table
## derives. Colours are by tile family, grey for free tiles.

## Tiles per row.
@export var columns := 6
## Distance between neighbouring tiles across a row and between rows, in
## metres; rows leave room for the labels.
@export var spacing := Vector2(5.4, 7.6)
## The view: yaw of the camera about +y from the +z side and its pitch below
## the horizon, in degrees.
@export var view_yaw := 30.0
@export var view_pitch := 35.0
@export var tileset: TileSet3D

const FAMILY_COLOURS: Array[Color] = [
	Color("#c8c2b4"), # floor
	Color("#e0a040"), # stair
	Color("#60a0e0"), # bridge
	Color("#50c0a0"), # catwalk
	Color("#e06050"), # ladder
	Color("#a080d0"), # tunnel
	Color("#f0d050"), # portal opening
]
const FREE_COLOUR := Color("#8a8f96")
const OUTLINE_COLOUR := Color(1, 1, 1, 0.25)
const AXIS_COLOUR := Color("#ff4040")

var _library: TileLibrary


func _ready() -> void:
	_library = TileLibrary.build(tileset)
	for error in _library.errors:
		push_error("tile contact sheet: %s" % error)
	for tile in _library.tiles:
		_add_tile(tile)
	_add_lines()
	_frame()


## Horizontal unit vector pointing from the scene towards the camera.
func _towards_camera() -> Vector3:
	return Vector3.BACK.rotated(Vector3.UP, deg_to_rad(view_yaw))


## Horizontal unit vector to the right in the image.
func _across() -> Vector3:
	return Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(view_yaw))


func _position(index: int) -> Vector3:
	return _across() * (index % columns) * spacing.x + _towards_camera() * (index / columns) * spacing.y


func _add_tile(tile: TileLibrary.Tile) -> void:
	var origin := _position(tile.index)
	if tile.prototype.mesh != null:
		var instance := MeshInstance3D.new()
		instance.name = tile.label().replace("@", "_")
		instance.mesh = tile.prototype.mesh
		instance.transform = Transform3D(Basis(Vector3.UP, tile.rotation * PI / 2), origin)
		var material := StandardMaterial3D.new()
		var family := tile.prototype.family
		material.albedo_color = FREE_COLOUR if family == TilePrototype.FAMILY_NONE else FAMILY_COLOURS[family]
		material.roughness = 0.9
		instance.material_override = material
		add_child(instance)
	var label := Label3D.new()
	label.text = "%s\n%s" % [tile.label(), " ".join(tile.sockets)]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.011
	label.font_size = 40
	label.outline_size = 12
	label.no_depth_test = true
	label.position = origin + Vector3(0, -1.6, 0) + _towards_camera() * 1.9
	add_child(label)


## Each cell's outline and a short line along its +x axis at the floor.
func _add_lines() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for tile in _library.tiles:
		var origin := _position(tile.index)
		var corners: Array[Vector3] = []
		for i in 8:
			corners.append(origin + Vector3(1 if i & 1 else -1, 1 if i & 2 else -1, 1 if i & 4 else -1))
		mesh.surface_set_color(OUTLINE_COLOUR)
		for i in 8:
			for bit in [1, 2, 4]:
				if i & bit == 0:
					mesh.surface_add_vertex(corners[i])
					mesh.surface_add_vertex(corners[i | bit])
		mesh.surface_set_color(AXIS_COLOUR)
		mesh.surface_add_vertex(origin + Vector3(0, -1, 0))
		mesh.surface_add_vertex(origin + Vector3(1.6, -1, 0))
	mesh.surface_end()
	var lines := MeshInstance3D.new()
	lines.name = "Outlines"
	lines.mesh = mesh
	add_child(lines)


## Points the camera and the sun at the grid and sizes the orthographic
## view to the width of a row.
func _frame() -> void:
	var camera := get_node_or_null("Camera") as Camera3D
	if camera == null or _library.tile_count() == 0:
		return
	var rows := ceili(float(_library.tile_count()) / columns)
	var centre := _across() * (columns - 1) * spacing.x / 2.0 + _towards_camera() * ((rows - 1) * spacing.y / 2.0 + 0.6)
	var pitch := deg_to_rad(view_pitch)
	var direction := _towards_camera() * cos(pitch) + Vector3.UP * sin(pitch)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.look_at_from_position(centre + direction * 80.0, centre, Vector3.UP)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = columns * spacing.x * 1.02
	camera.far = 200.0
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		# From above the -x, +z corner, so tops, -x and +z faces differ in shade.
		sun.look_at_from_position(centre + Vector3(-20, 40, 14), centre, Vector3.UP)
