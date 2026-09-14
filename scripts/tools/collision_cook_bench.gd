extends SceneTree
## Measures the main-thread cost of adding one sector's trimesh collision
## (decision #175) for the strategies that are cheap to try, on a real
## sector's `SectorMultiMesh.build` faces:
##
## - `merged`: what #96 shipped. `ConcavePolygonShape3D.set_faces` and a
##   `StaticBody3D` entering the tree, all on the main thread; Jolt builds the
##   mesh shape when the body enters its space.
## - `merged, server`: the same through `PhysicsServer3D` calls, no nodes.
## - `worker shape`: the `ConcavePolygonShape3D` created and filled on a
##   `WorkerThreadPool` task, then its body added on the main thread.
## - `chunk bodies`: `build(..., chunk_cells)` and one `PhysicsServer3D`
##   body per chunk, one added per frame.
## - `chunk shapes, one body`: the same chunks as shapes of one body, one
##   added per frame (Jolt rebuilds the body's compound shape each time).
## - `chunk shapes, 8 bodies`: the same through
##   `SectorMultiMesh.add_collision_chunk`, which spreads the chunks over
##   `BODY_BLOCKS`³ bodies; what streaming uses.
##
## Headless frames are paced by a sleep, switched off here, so the wall time
## between two process frames is the work done in the frame. For each
## strategy it prints the main-thread time from the first call to the end of
## the frame after the last one, the longest frame, the time to free it and
## the bodies used. Rays cast down through every 2 m column (off the cell
## edges, where neighbouring triangles meet) must hit the same heights within
## 1 mm as `merged`, so no strategy changes what collides.
##
##     godot --headless --path . --script res://scripts/tools/collision_cook_bench.gd -- [--sector x,y,z] [--seed N] [--chunk-cells N] [--repeat N]
##
## Run with `mise run collision-cook-bench`.

const TILESET := "res://resources/tilesets/placeholder.tres"
const HIT_TOLERANCE := 0.001

var _failures := 0
var _library: TileLibrary
var _sector := Vector3i(-1, 1, -1)
var _seed := 0
var _repeat := 2
var _chunk_cells := 3
var _faces := PackedVector3Array()
var _chunked := {}
var _n := 24
## Strategy -> Array of [place usec, longest frame usec, free usec, bodies].
var _times := {}
var _reference := PackedFloat64Array()
var _longest_frame_usec := 0
var _last_frame_usec := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if i + 1 >= args.size():
			_usage(args[i])
			return
		match args[i]:
			"--sector":
				var parts := args[i + 1].split(",")
				if parts.size() != 3:
					_usage(args[i + 1])
					return
				_sector = Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			"--seed":
				_seed = int(args[i + 1])
			"--chunk-cells":
				_chunk_cells = clampi(int(args[i + 1]), 1, 24)
			"--repeat":
				_repeat = maxi(int(args[i + 1]), 1)
			_:
				_usage(args[i])
				return
		i += 2
	_library = TileLibrary.build(load(TILESET) as TileSet3D)
	var faces := SectorMultiMesh.prototype_faces(_library)
	var result := SectorJobs.solve_sector(_library, SectorGrammar.new(), _seed, _sector, false, Callable(), faces)
	if result.outcome != SectorSolver.Outcome.SOLVED:
		printerr("collision cook bench: sector %s does not solve at seed %d" % [_sector, _seed])
		quit(1)
		return
	_faces = result.placement.faces
	_n = result.placement.cells_per_sector
	_chunked = SectorMultiMesh.build(_library, faces, result.cells, _chunk_cells)
	var with_faces := 0
	var most := 0
	for chunk: PackedVector3Array in _chunked.chunks:
		with_faces += int(not chunk.is_empty())
		most = maxi(most, chunk.size() / 3)
	print("collision cook bench: sector %s seed %d, %d triangles, %d chunks of %d³ cells with triangles (at most %d triangles), %d CPUs, %d runs" % [
		_sector, _seed, _faces.size() / 3, with_faces, _chunk_cells, most, OS.get_processor_count(), _repeat])
	# Headless paces frames with this sleep; without it a frame's wall time is
	# the work done in it.
	OS.low_processor_usage_mode_sleep_usec = 1
	process_frame.connect(_on_frame)
	await physics_frame
	for run in _repeat:
		await _merged()
		await _server()
		await _worker_shape()
		await _chunk_bodies()
		await _one_body()
		await _sector_bodies()
	_report()
	if _failures > 0:
		printerr("collision cook bench: %d failure(s)" % _failures)
		quit(1)
	else:
		print("collision cook bench: ok")
		quit(0)


func _usage(argument: String) -> void:
	printerr("collision cook bench: unexpected argument '%s'; usage: [--sector x,y,z] [--seed N] [--chunk-cells N] [--repeat N]" % argument)
	quit(1)


func _on_frame() -> void:
	var now := Time.get_ticks_usec()
	_longest_frame_usec = maxi(_longest_frame_usec, now - _last_frame_usec)
	_last_frame_usec = now


## Starts timing frames from now.
func _reset_frames() -> void:
	_longest_frame_usec = 0
	_last_frame_usec = Time.get_ticks_usec()


func _origin() -> Vector3:
	return SectorGridMap.sector_origin(_sector, _n)


func _end_of_frame() -> void:
	await process_frame
	await physics_frame


func _record(strategy: String, place_usec: int, longest_usec: int, free_usec: int, bodies: int) -> void:
	if not _times.has(strategy):
		_times[strategy] = []
	_times[strategy].append([place_usec, longest_usec, free_usec, bodies])


func _merged() -> void:
	_reset_frames()
	var started := Time.get_ticks_usec()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	var body := _body(shape)
	root.add_child(body)
	await _end_of_frame()
	var place_usec := Time.get_ticks_usec() - started
	var longest := _longest_frame_usec
	_compare("merged")
	started = Time.get_ticks_usec()
	body.queue_free()
	await _end_of_frame()
	_record("merged", place_usec, longest, Time.get_ticks_usec() - started, 1)


func _server() -> void:
	_reset_frames()
	var started := Time.get_ticks_usec()
	var shape := PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(shape, {"faces": _faces, "backface_collision": false})
	var body := _server_body()
	PhysicsServer3D.body_add_shape(body, shape)
	await _end_of_frame()
	var place_usec := Time.get_ticks_usec() - started
	var longest := _longest_frame_usec
	_compare("merged, server")
	started = Time.get_ticks_usec()
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	await _end_of_frame()
	_record("merged, server", place_usec, longest, Time.get_ticks_usec() - started, 1)


func _worker_shape() -> void:
	var made := []
	var faces := _faces
	var task := WorkerThreadPool.add_task(func() -> void:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		made.append(shape))
	WorkerThreadPool.wait_for_task_completion(task)
	_reset_frames()
	var started := Time.get_ticks_usec()
	var body := _body(made[0])
	root.add_child(body)
	await _end_of_frame()
	var place_usec := Time.get_ticks_usec() - started
	var longest := _longest_frame_usec
	_compare("worker shape")
	started = Time.get_ticks_usec()
	body.queue_free()
	made.clear()
	await _end_of_frame()
	_record("worker shape", place_usec, longest, Time.get_ticks_usec() - started, 1)


func _chunk_bodies() -> void:
	var bodies: Array[RID] = []
	var shapes: Array[RID] = []
	_reset_frames()
	var started := Time.get_ticks_usec()
	for chunk: PackedVector3Array in _chunked.chunks:
		if chunk.is_empty():
			continue
		var shape := PhysicsServer3D.concave_polygon_shape_create()
		PhysicsServer3D.shape_set_data(shape, {"faces": chunk, "backface_collision": false})
		var body := _server_body()
		PhysicsServer3D.body_add_shape(body, shape)
		shapes.append(shape)
		bodies.append(body)
		await _end_of_frame()
	var place_usec := Time.get_ticks_usec() - started
	var longest := _longest_frame_usec
	_compare("chunk bodies")
	started = Time.get_ticks_usec()
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	for shape in shapes:
		PhysicsServer3D.free_rid(shape)
	await _end_of_frame()
	_record("chunk bodies", place_usec, longest, Time.get_ticks_usec() - started, bodies.size())


func _one_body() -> void:
	var body := _server_body()
	var shapes: Array[RID] = []
	_reset_frames()
	var started := Time.get_ticks_usec()
	for chunk: PackedVector3Array in _chunked.chunks:
		if chunk.is_empty():
			continue
		var shape := PhysicsServer3D.concave_polygon_shape_create()
		PhysicsServer3D.shape_set_data(shape, {"faces": chunk, "backface_collision": false})
		PhysicsServer3D.body_add_shape(body, shape)
		shapes.append(shape)
		await _end_of_frame()
	var place_usec := Time.get_ticks_usec() - started
	var longest := _longest_frame_usec
	_compare("chunk shapes, one body")
	started = Time.get_ticks_usec()
	PhysicsServer3D.free_rid(body)
	for shape in shapes:
		PhysicsServer3D.free_rid(shape)
	await _end_of_frame()
	_record("chunk shapes, one body", place_usec, longest, Time.get_ticks_usec() - started, 1)


func _sector_bodies() -> void:
	var node := SectorMultiMesh.new()
	root.add_child(node)
	var no_meshes: Array[Mesh] = []
	node.place(no_meshes, _sector, _chunked)
	await _end_of_frame()
	_reset_frames()
	var started := Time.get_ticks_usec()
	for index in node.chunk_faces.size():
		if node.add_collision_chunk(index):
			await _end_of_frame()
	var place_usec := Time.get_ticks_usec() - started
	var longest := _longest_frame_usec
	var bodies := 0
	for body in node.collision_bodies:
		bodies += int(body.is_valid())
	_compare("chunk shapes, %d bodies" % bodies)
	started = Time.get_ticks_usec()
	node.queue_free()
	await _end_of_frame()
	_record("chunk shapes, %d bodies" % bodies, place_usec, longest, Time.get_ticks_usec() - started, bodies)


func _body(shape: Shape3D) -> StaticBody3D:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body := StaticBody3D.new()
	body.position = _origin()
	body.add_child(collision)
	return body


func _server_body() -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, _origin()))
	PhysicsServer3D.body_set_space(body, root.world_3d.space)
	return body


## Casts a ray down through every 2 m column, off the cell edges, and compares
## the hit heights with the first strategy's.
func _compare(strategy: String) -> void:
	var space := root.world_3d.direct_space_state
	var hits := PackedFloat64Array()
	var top := _origin().y + _n * WalkableGraph.CELL_SIZE + 1.0
	for x in _n:
		for z in _n:
			var at := _origin() + Vector3(x + 0.37, 0.0, z + 0.61) * WalkableGraph.CELL_SIZE
			var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, top, at.z), Vector3(at.x, top - _n * WalkableGraph.CELL_SIZE - 2.0, at.z))
			var hit := space.intersect_ray(query)
			hits.append(hit.position.y if not hit.is_empty() else INF)
	if _reference.is_empty():
		_reference = hits
		return
	var same := 0
	for i in hits.size():
		if absf(hits[i] - _reference[i]) <= HIT_TOLERANCE or (is_inf(hits[i]) and is_inf(_reference[i])):
			same += 1
	if same != hits.size():
		_failures += 1
		printerr("  FAIL  %s: %d of %d rays hit where merged does" % [strategy, same, hits.size()])


func _report() -> void:
	print("")
	print("| strategy | bodies | main thread, placing to the end of the frame after | longest frame | freeing |")
	print("| --- | ---: | ---: | ---: | ---: |")
	for strategy: String in _times:
		var place := PackedFloat64Array()
		var longest := PackedFloat64Array()
		var freeing := PackedFloat64Array()
		var bodies := 0
		for row: Array in _times[strategy]:
			place.append(row[0] / 1000.0)
			longest.append(row[1] / 1000.0)
			freeing.append(row[2] / 1000.0)
			bodies = row[3]
		print("| %s | %d | %s | %s | %s |" % [strategy, bodies, _span(place), _span(longest), _span(freeing)])


static func _span(values: PackedFloat64Array) -> String:
	values.sort()
	if values.size() == 1 or is_equal_approx(values[0], values[values.size() - 1]):
		return "%.1f ms" % values[0]
	return "%.1f to %.1f ms" % [values[0], values[values.size() - 1]]
