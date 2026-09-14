class_name WorldWalker
extends Node3D
## The walkable world view: streams the sectors around the player (or the
## free-fly camera) through a `SectorStreamer` and puts a `Player` capsule
## into the first one that solved.
##
## On start (and after every seed change) it starts the `SectorStreamer` at
## `streamer` with the `SectorJobs` at `jobs`, the placeholder tileset and the
## world seed. Each frame it hands the streamer the focus: the camera while
## flying or before the spawn, the capsule's feet while walking. The streamer
## loads the sectors within `radius` of the focus sector, frees them beyond
## `radius` + 1, caches solved cells, places at most one sector per frame and
## adds its collision in chunks within a frame budget; solved sectors become
## SectorMultiMeshes (with `use_gridmap`, a debugging path kept while #139 is
## open, SectorGridMaps), failed or degraded ones translucent red boxes, and
## sectors not placed yet translucent boxes in their skeleton type's colour.
## See docs/algorithms/sector-streaming.md.
##
## The player at `player` is frozen until the first solved sector with
## records is placed; then, unless `free_fly` is on, its feet are put on that
## sector's hub cell (the interior node every walk of the sector meets at) and
## it starts walking. While the collision around its feet is not added yet
## (it walked faster than sectors load) the capsule holds still: its physics
## stops until the chunks are there, so it never falls through a sector that
## is still loading. F toggles `free_fly`: on, the capsule freezes and the
## camera flies with its own WASD, QE and Shift; off, the capsule is put at
## the camera (feet `eye_height` below it) and walks. V toggles first and
## third person. Both keys follow UiKeys.
##
## `--seed N` after `--` on the command line sets the world seed on start.
## The legend under the HUD label lists the sectors placed, failed, queued,
## running and cached, the streaming radius, pending unloads and collision
## and the streamer's frame time, the placement path with the frame's draw
## calls and the mean worker build time, the mode and the feet position.

const TILESET := "res://resources/tilesets/placeholder.tres"
const TOGGLE_FLY_KEYS: Array[Key] = [KEY_F]
const TOGGLE_VIEW_KEYS: Array[Key] = [KEY_V]

@export var camera: NodePath
@export var player: NodePath
@export var jobs: NodePath
## The SectorStreamer that places the sectors.
@export var streamer: NodePath
## Hud whose label the legend is attached to (optional).
@export var hud: NodePath
@export var tileset: TileSet3D
## Sectors within this Chebyshev distance of the focus sector are loaded:
## (2 radius + 1)³.
@export_range(0, SectorStreamer.MAX_RADIUS) var radius := 1:
	set(value):
		radius = clampi(value, 0, SectorStreamer.MAX_RADIUS)
		if _streamer != null:
			_streamer.radius = radius
## Solved sectors the streamer remembers.
@export_range(0, 4096) var cache_size := 256:
	set(value):
		cache_size = maxi(value, 0)
		if _streamer != null:
			_streamer.cache_size = cache_size
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
		if _streamer != null:
			_streamer.show_failed = show_failed
## Draw the impostor boxes of sectors not placed.
@export var show_impostors := true:
	set(value):
		show_impostors = value
		if _streamer != null:
			_streamer.show_impostors = show_impostors
## Place sectors as GridMaps instead of MultiMeshes, for debugging (#139);
## changing it streams again.
@export var use_gridmap := false:
	set(value):
		if value == use_gridmap:
			return
		use_gridmap = value
		if is_node_ready():
			reload()

var library: TileLibrary

var _camera: FreeFlyCamera
var _player: Player
var _jobs: SectorJobs
var _streamer: SectorStreamer
var _rasteriser: EdgeRasteriser
var _spawned := false
## The capsule is waiting for the collision around its feet.
var _holding := false
## `free_fly` as last applied.
var _flying := false
var _legend: Label
## Worker build time of the MultiMesh sectors placed since the last reload.
var _build_usec := 0
var _built := 0


func _ready() -> void:
	_camera = get_node_or_null(camera) as FreeFlyCamera
	_player = get_node_or_null(player) as Player
	_jobs = get_node_or_null(jobs) as SectorJobs
	_streamer = get_node_or_null(streamer) as SectorStreamer
	if tileset == null:
		tileset = load(TILESET) as TileSet3D
	library = TileLibrary.build(tileset)
	for error in library.errors:
		push_error("WorldWalker: %s" % error)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--seed")
	if at >= 0 and at + 1 < args.size() and args[at + 1].is_valid_int():
		WorldState.seed = int(args[at + 1])
	_build_legend()
	if _streamer != null:
		_streamer.radius = radius
		_streamer.cache_size = cache_size
		_streamer.show_failed = show_failed
		_streamer.show_impostors = show_impostors
		_streamer.sector_placed.connect(_on_sector_placed)
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
	if _streamer != null:
		var walking := _spawned and not free_fly and _player != null
		if walking:
			_streamer.focus_position = _player.global_position
			var hold := not _streamer.is_collision_ready_at(_player.global_position)
			if hold != _holding:
				_holding = hold
				_player.set_physics_process(not hold)
		elif _camera != null:
			_streamer.focus_position = _camera.global_position
	_update_legend()


## Frees every placed sector and streams again for the current seed.
func reload() -> void:
	_build_usec = 0
	_built = 0
	_spawned = false
	_rasteriser = EdgeRasteriser.new(WalkableGraph.new(WorldState.seed))
	if _jobs == null or _streamer == null or not library.errors.is_empty():
		return
	_streamer.use_gridmap = use_gridmap
	_streamer.start(_jobs, library, WorldState.seed)
	_apply_mode()


## Adds the walk settings to the tweak panel.
func register_params(registry: ParamRegistry) -> void:
	var body := get_node_or_null(player) as Player
	registry.add_script_params("walk", {
		"free_fly": {"value": free_fly, "default": false},
		"show_failed": {"value": show_failed, "default": true},
		"show_impostors": {"value": show_impostors, "default": true},
		"use_gridmap": {"value": use_gridmap, "default": false},
		"radius": {"value": radius, "default": 1, "min": 0, "max": SectorStreamer.MAX_RADIUS, "step": 1},
		"cache_size": {"value": cache_size, "default": 256, "min": 0, "max": 4096, "step": 1},
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


func _on_sector_placed(sector: Vector3i, result: Dictionary) -> void:
	if result.outcome != SectorSolver.Outcome.SOLVED:
		return
	var placement: Dictionary = result.placement
	if not placement.is_empty() and not result.get("cached", false):
		_build_usec += placement.build_usec
		_built += 1
	if not _spawned and _player != null and not _rasteriser.records_for_sector(sector).is_empty():
		_spawned = true
		var n := _rasteriser.graph.cells_per_sector()
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
	if _legend == null or not _legend.is_visible_in_tree() or _streamer == null:
		return
	var failed := 0
	var degraded := 0
	for outcome: int in _streamer.outcomes.values():
		if outcome == SectorSolver.Outcome.FAILED:
			failed += 1
		elif outcome == SectorSolver.Outcome.DEGRADED:
			degraded += 1
	var lines := PackedStringArray()
	lines.append("sectors  %d placed  %d failed  %d degraded  %d queued  %d running  %d cached" % [
		_streamer.placed.size() - failed - degraded, failed, degraded, _jobs.pending_count() if _jobs != null else 0,
		_jobs.running_sectors().size() if _jobs != null else 0, _streamer.cache_count(),
	])
	lines.append("stream   R %d  %d to place  %d to free  %d collision pending  update %.1f ms (max %.1f)" % [
		radius, _streamer.ready_count(), _streamer.unload_count(), _streamer.collision_pending_count(),
		_streamer.last_update_usec / 1000.0, _streamer.max_update_usec / 1000.0,
	])
	lines.append("placing  %s  %d draw calls%s" % [
		"GridMap" if use_gridmap else "MultiMesh", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"" if use_gridmap or _built == 0 else "  worker build %.0f ms per sector" % (_build_usec / 1000.0 / _built),
	])
	var mode := "free fly" if free_fly or not _spawned else "walk, %s person" % ("first" if _player.first_person else "third")
	if not _spawned and not free_fly:
		mode += " (waiting for a solved sector)"
	elif _holding and not free_fly:
		mode += " (holding: collision loading)"
	lines.append("mode     %s   F fly  V view  Space jump" % mode)
	if _player != null:
		var feet := _player.global_position
		lines.append("feet     %.1f, %.1f, %.1f%s" % [feet.x, feet.y, feet.z, "  on floor" if _player.is_on_floor() else ""])
	_legend.text = "\n".join(lines)
