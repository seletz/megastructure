class_name SkeletonViewer
extends Node3D
## Debug view of the skeleton: every sector within `radius` sectors of the
## camera drawn as a colour-coded box, one MultiMeshInstance3D per type.
##
## Boxes are inset (44 m of a 48 m sector) so neighbours stay apart. Shaft,
## cavity, chasm and stratum are unshaded and translucent without depth write;
## solid is opaque grey. Stratum is hidden by default because it is the
## majority and would hide everything else.
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
const TYPE_COLORS: Array[Color] = [
	Color(0.55, 0.62, 0.75, 0.12),
	Color(0.2, 0.75, 1.0, 0.35),
	Color(1.0, 0.6, 0.15, 0.35),
	Color(0.42, 0.42, 0.45, 1.0),
	Color(0.95, 0.2, 0.35, 0.35),
]

## FreeFlyCamera whose sector the region is centred on.
@export var camera: NodePath
## Hud whose label the legend is attached to (optional).
@export var hud: NodePath
## Region radius in sectors: (2 radius + 1)^3 sectors are drawn.
@export_range(0, MAX_RADIUS) var radius := 3:
	set(value):
		radius = clampi(value, 0, MAX_RADIUS)
		_dirty = true
@export var show_stratum := false:
	set(value):
		show_stratum = value
		_dirty = true
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
var _camera: FreeFlyCamera
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
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for type in Skeleton.SectorType.size():
		var instance := MultiMeshInstance3D.new()
		instance.name = Skeleton.type_name(type).capitalize()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = box
		instance.multimesh = multimesh
		instance.material_override = _material(TYPE_COLORS[type])
		add_child(instance)
		_instances.append(instance)
	_build_legend()
	WorldState.seed_changed.connect(func(_seed: int) -> void: invalidate_types())


func _process(_delta: float) -> void:
	if follow_camera and _camera != null:
		var cell := sector_of(_camera.global_position)
		if cell != center:
			center = cell
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

	var size := _sector_size()
	var box_size := maxf(size - BOX_MARGIN, size * 0.5)
	var origin := Vector3(center - Vector3i.ONE * radius) * size + Vector3.ONE * (size * 0.5)
	for type in Skeleton.SectorType.size():
		var multimesh := _instances[type].multimesh
		var count := counts[type] if type != Skeleton.SectorType.STRATUM or show_stratum else 0
		# MultiMesh.buffer holds 12 floats per instance: the basis rows with the
		# origin as the fourth column.
		var buffer := PackedFloat32Array()
		buffer.resize(count * 12)
		var offset := 0
		index = 0
		if count > 0:
			for x in side:
				for y in side:
					for z in side:
						if types[index] == type:
							buffer[offset] = box_size
							buffer[offset + 3] = origin.x + x * size
							buffer[offset + 5] = box_size
							buffer[offset + 7] = origin.y + y * size
							buffer[offset + 10] = box_size
							buffer[offset + 11] = origin.z + z * size
							offset += 12
						index += 1
		multimesh.instance_count = count
		if count > 0:
			multimesh.buffer = buffer
	last_refresh_usec = Time.get_ticks_usec() - start
	refresh_count += 1
	_update_legend()


## Adds the viewer's own settings and every SectorGrammar export to the panel.
func register_params(registry: ParamRegistry) -> void:
	if grammar == null:
		grammar = SectorGrammar.new()
	registry.add_script_params("viewer", {
		"radius": {"value": radius, "default": 3, "min": 0, "max": MAX_RADIUS, "step": 1},
		"show_stratum": {"value": show_stratum, "default": false},
		"follow_camera": {"value": follow_camera, "default": true},
	}, func(param_name: String, value: Variant) -> void: set(param_name, value))
	registry.add_object_exports(grammar, func(param_name: String, value: Variant) -> void:
		grammar.set(param_name, value)
		if param_name == "sector_size":
			_dirty = true
		else:
			invalidate_types()
	, "grammar")


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


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
