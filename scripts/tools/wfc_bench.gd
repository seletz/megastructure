extends SceneTree
## Benchmarks the sector solver on the placeholder tileset against the native
## extension threshold of decision #138 (1 s mean per stratum sector).
##
## Walks sectors from the origin outwards, shell by shell of growing
## Chebyshev radius (z, then y, then x ascending inside a shell), and keeps
## the first `--sectors` stratum sectors at world seed `--seed`. Each runs
## through the real pipeline, `SolverSectorRun` (records, `SectorDomains`,
## `SectorSolver.solve` with restarts, solve seed = world seed); with
## `--boundaries` each also runs cold through `SectorBoundaries.solve_sector`
## (the cache cleared before every sector, so its 8 corners, 12 edges, 6
## faces and interior are all solved). Many real sectors currently fail
## before an attempt (#159, #161), so the same sectors are also solved
## unconstrained, without domains, to give a time that means something today.
##
## Prints markdown tables to paste into an issue: one row per sector with
## outcome, attempts, steps, propagations and time, then a summary per run
## (mean and max time over the sectors that ran an attempt, mean attempts,
## contradictions, degraded and failed-before-attempt counts) and a one-line
## verdict. For the boundaries run a sector counts as searched when any of its
## pieces ran an attempt, as degraded or failed when any piece did, and its
## attempts, steps and propagations are summed over its pieces. The verdict uses the real pipeline when at least one sector ran an
## attempt, otherwise the unconstrained solves. Not part of `check`; exits 1
## only on bad arguments or an invalid tileset.
##
##     godot --headless --path . --script res://scripts/tools/wfc_bench.gd -- --seed 0 --sectors 10 --boundaries
##
## Run with `mise run wfc-bench [--seed N] [--sectors N] [--boundaries]`.

const TILESET := "res://resources/tilesets/placeholder.tres"
## Decision #138: port the solver when the mean per stratum sector is above.
const THRESHOLD_USEC := 1000000
const DEFAULT_SECTORS := 10
## Shells walked before giving up on finding enough stratum sectors.
const MAX_RADIUS := 64


## One benchmarked sector of one run.
class Row:
	extends RefCounted
	var sector := Vector3i.ZERO
	var records := 0
	## "solved", "degraded", "failed" (inconsistent in the solver) or
	## "rejected" (by `SectorDomains`); with boundaries "solved" or
	## "N degraded, M failed" pieces.
	var outcome := ""
	## Whether a search ran: at least one attempt.
	var searched := false
	var degraded := false
	## Failed before any attempt: rejected or inconsistent records.
	var failed_early := false
	var attempts := 0
	var restarts := 0
	var steps := 0
	var propagations := 0
	var time_usec := 0
	var note := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := 0
	var count := DEFAULT_SECTORS
	var boundaries := false
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg == "--boundaries":
			boundaries = true
			i += 1
			continue
		if (arg == "--seed" or arg == "--sectors") and i + 1 < args.size() and args[i + 1].is_valid_int():
			if arg == "--seed":
				seed = int(args[i + 1])
			else:
				count = int(args[i + 1])
			i += 2
			continue
		printerr("wfc bench: unexpected argument '%s'; usage: [--seed N] [--sectors N] [--boundaries]" % arg)
		quit(1)
		return
	if count < 1:
		printerr("wfc bench: --sectors must be at least 1")
		quit(1)
		return

	var library := TileLibrary.build(load(TILESET) as TileSet3D)
	if not library.errors.is_empty():
		printerr("wfc bench: %s: %s" % [TILESET, library.errors])
		quit(1)
		return
	var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed))
	var sectors := _stratum_sectors(rasteriser.graph, seed, count)
	if sectors.size() < count:
		printerr("wfc bench: only %d stratum sectors within radius %d at seed %d" % [sectors.size(), MAX_RADIUS, seed])
		quit(1)
		return
	var n := rasteriser.graph.cells_per_sector()
	var size := Vector3i(n, n, n)
	print("## wfc-bench: seed %d, %d stratum sectors, %d³ cells" % [seed, count, n])
	print("")
	print("Placeholder tileset, %d tiles, %d word(s); Godot %s, headless; %s; threshold %.0f ms mean per sector (#138)." % [
		library.tile_count(), library.word_count, Engine.get_version_info().string, OS.get_processor_name(), THRESHOLD_USEC / 1000.0,
	])

	var solver := SectorSolver.new(library, size)
	var real: Array[Row] = []
	for sector in sectors:
		real.append(_real_row(library, rasteriser, sector, seed, solver))
	_print_table("Real pipeline (records, domains, solve)", real)

	var free: Array[Row] = []
	for sector in sectors:
		free.append(_free_row(solver.solve(seed, sector), sector))
	_print_table("Unconstrained %d³ solves (same sectors and seeds, no domains)" % n, free)

	var composed: Array[Row] = []
	if boundaries:
		var boundary := SectorBoundaries.new(library, seed, rasteriser)
		for sector in sectors:
			boundary.clear_cache()
			composed.append(_boundary_row(boundary, rasteriser, sector, seed))
		_print_table("Face-first boundaries, cold (SectorBoundaries.solve_sector)", composed)

	print("")
	print("### Summary")
	print("")
	print("| Run | Searched | Mean time | Max time | Mean attempts | Contradictions | Degraded | Failed before an attempt |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- |")
	_print_summary("real pipeline", real)
	_print_summary("unconstrained", free)
	if boundaries:
		_print_summary("boundaries, cold", composed)
	print("")
	var verdict_rows := real if _searched(real) > 0 else free
	var verdict_name := "real pipeline" if _searched(real) > 0 else "unconstrained solves (no real sector ran an attempt)"
	var mean := _mean_usec(verdict_rows)
	print("**Verdict:** mean %.0f ms per stratum sector over %d searched, %s: %s the 1 s threshold of #138, %s." % [
		mean / 1000.0, _searched(verdict_rows), verdict_name,
		"above" if mean > THRESHOLD_USEC else "within",
		"port SectorSolver.solve() to a native extension" if mean > THRESHOLD_USEC else "keep the solver in typed GDScript",
	])
	quit(0)


## The first `count` stratum sectors walking shells outwards from the origin.
static func _stratum_sectors(graph: WalkableGraph, seed: int, count: int) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	for radius in MAX_RADIUS + 1:
		for z in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				for x in range(-radius, radius + 1):
					if maxi(absi(x), maxi(absi(y), absi(z))) != radius:
						continue
					var sector := Vector3i(x, y, z)
					if graph.skeleton.sector_type(seed, sector) != Skeleton.SectorType.STRATUM:
						continue
					found.append(sector)
					if found.size() == count:
						return found
	return found


static func _real_row(library: TileLibrary, rasteriser: EdgeRasteriser, sector: Vector3i, seed: int, solver: SectorSolver) -> Row:
	var run := SolverSectorRun.run(library, rasteriser, sector, seed, solver)
	if not run.error.is_empty():
		var rejected := Row.new()
		rejected.sector = sector
		rejected.records = run.records.size()
		rejected.outcome = "rejected"
		rejected.failed_early = true
		rejected.time_usec = run.domains_usec
		rejected.note = run.error
		return rejected
	var row := _free_row(run.result, sector)
	row.records = run.records.size()
	row.time_usec += run.domains_usec
	return row


static func _free_row(result: SectorSolver.Result, sector: Vector3i) -> Row:
	var row := Row.new()
	row.sector = sector
	row.outcome = SectorSolver.OUTCOME_NAMES[result.outcome]
	row.attempts = result.attempts
	row.restarts = result.restarts
	row.searched = result.attempts > 0
	row.degraded = result.outcome == SectorSolver.Outcome.DEGRADED
	row.failed_early = result.outcome == SectorSolver.Outcome.FAILED
	row.steps = result.steps
	row.propagations = result.propagations
	row.time_usec = result.time_usec
	row.note = result.error
	return row


static func _boundary_row(boundary: SectorBoundaries, rasteriser: EdgeRasteriser, sector: Vector3i, seed: int) -> Row:
	var started := Time.get_ticks_usec()
	var result := boundary.solve_sector(seed, sector)
	var row := Row.new()
	row.time_usec = Time.get_ticks_usec() - started
	row.sector = sector
	row.records = rasteriser.records_for_sector(sector).size()
	row.outcome = "solved" if result.solved else "%d degraded, %d failed pieces" % [result.degraded, result.failed]
	row.degraded = result.degraded > 0
	row.failed_early = result.failed > 0
	for piece in result.pieces:
		row.attempts += piece.attempts
		row.restarts += maxi(piece.attempts - 1, 0) if piece.outcome == SectorSolver.Outcome.SOLVED else piece.attempts
		row.steps += piece.steps
		row.propagations += piece.propagations
		row.searched = row.searched or piece.attempts > 0
	row.note = "interior %s after %d attempt(s); corner/edge/face/interior %s ms" % [
		SectorSolver.OUTCOME_NAMES[result.interior.outcome], result.interior.attempts,
		" / ".join(PackedStringArray(Array(result.level_usec).map(func(usec: int) -> String: return "%.0f" % (usec / 1000.0)))),
	]
	if not result.errors.is_empty():
		row.note += "; %s" % result.errors[0]
	return row


static func _print_table(title: String, rows: Array[Row]) -> void:
	print("")
	print("### %s" % title)
	print("")
	print("| Sector | Records | Outcome | Attempts | Steps | Propagations | Time | Note |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- |")
	for row in rows:
		print("| (%d, %d, %d) | %d | %s | %d | %d | %d | %.0f ms | %s |" % [
			row.sector.x, row.sector.y, row.sector.z, row.records, row.outcome, row.attempts,
			row.steps, row.propagations, row.time_usec / 1000.0, row.note.replace("|", "\\|"),
		])


static func _print_summary(name: String, rows: Array[Row]) -> void:
	var searched := _searched(rows)
	var attempts := 0
	var contradictions := 0
	var degraded := 0
	var failed := 0
	var max_usec := 0
	for row in rows:
		contradictions += row.restarts
		degraded += int(row.degraded)
		failed += int(row.failed_early)
		if row.searched:
			attempts += row.attempts
			max_usec = maxi(max_usec, row.time_usec)
	if searched == 0:
		print("| %s | 0 of %d | – | – | – | %d | %d | %d |" % [name, rows.size(), contradictions, degraded, failed])
		return
	print("| %s | %d of %d | %.0f ms | %.0f ms | %.2f | %d | %d | %d |" % [
		name, searched, rows.size(), _mean_usec(rows) / 1000.0, max_usec / 1000.0,
		float(attempts) / searched, contradictions, degraded, failed,
	])


static func _searched(rows: Array[Row]) -> int:
	var searched := 0
	for row in rows:
		searched += int(row.searched)
	return searched


## Mean time over the rows that ran an attempt, in microseconds.
static func _mean_usec(rows: Array[Row]) -> float:
	var total := 0
	for row in rows:
		if row.searched:
			total += row.time_usec
	return float(total) / maxi(_searched(rows), 1)
