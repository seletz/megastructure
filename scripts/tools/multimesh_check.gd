extends SceneTree
## Checks `SectorMultiMesh` against hand-computed numbers and against
## `SectorGridMap` on the placeholder tileset.
##
## Headless (the default, `mise run multimesh-check`, part of `check`):
##
## - Buffer layout: one stair turned one quarter turn at local cell (3, 5, 7)
##   of an 8³ grid of air gives the stair's buffer exactly the 12 floats
##   `LAYOUT_EXPECTED` (basis rows, each followed by its origin component) and
##   every other buffer is empty; the buffer reads back as that transform and
##   survives `MultiMesh.buffer`.
## - Collision triangles: that stair's faces are its mesh's `get_faces()` with
##   each corner (x, y, z) moved to (z + 7, y + 11, 15 - x), worked out by
##   hand for the quarter turn and the cell centre (7, 11, 15). Two solid
##   cells side by side keep 20 of their 24 triangles (the two hidden
##   squares go) and a lone solid cell keeps all 12.
## - A solved 8³ sector placed at sector (1, -1, 2) as a `SectorGridMap` and
##   as a `SectorMultiMesh` gives the same world-space instance transforms per
##   mesh (GridMap's `get_meshes()` against the buffers), and rays down, rays
##   along x and z and capsule casts down through every column hit the same
##   surfaces within 1 cm.
## - Through `SectorJobs` with `build_placement`, a real 24³ sector solved on a
##   worker thread carries placement data equal to a main-thread
##   `SectorMultiMesh.build` of its cells; prints the worker's build time and
##   the main-thread time of placing that sector both ways, up to the end of
##   the next frame.
##
## `--render` (`mise run multimesh-draw-calls`, needs a renderer, so under
## xvfb-run): `set_instance_transform` on the OpenGL renderer writes exactly
## the layout `write_instance` writes, and for the solved sectors of the 3³
## block around the origin at seed 0 placed
## one at a time in front of a camera, prints the draw calls of the frame
## (`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, minus the empty scene)
## with GridMap and with MultiMesh and the placement build time (on the main
## thread here); fails when a MultiMesh sector takes more draw
## calls than the tileset has meshes.
##
##     godot --headless --path . --script res://scripts/tools/multimesh_check.gd
##     godot --display-driver x11 --rendering-driver opengl3 --path . --script res://scripts/tools/multimesh_check.gd -- --render

const TILESET := "res://resources/tilesets/placeholder.tres"
const SMALL := 8
const SMALL_SECTOR := Vector3i(1, -1, 2)
const LAYOUT_CELL := Vector3i(3, 5, 7)
const LAYOUT_EXPECTED: Array[float] = [0, 0, 1, 7, 0, 1, 0, 11, -1, 0, 0, 15]
## World seed of the real sectors.
const REAL_SEED := 0
## A stratum sector that solves at seed 0, for the worker path.
const WORKER_SECTOR := Vector3i(-1, 1, -1)
## The draw call report covers the sectors within this many sectors of the
## origin, the walk scene's default block.
const REPORT_RADIUS := 1
const HIT_TOLERANCE := 0.01
const RENDER_FRAMES := 6
const JOB_TIMEOUT_MSEC := 120000

var _failures := 0
var _library: TileLibrary
var _faces: Array


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_library = TileLibrary.build(load(TILESET) as TileSet3D)
	_expect(_library.errors.is_empty(), "placeholder library builds")
	if not _library.errors.is_empty():
		_finish()
		return
	_faces = SectorMultiMesh.prototype_faces(_library)
	if "--render" in OS.get_cmdline_user_args():
		_check_renderer_layout()
		await _report_draw_calls()
	else:
		_check_layout()
		_check_collision()
		await _check_against_gridmap()
		await _check_worker()
	_finish()


func _check_layout() -> void:
	var stair := _tile("stair", 1)
	var cells := _air(SMALL)
	cells[_index(LAYOUT_CELL, SMALL)] = stair.index
	var placement := SectorMultiMesh.build(_library, _faces, cells)
	var buffers: Array = placement.buffers
	var buffer: PackedFloat32Array = buffers[stair.prototype_index]
	_expect(Array(buffer) == LAYOUT_EXPECTED, "stair@1 at %s: buffer %s, expected %s" % [LAYOUT_CELL, buffer, LAYOUT_EXPECTED])
	var others := 0
	for p in buffers.size():
		if p != stair.prototype_index:
			others += (buffers[p] as PackedFloat32Array).size()
	_expect(others == 0 and placement.instances == 1 and placement.cells_per_sector == SMALL, "no other instance (%d floats elsewhere, %d instances)" % [others, placement.instances])
	var expected := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(7, 11, 15))
	_expect(SectorMultiMesh.read_instance(buffer, 0).is_equal_approx(expected), "the buffer reads back as a quarter turn at (7, 11, 15)")
	_expect(SectorMultiMesh.yaw_basis(1).is_equal_approx(Basis(Vector3.UP, PI / 2.0)) and SectorMultiMesh.yaw_basis(-1) == SectorMultiMesh.YAW_BASES[3],
		"the exact yaw table matches Basis(Vector3.UP, r * PI / 2) and wraps")
	for r in 4:
		_expect(SectorMultiMesh.yaw_basis(r).is_equal_approx(Basis(Vector3.UP, r * PI / 2.0)), "yaw basis %d" % r)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = 1
	multimesh.buffer = buffer
	_expect(multimesh.buffer == buffer, "MultiMesh.buffer takes the 12 floats of one instance")


func _check_collision() -> void:
	var stair := _tile("stair", 1)
	var cells := _air(SMALL)
	cells[_index(LAYOUT_CELL, SMALL)] = stair.index
	var faces: PackedVector3Array = SectorMultiMesh.build(_library, _faces, cells).faces
	var expected := PackedVector3Array()
	for v in stair.prototype.mesh.get_faces():
		expected.append(Vector3(v.z + 7.0, v.y + 11.0, 15.0 - v.x))
	_expect(_triangle_keys(faces) == _triangle_keys(expected), "stair@1 collision: %d triangles, the mesh's %d turned and moved by hand" % [faces.size() / 3, expected.size() / 3])

	var solid := _library.tiles[_library.solid_tile]
	cells = _air(SMALL)
	cells[_index(Vector3i(2, 2, 2), SMALL)] = solid.index
	cells[_index(Vector3i(3, 2, 2), SMALL)] = solid.index
	var pair := SectorMultiMesh.build(_library, _faces, cells)
	_expect(pair.triangles == 20 and pair.culled_triangles == 4, "two solid cells side by side keep 20 triangles, cull 4 (%d, %d)" % [pair.triangles, pair.culled_triangles])
	var shared_faces: PackedVector3Array = pair.faces
	for t in range(0, shared_faces.size() - 2, 3):
		if absf(shared_faces[t].x - 6.0) < 0.001 and absf(shared_faces[t + 1].x - 6.0) < 0.001 and absf(shared_faces[t + 2].x - 6.0) < 0.001:
			_fail("a triangle on the shared face x = 6 m survived: %s" % shared_faces.slice(t, t + 3))
			break
	cells = _air(SMALL)
	cells[_index(Vector3i(0, 0, 0), SMALL)] = solid.index
	var lone := SectorMultiMesh.build(_library, _faces, cells)
	_expect(lone.triangles == 12 and lone.culled_triangles == 0, "a lone solid cell at the border keeps its 12 triangles (%d)" % lone.triangles)


func _check_against_gridmap() -> void:
	var solver := SectorSolver.new(_library, Vector3i(SMALL, SMALL, SMALL))
	var solved: SectorSolver.Result = null
	for seed in 20:
		solved = solver.solve(seed, SMALL_SECTOR)
		if solved.outcome == SectorSolver.Outcome.SOLVED:
			print("  8³ sector solved at solve seed %d" % seed)
			break
	_expect(solved.outcome == SectorSolver.Outcome.SOLVED, "an 8³ sector solves")
	if solved.outcome != SectorSolver.Outcome.SOLVED:
		return

	var grid := SectorGridMap.new()
	grid.mesh_library = SectorGridMap.build_mesh_library(_library, false)
	root.add_child(grid)
	grid.place(_library, SMALL_SECTOR, solved.cells)
	var prototype_of := {}
	for p in grid.mesh_library.get_item_list():
		prototype_of[grid.mesh_library.get_item_mesh(p)] = p
	var grid_keys := {}
	var pairs := grid.get_meshes()
	for k in range(0, pairs.size(), 2):
		var world: Transform3D = grid.global_transform * (pairs[k] as Transform3D)
		_count(grid_keys, "%d %s" % [prototype_of[pairs[k + 1]], _transform_key(world)])
	await physics_frame
	await physics_frame
	var grid_hits := _probe()
	var grid_position := grid.position
	grid.queue_free()
	await process_frame
	await physics_frame

	var node := SectorMultiMesh.new()
	root.add_child(node)
	var placement := SectorMultiMesh.build(_library, _faces, solved.cells)
	var made := node.place(SectorMultiMesh.build_meshes(_library, false), SMALL_SECTOR, placement)
	var multimesh_keys := {}
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var instance := child as MultiMeshInstance3D
			var p := int(String(instance.name).trim_prefix("Mesh_"))
			var buffer := instance.multimesh.buffer
			for i in instance.multimesh.instance_count:
				_count(multimesh_keys, "%d %s" % [p, _transform_key(instance.global_transform * SectorMultiMesh.read_instance(buffer, i))])
	_expect(node.position == SectorGridMap.sector_origin(SMALL_SECTOR, SMALL) and node.position == grid_position, "both sit at the sector corner %s" % node.position)
	_expect(grid_keys.size() > 0 and grid_keys == multimesh_keys,
		"%d GridMap instances and %d MultiMesh instances in %d MultiMeshes have the same world transforms per mesh" % [pairs.size() / 2, placement.instances, made])
	await physics_frame
	await physics_frame
	var multimesh_hits := _probe()
	node.queue_free()
	await process_frame

	var hits := 0
	var mismatches := 0
	for k in grid_hits.size():
		var a: float = grid_hits[k]
		var b: float = multimesh_hits[k]
		if is_inf(a) != is_inf(b) or (not is_inf(a) and absf(a - b) > HIT_TOLERANCE):
			if mismatches < 5:
				print("        probe %d: GridMap %s, MultiMesh %s" % [k, a, b])
			mismatches += 1
		elif not is_inf(a):
			hits += 1
	_expect(mismatches == 0 and hits > 0, "%d rays and capsule casts: %d hit, %d disagree (%d triangles, %d culled)" % [grid_hits.size(), hits, mismatches, placement.triangles, placement.culled_triangles])


## Hit distances (INF for a miss) of rays down, rays along +x and +z and
## capsule casts down through the small sector, in a fixed order.
func _probe() -> PackedFloat64Array:
	var space := root.world_3d.direct_space_state
	var origin := SectorGridMap.sector_origin(SMALL_SECTOR, SMALL)
	var extent := SMALL * WalkableGraph.CELL_SIZE
	var out := PackedFloat64Array()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	for a in SMALL * 2:
		for b in SMALL * 2:
			var u := (a + 0.37) * extent / (SMALL * 2)
			var v := (b + 0.61) * extent / (SMALL * 2)
			out.append(_ray(space, origin + Vector3(u, extent + 1.0, v), Vector3.DOWN * (extent + 2.0)))
			out.append(_ray(space, origin + Vector3(-1.0, u, v), Vector3.RIGHT * (extent + 2.0)))
			out.append(_ray(space, origin + Vector3(u, v, -1.0), Vector3.BACK * (extent + 2.0)))
			if a % 2 == 0 and b % 2 == 0:
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.transform = Transform3D(Basis.IDENTITY, origin + Vector3(u, extent + 2.0, v))
				query.motion = Vector3.DOWN * (extent + 4.0)
				var fractions := space.cast_motion(query)
				out.append(INF if fractions[0] >= 1.0 else fractions[0] * (extent + 4.0))
	return out


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + motion))
	return INF if hit.is_empty() else from.distance_to(hit.position)


func _check_worker() -> void:
	var jobs := SectorJobs.new()
	root.add_child(jobs)
	jobs.configure(_library, REAL_SEED)
	jobs.build_placement = true
	var results := []
	jobs.sector_ready.connect(func(result: Dictionary) -> void: results.append(result))
	var sector := WORKER_SECTOR
	jobs.request(sector)
	var started := Time.get_ticks_msec()
	while results.is_empty() and Time.get_ticks_msec() - started < JOB_TIMEOUT_MSEC:
		await process_frame
	_expect(not results.is_empty(), "SectorJobs returns sector %s" % sector)
	if not results.is_empty():
		var result: Dictionary = results[0]
		var placement: Dictionary = result.placement
		_expect(result.outcome == SectorSolver.Outcome.SOLVED and not placement.is_empty(), "sector %s solved on a worker with placement data" % sector)
		if not placement.is_empty():
			var again := SectorMultiMesh.build(_library, _faces, result.cells)
			_expect(placement.buffers == again.buffers and placement.faces == again.faces and placement.instances == again.instances,
				"worker placement equals a main-thread build: %d instances, %d triangles (%d culled)" % [placement.instances, placement.triangles, placement.culled_triangles])
			print("  worker build %.1f ms, main-thread build %.1f ms, solve %.1f ms" % [placement.build_usec / 1000.0, again.build_usec / 1000.0, result.time_usec / 1000.0])
			await _time_placing(sector, result.cells, placement)
	jobs.queue_free()
	await process_frame


## Prints the main-thread time from placing `cells` to the end of the next
## process and physics frame, where GridMap builds its octants and Jolt the
## body's shapes, for both placements. Headless, so no rendering is counted.
func _time_placing(sector: Vector3i, cells: PackedInt32Array, placement: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var grid := SectorGridMap.new()
	grid.mesh_library = SectorGridMap.build_mesh_library(_library)
	root.add_child(grid)
	grid.place(_library, sector, cells)
	await process_frame
	await physics_frame
	var grid_usec := Time.get_ticks_usec() - started
	grid.free()
	var meshes := SectorMultiMesh.build_meshes(_library)
	started = Time.get_ticks_usec()
	var node := SectorMultiMesh.new()
	root.add_child(node)
	node.place(meshes, sector, placement)
	await process_frame
	await physics_frame
	var node_usec := Time.get_ticks_usec() - started
	node.free()
	print("  main thread, placing to the end of the next frame: GridMap %.1f ms, MultiMesh %.1f ms" % [grid_usec / 1000.0, node_usec / 1000.0])


func _check_renderer_layout() -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = BoxMesh.new()
	multimesh.instance_count = 2
	var transforms: Array[Transform3D] = [
		Transform3D(Basis(Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9)), Vector3(10, 11, 12)),
		SectorMultiMesh.cell_transform(LAYOUT_CELL, 1),
	]
	var expected := PackedFloat32Array()
	expected.resize(2 * SectorMultiMesh.FLOATS_PER_INSTANCE)
	for i in 2:
		multimesh.set_instance_transform(i, transforms[i])
		SectorMultiMesh.write_instance(expected, i, transforms[i])
	_expect(not multimesh.buffer.is_empty(), "the renderer keeps instance transforms (run under a renderer, not --headless)")
	_expect(multimesh.buffer == expected, "the renderer's buffer %s equals write_instance %s" % [multimesh.buffer, expected])


func _report_draw_calls() -> void:
	var camera := Camera3D.new()
	camera.far = 1000.0
	root.add_child(camera)
	var meshes := SectorMultiMesh.build_meshes(_library)
	var mesh_library := SectorGridMap.build_mesh_library(_library)
	var tile_meshes := 0
	for mesh in meshes:
		tile_meshes += 1 if mesh != null else 0
	var baseline := await _draw_calls()
	print("  %d tile meshes; empty scene %d draw calls" % [tile_meshes, baseline])
	print("")
	print("| sector | cells placed | meshes used | GridMap draw calls | MultiMesh draw calls | build ms | triangles | culled |")
	print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	var grammar := SectorGrammar.new()
	var reported := 0
	var sectors: Array[Vector3i] = []
	for x in range(-REPORT_RADIUS, REPORT_RADIUS + 1):
		for y in range(-REPORT_RADIUS, REPORT_RADIUS + 1):
			for z in range(-REPORT_RADIUS, REPORT_RADIUS + 1):
				sectors.append(Vector3i(x, y, z))
	for sector in sectors:
		var result := SectorJobs.solve_sector(_library, grammar, REAL_SEED, sector, false, Callable(), _faces)
		if result.outcome != SectorSolver.Outcome.SOLVED:
			continue
		var placement: Dictionary = result.placement
		var n: int = placement.cells_per_sector
		var centre := SectorGridMap.sector_origin(sector, n) + Vector3.ONE * n
		camera.look_at_from_position(centre + Vector3(1.2, 0.9, 1.5) * n * 2.0, centre)

		var grid := SectorGridMap.new()
		grid.mesh_library = mesh_library
		root.add_child(grid)
		var cells_placed := grid.place(_library, sector, result.cells)
		var grid_calls := await _draw_calls() - baseline
		grid.free()

		var node := SectorMultiMesh.new()
		root.add_child(node)
		var used := node.place(meshes, sector, placement)
		var multimesh_calls := await _draw_calls() - baseline
		node.free()

		print("| %s | %d | %d | %d | %d | %.1f | %d | %d |" % [sector, cells_placed, used, grid_calls, multimesh_calls,
			placement.build_usec / 1000.0, placement.triangles, placement.culled_triangles])
		_expect(multimesh_calls <= tile_meshes and multimesh_calls <= used, "sector %s: %d MultiMesh draw calls, at most %d meshes" % [sector, multimesh_calls, used])
		reported += 1
	print("")
	_expect(reported > 0, "at least one real sector solved to report")


func _draw_calls() -> int:
	for frame in RENDER_FRAMES:
		await process_frame
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


func _tile(prototype: String, rotation: int) -> TileLibrary.Tile:
	for tile in _library.tiles:
		if tile.prototype.name == prototype and tile.rotation == rotation:
			return tile
	push_error("multimesh check: no tile %s@%d" % [prototype, rotation])
	return null


func _air(n: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	cells.resize(n * n * n)
	cells.fill(_library.air_tile)
	return cells


static func _index(cell: Vector3i, n: int) -> int:
	return cell.x + n * (cell.y + n * cell.z)


## Sorted triangle strings, corners rounded to the millimetre; order and the
## starting corner of each triangle do not matter, winding does.
static func _triangle_keys(faces: PackedVector3Array) -> PackedStringArray:
	var keys := PackedStringArray()
	for t in range(0, faces.size() - 2, 3):
		var corners := [_vector_key(faces[t]), _vector_key(faces[t + 1]), _vector_key(faces[t + 2])]
		var first := corners.find(corners.min())
		keys.append("%s %s %s" % [corners[first], corners[(first + 1) % 3], corners[(first + 2) % 3]])
	keys.sort()
	return keys


static func _vector_key(v: Vector3) -> String:
	return "(%d,%d,%d)" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0)]


static func _transform_key(t: Transform3D) -> String:
	return "%s %s %s %s" % [_vector_key(t.basis.x), _vector_key(t.basis.y), _vector_key(t.basis.z), _vector_key(t.origin)]


static func _count(counts: Dictionary, key: String) -> void:
	counts[key] = counts.get(key, 0) + 1


func _finish() -> void:
	print("multimesh check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)
