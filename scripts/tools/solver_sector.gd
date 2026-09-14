extends SceneTree
## Runs the whole fill pipeline for one real sector on the placeholder
## tileset: skeleton type, walkable graph edges, edge rasteriser records,
## `SectorDomains`, then `SectorSolver.solve` with restarts. Prints the sector
## type, the records, the outcome, attempts, time, a family histogram of the
## result (free tiles by prototype name), and whether every record and
## adjacency holds. Exits 1 when the pipeline fails or a solved result breaks
## a record or an adjacency; a degraded sector is reported, not a failure.
##
##     godot --headless --path . --script res://scripts/tools/solver_sector.gd -- 0 0 0 --seed 3
##
## Run with `mise run solver-sector <x> <y> <z> [--seed N]`. The world seed
## and the solve seed are both N (default 0).

const TILESET := "res://resources/tilesets/placeholder.tres"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var numbers: Array[int] = []
	var seed := 0
	var i := 0
	while i < args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			seed = int(args[i + 1])
			i += 2
			continue
		if not args[i].is_valid_int():
			printerr("solver sector: unexpected argument '%s'; usage: <x> <y> <z> [--seed N]" % args[i])
			quit(1)
			return
		numbers.append(int(args[i]))
		i += 1
	if numbers.size() != 3:
		printerr("solver sector: usage: <x> <y> <z> [--seed N]")
		quit(1)
		return
	var sector := Vector3i(numbers[0], numbers[1], numbers[2])

	var library := TileLibrary.build(load(TILESET) as TileSet3D)
	if not library.errors.is_empty():
		printerr("solver sector: %s: %s" % [TILESET, library.errors])
		quit(1)
		return
	var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed))
	var run := SolverSectorRun.run(library, rasteriser, sector, seed)
	print("solver sector: seed %d, sector %s, %s, %d records" % [seed, sector, Skeleton.type_name(run.type), run.records.size()])
	if not run.error.is_empty():
		printerr("solver sector: %s" % run.error)
		quit(1)
		return
	var result := run.result
	print("  outcome %s, %d attempt(s), %d restart(s), %d pre-collapsed cells, %d steps, %.1f ms (domains %.1f ms)" % [
		SectorSolver.OUTCOME_NAMES[result.outcome], result.attempts, result.restarts, result.precollapsed.size(),
		result.steps, result.time_usec / 1000.0, run.domains_usec / 1000.0,
	])
	if result.outcome == SectorSolver.Outcome.FAILED:
		printerr("solver sector: %s" % result.error)
		quit(1)
		return
	print("  families: %s" % SolverSectorRun.histogram(library, result.cells))
	var failed := false
	if result.outcome == SectorSolver.Outcome.SOLVED:
		var broken := run.broken_records(library)
		var bad := SolverSectorRun.bad_adjacencies(library, run.size, result.cells)
		print("  %d of %d records hold, %d forbidden adjacencies" % [run.records.size() - broken, run.records.size(), bad])
		failed = broken > 0 or bad > 0
	else:
		print("  degraded: every cell solid, the records are not kept (last contradiction at cell %s)" % [
			Vector3i(result.contradiction_cell % run.size.x, (result.contradiction_cell / run.size.x) % run.size.y, result.contradiction_cell / (run.size.x * run.size.y)),
		])
	quit(1 if failed else 0)
