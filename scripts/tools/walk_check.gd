extends SceneTree
## Walks a `Player` capsule along a route of cells through a placed sector,
## once as a `SectorMultiMesh` and once as a `SectorGridMap`, and fails when it
## falls, gets stuck or ends away from the goal.
##
## Two routes:
##
## - The course (default): a 24³ grid of placeholder tiles laid by hand the
##   way the edge rasteriser lays a walk: a floor run, a three-stair flight up
##   onto a landing (solid under every stair and at its high end), a turn, a
##   flight down and a floor run. It needs no solve, so it checks the
##   placement and the controller (step-up onto 0.4 m treads and the 0.6 m
##   landing lip, snapping down a flight) whatever the solver and tileset do.
## - `--sector x,y,z` (`--seed N`, default 0): a real sector solved with
##   `SectorJobs.solve_sector`, the walk scene's pipeline; it must solve. The
##   route runs from the portal of the first kept horizontal edge (edge_ref
##   order) back along its records to the hub, then along the last such
##   edge's records to its portal.
##
## `--placement multimesh` or `--placement gridmap` walks only that
## placement; by default both walk, MultiMesh first, each in a fresh tree.
##
## The capsule starts on the first cell and, one physics frame at a time,
## `scripted_direction` points it at the centre of the next cell until it is
## within `REACHED` metres across; `move_and_slide` and the player's step-up
## do the rest. Fails when the feet drop more than `FALL_TOLERANCE` below the
## bottom of the lower of the two cells walked between, when a cell is not
## reached within `WAYPOINT_FRAMES`, or when the feet end more than
## `ARRIVE_DISTANCE` from the last cell's walking point (centre across,
## `SLAB_TOP` above the cell bottom). Prints the route with each cell's
## tile, frames per cell, steps climbed and the final distance, and on a
## failure the tiles around the feet.
##
##     godot --headless --fixed-fps 60 --path . --script res://scripts/tools/walk_check.gd -- [--sector x,y,z] [--seed N] [--placement multimesh|gridmap]
##
## Run with `mise run walk-check [--sector x,y,z] [--seed N] [--placement P]`.

const TILESET := "res://resources/tilesets/placeholder.tres"
const REACHED := 0.3
const FALL_TOLERANCE := 0.5
const ARRIVE_DISTANCE := 1.0
const WAYPOINT_FRAMES := 240
const SETTLE_FRAMES := 30
## Height of the walking surface of a flat cell above the cell bottom.
const SLAB_TOP := 0.6
const CELLS := 24
const PLACEMENTS: Array[String] = ["multimesh", "gridmap"]

var _failures := 0
var _library: TileLibrary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var sector := Vector3i.ZERO
	var real := false
	var seed := 0
	var placements := PLACEMENTS.duplicate()
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--seed" and i + 1 < args.size() and args[i + 1].is_valid_int():
			seed = int(args[i + 1])
			i += 2
			continue
		if args[i] == "--sector" and i + 1 < args.size() and args[i + 1].split(",").size() == 3:
			var parts := args[i + 1].split(",")
			sector = Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			real = true
			i += 2
			continue
		if args[i] == "--placement" and i + 1 < args.size() and args[i + 1] in PLACEMENTS:
			placements = [args[i + 1]]
			i += 2
			continue
		printerr("walk check: unexpected argument '%s'; usage: [--sector x,y,z] [--seed N] [--placement multimesh|gridmap]" % args[i])
		quit(1)
		return
	_library = TileLibrary.build(load(TILESET) as TileSet3D)
	if not _library.errors.is_empty():
		_fail("%s: %s" % [TILESET, _library.errors])
		quit(1)
		return

	var cells := PackedInt32Array()
	var route: Array[Vector3i] = []
	if real:
		var grammar := SectorGrammar.new()
		var result := SectorJobs.solve_sector(_library, grammar, seed, sector)
		var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed, Skeleton.new(grammar)))
		print("walk check: seed %d, sector %s, %s, %s in %d attempt(s), %.0f ms" % [
			seed, sector, Skeleton.type_name(rasteriser.graph.skeleton.sector_type(seed, sector)),
			SectorSolver.OUTCOME_NAMES[result.outcome], result.attempts, result.time_usec / 1000.0,
		])
		if result.outcome != SectorSolver.Outcome.SOLVED:
			_fail("sector %s does not solve at seed %d: %s" % [sector, seed, result.error if result.error != "" else "degraded"])
			_finish()
			return
		cells = result.cells
		route = _portal_route(rasteriser.rasterise(sector))
		if route.size() < 2:
			_fail("sector %s has fewer than two kept horizontal portals" % sector)
			_finish()
			return
	else:
		print("walk check: hand-laid course of placeholder tiles")
		cells = _course(route)

	for cell in route:
		print("  route %s %s" % [cell, _tile_at(cells, cell).label()])
	for placement in placements:
		var failures := _failures
		var node: Node3D
		if placement == "gridmap":
			var grid := SectorGridMap.new()
			grid.mesh_library = SectorGridMap.build_mesh_library(_library, false)
			root.add_child(grid)
			print("  gridmap: placed %d cells" % grid.place(_library, sector, cells))
			node = grid
		else:
			var built := SectorMultiMesh.build(_library, SectorMultiMesh.prototype_faces(_library), cells)
			var multimesh := SectorMultiMesh.new()
			root.add_child(multimesh)
			multimesh.place(SectorMultiMesh.build_meshes(_library, false), sector, built)
			print("  multimesh: placed %d instances in %d MultiMeshes, %d collision triangles (%d culled), built in %.1f ms" % [
				built.instances, multimesh.multimesh_count, built.triangles, built.culled_triangles, built.build_usec / 1000.0,
			])
			node = multimesh
		await _walk(route, cells, sector)
		print("  %s walk: %s" % [placement, "ok" if _failures == failures else "failed"])
		node.queue_free()
		await physics_frame
	_finish()


func _walk(route: Array[Vector3i], cells: PackedInt32Array, sector: Vector3i) -> void:
	var player := Player.new()
	root.add_child(player)
	await _walk_player(player, route, cells, sector)
	player.queue_free()


func _walk_player(player: Player, route: Array[Vector3i], cells: PackedInt32Array, sector: Vector3i) -> void:
	player.teleport(_walk_point(sector, route[0]))
	for frame in SETTLE_FRAMES:
		await physics_frame
	var frames_total := 0
	for w in range(1, route.size()):
		var previous := route[w - 1]
		var cell := route[w]
		var target := SectorGridMap.cell_centre(sector, cell, CELLS)
		var floor_y := SectorGridMap.sector_origin(sector, CELLS).y + mini(previous.y, cell.y) * WalkableGraph.CELL_SIZE - FALL_TOLERANCE
		var frames := 0
		while true:
			var offset := Vector3(target.x - player.global_position.x, 0.0, target.z - player.global_position.z)
			if offset.length() <= REACHED:
				break
			if frames >= WAYPOINT_FRAMES:
				_fail("cell %s not reached in %d frames: feet at %s, %.2f m away" % [cell, frames, player.global_position, offset.length()])
				_print_surroundings(cells, sector, player.global_position, offset)
				return
			player.scripted_direction = offset
			await physics_frame
			frames += 1
			if player.global_position.y < floor_y:
				_fail("fell below the floor between %s and %s: feet at %s, floor %.2f" % [previous, cell, player.global_position, floor_y + FALL_TOLERANCE])
				_print_surroundings(cells, sector, player.global_position, offset)
				return
		frames_total += frames
		print("  reached %s in %3d frames, feet %s" % [cell, frames, player.global_position])
	player.scripted_direction = Vector3.ZERO
	for frame in SETTLE_FRAMES:
		await physics_frame
	var goal := _walk_point(sector, route[-1])
	var distance := player.global_position.distance_to(goal)
	print("  arrived %.2f m from the walking point %s after %d frames, %d steps climbed" % [distance, goal, frames_total, player.steps_climbed])
	if distance > ARRIVE_DISTANCE:
		_fail("ended %.2f m from the last cell's walking point, more than %.1f m" % [distance, ARRIVE_DISTANCE])


## Portal of the first kept horizontal edge back to the hub, then the hub to
## the portal of the last one.
static func _portal_route(raster: EdgeRasteriser.SectorRaster) -> Array[Vector3i]:
	var chains: Array = []
	var refs: Array = raster.edge_records.keys()
	refs.sort()
	for ref: Vector4i in refs:
		var chain: Array = raster.edge_records[ref]
		if ref.w == Vector3i.AXIS_Y or raster.rejected.has(ref) or chain.size() < 2:
			continue
		var portal: EdgeRasteriser.Record = chain[-1]
		if portal.family == EdgeRasteriser.TileFamily.PORTAL_OPENING and portal.orientation < EdgeRasteriser.ORIENTATION_UP:
			chains.append(chain)
	var route: Array[Vector3i] = []
	if chains.size() < 2:
		return route
	var first: Array = chains[0]
	for k in range(first.size() - 1, -1, -1):
		route.append((first[k] as EdgeRasteriser.Record).cell)
	var last: Array = chains[-1]
	for k in range(1, last.size()):
		route.append((last[k] as EdgeRasteriser.Record).cell)
	return route


## The hand-laid course; appends its route to `route` and returns the cells.
func _course(route: Array[Vector3i]) -> PackedInt32Array:
	var cells := PackedInt32Array()
	cells.resize(CELLS * CELLS * CELLS)
	cells.fill(_library.air_tile)
	# Floor run along +x at level 4.
	for x in range(2, 5):
		_lay(cells, route, Vector3i(x, 4, 4), "floor", 0)
	# Flight up towards +x (stair yaw 0), onto a landing at level 7.
	for k in 3:
		_lay(cells, route, Vector3i(5 + k, 4 + k, 4), "stair", 0)
		_put(cells, Vector3i(6 + k, 4 + k, 4), "solid", 0)
	_lay(cells, route, Vector3i(8, 7, 4), "floor", 0)
	_lay(cells, route, Vector3i(9, 7, 4), "floor", 0)
	# Turn to +z along the landing.
	_lay(cells, route, Vector3i(9, 7, 5), "floor", 0)
	_lay(cells, route, Vector3i(9, 7, 6), "floor", 0)
	# Flight down towards +z: the way up is -z, stair yaw 1.
	for k in 3:
		_lay(cells, route, Vector3i(9, 6 - k, 7 + k), "stair", 1)
		_put(cells, Vector3i(9, 6 - k, 6 + k), "solid", 0)
	for z in range(10, 13):
		_lay(cells, route, Vector3i(9, 4, z), "floor", 0)
	return cells


## Sets `cell` to the tile, puts solid under it and appends it to `route`.
func _lay(cells: PackedInt32Array, route: Array[Vector3i], cell: Vector3i, prototype: String, rotation: int) -> void:
	_put(cells, cell, prototype, rotation)
	_put(cells, cell + Vector3i.DOWN, "solid", 0)
	route.append(cell)


func _put(cells: PackedInt32Array, cell: Vector3i, prototype: String, rotation: int) -> void:
	for tile in _library.tiles:
		if tile.prototype.name == prototype and tile.rotation == rotation:
			cells[cell.x + CELLS * (cell.y + CELLS * cell.z)] = tile.index
			return
	push_error("walk check: no tile %s@%d" % [prototype, rotation])


func _tile_at(cells: PackedInt32Array, cell: Vector3i) -> TileLibrary.Tile:
	return _library.tiles[cells[cell.x + CELLS * (cell.y + CELLS * cell.z)]]


## Tiles of the column at the feet and of the column ahead, from one cell
## below the feet to two above.
func _print_surroundings(cells: PackedInt32Array, sector: Vector3i, feet: Vector3, heading: Vector3) -> void:
	var local := feet - SectorGridMap.sector_origin(sector, CELLS)
	var here := Vector3i((local / WalkableGraph.CELL_SIZE).floor())
	var along := heading.normalized()
	var step := Vector3i(roundi(along.x), 0, roundi(along.z))
	for column: Vector3i in [here, here + step]:
		var parts := PackedStringArray()
		for dy in range(-1, 3):
			var cell := column + Vector3i(0, dy, 0)
			if cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < CELLS and cell.y < CELLS and cell.z < CELLS:
				parts.append("%s %s" % [cell, _tile_at(cells, cell).label()])
		print("        %s" % ", ".join(parts))


## Cell centre across, slab top height: where feet stand on a flat cell.
static func _walk_point(sector: Vector3i, cell: Vector3i) -> Vector3:
	var centre := SectorGridMap.cell_centre(sector, cell, CELLS)
	return Vector3(centre.x, centre.y - WalkableGraph.CELL_SIZE * 0.5 + SLAB_TOP, centre.z)


func _finish() -> void:
	print("walk check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)
