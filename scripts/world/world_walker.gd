class_name WorldWalker
extends Node3D
## The walkable world view: solves the sectors around the origin on worker
## threads, places each as a `SectorMultiMesh` as its result arrives, and
## puts a `Player` capsule into the first one that solved.
##
## On start (and after every seed change) it configures the `SectorJobs` at
## `jobs` with the placeholder tileset and the world seed and requests the
## (2 `block_radius` + 1)³ sectors around sector (0, 0, 0), nearest first.
## The jobs build the MultiMesh buffers and collision faces on their worker
## threads; each `sector_ready` result that SOLVED becomes a SectorMultiMesh
## child of `sectors`, offset to `sector * 48` m, or with `use_gridmap` (a
## debugging path kept while #139 is open) a SectorGridMap; a FAILED or DEGRADED sector gets a
## translucent red box filling its 48 m instead, so the gap is visible (a
## degraded result is all solid and would hide it).
##
## The player at `player` is frozen until the first solved sector with
## records arrives; then, unless `free_fly` is on, its feet are put on that
## sector's hub cell (the interior node every walk of the sector meets at) and
## it starts walking. F toggles `free_fly`: on, the capsule freezes and the
## camera flies with its own WASD, QE and Shift; off, the capsule is put at
## the camera (feet `eye_height` below it) and walks. V toggles first and
## third person. Both keys follow UiKeys.
##
## `--seed N` after `--` on the command line sets the world seed on start.
## The legend under the HUD label lists the sectors placed, failed, queued
## and running, the placement path with the frame's draw calls and the mean
## worker build time, the mode and the feet position.

const TILESET := "res://resources/tilesets/placeholder.tres"
const MAX_BLOCK_RADIUS := 2
const FAILED_COLOUR := Color(0.95, 0.15, 0.1, 0.18)
## Failed boxes are inset this much from the sector edge, in metres.
const FAILED_INSET := 0.5
const TOGGLE_FLY_KEYS: Array[Key] = [KEY_F]
const TOGGLE_VIEW_KEYS: Array[Key] = [KEY_V]

@export var camera: NodePath
@export var player: NodePath
@export var jobs: NodePath
## Parent of the placed sectors and failure boxes.
@export var sectors: NodePath
## Hud whose label the legend is attached to (optional).
@export var hud: NodePath
@export var tileset: TileSet3D
## Sectors requested around the origin: (2 block_radius + 1)³.
@export_range(0, MAX_BLOCK_RADIUS) var block_radius := 1:
	set(value):
		block_radius = clampi(value, 0, MAX_BLOCK_RADIUS)
		if is_node_ready():
			reload()
## Camera flies freely and the capsule is frozen.
@export var free_fly := false:
	set(value):
		free_fly = value
		if is_node_ready():
			_apply_mode()
## Draw failed and degraded sectors as red boxes.
@export var show_failed := true:
	set(value):
		show_failed = value
		for box: Node3D in _failed.values():
			box.visible = show_failed
## Place sectors as GridMaps instead of MultiMeshes, for debugging (#139);
## changing it places the block again.
@export var use_gridmap := false:
	set(value):
		if value == use_gridmap:
			return
		use_gridmap = value
		if is_node_ready():
			reload()

var library: TileLibrary
var mesh_library: MeshLibrary
## `SectorMultiMesh.build_meshes` of `library`, by prototype index.
var meshes: Array[Mesh] = []
## Sector -> SectorMultiMesh or SectorGridMap of the solved sectors placed.
var placed := {}
## Sector -> outcome name of every result received since the last reload.
var outcomes := {}

var _camera: FreeFlyCamera
var _player: Player
var _jobs: SectorJobs
var _sectors: Node3D
var _rasteriser: EdgeRasteriser
## Sector -> red box of the failed and degraded sectors.
var _failed := {}
var _spawned := false
## `free_fly` as last applied.
var _flying := false
var _box_mesh: BoxMesh
var _legend: Label
## Worker build time of the MultiMesh sectors placed since the last reload.
var _build_usec := 0
var _built := 0


func _ready() -> void:
	_camera = get_node_or_null(camera) as FreeFlyCamera
	_player = get_node_or_null(player) as Player
	_jobs = get_node_or_null(jobs) as SectorJobs
	_sectors = get_node_or_null(sectors) as Node3D
	if _sectors == null:
		_sectors = self
	if tileset == null:
		tileset = load(TILESET) as TileSet3D
	library = TileLibrary.build(tileset)
	for error in library.errors:
		push_error("WorldWalker: %s" % error)
	mesh_library = SectorGridMap.build_mesh_library(library)
	meshes = SectorMultiMesh.build_meshes(library)
	_box_mesh = BoxMesh.new()
	_box_mesh.material = _failed_material()
	var args := OS.get_cmdline_user_args()
	var at := args.find("--seed")
	if at >= 0 and at + 1 < args.size() and args[at + 1].is_valid_int():
		WorldState.seed = int(args[at + 1])
	_build_legend()
	if _jobs != null:
		_jobs.sector_ready.connect(_on_sector_ready)
	WorldState.seed_changed.connect(func(_seed: int) -> void: reload())
	reload()


func _unhandled_input(event: InputEvent) -> void:
	if UiKeys.text_field_focused(get_viewport()):
		return
	if UiKeys.is_shortcut(event, TOGGLE_FLY_KEYS):
		free_fly = not free_fly
		get_viewport().set_input_as_handled()
	elif UiKeys.is_shortcut(event, TOGGLE_VIEW_KEYS) and _player != null:
		_player.first_person = not _player.first_person
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_update_legend()


## Removes every placed sector and box and requests the block again for the
## current seed.
func reload() -> void:
	for child: Node in placed.values() + _failed.values():
		child.queue_free()
	placed.clear()
	_failed.clear()
	outcomes.clear()
	_build_usec = 0
	_built = 0
	_spawned = false
	_rasteriser = EdgeRasteriser.new(WalkableGraph.new(WorldState.seed))
	_box_mesh.size = Vector3.ONE * (_rasteriser.graph.cells_per_sector() * WalkableGraph.CELL_SIZE - 2.0 * FAILED_INSET)
	if _jobs == null or not library.errors.is_empty():
		return
	_jobs.configure(library, WorldState.seed)
	_jobs.build_placement = not use_gridmap
	_jobs.focus = Vector3i.ZERO
	for x in range(-block_radius, block_radius + 1):
		for y in range(-block_radius, block_radius + 1):
			for z in range(-block_radius, block_radius + 1):
				_jobs.request(Vector3i(x, y, z))
	_apply_mode()


## Adds the walk settings to the tweak panel.
func register_params(registry: ParamRegistry) -> void:
	var body := get_node_or_null(player) as Player
	registry.add_script_params("walk", {
		"free_fly": {"value": free_fly, "default": false},
		"show_failed": {"value": show_failed, "default": true},
		"use_gridmap": {"value": use_gridmap, "default": false},
		"block_radius": {"value": block_radius, "default": 1, "min": 0, "max": MAX_BLOCK_RADIUS, "step": 1},
	}, func(param_name: String, value: Variant) -> void: set(param_name, value))
	if body != null:
		registry.add_script_params("player", {
			"first_person": {"value": body.first_person, "default": true},
			"walk_speed": {"value": body.walk_speed, "default": 4.0, "min": 0.5, "max": 20.0, "step": 0.5},
			"run_speed": {"value": body.run_speed, "default": 8.0, "min": 0.5, "max": 40.0, "step": 0.5},
			"jump_velocity": {"value": body.jump_velocity, "default": 4.5, "min": 0.0, "max": 20.0, "step": 0.1},
			"step_height": {"value": body.step_height, "default": 0.65, "min": 0.0, "max": 1.2, "step": 0.05},
			"third_person_distance": {"value": body.third_person_distance, "default": 4.0, "min": 1.0, "max": 20.0, "step": 0.5},
		}, func(param_name: String, value: Variant) -> void: body.set(param_name, value))


func _on_sector_ready(result: Dictionary) -> void:
	var sector: Vector3i = result.sector
	var outcome: int = result.outcome
	outcomes[sector] = SectorSolver.OUTCOME_NAMES[outcome]
	var n := _rasteriser.graph.cells_per_sector()
	if outcome != SectorSolver.Outcome.SOLVED:
		var box := MeshInstance3D.new()
		box.name = "Failed_%d_%d_%d" % [sector.x, sector.y, sector.z]
		box.mesh = _box_mesh
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		box.position = SectorGridMap.sector_origin(sector, n) + Vector3.ONE * n * WalkableGraph.CELL_SIZE * 0.5
		box.visible = show_failed
		_sectors.add_child(box)
		_failed[sector] = box
		return
	var node_name := "Sector_%d_%d_%d" % [sector.x, sector.y, sector.z]
	if use_gridmap:
		var grid := SectorGridMap.new()
		grid.name = node_name
		grid.mesh_library = mesh_library
		_sectors.add_child(grid)
		grid.place(library, sector, result.cells)
		placed[sector] = grid
	else:
		var placement: Dictionary = result.placement
		if placement.is_empty():
			# A job started without build_placement; build it here.
			placement = SectorMultiMesh.build(library, _jobs.faces(), result.cells)
		_build_usec += placement.build_usec
		_built += 1
		var node := SectorMultiMesh.new()
		node.name = node_name
		_sectors.add_child(node)
		node.place(meshes, sector, placement)
		placed[sector] = node
	if not _spawned and _player != null and not _rasteriser.records_for_sector(sector).is_empty():
		_spawned = true
		_player.teleport(SectorGridMap.cell_centre(sector, _rasteriser.hub_cell(sector), n) + Vector3.DOWN * (WalkableGraph.CELL_SIZE * 0.5 - 0.6))
		_apply_mode()


## Freezes or releases the capsule for the current `free_fly` and spawn
## state. Leaving free flight drops the capsule at the camera.
func _apply_mode() -> void:
	if _player == null:
		return
	var walk := not free_fly and _spawned
	if walk and _flying and _camera != null:
		_player.teleport(_camera.global_position + Vector3.DOWN * _player.eye_height)
	_flying = free_fly
	_player.walking = walk


func _failed_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = FAILED_COLOUR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_legend() -> void:
	var hud_node := get_node_or_null(hud) as Hud
	if hud_node == null:
		return
	var label := hud_node.get_node("Label") as Label
	_legend = Label.new()
	_legend.name = "Legend"
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.anchor_top = 1.0
	_legend.anchor_bottom = 1.0
	_legend.offset_top = 8.0
	_legend.add_theme_font_override("font", label.get_theme_font("font"))
	_legend.add_theme_font_size_override("font_size", 14)
	label.add_child(_legend)


func _update_legend() -> void:
	if _legend == null or not _legend.is_visible_in_tree():
		return
	var failed := 0
	var degraded := 0
	for outcome: String in outcomes.values():
		if outcome == "failed":
			failed += 1
		elif outcome == "degraded":
			degraded += 1
	var lines := PackedStringArray()
	lines.append("sectors  %d placed  %d failed  %d degraded  %d queued  %d running" % [
		placed.size(), failed, degraded, _jobs.pending_count() if _jobs != null else 0, _jobs.running_sectors().size() if _jobs != null else 0,
	])
	lines.append("placing  %s  %d draw calls%s" % [
		"GridMap" if use_gridmap else "MultiMesh", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"" if use_gridmap or _built == 0 else "  worker build %.0f ms per sector" % (_build_usec / 1000.0 / _built),
	])
	var mode := "free fly" if free_fly or not _spawned else "walk, %s person" % ("first" if _player.first_person else "third")
	if not _spawned and not free_fly:
		mode += " (waiting for a solved sector)"
	lines.append("mode     %s   F fly  V view  Space jump" % mode)
	if _player != null:
		var feet := _player.global_position
		lines.append("feet     %.1f, %.1f, %.1f%s" % [feet.x, feet.y, feet.z, "  on floor" if _player.is_on_floor() else ""])
	_legend.text = "\n".join(lines)
