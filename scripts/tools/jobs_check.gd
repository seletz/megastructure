extends SceneTree
## Checks `SectorJobs` on the placeholder tileset.
##
## Queue: with one slot, a sector near `focus` starts before one requested
## earlier but farther away; a duplicate request is refused; cancelling a
## queued sector removes it, cancelling a running one and `clear` discard
## their results, and no `sector_ready` fires for any of them.
##
## Jobs: requests the sectors of the 3³ block around the origin (the first
## `--sectors`, nearest first, default all 27) at `--seed` and polls once per
## frame from `_process`, timing every `poll` with `Time.get_ticks_usec`
## (the `sector_ready` handler only stores the result). Fails when a poll
## takes more than `MAX_POLL_USEC`, a sector is missing, reported twice or
## cancelled, or when the task ids started and waited on differ. Then solves
## every sector again synchronously on the main thread, through
## `SolverSectorRun` (or one `SectorBoundaries` with `--boundaries`), and
## fails unless outcome, attempts, degraded flag and every cell match the
## worker's result. Prints one row per sector, the poll times and the
## throughput: sectors per second, the summed worker time and the speed-up
## over the synchronous run.
##
##     godot --headless --path . --script res://scripts/tools/jobs_check.gd -- --sectors 27 [--seed N] [--workers N] [--boundaries]
##
## `--workers` sets `max_in_flight` (default `SectorJobs.default_max_in_flight`).
## Run with `mise run jobs-check [--quick] [--boundaries] [--seed N] [--workers N]`.

const TILESET := "res://resources/tilesets/placeholder.tres"
const BLOCK_SECTORS := 27
## Longest a single poll may block the main thread (issue #97).
const MAX_POLL_USEC := 4000
## Gives up when the jobs are not done after this long.
const TIMEOUT_USEC := 900 * 1000000

var _failures := 0
var _library: TileLibrary
var _jobs: SectorJobs
var _seed := 0
var _boundaries := false
var _workers := SectorJobs.default_max_in_flight()
var _sectors: Array[Vector3i] = []
## Sector -> worker result.
var _results := {}
## Results emitted by the queue checks, which must stay empty.
var _unexpected := 0
var _started_usec := 0
var _finished_usec := 0
var _polls := 0
var _poll_total_usec := 0
var _poll_max_usec := 0
var _polls_over := 0
var _done := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var count := BLOCK_SECTORS
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg == "--boundaries":
			_boundaries = true
			i += 1
			continue
		if (arg == "--seed" or arg == "--sectors" or arg == "--workers") and i + 1 < args.size() and args[i + 1].is_valid_int():
			if arg == "--seed":
				_seed = int(args[i + 1])
			elif arg == "--workers":
				_workers = int(args[i + 1])
			else:
				count = int(args[i + 1])
			i += 2
			continue
		printerr("jobs check: unexpected argument '%s'; usage: [--sectors N] [--seed N] [--workers N] [--boundaries]" % arg)
		quit(1)
		return
	if count < 1 or count > BLOCK_SECTORS or _workers < 1:
		printerr("jobs check: --sectors must be 1..%d and --workers at least 1" % BLOCK_SECTORS)
		quit(1)
		return

	_library = TileLibrary.build(load(TILESET) as TileSet3D)
	if not _library.errors.is_empty():
		_expect(false, "%s: %s" % [TILESET, _library.errors])
		quit(1)
		return
	_jobs = SectorJobs.new()
	# The check calls poll itself to time it.
	_jobs.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(_jobs)
	_jobs.configure(_library, _seed)
	_jobs.use_boundaries = _boundaries
	_jobs.max_in_flight = _workers
	print("jobs check: %s, %d tiles, seed %d, %d sectors%s, %d CPUs, %d in flight" % [
		TILESET.trim_prefix("res://"), _library.tile_count(), _seed, count,
		", boundaries" if _boundaries else "", OS.get_processor_count(), _jobs.max_in_flight,
	])

	_check_queue()

	_sectors = _block(count)
	_jobs.sector_ready.connect(_on_sector_ready)
	_jobs.focus = Vector3i.ZERO
	_started_usec = Time.get_ticks_usec()
	for sector in _sectors:
		_expect(_jobs.request(sector), "request %s is accepted" % sector, true)


func _process(_delta: float) -> bool:
	if _done or _jobs == null:
		return false
	var started := Time.get_ticks_usec()
	_jobs.poll()
	var usec := Time.get_ticks_usec() - started
	_polls += 1
	_poll_total_usec += usec
	_poll_max_usec = maxi(_poll_max_usec, usec)
	if usec > MAX_POLL_USEC:
		_polls_over += 1
	if _jobs.is_busy():
		if Time.get_ticks_usec() - _started_usec > TIMEOUT_USEC:
			_expect(false, "jobs finish within %d s (%d of %d done)" % [TIMEOUT_USEC / 1000000, _results.size(), _sectors.size()])
			_finish()
		return false
	_finished_usec = Time.get_ticks_usec()
	_verify()
	_finish()
	return false


## Priority, duplicate requests, cancellation and clear, before the timed run.
func _check_queue() -> void:
	var probe := func(_result: Dictionary) -> void: _unexpected += 1
	_jobs.sector_ready.connect(probe)
	var far := Vector3i(40, 0, 0)
	var near := Vector3i(99, 0, 0)
	_jobs.max_in_flight = 1
	_jobs.focus = Vector3i(100, 0, 0)
	_expect(_jobs.request(far), "request far sector")
	_expect(_jobs.request(near), "request near sector")
	_expect(not _jobs.request(near), "a duplicate request is refused")
	_jobs.poll()
	var running := _jobs.running_sectors()
	_expect(running.size() == 1 and running[0] == near, "the sector nearest the focus starts first (running %s)" % [running])
	_expect(_jobs.pending_count() == 1, "the farther sector stays queued")
	_expect(_jobs.cancel(far) and _jobs.pending_count() == 0 and not _jobs.has_sector(far), "cancel removes a queued sector")
	_expect(not _jobs.cancel(far), "cancelling it again reports nothing to cancel")
	_expect(_jobs.cancel(near) and not _jobs.has_sector(near) and _jobs.in_flight_count() == 1, "cancel marks a running sector and keeps its task to wait on")
	_expect(_jobs.request(near), "a cancelled sector can be requested again")
	_expect(_jobs.request(Vector3i(41, 0, 0)), "request a third sector")
	_jobs.max_in_flight = 2
	_jobs.poll()
	_jobs.clear()
	_expect(_jobs.pending_count() == 0 and _jobs.running_sectors().is_empty(), "clear empties the queue and cancels the running sectors")
	_jobs.wait_all()
	_jobs.poll()
	_expect(not _jobs.is_busy(), "nothing queued or running after clear and wait_all")
	_expect(_unexpected == 0, "no sector_ready for cancelled sectors (%d emitted)" % _unexpected)
	_expect(_jobs.tasks_started == _jobs.tasks_waited, "every started task was waited on (%d started, %d waited)" % [_jobs.tasks_started, _jobs.tasks_waited])
	_jobs.sector_ready.disconnect(probe)
	_jobs.max_in_flight = _workers


func _on_sector_ready(result: Dictionary) -> void:
	var sector: Vector3i = result.sector
	if _results.has(sector) or not _sectors.has(sector) or result.cancelled:
		_unexpected += 1
		return
	_results[sector] = result


## Compares every worker result with a synchronous solve on the main thread.
func _verify() -> void:
	var wall_usec := _finished_usec - _started_usec
	_expect(_unexpected == 0, "no duplicate, unrequested or cancelled result")
	_expect(_results.size() == _sectors.size(), "every sector reported (%d of %d)" % [_results.size(), _sectors.size()])
	_expect(_jobs.tasks_started == _jobs.tasks_waited and _jobs.in_flight_count() == 0, "every task id was waited on (%d started, %d waited)" % [_jobs.tasks_started, _jobs.tasks_waited])
	_expect(_polls_over == 0, "no poll blocks the main thread over %.1f ms (max %.3f ms, %d over)" % [MAX_POLL_USEC / 1000.0, _poll_max_usec / 1000.0, _polls_over])

	var rasteriser := EdgeRasteriser.new(WalkableGraph.new(_seed))
	var boundaries := SectorBoundaries.new(_library, _seed, rasteriser)
	var solver := SectorSolver.new(_library, Vector3i(rasteriser.graph.cells_per_sector(), rasteriser.graph.cells_per_sector(), rasteriser.graph.cells_per_sector()))
	var worker_usec := 0
	var sync_usec := 0
	var matching := 0
	var outcomes := PackedInt32Array([0, 0, 0])
	print("")
	print("| Sector | Type | Outcome | Attempts | Worker | Main thread | Same |")
	print("| --- | --- | --- | --- | --- | --- | --- |")
	for sector in _sectors:
		if not _results.has(sector):
			continue
		var result: Dictionary = _results[sector]
		var started := Time.get_ticks_usec()
		var expected := _synchronous(boundaries, rasteriser, solver, sector)
		var usec := Time.get_ticks_usec() - started
		var same: bool = (
			result.outcome == expected.outcome and result.attempts == expected.attempts
			and result.degraded == expected.degraded and result.cells == expected.cells
		)
		matching += int(same)
		worker_usec += result.time_usec
		sync_usec += usec
		outcomes[result.outcome] += 1
		print("| (%d, %d, %d) | %s | %s | %d | %.0f ms | %.0f ms | %s |" % [
			sector.x, sector.y, sector.z, Skeleton.type_name(rasteriser.graph.skeleton.sector_type(_seed, sector)),
			SectorSolver.OUTCOME_NAMES[result.outcome], result.attempts, result.time_usec / 1000.0, usec / 1000.0,
			"yes" if same else "NO",
		])
	print("")
	_expect(matching == _results.size(), "every worker result equals the main-thread solve (%d of %d)" % [matching, _results.size()])
	print("outcomes: %d solved, %d degraded, %d failed" % [outcomes[0], outcomes[1], outcomes[2]])
	print("polls: %d, mean %.3f ms, max %.3f ms (limit %.1f ms)" % [_polls, _poll_total_usec / 1000.0 / maxi(_polls, 1), _poll_max_usec / 1000.0, MAX_POLL_USEC / 1000.0])
	print("throughput: %d sectors in %.2f s = %.2f sectors/s on %d workers; summed worker time %.2f s; main thread alone %.2f s, speed-up %.1fx" % [
		_results.size(), wall_usec / 1000000.0, _results.size() / maxf(wall_usec / 1000000.0, 0.000001), _jobs.max_in_flight,
		worker_usec / 1000000.0, sync_usec / 1000000.0, float(sync_usec) / maxi(wall_usec, 1),
	])


## The same sector through the synchronous pipeline, shaped like a job result.
func _synchronous(boundaries: SectorBoundaries, rasteriser: EdgeRasteriser, solver: SectorSolver, sector: Vector3i) -> Dictionary:
	if _boundaries:
		var composed := boundaries.solve_sector(_seed, sector)
		var attempts := 0
		for piece in composed.pieces:
			attempts += piece.attempts
		var outcome := SectorSolver.Outcome.FAILED if composed.failed > 0 else SectorSolver.Outcome.DEGRADED if composed.degraded > 0 else SectorSolver.Outcome.SOLVED
		return {"outcome": outcome, "attempts": attempts, "degraded": not composed.solved, "cells": composed.cells}
	var run := SolverSectorRun.run(_library, rasteriser, sector, _seed, solver)
	if not run.error.is_empty():
		return {"outcome": SectorSolver.Outcome.FAILED, "attempts": 0, "degraded": false, "cells": PackedInt32Array()}
	return {"outcome": run.result.outcome, "attempts": run.result.attempts, "degraded": run.result.degraded, "cells": run.result.cells}


## The first `count` sectors of the 3³ block around the origin, nearest first
## (then z, y, x ascending).
static func _block(count: int) -> Array[Vector3i]:
	var sectors: Array[Vector3i] = []
	for distance in 4:
		for z in range(-1, 2):
			for y in range(-1, 2):
				for x in range(-1, 2):
					if absi(x) + absi(y) + absi(z) == distance:
						sectors.append(Vector3i(x, y, z))
	sectors.resize(count)
	return sectors


func _finish() -> void:
	_done = true
	if _failures > 0:
		printerr("jobs check: %d failure(s)" % _failures)
		quit(1)
	else:
		print("jobs check: ok")
		quit(0)


func _expect(condition: bool, message: String, quiet := false) -> void:
	if condition:
		if not quiet:
			print("  ok    %s" % message)
		return
	_failures += 1
	printerr("  FAIL  %s" % message)
