extends SceneTree
## Runs real stratum sectors with records through the fill pipeline on the
## placeholder tileset, per world seed, and explains every sector that fails
## before an attempt. The sectors are the ones `solver-check` runs: sampled
## with `SolverSectorRun.real_sector` until `--count` stratum sectors with
## records are found, the world seed and the solve seed both equal to the seed.
##
##     godot --headless --path . --script res://scripts/tools/solver_real.gd -- --seeds 0,1,2,3,4 --count 20
##
## For a sector rejected by the record checks it prints the record pair
## `SectorDomains` names. For one whose starting domains propagate to an empty
## cell it shrinks the records to a minimal set that still empties a cell
## (each record dropped in turn while the rest still fail) and prints those
## records relative to the first. With `--no-solve` it only builds and
## propagates the starting domains, which is enough to count failures before
## an attempt. Exits 1 when any sector fails before an attempt, or when
## `--min-solved N` is given and fewer than N sectors of some seed solve.
## Run with `mise run solver-real [--seeds S] [--count N] [--no-solve]
## [--min-solved N]`.

const TILESET := "res://resources/tilesets/placeholder.tres"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds: Array[int] = [0]
	var count := 20
	var solve := true
	var min_solved := -1
	var i := 0
	while i < args.size():
		match args[i]:
			"--seeds":
				seeds.clear()
				for part in args[i + 1].split(",", false):
					seeds.append(int(part))
				i += 1
			"--count":
				count = int(args[i + 1])
				i += 1
			"--min-solved":
				min_solved = int(args[i + 1])
				i += 1
			"--no-solve":
				solve = false
			_:
				printerr("solver real: unexpected argument '%s'" % args[i])
				quit(1)
				return
		i += 1

	var library := TileLibrary.build(load(TILESET) as TileSet3D)
	if not library.errors.is_empty():
		printerr("solver real: %s: %s" % [TILESET, library.errors])
		quit(1)
		return
	var failed_before := 0
	var short := 0
	var rows := PackedStringArray()
	for seed in seeds:
		var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed))
		var solver := SectorSolver.new(library, Vector3i(24, 24, 24))
		var counts := {"solved": 0, "degraded": 0, "failed": 0, "rejected": 0, "propagation": 0}
		for sector in SolverSectorRun.real_sectors(rasteriser, count):
			var records := rasteriser.records_for_sector(sector)
			var n := rasteriser.graph.cells_per_sector()
			var size := Vector3i(n, n, n)
			var built := SectorDomains.build(library, size, Skeleton.SectorType.STRATUM, records)
			if not built.error.is_empty():
				counts.rejected += 1
				print("  seed %d %s: %d records, rejected: %s" % [seed, sector, records.size(), built.error])
				continue
			var empty := SolverSectorRun.empty_cell(library, size, built.words)
			if empty >= 0:
				counts.propagation += 1
				print("  seed %d %s: %d records, empties cell %s; minimal records:" % [seed, sector, records.size(), SolverSectorRun.position(size, empty)])
				for line in _minimal(library, size, records):
					print("      %s" % line)
				continue
			if not solve:
				continue
			var result := solver.solve(seed, sector, built.words)
			var outcome: String = SectorSolver.OUTCOME_NAMES[result.outcome]
			counts[outcome] += 1
			print("  seed %d %s: %d records, %s after %d attempt(s)%s" % [seed, sector, records.size(), outcome, result.attempts, "" if result.ok else ": %s" % result.error])
		var before: int = counts.rejected + counts.propagation
		failed_before += before
		if min_solved >= 0 and counts.solved < min_solved:
			short += 1
		rows.append("  seed %d: %d solved, %d degraded, %d failed in an attempt, %d rejected by the record checks, %d failed on the starting propagation" % [
			seed, counts.solved, counts.degraded, counts.failed, counts.rejected, counts.propagation,
		])
	for row in rows:
		print(row)
	var ok := failed_before == 0 and short == 0
	print("solver real: %s" % ("ok" if ok else "%d sector(s) failed before an attempt, %d seed(s) below %d solved" % [failed_before, short, min_solved]))
	quit(0 if ok else 1)


## The records of a minimal failing subset, relative to the first of them:
## chunks of records are dropped while the rest still fail, halving the chunk
## size down to single records.
func _minimal(library: TileLibrary, size: Vector3i, records: Array[EdgeRasteriser.Record]) -> PackedStringArray:
	var kept: Array[EdgeRasteriser.Record] = records.duplicate()
	var chunk := maxi(kept.size() / 2, 1)
	while true:
		var k := 0
		while k < kept.size():
			var trial: Array[EdgeRasteriser.Record] = kept.slice(0, k)
			trial.append_array(kept.slice(k + chunk))
			if _fails(library, size, trial):
				kept = trial
			else:
				k += chunk
		if chunk == 1:
			break
		chunk = maxi(chunk / 2, 1)
	var lines := PackedStringArray()
	var origin := kept[0].cell
	for record in kept:
		var orientation := str(record.orientation)
		if record.orientation == EdgeRasteriser.ORIENTATION_UP:
			orientation = "up"
		elif record.orientation == EdgeRasteriser.ORIENTATION_DOWN:
			orientation = "down"
		lines.append("%s %s %s at %s" % [record.cell - origin, EdgeRasteriser.family_name(record.family), orientation, record.cell])
	return lines


## Whether `records` fail before an attempt: rejected by the record checks or
## emptying a cell when propagated.
static func _fails(library: TileLibrary, size: Vector3i, records: Array[EdgeRasteriser.Record]) -> bool:
	var built := SectorDomains.build(library, size, Skeleton.SectorType.STRATUM, records)
	return not built.error.is_empty() or SolverSectorRun.empty_cell(library, size, built.words) >= 0
