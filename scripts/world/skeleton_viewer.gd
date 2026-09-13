class_name SkeletonViewer
extends Node3D
## Debug view of the skeleton: every sector within `radius` sectors of the
## camera drawn as a colour-coded cube, one MultiMeshInstance3D per type.
##
## The style is per type. With `fill` (the default) shaft, cavity, chasm and
## solid are translucent filled boxes, solid a little more opaque than the
## voids; off, they are wireframe cubes (12 edges, PRIMITIVE_LINES). Stratum is
## the majority, so with `stratum_wireframe` (the default) it is a faint
## wireframe cube that does not hide the rest; off, a faint filled box.
## `show_stratum` hides it. Every material is unshaded, translucent and
## without depth write, so the region reads through itself from inside and
## outside; render priorities fix the blending order between types: solid,
## then the voids over it, then stratum on top. Cubes are inset (44 m of a
## 48 m sector) so neighbours stay apart. The sector the camera is in is never
## drawn, and cubes farther than half the radius from the centre fade towards
## FADE_MIN so the near structure dominates.
##
## The instance buffers are rebuilt only when the camera enters another
## sector or the radius, a toggle, the seed or a grammar parameter changes, as
## one PackedFloat32Array per type handed to MultiMesh.buffer. Sector types
## are cached per cell for the drawn region, so crossing a sector boundary
## hashes only the new slab; a seed or grammar change clears the cache. With
## `follow_camera` off the region stays where it is, so it can be looked at
## from outside.
##
## The legend (type colours, counts in view, refresh time) is added under the
## label of the Hud at `hud`, so H hides it together with the HUD.

const MAX_RADIUS := 6
## Box edge is the sector edge minus this, in metres (44 m of 48 m).
const BOX_MARGIN := 4.0
## Filled box colours per type; solid is more opaque than the voids.
const TYPE_COLORS: Array[Color] = [
	Color(0.55, 0.62, 0.75, 0.12),
	Color(0.2, 0.75, 1.0, 0.35),
	Color(1.0, 0.6, 0.15, 0.35),
	Color(0.42, 0.42, 0.45, 0.45),
	Color(0.95, 0.2, 0.35, 0.35),
]
## Wireframe edge colours per type.
const WIRE_COLORS: Array[Color] = [
	Color(0.55, 0.62, 0.75, 0.12),
	Color(0.2, 0.75, 1.0, 0.95),
	Color(1.0, 0.6, 0.15, 0.95),
	Color(0.6, 0.6, 0.64, 0.45),
	Color(0.95, 0.2, 0.35, 0.95),
]
## Brightness of cubes at the radius and beyond; cubes within half the radius
## stay at 1.
const FADE_MIN := 0.2
## Translucent passes draw in ascending render priority: solid first, the
## voids blended over it, stratum last so its faint edges stay visible.
const RENDER_PRIORITIES: Array[int] = [2, 1, 1, 0, 1]

## FreeFlyCamera whose sector the region is centred on.
@export var camera: NodePath
## Hud whose label the legend is attached to (optional).
@export var hud: NodePath
## Region radius in sectors: (2 radius + 1)^3 sectors are drawn.
@export_range(0, MAX_RADIUS) var radius := 4:
	set(value):
		radius = clampi(value, 0, MAX_RADIUS)
		_dirty = true
@export var show_stratum := true:
	set(value):
		show_stratum = value
		_dirty = true
## Shaft, cavity, solid and chasm as translucent filled boxes instead of
## wireframe cubes.
@export var fill := true:
	set(value):
		fill = value
		_apply_style()
## Stratum as a faint wireframe cube instead of a faint filled box.
@export var stratum_wireframe := true:
	set(value):
		stratum_wireframe = value
		_apply_style()
## When false, the region stays at `center` while the camera moves.
@export var follow_camera := true:
	set(value):
		follow_camera = value
		_dirty = true
## Centre sector of the region; tracks the camera while follow_camera is on.
@export var center := Vector3i.ZERO:
	set(value):
		center = value
		_dirty = true
@export var grammar: SectorGrammar

var skeleton: Skeleton
## Sectors of each type in the drawn region, hidden stratum included.
var counts := PackedInt32Array([0, 0, 0, 0, 0])
## Duration of the last rebuild in microseconds.
var last_refresh_usec := 0
var refresh_count := 0

var _instances: Array[MultiMeshInstance3D] = []
var _box_mesh: BoxMesh
var _wire_mesh: ArrayMesh
var _camera: FreeFlyCamera
## Sector the camera was in at the last refresh; it is left out of the drawing.
var _camera_cell := Vector3i.ZERO
var _dirty := true
## Sector index -> SectorType of the cells drawn by the last refresh.
var _type_cache := {}
var _legend_counts: Array[Label] = []
var _legend_status: Label


func _ready() -> void:
	if grammar == null:
		grammar = SectorGrammar.new()
	skeleton = Skeleton.new(grammar)
	_camera = get_node_or_null(camera) as FreeFlyCamera
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_wire_mesh = _cube_edges()
	for type in Skeleton.SectorType.size():
		var instance := MultiMeshInstance3D.new()
		instance.name = Skeleton.type_name(type).capitalize()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		instance.multimesh = multimesh
		add_child(instance)
		_instances.append(instance)
	_apply_style()
	_build_legend()
	WorldState.seed_changed.connect(func(_seed: int) -> void: invalidate_types())


func _process(_delta: float) -> void:
	if _camera != null:
		var cell := sector_of(_camera.global_position)
		if follow_camera and cell != center:
			center = cell
		if cell != _camera_cell:
			_dirty = true
	if _dirty:
		refresh()


## Forgets every cached sector type and redraws (after a seed or grammar change).
func invalidate_types() -> void:
	_type_cache.clear()
	_dirty = true


## Sector index containing a world position.
func sector_of(world_position: Vector3) -> Vector3i:
	return Vector3i((world_position / _sector_size()).floor())


## The grammar's sector edge, kept at 1 m or more (the panel slider reaches 0).
func _sector_size() -> float:
	return maxf(grammar.sector_size, 1.0)


## Rebuilds every type's instance buffer for the region around `center`.
func refresh() -> void:
	_dirty = false
	var start := Time.get_ticks_usec()
	var side := 2 * radius + 1
	var total := side * side * side
	var types := PackedByteArray()
	types.resize(total)
	counts = PackedInt32Array([0, 0, 0, 0, 0])
	var world_seed := WorldState.seed
	var cache := {}
	var index := 0
	for ix in range(center.x - radius, center.x + radius + 1):
		for iy in range(center.y - radius, center.y + radius + 1):
			for iz in range(center.z - radius, center.z + radius + 1):
				var cell := Vector3i(ix, iy, iz)
				var type: int = _type_cache.get(cell, -1)
				if type < 0:
					type = skeleton.sector_type(world_seed, cell)
				cache[cell] = type
				types[index] = type
				counts[type] += 1
				index += 1
	_type_cache = cache

	# Index of the camera's sector inside the region; -1 (never matched) without a camera.
	var skipped := -Vector3i.ONE
	if _camera != null:
		_camera_cell = sector_of(_camera.global_position)
		skipped = _camera_cell - (center - Vector3i.ONE * radius)
	var size := _sector_size()
	var box_size := maxf(size - BOX_MARGIN, size * 0.5)
	var origin := Vector3(center - Vector3i.ONE * radius) * size + Vector3.ONE * (size * 0.5)
	var fade_start := radius * 0.5
	var fade_span := maxf(radius - fade_start, 0.001)
	for type in Skeleton.SectorType.size():
		var multimesh := _instances[type].multimesh
		var drawn := type != Skeleton.SectorType.STRATUM or show_stratum
		# MultiMesh.buffer holds 16 floats per instance: the basis rows with the
		# origin as the fourth column, then the instance colour.
		var buffer := PackedFloat32Array()
		buffer.resize(counts[type] * 16 if drawn else 0)
		var offset := 0
		index = 0
		if drawn:
			for x in side:
				for y in side:
					for z in side:
						if types[index] == type and Vector3i(x, y, z) != skipped:
							var distance := Vector3(x - radius, y - radius, z - radius).length()
							var brightness := lerpf(1.0, FADE_MIN, clampf((distance - fade_start) / fade_span, 0.0, 1.0))
							buffer[offset] = box_size
							buffer[offset + 3] = origin.x + x * size
							buffer[offset + 5] = box_size
							buffer[offset + 7] = origin.y + y * size
							buffer[offset + 10] = box_size
							buffer[offset + 11] = origin.z + z * size
							buffer[offset + 12] = 1.0
							buffer[offset + 13] = 1.0
							buffer[offset + 14] = 1.0
							buffer[offset + 15] = brightness
							offset += 16
						index += 1
		buffer.resize(offset)
		multimesh.instance_count = offset / 16
		if offset > 0:
			multimesh.buffer = buffer
	last_refresh_usec = Time.get_ticks_usec() - start
	refresh_count += 1
	_update_legend()


## Adds the viewer's own settings and every SectorGrammar export to the panel.
func register_params(registry: ParamRegistry) -> void:
	if grammar == null:
		grammar = SectorGrammar.new()
	registry.add_script_params("viewer", {
		"radius": {"value": radius, "default": 4, "min": 0, "max": MAX_RADIUS, "step": 1},
		"show_stratum": {"value": show_stratum, "default": true},
		"fill": {"value": fill, "default": true},
		"stratum_wireframe": {"value": stratum_wireframe, "default": true},
		"follow_camera": {"value": follow_camera, "default": true},
	}, func(param_name: String, value: Variant) -> void: set(param_name, value))
	registry.add_object_exports(grammar, func(param_name: String, value: Variant) -> void:
		grammar.set(param_name, value)
		if param_name == "sector_size":
			_dirty = true
		else:
			invalidate_types()
	, "grammar")


## Mesh and material of every type for the current `fill` and
## `stratum_wireframe` settings. The instance buffers do not depend on them.
func _apply_style() -> void:
	for type in _instances.size():
		var filled := not stratum_wireframe if type == Skeleton.SectorType.STRATUM else fill
		var instance := _instances[type]
		instance.multimesh.mesh = _box_mesh if filled else _wire_mesh
		var material := _material(TYPE_COLORS[type] if filled else WIRE_COLORS[type])
		material.render_priority = RENDER_PRIORITIES[type]
		instance.material_override = material


## Unshaded translucent material without depth write; the instance colour's
## alpha multiplies `color.a` (the distance fade).
static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## The 12 edges of the unit cube centred on the origin as a line mesh.
static func _cube_edges() -> ArrayMesh:
	var vertices := PackedVector3Array()
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for a in [-0.5, 0.5]:
			for b in [-0.5, 0.5]:
				var start := Vector3.ZERO
				start[axis] = -0.5
				start[u] = a
				start[v] = b
				var end := start
				end[axis] = 0.5
				vertices.append(start)
				vertices.append(end)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _build_legend() -> void:
	var hud_node := get_node_or_null(hud) as Hud
	if hud_node == null:
		return
	var label := hud_node.get_node("Label") as Label
	var legend := VBoxContainer.new()
	legend.name = "Legend"
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.anchor_top = 1.0
	legend.anchor_bottom = 1.0
	legend.offset_top = 8.0
	legend.add_theme_constant_override("separation", 2)
	label.add_child(legend)
	var font := label.get_theme_font("font")
	for type in Skeleton.SectorType.size():
		var row := HBoxContainer.new()
		legend.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = Color(TYPE_COLORS[type], 1.0)
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var text := Label.new()
		text.add_theme_font_override("font", font)
		text.add_theme_font_size_override("font_size", 14)
		row.add_child(text)
		_legend_counts.append(text)
	_legend_status = Label.new()
	_legend_status.add_theme_font_override("font", font)
	_legend_status.add_theme_font_size_override("font_size", 14)
	legend.add_child(_legend_status)


func _update_legend() -> void:
	if _legend_status == null:
		return
	for type in Skeleton.SectorType.size():
		var is_hidden := type == Skeleton.SectorType.STRATUM and not show_stratum
		_legend_counts[type].text = "%-8s %4d%s" % [Skeleton.type_name(type), counts[type], " (hidden)" if is_hidden else ""]
	var side := 2 * radius + 1
	_legend_status.text = "sector %s  radius %d (%d sectors)  refresh %.2f ms" % [
		center, radius, side * side * side, last_refresh_usec / 1000.0,
	]
