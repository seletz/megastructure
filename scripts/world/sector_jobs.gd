class_name SectorJobs
extends Node
## Solves sectors on the `WorkerThreadPool` and hands each result back to the
## main thread as plain data.
##
##     var jobs := SectorJobs.new()
##     add_child(jobs)
##     jobs.configure(TileLibrary.build(load("res://resources/tilesets/placeholder.tres")), seed)
##     jobs.sector_ready.connect(func(result: Dictionary) -> void: print(result.sector, " ", result.outcome))
##     jobs.focus = player_sector
##     jobs.request(Vector3i(3, 0, 7))
##
## `request` only queues a sector. Every `poll` (called from `_process`)
## waits on the tasks that completed, emits `sector_ready` for each result
## that was not cancelled, and starts queued sectors, nearest to `focus`
## first, while fewer than `max_in_flight` run. A task never blocks: the
## main thread only calls `WorkerThreadPool.wait_for_task_completion` on ids
## `is_task_completed` already reported, so waiting returns at once, and every
## id is waited exactly once (`tasks_waited` catches up with `tasks_started`).
##
## A task runs the whole pipeline for one sector on instances of its own:
## a `Skeleton` and a `WalkableGraph` (whose face cache it writes), an
## `EdgeRasteriser`, then `SectorDomains` and a `SectorSolver`, or with
## `use_boundaries` a cold `SectorBoundaries`. The only objects tasks share
## are read-only after `configure`: the `TileLibrary`, a private copy of
## the `SectorGrammar` and the tile faces `SectorMultiMesh.prototype_faces`
## read from the meshes on the main thread. With `build_placement` a task
## that solved also builds the sector's MultiMesh buffers and collision faces
## (`SectorMultiMesh.build`), so the main thread only makes nodes. The result dictionary is built on the worker, pushed
## into a mutex-protected outbox keyed by job id and taken out by the main
## thread after the wait. Its fields are in `solve_sector`; the pipeline,
## thread-safety rules and cancellation are in docs/algorithms/sector-jobs.md.

## Emitted on the main thread, from `poll`, once per finished sector that was
## not cancelled. See `solve_sector` for the fields.
signal sector_ready(result: Dictionary)


## One requested sector. Its fields are written on the main thread before the
## task starts and only read by the task.
class Job:
	extends RefCounted
	var id := 0
	var sector := Vector3i.ZERO
	## WorkerThreadPool task id, -1 while queued.
	var task_id := -1
	## Main-thread flag; the task sees cancellation through the outbox.
	var cancelled := false
	var library: TileLibrary
	var grammar: SectorGrammar
	var seed := 0
	var boundaries := false
	## `SectorMultiMesh.prototype_faces`, or an empty Array for no placement.
	var faces := []
	var outbox: Outbox

	## Runs on a worker thread.
	func run() -> void:
		var result := SectorJobs.solve_sector(library, grammar, seed, sector, boundaries, outbox.is_cancelled.bind(id), faces)
		outbox.push(id, result)


## Results travelling from the workers to the main thread, the ids of the
## jobs that pushed one, and the ids the main thread cancelled, all behind one
## mutex.
class Outbox:
	extends RefCounted
	var _mutex := Mutex.new()
	## Job id -> result dictionary.
	var _results := {}
	## Ids pushed since the last `drain`, in push order.
	var _finished := PackedInt64Array()
	## Job id -> true.
	var _cancelled := {}

	## The last thing a task does.
	func push(id: int, result: Dictionary) -> void:
		_mutex.lock()
		_results[id] = result
		_finished.append(id)
		_mutex.unlock()

	## Ids pushed since the last call.
	func drain() -> PackedInt64Array:
		_mutex.lock()
		var ids := _finished
		_finished = PackedInt64Array()
		_mutex.unlock()
		return ids

	func take(id: int) -> Dictionary:
		_mutex.lock()
		var result: Dictionary = _results.get(id, {})
		_results.erase(id)
		_cancelled.erase(id)
		_mutex.unlock()
		return result

	func cancel(id: int) -> void:
		_mutex.lock()
		_cancelled[id] = true
		_mutex.unlock()

	func is_cancelled(id: int) -> bool:
		_mutex.lock()
		var cancelled := _cancelled.has(id)
		_mutex.unlock()
		return cancelled


## Tiles of every task; set by `configure`.
var library: TileLibrary
## World seed and solve seed of every task started from now on.
var world_seed := 0
## Solve through `SectorBoundaries` (cold, one instance per task) instead of
## `SectorDomains` and one `SectorSolver`; applies to tasks started from now on.
var use_boundaries := false
## Tasks that solve also build `SectorMultiMesh` placement data into the
## result's `placement`; applies to tasks started from now on.
var build_placement := false
## Most tasks running at once, cancelled ones included. The default is half
## the logical CPUs: with one task per logical CPU but one, polls on an
## 8-core, 16-thread CPU blocked up to 9 ms instead of under 1 ms at the same
## throughput (decision #168).
var max_in_flight := default_max_in_flight()
## Queued sectors start nearest to this sector first (squared distance in
## sector units, then request order).
var focus := Vector3i.ZERO
## Passed to `WorkerThreadPool.add_task`. Low-priority tasks only get a share
## of the pool (`threading/worker_pool/low_priority_thread_ratio`), so the
## default is high priority, bounded by `max_in_flight`.
var high_priority := true
## A poll starts no further task once it has run this long, in microseconds;
## it always starts at least one when a slot is free. Starting a task wakes a
## pool thread, which can cost the main thread a millisecond or more on a
## loaded machine.
var start_budget_usec := 1000
## Tasks started and waited on since construction.
var tasks_started := 0
var tasks_waited := 0
## Wall time of the last `poll` and the longest since `reset_poll_stats`,
## without the `sector_ready` handlers, in microseconds.
var last_poll_usec := 0
var max_poll_usec := 0

var _grammar: SectorGrammar
## `SectorMultiMesh.prototype_faces(library)`, read once in `configure`.
var _faces := []
var _outbox := Outbox.new()
var _next_id := 0
## Queued jobs, in request order.
var _pending: Array[Job] = []
## Job id -> started job not yet waited on, cancelled ones included, in
## start order.
var _in_flight := {}
## Jobs that pushed their result but whose task was not yet reported
## completed.
var _completing: Array[Job] = []
## Sector -> its queued or running job that is not cancelled.
var _by_sector := {}


func _process(_delta: float) -> void:
	poll()


func _exit_tree() -> void:
	clear()
	wait_all()


## Sets the library, seed and grammar of the tasks started from now on and
## cancels everything queued or running. The grammar (default: a new
## `SectorGrammar`) is copied, so later edits to the caller's resource never
## reach a running task; call `configure` again after changing it.
func configure(tile_library: TileLibrary, seed := 0, grammar: SectorGrammar = null) -> void:
	clear()
	library = tile_library
	world_seed = seed
	_faces = SectorMultiMesh.prototype_faces(tile_library) if tile_library != null and tile_library.errors.is_empty() else []
	_grammar = grammar.duplicate() as SectorGrammar if grammar != null else SectorGrammar.new()


## Queues `sector`. Returns false when it is already queued or running (and
## not cancelled) or when `configure` was never called.
func request(sector: Vector3i) -> bool:
	if library == null or _grammar == null:
		push_error("SectorJobs: request(%s) before configure()" % sector)
		return false
	if _by_sector.has(sector):
		return false
	var job := Job.new()
	job.id = _next_id
	_next_id += 1
	job.sector = sector
	_pending.append(job)
	_by_sector[sector] = job
	return true


## Drops `sector` from the queue, or marks its running task cancelled: the
## task skips its solve when it has not started it yet, is still waited on,
## and its result is discarded. Returns false when the sector was neither
## queued nor running.
func cancel(sector: Vector3i) -> bool:
	var job: Job = _by_sector.get(sector)
	if job == null:
		return false
	_by_sector.erase(sector)
	if job.task_id < 0:
		_pending.erase(job)
	else:
		job.cancelled = true
		_outbox.cancel(job.id)
	return true


## Cancels every queued and running sector.
func clear() -> void:
	for sector: Vector3i in _by_sector.keys():
		cancel(sector)


## Whether `sector` is queued or running and not cancelled.
func has_sector(sector: Vector3i) -> bool:
	return _by_sector.has(sector)


func pending_count() -> int:
	return _pending.size()


## Started tasks not yet waited on, cancelled ones included.
func in_flight_count() -> int:
	return _in_flight.size()


## Sectors of the running tasks that are not cancelled, in start order.
func running_sectors() -> Array[Vector3i]:
	var sectors: Array[Vector3i] = []
	for job: Job in _in_flight.values():
		if not job.cancelled:
			sectors.append(job.sector)
	return sectors


## True while anything is queued or running.
func is_busy() -> bool:
	return not _pending.is_empty() or not _in_flight.is_empty()


func reset_poll_stats() -> void:
	last_poll_usec = 0
	max_poll_usec = 0


## `SectorMultiMesh.prototype_faces` of `library`, read in `configure`.
func faces() -> Array:
	return _faces


## Half the logical CPUs, at least 1.
static func default_max_in_flight() -> int:
	return maxi(OS.get_processor_count() / 2, 1)


## Waits on the tasks that pushed a result, starts queued sectors and emits
## `sector_ready` for the finished ones. Never blocks on a running task, and
## only asks the pool about tasks that already pushed their result, so a
## frame in which nothing finished costs one mutex lock.
func poll() -> void:
	var started := Time.get_ticks_usec()
	for id in _outbox.drain():
		_completing.append(_in_flight[id])
	var ready: Array[Dictionary] = []
	var i := 0
	while i < _completing.size():
		var job := _completing[i]
		# The task returns right after its push; if it has not yet, next poll.
		if not WorkerThreadPool.is_task_completed(job.task_id):
			i += 1
			continue
		_completing.remove_at(i)
		var result := _wait(job)
		if not job.cancelled:
			ready.append(result)
	_start_pending(started)
	last_poll_usec = Time.get_ticks_usec() - started
	max_poll_usec = maxi(max_poll_usec, last_poll_usec)
	for result in ready:
		sector_ready.emit(result)


## Blocks until every started task finished and was waited on; results of
## tasks that were not cancelled are emitted. For shutdown and tools.
func wait_all() -> void:
	var ready: Array[Dictionary] = []
	for job: Job in _in_flight.values():
		var result := _wait(job)
		if not job.cancelled:
			ready.append(result)
	_outbox.drain()
	_completing.clear()
	for result in ready:
		sector_ready.emit(result)


## The whole pipeline for one sector, on any thread, touching nothing but its
## arguments (read only) and instances it creates. `cancelled`, when valid,
## is asked before the domains and before the solve; once it returns true the
## result has `cancelled` true and no cells. Result fields:
##
## - `sector` (Vector3i).
## - `outcome` (`SectorSolver.Outcome`): without boundaries the solver's, or
##   FAILED when the records cannot be turned into domains; with boundaries
##   FAILED when any piece failed, else DEGRADED when any degraded, else SOLVED.
## - `cells` (PackedInt32Array): tile index per cell `x + n * (y + n * z)`;
##   empty when the solve FAILED without boundaries (with boundaries failed
##   pieces are solid, so the cells are always there).
## - `attempts` (int): solver attempts, summed over the pieces with boundaries.
## - `time_usec` (int): wall time of the whole pipeline on its thread.
## - `degraded` (bool): some or all cells are the solid fallback, not a solve.
## - `error` (String): why it failed, or "".
## - `cancelled` (bool).
## - `placement` (Dictionary): with `faces` (from
##   `SectorMultiMesh.prototype_faces`) and a SOLVED outcome,
##   `SectorMultiMesh.build` of the cells, built on this thread; else empty.
##   Its `build_usec` is not part of `time_usec`.
static func solve_sector(tile_library: TileLibrary, grammar: SectorGrammar, seed: int, sector: Vector3i, boundaries := false, cancelled := Callable(), faces := []) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := {
		"sector": sector,
		"outcome": SectorSolver.Outcome.FAILED,
		"cells": PackedInt32Array(),
		"attempts": 0,
		"time_usec": 0,
		"degraded": false,
		"error": "",
		"cancelled": false,
		"placement": {},
	}
	if cancelled.is_valid() and cancelled.call():
		return _cancelled(result, started)
	var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed, Skeleton.new(grammar)))
	if boundaries:
		var composed := SectorBoundaries.new(tile_library, seed, rasteriser).solve_sector(seed, sector)
		var attempts := 0
		for piece in composed.pieces:
			attempts += piece.attempts
		result.outcome = SectorSolver.Outcome.FAILED if composed.failed > 0 else SectorSolver.Outcome.DEGRADED if composed.degraded > 0 else SectorSolver.Outcome.SOLVED
		result.cells = composed.cells
		result.attempts = attempts
		result.degraded = not composed.solved
		result.error = "" if composed.errors.is_empty() else composed.errors[0]
	else:
		var graph := rasteriser.graph
		var n := graph.cells_per_sector()
		var size := Vector3i(n, n, n)
		var built := SectorDomains.build(tile_library, size, graph.skeleton.sector_type(seed, sector), rasteriser.records_for_sector(sector))
		if not built.error.is_empty():
			result.error = built.error
		else:
			if cancelled.is_valid() and cancelled.call():
				return _cancelled(result, started)
			var solved := SectorSolver.new(tile_library, size).solve(seed, sector, built.words)
			result.outcome = solved.outcome
			result.cells = solved.cells
			result.attempts = solved.attempts
			result.degraded = solved.degraded
			result.error = solved.error
	result.time_usec = Time.get_ticks_usec() - started
	if not faces.is_empty() and result.outcome == SectorSolver.Outcome.SOLVED:
		result.placement = SectorMultiMesh.build(tile_library, faces, result.cells)
	return result


static func _cancelled(result: Dictionary, started: int) -> Dictionary:
	result.cancelled = true
	result.time_usec = Time.get_ticks_usec() - started
	return result


## Waits on the task of `job` and returns its result.
func _wait(job: Job) -> Dictionary:
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	tasks_waited += 1
	_in_flight.erase(job.id)
	if not job.cancelled:
		_by_sector.erase(job.sector)
	return _outbox.take(job.id)


## Starts queued jobs, nearest to `focus` first, while slots are free and
## the poll that began at `poll_started` is within `start_budget_usec`.
func _start_pending(poll_started: int) -> void:
	var first := true
	while _in_flight.size() < max_in_flight and not _pending.is_empty():
		if not first and Time.get_ticks_usec() - poll_started > start_budget_usec:
			break
		first = false
		var best := 0
		var best_distance := (_pending[0].sector - focus).length_squared()
		for i in range(1, _pending.size()):
			var distance := (_pending[i].sector - focus).length_squared()
			if distance < best_distance:
				best = i
				best_distance = distance
		var job := _pending[best]
		_pending.remove_at(best)
		job.library = library
		job.grammar = _grammar
		job.seed = world_seed
		job.boundaries = use_boundaries
		job.faces = _faces if build_placement else []
		job.outbox = _outbox
		job.task_id = WorkerThreadPool.add_task(job.run, high_priority, "SectorJobs %s" % job.sector)
		tasks_started += 1
		_in_flight[job.id] = job
