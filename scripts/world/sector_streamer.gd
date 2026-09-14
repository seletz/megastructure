class_name SectorStreamer
extends Node3D
## Keeps the sectors around a moving focus loaded: solves them through a
## `SectorJobs`, places them a frame budget at a time, frees them again, and
## remembers solved cells so a sector walked back into is placed without
## solving.
##
##     var streamer := SectorStreamer.new()
##     add_child(streamer)
##     streamer.start(jobs, library, seed)       # both inside the tree
##     streamer.focus_position = player.global_position   # every frame
##
## Rules (docs/algorithms/sector-streaming.md):
##
## - **Load** every sector within `radius` of the focus sector (Chebyshev
##   distance in sector units, the sector `focus_position` lies in): request
##   it from the jobs, nearest first, or take it from the cache.
## - **Unload** a placed sector once it is more than `radius` + 1 away: the
##   ring between is the hysteresis, so walking along a boundary never loads
##   and frees the same sectors over and over. Queued and running jobs beyond
##   `radius` + 1 are cancelled, results arriving for such sectors dropped.
## - **Cache**: an LRU of the last `cache_size` results by sector, holding
##   the outcome and the solved cells, not the placement data (a sector's
##   collision faces are about 11 MB; its cells 55 KB). A cached SOLVED sector
##   is requested with its cells, so its task only builds the placement data;
##   a cached FAILED or DEGRADED sector gets its box at once.
## - **Frame budget**: `update` (from `_process`) frees at most one sector,
##   places at most one ready result, nearest first, adds collision chunks
##   and makes impostor boxes, each step only while the frame's work is
##   under `frame_budget_usec`; an item started under budget finishes.
## - **Collision** per decision #175: placement data comes with its collision
##   in chunks of `collision_chunk_cells`³ cells, each added as a shape of one
##   of the sector's 8 bodies by `SectorMultiMesh.add_collision_chunk`. The
##   27 chunks around the focus come first, whatever their sector, then the
##   nearest sector's chunks, nearest first.
## - **Impostors**: every sector within `radius` + 1 has a translucent box in
##   its skeleton type's colour (`SkeletonViewer.TYPE_COLORS`), so the world
##   does not end at the last placed sector. A box of a sector not placed yet
##   hides only when the camera is inside it (`visibility_range_begin`); a
##   placed sector's MultiMeshes use its box as `visibility_parent`, so beyond
##   `impostor_distance` the box replaces the tiles.
##
## Unloading is free of state: a sector is a pure function of the seed and its
## coordinates, so one loaded again, from the cache or solved anew, is the same.

## Emitted after a result was placed: a SectorMultiMesh, SectorGridMap or
## failure box is in `placed`.
signal sector_placed(sector: Vector3i, result: Dictionary)
## Emitted after a sector's node and bodies were freed.
signal sector_unloaded(sector: Vector3i)

const MAX_RADIUS := 3
const FAILED_COLOUR := Color(0.95, 0.15, 0.1, 0.18)
## Failure boxes are inset this much from the sector edge, in metres.
const FAILED_INSET := 0.5
## Impostor boxes are inset this much, in metres.
const IMPOSTOR_INSET := 2.0
## Chebyshev offsets of the 27 chunks around the focus chunk.
const NEAR_CHUNKS := 1

## Sectors within this Chebyshev distance of the focus sector are loaded.
@export_range(0, MAX_RADIUS) var radius := 1:
	set(value):
		radius = clampi(value, 0, MAX_RADIUS)
		_refresh_pending = true
## Most results kept in the LRU cache.
@export_range(0, 4096) var cache_size := 256:
	set(value):
		cache_size = maxi(value, 0)
		_trim_cache()
## Main-thread work per `update`, in microseconds.
@export_range(1000, 33000) var frame_budget_usec := 6000
## Cells per collision chunk edge; applies from the next `start`.
@export_range(1, 24) var collision_chunk_cells := 3
## Draw the impostor boxes.
@export var show_impostors := true:
	set(value):
		show_impostors = value
		for box: MeshInstance3D in _impostors.values():
			box.transparency = 0.0 if show_impostors else 1.0
## Draw failed and degraded sectors as red boxes.
@export var show_failed := true:
	set(value):
		show_failed = value
		for sector: Vector3i in placed:
			if outcomes.get(sector, SectorSolver.Outcome.SOLVED) != SectorSolver.Outcome.SOLVED:
				(placed[sector] as Node3D).visible = show_failed
## Place GridMaps instead of MultiMeshes (debugging, #139); their collision
## is built in one piece when placed. Applies from the next `start`.
var use_gridmap := false
## World position the loaded sectors follow.
var focus_position := Vector3.ZERO

var jobs: SectorJobs
var library: TileLibrary
var world_seed := 0
## `SectorMultiMesh.build_meshes` of `library`.
var meshes: Array[Mesh] = []
var mesh_library: MeshLibrary
## Sector -> SectorMultiMesh, SectorGridMap or failure box of every placed sector.
var placed := {}
## Sector -> `SectorSolver.Outcome` of every placed sector.
var outcomes := {}
## The focus sector of the last refresh.
var focus_sector := Vector3i.ZERO
## Counters since `start`.
var solved_count := 0
var cache_hits := 0
var placed_count := 0
var unloaded_count := 0
var chunks_added_count := 0
## Main-thread time of the last `update` and the longest since `start`, in
## microseconds.
var last_update_usec := 0
var max_update_usec := 0
## Longest single placement (MultiMesh nodes or GridMap) since `start`.
var max_place_usec := 0
## Longest single unload since `start`.
var max_unload_usec := 0
## Longest refresh of the wanted set (focus sector changes) since `start`.
var max_refresh_usec := 0
## What the last `update` did: refresh time (0 without one), sectors freed,
## sectors placed and collision chunks added.
var last_refresh_usec := 0
var last_unloads := 0
var last_places := 0
var last_chunks := 0

var _skeleton := Skeleton.new(SectorGrammar.new())
var _cells_per_sector := 24
var _sector_size := 48.0
var _started := false
var _refresh_pending := true
## `radius` at the last refresh.
var _refreshed_radius := -1
## Sector -> true for sectors requested from the jobs and not yet returned.
var _requested := {}
## Sector -> result received and waiting to be placed.
var _results_ready := {}
## Sectors waiting to be freed, in the order they left the hysteresis ring.
var _unload: Array[Vector3i] = []
## Sector -> impostor box.
var _impostors := {}
## Sectors whose impostor box is still to be made, nearest last.
var _impostors_to_add: Array[Vector3i] = []
## Sector -> {outcome, cells, degraded, error}; insertion order is recency.
var _cache := {}
## Sector -> PackedInt32Array of chunk indices, nearest to the focus at
## placement first, and the position of the next one to try.
var _chunk_order := {}
var _chunk_cursor := {}
## Chunk shapes of unloaded sectors still to free, whose bodies are gone.
var _shapes_to_free: Array[RID] = []
var _failed_mesh: BoxMesh
var _impostor_meshes: Array[BoxMesh] = []


func _process(_delta: float) -> void:
	if _started:
		update()


func _exit_tree() -> void:
	clear()


## Frees everything, then streams around `focus_position` with `jobs`
## configured for `tile_library` and `seed`.
func start(sector_jobs: SectorJobs, tile_library: TileLibrary, seed: int) -> void:
	clear()
	if jobs != null and jobs != sector_jobs and jobs.sector_ready.is_connected(_on_sector_ready):
		jobs.sector_ready.disconnect(_on_sector_ready)
	jobs = sector_jobs
	library = tile_library
	world_seed = seed
	_cells_per_sector = WalkableGraph.new(seed).cells_per_sector()
	_sector_size = _cells_per_sector * WalkableGraph.CELL_SIZE
	if _failed_mesh == null:
		_failed_mesh = BoxMesh.new()
		_failed_mesh.material = _translucent_material(FAILED_COLOUR)
		for type in Skeleton.SectorType.size():
			var mesh := BoxMesh.new()
			mesh.material = _translucent_material(SkeletonViewer.TYPE_COLORS[type])
			_impostor_meshes.append(mesh)
	if meshes.is_empty():
		meshes = SectorMultiMesh.build_meshes(library)
	if use_gridmap and mesh_library == null:
		mesh_library = SectorGridMap.build_mesh_library(library)
	_failed_mesh.size = Vector3.ONE * (_sector_size - 2.0 * FAILED_INSET)
	for mesh in _impostor_meshes:
		mesh.size = Vector3.ONE * (_sector_size - 2.0 * IMPOSTOR_INSET)
	jobs.configure(library, seed)
	jobs.build_placement = not use_gridmap
	jobs.collision_chunk_cells = collision_chunk_cells
	if not jobs.sector_ready.is_connected(_on_sector_ready):
		jobs.sector_ready.connect(_on_sector_ready)
	solved_count = 0
	cache_hits = 0
	placed_count = 0
	unloaded_count = 0
	chunks_added_count = 0
	max_update_usec = 0
	max_place_usec = 0
	max_unload_usec = 0
	max_refresh_usec = 0
	_started = true
	_refresh_pending = true


## Frees every placed sector, impostor and cached result and cancels the jobs.
## `start` streams again.
func clear() -> void:
	if jobs != null and jobs.is_inside_tree():
		jobs.clear()
	for sector: Vector3i in placed.keys():
		_free_sector(sector)
	for box: Node in _impostors.values():
		box.queue_free()
	_impostors.clear()
	_impostors_to_add.clear()
	_refreshed_radius = -1
	_requested.clear()
	_results_ready.clear()
	_unload.clear()
	for shape in _shapes_to_free:
		PhysicsServer3D.free_rid(shape)
	_shapes_to_free.clear()
	_cache.clear()
	_started = false


## Refreshes the wanted set when the focus sector or `radius` changed, then
## frees, places and adds collision within the frame budget.
func update() -> void:
	var started := Time.get_ticks_usec()
	var sector := sector_of(focus_position)
	last_refresh_usec = 0
	last_unloads = unloaded_count
	last_places = placed_count
	last_chunks = chunks_added_count
	if sector != focus_sector or _refresh_pending:
		focus_sector = sector
		_refresh_pending = false
		_refresh()
		last_refresh_usec = Time.get_ticks_usec() - started
		max_refresh_usec = maxi(max_refresh_usec, last_refresh_usec)
	_unload_within_budget(started)
	_place_nearest(started)
	_add_collision_within_budget(started)
	_add_impostors_within_budget(started)
	last_update_usec = Time.get_ticks_usec() - started
	max_update_usec = maxi(max_update_usec, last_update_usec)
	last_unloads = unloaded_count - last_unloads
	last_places = placed_count - last_places
	last_chunks = chunks_added_count - last_chunks


## The sector `position` lies in.
func sector_of(position: Vector3) -> Vector3i:
	return Vector3i((position / _sector_size).floor())


## Chebyshev distance between two sectors.
static func distance(a: Vector3i, b: Vector3i) -> int:
	var d := (a - b).abs()
	return maxi(d.x, maxi(d.y, d.z))


## Whether `sector` is placed (solved, or failed with its box).
func is_loaded(sector: Vector3i) -> bool:
	return placed.has(sector)


## Whether the collision around `position` is there: every one of the 27
## chunks around it belongs to a placed sector and has its body, or has no
## triangles, or its sector has no collision to add (failed, degraded).
func is_collision_ready_at(position: Vector3) -> bool:
	var chunk_size := collision_chunk_cells * WalkableGraph.CELL_SIZE
	for dz in range(-NEAR_CHUNKS, NEAR_CHUNKS + 1):
		for dy in range(-NEAR_CHUNKS, NEAR_CHUNKS + 1):
			for dx in range(-NEAR_CHUNKS, NEAR_CHUNKS + 1):
				var at := position + Vector3(dx, dy, dz) * chunk_size
				var sector := sector_of(at)
				if not placed.has(sector):
					return false
				var node := placed[sector] as SectorMultiMesh
				if node != null and not node.is_chunk_ready(_chunk_at(node, at)):
					return false
	return true


## Sectors requested from the jobs and not returned yet.
func requested_count() -> int:
	return _requested.size()


## Results waiting to be placed.
func ready_count() -> int:
	return _results_ready.size()


func unload_count() -> int:
	return _unload.size()


## Chunk shapes of unloaded sectors not freed yet.
func shapes_to_free_count() -> int:
	return _shapes_to_free.size()


func cache_count() -> int:
	return _cache.size()


func impostor_count() -> int:
	return _impostors.size()


## Placed MultiMesh sectors whose collision chunks are not all added.
func collision_pending_count() -> int:
	return _chunk_order.size()


## True when the focus sector is refreshed and every sector within `radius`
## is placed: nothing is requested, waiting to be placed or waiting to be
## freed. Collision chunks may still be missing.
func is_loading_done() -> bool:
	if not _started or _refresh_pending or sector_of(focus_position) != focus_sector:
		return false
	return _requested.is_empty() and _results_ready.is_empty() and _unload.is_empty()


## `is_loading_done`, all collision added and every freed sector's shapes freed.
func is_settled() -> bool:
	return is_loading_done() and _chunk_order.is_empty() and _shapes_to_free.is_empty()


## The cached entry of `sector` (outcome, cells, degraded, error), or empty.
func cached(sector: Vector3i) -> Dictionary:
	return _cache.get(sector, {})


func _refresh() -> void:
	jobs.focus = focus_sector
	var keep := radius + 1
	if radius != _refreshed_radius:
		_refreshed_radius = radius
		for sector: Vector3i in placed:
			_link_impostor(sector)
	for sector: Vector3i in _requested.keys():
		if distance(sector, focus_sector) > keep:
			jobs.cancel(sector)
			_requested.erase(sector)
	for sector: Vector3i in _results_ready.keys():
		if distance(sector, focus_sector) > keep:
			_results_ready.erase(sector)
	for sector: Vector3i in placed:
		if distance(sector, focus_sector) > keep and not _unload.has(sector):
			_unload.append(sector)
	for sector: Vector3i in _impostors.keys():
		if distance(sector, focus_sector) > keep and not placed.has(sector):
			(_impostors[sector] as Node).queue_free()
			_impostors.erase(sector)
	_impostors_to_add.clear()
	for z in range(-keep, keep + 1):
		for y in range(-keep, keep + 1):
			for x in range(-keep, keep + 1):
				var sector := focus_sector + Vector3i(x, y, z)
				if not _impostors.has(sector):
					_impostors_to_add.append(sector)
				if distance(sector, focus_sector) <= radius:
					_want(sector)
	# Made from the back, so nearest first.
	_impostors_to_add.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return (a - focus_sector).length_squared() > (b - focus_sector).length_squared())


## Requests `sector` unless it is placed, requested or ready; a cache hit
## skips the solve.
func _want(sector: Vector3i) -> void:
	if placed.has(sector) or _requested.has(sector) or _results_ready.has(sector):
		return
	var entry: Dictionary = _cache.get(sector, {})
	if entry.is_empty():
		if jobs.request(sector):
			_requested[sector] = true
		return
	_touch(sector)
	cache_hits += 1
	if entry.outcome != SectorSolver.Outcome.SOLVED or use_gridmap:
		_results_ready[sector] = {
			"sector": sector, "outcome": entry.outcome, "cells": entry.cells, "degraded": entry.degraded,
			"error": entry.error, "cancelled": false, "cached": true, "placement": {},
		}
	elif jobs.request(sector, entry.cells):
		_requested[sector] = true


func _on_sector_ready(result: Dictionary) -> void:
	var sector: Vector3i = result.sector
	if not _requested.has(sector):
		return
	_requested.erase(sector)
	if not result.get("cached", false):
		solved_count += 1
		_remember(sector, result)
	if distance(sector, focus_sector) > radius + 1:
		return
	_results_ready[sector] = result


## Frees queued chunk shapes for a quarter of the budget, then at most one
## queued unload while under budget: its nodes are deleted at the end of the
## frame, outside this measurement. A sector back within the hysteresis ring
## stays.
func _unload_within_budget(started: int) -> void:
	while not _shapes_to_free.is_empty() and Time.get_ticks_usec() - started < frame_budget_usec / 4:
		PhysicsServer3D.free_rid(_shapes_to_free.pop_back())
	while not _unload.is_empty():
		if Time.get_ticks_usec() - started > frame_budget_usec:
			return
		var sector: Vector3i = _unload.pop_front()
		if not placed.has(sector) or distance(sector, focus_sector) <= radius + 1:
			continue
		var begun := Time.get_ticks_usec()
		_free_sector(sector)
		if _impostors.has(sector):
			(_impostors[sector] as Node).queue_free()
			_impostors.erase(sector)
		unloaded_count += 1
		max_unload_usec = maxi(max_unload_usec, Time.get_ticks_usec() - begun)
		sector_unloaded.emit(sector)
		return


func _free_sector(sector: Vector3i) -> void:
	var node: Node3D = placed[sector]
	placed.erase(sector)
	outcomes.erase(sector)
	_chunk_order.erase(sector)
	_chunk_cursor.erase(sector)
	if node is SectorMultiMesh:
		_shapes_to_free.append_array((node as SectorMultiMesh).release_collision())
	node.queue_free()


## Places the ready result nearest to the focus, if the frame has budget left.
func _place_nearest(started: int) -> void:
	if _results_ready.is_empty() or Time.get_ticks_usec() - started > frame_budget_usec:
		return
	var best := Vector3i.ZERO
	var best_distance := -1
	for sector: Vector3i in _results_ready:
		var d := (sector - focus_sector).length_squared()
		if best_distance < 0 or d < best_distance:
			best = sector
			best_distance = d
	var result: Dictionary = _results_ready[best]
	_results_ready.erase(best)
	var begun := Time.get_ticks_usec()
	_place(best, result)
	max_place_usec = maxi(max_place_usec, Time.get_ticks_usec() - begun)
	placed_count += 1
	sector_placed.emit(best, result)


func _place(sector: Vector3i, result: Dictionary) -> void:
	var outcome: int = result.outcome
	outcomes[sector] = outcome
	var origin := SectorGridMap.sector_origin(sector, _cells_per_sector)
	if outcome != SectorSolver.Outcome.SOLVED:
		var box := MeshInstance3D.new()
		box.name = "Failed_%d_%d_%d" % [sector.x, sector.y, sector.z]
		box.mesh = _failed_mesh
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		box.position = origin + Vector3.ONE * _sector_size * 0.5
		box.visible = show_failed
		add_child(box)
		placed[sector] = box
		_link_impostor(sector)
		return
	var node_name := "Sector_%d_%d_%d" % [sector.x, sector.y, sector.z]
	if use_gridmap:
		var grid := SectorGridMap.new()
		grid.name = node_name
		grid.mesh_library = mesh_library
		add_child(grid)
		grid.place(library, sector, result.cells)
		placed[sector] = grid
		_link_impostor(sector)
		return
	var placement: Dictionary = result.placement
	if placement.is_empty():
		# A job started without build_placement; build it here.
		placement = SectorMultiMesh.build(library, jobs.faces(), result.cells, collision_chunk_cells)
	var node := SectorMultiMesh.new()
	node.name = node_name
	add_child(node)
	node.place(meshes, sector, placement)
	placed[sector] = node
	_link_impostor(sector)
	if not node.is_collision_complete():
		_chunk_order[sector] = _chunks_by_distance(node)
		_chunk_cursor[sector] = 0


## Beyond this distance from the camera, in metres, a placed sector's
## impostor replaces its tiles: the farthest a sector within `radius` can be
## from a camera inside the focus sector, measured to its centre, plus a
## quarter sector.
func impostor_distance() -> float:
	return (radius + 0.5) * _sector_size * sqrt(3.0) + _sector_size * 0.25


## Adds the chunks around the focus first, then the nearest incomplete
## sector's chunks in their order: one when the frame is under budget, more
## while it still is.
func _add_collision_within_budget(started: int) -> void:
	if _chunk_order.is_empty() or Time.get_ticks_usec() - started > frame_budget_usec:
		return
	var added := false
	var chunk_size := collision_chunk_cells * WalkableGraph.CELL_SIZE
	for dz in range(-NEAR_CHUNKS, NEAR_CHUNKS + 1):
		for dy in range(-NEAR_CHUNKS, NEAR_CHUNKS + 1):
			for dx in range(-NEAR_CHUNKS, NEAR_CHUNKS + 1):
				if added and Time.get_ticks_usec() - started > frame_budget_usec:
					return
				var at := focus_position + Vector3(dx, dy, dz) * chunk_size
				var node := placed.get(sector_of(at)) as SectorMultiMesh
				if node != null and node.add_collision_chunk(_chunk_at(node, at)):
					added = true
					chunks_added_count += 1
					_finish_collision(node.sector)
	while not _chunk_order.is_empty():
		if added and Time.get_ticks_usec() - started > frame_budget_usec:
			return
		var sector := _nearest_incomplete()
		var node := placed[sector] as SectorMultiMesh
		var order: PackedInt32Array = _chunk_order[sector]
		var cursor: int = _chunk_cursor[sector]
		while cursor < order.size() and not node.add_collision_chunk(order[cursor]):
			cursor += 1
		if cursor < order.size():
			added = true
			chunks_added_count += 1
			cursor += 1
		_chunk_cursor[sector] = cursor
		_finish_collision(sector)
		if cursor >= order.size():
			_chunk_order.erase(sector)
			_chunk_cursor.erase(sector)


func _finish_collision(sector: Vector3i) -> void:
	var node := placed.get(sector) as SectorMultiMesh
	if node != null and node.is_collision_complete():
		_chunk_order.erase(sector)
		_chunk_cursor.erase(sector)


func _nearest_incomplete() -> Vector3i:
	var best := Vector3i.ZERO
	var best_distance := INF
	for sector: Vector3i in _chunk_order:
		var origin := SectorGridMap.sector_origin(sector, _cells_per_sector)
		var box := AABB(origin, Vector3.ONE * _sector_size)
		var nearest := focus_position.clamp(box.position, box.end)
		var d := nearest.distance_squared_to(focus_position)
		if d < best_distance:
			best = sector
			best_distance = d
	return best


## Chunk index of `node` at world position `at` (clamped into the sector).
func _chunk_at(node: SectorMultiMesh, at: Vector3) -> int:
	var cell := Vector3i(((at - node.global_position) / WalkableGraph.CELL_SIZE).floor()).clamp(Vector3i.ZERO, Vector3i.ONE * (_cells_per_sector - 1))
	return SectorMultiMesh.chunk_index(cell, _cells_per_sector, node.chunk_cells)


## The chunk indices of `node` with triangles, nearest to the focus first:
## squared distance in whole metres above 16 bits of index, sorted natively.
func _chunks_by_distance(node: SectorMultiMesh) -> PackedInt32Array:
	var keys := PackedInt64Array()
	var local := focus_position - node.global_position
	var k := SectorMultiMesh.chunks_per_axis(_cells_per_sector, node.chunk_cells)
	var edge := node.chunk_cells * WalkableGraph.CELL_SIZE
	var faces := node.chunk_faces
	var index := 0
	for cz in k:
		var dz := (cz + 0.5) * edge - local.z
		for cy in k:
			var dy := (cy + 0.5) * edge - local.y
			for cx in k:
				if not (faces[index] as PackedVector3Array).is_empty():
					var dx := (cx + 0.5) * edge - local.x
					keys.append((int(dx * dx + dy * dy + dz * dz) << 16) | index)
				index += 1
	keys.sort()
	var order := PackedInt32Array()
	order.resize(keys.size())
	for i in keys.size():
		order[i] = keys[i] & 0xFFFF
	return order


## Makes queued impostor boxes while under budget.
func _add_impostors_within_budget(started: int) -> void:
	while not _impostors_to_add.is_empty() and Time.get_ticks_usec() - started < frame_budget_usec:
		var sector: Vector3i = _impostors_to_add.pop_back()
		if not _impostors.has(sector) and distance(sector, focus_sector) <= radius + 1:
			_add_impostor(sector)


func _add_impostor(sector: Vector3i) -> void:
	var box := MeshInstance3D.new()
	box.name = "Impostor_%d_%d_%d" % [sector.x, sector.y, sector.z]
	box.mesh = _impostor_meshes[_skeleton.sector_type(world_seed, sector)]
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.position = SectorGridMap.sector_origin(sector, _cells_per_sector) + Vector3.ONE * _sector_size * 0.5
	# Hidden while the camera is inside the box, so it never fills the view.
	box.visibility_range_begin = _sector_size * sqrt(3.0) * 0.5
	box.transparency = 0.0 if show_impostors else 1.0
	add_child(box)
	_impostors[sector] = box
	_link_impostor(sector)


## Ties a placed sector to its impostor box, whichever came first: a failed
## or GridMap sector hides the box; a MultiMesh sector's instances take the
## box as visibility parent, which now hides only beyond `impostor_distance`.
func _link_impostor(sector: Vector3i) -> void:
	var impostor: MeshInstance3D = _impostors.get(sector)
	var node: Node3D = placed.get(sector)
	if impostor == null or node == null:
		return
	if not node is SectorMultiMesh:
		impostor.visible = false
		return
	impostor.visibility_range_begin = impostor_distance()
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			(child as MultiMeshInstance3D).visibility_parent = child.get_path_to(impostor)


## Stores the outcome and cells of a fresh result as most recent, evicting
## the least recent beyond `cache_size`.
func _remember(sector: Vector3i, result: Dictionary) -> void:
	if cache_size == 0:
		return
	_cache.erase(sector)
	_cache[sector] = {
		"outcome": result.outcome, "cells": result.cells, "degraded": result.degraded, "error": result.error,
	}
	_trim_cache()


func _touch(sector: Vector3i) -> void:
	var entry: Dictionary = _cache[sector]
	_cache.erase(sector)
	_cache[sector] = entry


func _trim_cache() -> void:
	while _cache.size() > cache_size:
		for oldest: Vector3i in _cache:
			_cache.erase(oldest)
			break


static func _translucent_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
