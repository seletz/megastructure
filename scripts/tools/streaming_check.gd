extends SceneTree
## Walks a frozen `Player` capsule through the streamed world in a straight
## line and checks `SectorStreamer`'s load, unload, cache, collision and
## frame budget on the placeholder tileset.
##
## Setup: a `SectorJobs`, a `SectorStreamer` (`--radius`, default 1) and a
## `Player` with `walking` off, whose feet are the streamer's focus. The walk
## runs along +x through the centres of sectors (x, 0, 0), 4 m per step:
##
## 1. Start in sector 0 and wait until everything is placed and all collision
##    added (the first placements; frames before this are not timed).
## 2. Warm-up: walk to sector 1 and back to sector 0, then settle. The loaded
##    set is now sectors x = -1..2 (within `radius` of sector 0, plus the
##    hysteresis slab at x = 2): the baseline of `Performance.MEMORY_STATIC`,
##    `OBJECT_COUNT` and `OBJECT_NODE_COUNT`.
## 3. Walk out to sector `--sectors` (default 10) and back to sector 0, then
##    settle and compare with the baseline: the same sectors are loaded, so
##    memory and objects must be within 10 % and the node count equal.
##
## A step is taken only once the streamer has placed everything within
## `radius` (collision chunks may still be coming) and the collision around
## the next position is there. Checked:
##
## - every frame after the first placements: the player's sector is placed
##   and the collision around its feet is there (no hole to fall through);
##   no frame's wall time exceeds 33 ms (headless frames run back to back:
##   the frame pacing sleep is switched off);
## - at every step, once loading is done: the player's sector and its 6 face
##   neighbours are placed, every sector within `radius` is placed, and no
##   placed sector is farther than `radius` + 1;
## - walking back re-enters cached sectors: cache hits and no new solves for
##   sectors solved on the way out.
##
## Prints the loaded-sector timeline (one line per sector boundary crossed
## and per settle), the longest frame, frames over 16 ms, the longest
## placement, unload and streamer update, and the memory table.
##
##     godot --headless --path . --script res://scripts/tools/streaming_check.gd -- [--sectors N] [--radius R] [--seed N]
##
## Run with `mise run streaming-check [--quick]`; `--quick` walks 2 sectors.

const TILESET := "res://resources/tilesets/placeholder.tres"
const STEP_METRES := 4.0
const MAX_FRAME_USEC := 33000
const MEMORY_TOLERANCE := 0.10
## Frames waited after settling before reading memory, so queued frees run.
const FLUSH_FRAMES := 10
const TIMEOUT_USEC := 1200 * 1000000
const SLOW_FRAMES_SHOWN := 12

enum Phase { FIRST, WARM_OUT, WARM_BACK, BASELINE, OUT, BACK, FINAL, DONE }

var _failures := 0
var _seed := 0
var _radius := 1
var _sectors := 10
var _library: TileLibrary
var _jobs: SectorJobs
var _streamer: SectorStreamer
var _player: Player
var _sector_size := 48.0
var _phase := Phase.FIRST
var _target_x := 0.0
var _started_usec := 0
var _last_frame_usec := 0
var _timing := false
var _frames := 0
var _longest_frame_usec := 0
var _longest_frame_at := ""
var _frames_over_16 := 0
var _frames_over_limit := 0
## One line per frame over 16 ms, the first `SLOW_FRAMES_SHOWN`.
var _slow_frames := PackedStringArray()
var _hole_frames := 0
var _hole_first := ""
var _step_failures := 0
var _flush := 0
var _last_sector := Vector3i.ZERO
var _placed_since := 0
var _unloaded_since := 0
var _baseline := {}
var _solved_before_back := 0
var _cache_hits_before_back := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if i + 1 < args.size() and args[i + 1].is_valid_int() and args[i] in ["--sectors", "--radius", "--seed"]:
			match args[i]:
				"--sectors": _sectors = maxi(int(args[i + 1]), 2)
				"--radius": _radius = clampi(int(args[i + 1]), 1, SectorStreamer.MAX_RADIUS)
				"--seed": _seed = int(args[i + 1])
			i += 2
			continue
		printerr("streaming check: unexpected argument '%s'; usage: [--sectors N] [--radius R] [--seed N]" % args[i])
		quit(1)
		return
	# Headless paces frames with this sleep; without it a frame's wall time is
	# the work done in it.
	OS.low_processor_usage_mode_sleep_usec = 1
	_library = TileLibrary.build(load(TILESET) as TileSet3D)
	_jobs = SectorJobs.new()
	root.add_child(_jobs)
	_streamer = SectorStreamer.new()
	_streamer.radius = _radius
	root.add_child(_streamer)
	_player = Player.new()
	_player.walking = false
	root.add_child(_player)
	_streamer.sector_placed.connect(func(_sector: Vector3i, _result: Dictionary) -> void: _placed_since += 1)
	_streamer.sector_unloaded.connect(func(_sector: Vector3i) -> void: _unloaded_since += 1)
	_streamer.start(_jobs, _library, _seed)
	_sector_size = WalkableGraph.new(_seed).cells_per_sector() * WalkableGraph.CELL_SIZE
	_player.teleport(_centre(0))
	_streamer.focus_position = _player.global_position
	_last_sector = _streamer.sector_of(_player.global_position)
	_started_usec = Time.get_ticks_usec()
	print("streaming check: seed %d, radius %d, walk %d sectors along +x, %d CPUs, %d tasks in flight, budget %.1f ms, chunks of %d³ cells, cache %d" % [
		_seed, _radius, _sectors, OS.get_processor_count(), _jobs.max_in_flight, _streamer.frame_budget_usec / 1000.0,
		_streamer.collision_chunk_cells, _streamer.cache_size,
	])
	print("")
	print("| t (s) | frame | event | player sector | placed | +placed | -freed | requested | solved | cache hits | collision pending |")
	print("| ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")


func _process(_delta: float) -> bool:
	if _phase == Phase.DONE:
		return true
	if _streamer == null:
		return false
	var now := Time.get_ticks_usec()
	if _timing and _last_frame_usec > 0:
		var frame := now - _last_frame_usec
		_frames += 1
		if frame > _longest_frame_usec:
			_longest_frame_usec = frame
			_longest_frame_at = "t %.1f s, player sector %s, phase %s" % [(now - _started_usec) / 1000000.0, _streamer.sector_of(_player.global_position), Phase.keys()[_phase]]
		if frame > 16000:
			_frames_over_16 += 1
			if _slow_frames.size() < SLOW_FRAMES_SHOWN:
				# The streamer and jobs figures are from the previous frame's
				# update, the one this interval measured.
				_slow_frames.append("| %.1f | %s | %.1f | %.1f | %d | %d | %d | %.1f | %.1f |" % [
					frame / 1000.0, _streamer.focus_sector, _streamer.last_update_usec / 1000.0, _streamer.last_refresh_usec / 1000.0,
					_streamer.last_unloads, _streamer.last_places, _streamer.last_chunks, _jobs.last_poll_usec / 1000.0,
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				])
		if frame > MAX_FRAME_USEC:
			_frames_over_limit += 1
	_last_frame_usec = now
	if now - _started_usec > TIMEOUT_USEC:
		_expect(false, "the walk finishes within %d s (phase %s)" % [TIMEOUT_USEC / 1000000, Phase.keys()[_phase]])
		_finish()
		return true

	var sector := _streamer.sector_of(_player.global_position)
	if _timing and not (_streamer.is_loaded(sector) and _streamer.is_collision_ready_at(_player.global_position)):
		_hole_frames += 1
		if _hole_first.is_empty():
			_hole_first = "at %s in sector %s (placed %s)" % [_player.global_position, sector, _streamer.is_loaded(sector)]
	if sector != _last_sector:
		_row("enter")
		_last_sector = sector

	match _phase:
		Phase.FIRST:
			if _streamer.is_settled():
				_row("first placements done")
				_timing = true
				_last_frame_usec = Time.get_ticks_usec()
				_streamer.max_update_usec = 0
				_streamer.max_refresh_usec = 0
				_streamer.max_place_usec = 0
				_streamer.max_unload_usec = 0
				_jobs.reset_poll_stats()
				_set_target(1, Phase.WARM_OUT)
		Phase.WARM_OUT:
			if _walk():
				_set_target(0, Phase.WARM_BACK)
		Phase.WARM_BACK:
			if _walk():
				_phase = Phase.BASELINE
				_flush = 0
		Phase.BASELINE:
			if _settle_and_flush():
				_row("baseline")
				_baseline = _measure()
				_set_target(_sectors, Phase.OUT)
		Phase.OUT:
			if _walk():
				_solved_before_back = _streamer.solved_count
				_cache_hits_before_back = _streamer.cache_hits
				_set_target(0, Phase.BACK)
		Phase.BACK:
			if _walk():
				_phase = Phase.FINAL
				_flush = 0
		Phase.FINAL:
			if _settle_and_flush():
				_row("final")
				_verify()
				_finish()
				return true
	return false


func _centre(x: int) -> Vector3:
	return Vector3((x + 0.5) * _sector_size, 0.5 * _sector_size, 0.5 * _sector_size)


func _set_target(x: int, phase: Phase) -> void:
	_target_x = _centre(x).x
	_phase = phase


## Takes one step towards the target once loading is done and the collision
## ahead is there; checks the step's sectors first. True on arrival with
## loading done.
func _walk() -> bool:
	_streamer.focus_position = _player.global_position
	if not _streamer.is_loading_done():
		return false
	_check_step()
	var position := _player.global_position
	if is_equal_approx(position.x, _target_x):
		return true
	var next := position
	next.x = move_toward(position.x, _target_x, STEP_METRES)
	if not _streamer.is_collision_ready_at(next) or not _streamer.is_loaded(_streamer.sector_of(next)):
		return false
	_player.teleport(next)
	_streamer.focus_position = next
	return false


func _settle_and_flush() -> bool:
	_streamer.focus_position = _player.global_position
	if not _streamer.is_settled():
		_flush = 0
		return false
	_flush += 1
	return _flush > FLUSH_FRAMES


## The player's sector and its 6 face neighbours are placed, all of `radius`
## is placed and nothing beyond `radius` + 1 is.
func _check_step() -> void:
	var sector := _streamer.focus_sector
	var missing: Array[Vector3i] = []
	for step in SectorMultiMesh.STEPS + [Vector3i.ZERO]:
		if not _streamer.is_loaded(sector + step):
			missing.append(sector + step)
	for z in range(-_radius, _radius + 1):
		for y in range(-_radius, _radius + 1):
			for x in range(-_radius, _radius + 1):
				var s := sector + Vector3i(x, y, z)
				if not _streamer.is_loaded(s) and not missing.has(s):
					missing.append(s)
	var far: Array[Vector3i] = []
	for s: Vector3i in _streamer.placed:
		if SectorStreamer.distance(s, sector) > _radius + 1:
			far.append(s)
	if not missing.is_empty() or not far.is_empty():
		_step_failures += 1
		if _step_failures <= 5:
			_expect(false, "at %s: sectors within radius %d not placed %s, placed beyond %d %s" % [_player.global_position, _radius, missing, _radius + 1, far])


func _measure() -> Dictionary:
	return {
		"memory": Performance.get_monitor(Performance.MEMORY_STATIC),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"placed": _streamer.placed.keys(),
	}


func _row(event: String) -> void:
	print("| %.1f | %d | %s | %s | %d | %d | %d | %d | %d | %d | %d |" % [
		(Time.get_ticks_usec() - _started_usec) / 1000000.0, Engine.get_process_frames(), event,
		_streamer.sector_of(_player.global_position), _streamer.placed.size(), _placed_since, _unloaded_since,
		_streamer.requested_count(), _streamer.solved_count, _streamer.cache_hits, _streamer.collision_pending_count(),
	])
	_placed_since = 0
	_unloaded_since = 0


func _verify() -> void:
	var final := _measure()
	print("")
	_expect(_step_failures == 0, "at every step the player's sector, its 6 face neighbours and all sectors within radius %d are placed and none beyond %d (%d failing steps)" % [_radius, _radius + 1, _step_failures])
	_expect(_hole_frames == 0, "every frame the player's sector is placed and the collision around its feet is there (%d frames without%s)" % [_hole_frames, "" if _hole_first.is_empty() else ", first " + _hole_first])
	var same_set := (final.placed as Array).size() == (_baseline.placed as Array).size()
	for s: Vector3i in final.placed:
		same_set = same_set and (_baseline.placed as Array).has(s)
	_expect(same_set, "after walking back the same %d sectors are placed as at the baseline (%d now)" % [(_baseline.placed as Array).size(), (final.placed as Array).size()])
	_expect(_streamer.solved_count == _solved_before_back, "walking back solves nothing: every sector comes from the cache (%d solves before, %d after, %d cache hits on the way back)" % [
		_solved_before_back, _streamer.solved_count, _streamer.cache_hits - _cache_hits_before_back])
	_expect(_streamer.cache_hits > _cache_hits_before_back, "walking back hits the cache")
	_expect(_streamer.unloaded_count > 0, "sectors beyond radius + 1 were freed (%d unloads)" % _streamer.unloaded_count)
	print("")
	print("| measure | baseline | after walking back | change |")
	print("| --- | ---: | ---: | ---: |")
	for key: String in ["memory", "objects", "nodes"]:
		var before: float = _baseline[key]
		var after: float = final[key]
		print("| %s | %s | %s | %+.1f %% |" % [key, _amount(key, before), _amount(key, after), (after - before) / maxf(before, 1.0) * 100.0])
	print("")
	_expect(absf(final.memory - _baseline.memory) <= MEMORY_TOLERANCE * _baseline.memory, "static memory returns to within %d %% of the baseline" % roundi(MEMORY_TOLERANCE * 100))
	_expect(absf(final.objects - _baseline.objects) <= MEMORY_TOLERANCE * _baseline.objects, "object count returns to within %d %% of the baseline" % roundi(MEMORY_TOLERANCE * 100))
	_expect(final.nodes == _baseline.nodes, "node count returns to the baseline")
	_expect(_frames_over_limit == 0, "no frame after the first placements takes over %d ms (%d of %d frames did)" % [MAX_FRAME_USEC / 1000, _frames_over_limit, _frames])
	print("longest frame %.1f ms (%s); %d of %d frames over 16 ms" % [_longest_frame_usec / 1000.0, _longest_frame_at, _frames_over_16, _frames])
	if not _slow_frames.is_empty():
		print("")
		print("| frame ms | focus sector | streamer update ms | refresh ms | freed | placed | chunks | jobs poll ms | physics ms |")
		print("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
		for line in _slow_frames:
			print(line)
		print("")
	print("streamer after the first placements: longest update %.1f ms, refresh %.1f ms, placement %.1f ms, unload %.1f ms; %d placed, %d freed, %d solved, %d cache hits; longest jobs poll %.1f ms" % [
		_streamer.max_update_usec / 1000.0, _streamer.max_refresh_usec / 1000.0, _streamer.max_place_usec / 1000.0, _streamer.max_unload_usec / 1000.0,
		_streamer.placed_count, _streamer.unloaded_count, _streamer.solved_count, _streamer.cache_hits, _jobs.max_poll_usec / 1000.0,
	])


static func _amount(key: String, value: float) -> String:
	return "%.1f MB" % (value / 1048576.0) if key == "memory" else "%d" % int(value)


func _finish() -> void:
	_phase = Phase.DONE
	_streamer.clear()
	_jobs.clear()
	_jobs.wait_all()
	if _failures > 0:
		printerr("streaming check: %d failure(s)" % _failures)
		quit(1)
	else:
		print("streaming check: ok")
		quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
		return
	_failures += 1
	printerr("  FAIL  %s" % message)
