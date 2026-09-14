extends SceneTree
## Checks `SectorSolver` on the placeholder tileset. Solves an unconstrained
## 8³ grid at seeds 0 to 4 and fails unless every solve succeeds, a second
## solver instance returns byte-identical cells, every face adjacency in the
## result is allowed, and the seed 0 cells hash to the SHA-256 recorded in
## docs/solver_reference_seed0.md. Also checks the Shannon entropy flag the
## same way, that a `domains` restriction holds in the result and that an
## unsatisfiable one fails, then prints the tile histogram, steps and time
## per seed and the time of a 24³ solve with restarts.
##
## Restarts and pre-collapse: seed 1502 fails its first 8³ attempt, so it
## degrades to all solid with one attempt allowed and solves on the second
## by default, the same on a second instance. Records that cannot hold
## fail fast with a clear error, in `SectorDomains` (two records, a bad
## orientation, a record outside the grid, face-neighbour records with no
## allowed pair) and in the solver (records whose propagation empties a cell
## between them). Consistent records on an 8³ stratum grid, with headroom
## above the walk, hold in every solved result over seeds 0 to 9, the
## placeholder's headroom tiles are air, the wall doorway, the vaults and the
## stairwells (#182), and fixed faces
## restrict the boundary cells. Last, `REAL_SECTORS` real stratum sectors and
## `REAL_VOID_SECTORS` shaft, cavity and chasm sectors each at seed 0 run
## through the whole pipeline; every solved one must keep its records and
## adjacencies and hold walk-family tiles only in record cells (#180), and the
## solved, degraded and inconsistent counts and mean attempts are printed.
## Run headless with `mise run solver-check`; pass `--update` to rewrite the
## reference file instead of comparing against it.

const TILESET := "res://resources/tilesets/placeholder.tres"
const REFERENCE_PATH := "res://docs/solver_reference_seed0.md"
const SMALL := Vector3i(8, 8, 8)
const LARGE := Vector3i(24, 24, 24)
const SEEDS: Array[int] = [0, 1, 2, 3, 4]
## With `--quick` (the `check` tier): 8³ solves at these seeds only, and no
## 24³ solve or real sectors.
const QUICK_SEEDS: Array[int] = [0, 1]
const SECTOR := Vector3i.ZERO
## An 8³ seed whose attempts before RESTART_ATTEMPTS hit a contradiction.
const RESTART_SEED := 1502
## The attempt RESTART_SEED solves at.
const RESTART_ATTEMPTS := 2
## Real stratum sectors the pipeline runs at seed 0.
const REAL_SECTORS := 20
## Real sectors of each void type (shaft, cavity, chasm) the pipeline runs at
## seed 0.
const REAL_VOID_SECTORS := 2
const REAL_RANGE := 1000
## Salt for picking the real sectors; outside the grammar's salt range.
const SALT_TEST_SOLVER := 905

var _failures := 0


func _init() -> void:
	var update := "--update" in OS.get_cmdline_user_args()
	var quick := "--quick" in OS.get_cmdline_user_args()
	var library := TileLibrary.build(load(TILESET) as TileSet3D)
	if not library.errors.is_empty():
		_expect(false, "%s: %s" % [TILESET, library.errors])
		quit(1)
		return
	print("solver check: %s, %d tiles, %d word(s)" % [TILESET.trim_prefix("res://"), library.tile_count(), library.word_count])

	var first := SectorSolver.new(library, SMALL)
	var second := SectorSolver.new(library, SMALL)
	var reference_digest := ""
	for seed in QUICK_SEEDS if quick else SEEDS:
		var result := first.solve(seed, SECTOR)
		var again := second.solve(seed, SECTOR)
		var solved := result.outcome == SectorSolver.Outcome.SOLVED
		_expect(solved and result.attempts == 1, "seed %d: 8³ solved at the first attempt%s" % [seed, "" if solved else " (%s)" % SectorSolver.OUTCOME_NAMES[result.outcome]])
		if not solved:
			continue
		_expect(result.cells == again.cells and result.steps == again.steps, "seed %d: second solver instance identical" % seed)
		_expect(_bad_adjacencies(library, first, result.cells) == 0, "seed %d: every adjacency allowed" % seed)
		print("  seed %d: %d steps, %d propagations, %.1f ms, sha256 %s" % [
			seed, result.steps, result.propagations, result.time_usec / 1000.0, _digest(result.cells).substr(0, 16),
		])
		_print_histogram(library, result.cells)
		if seed == 0:
			reference_digest = _digest(result.cells)

	_check_entropy(library)
	_check_domains(library)
	_check_restarts(library)
	_check_inconsistent(library)
	_check_consistent(library)
	_check_faces(library)

	if not reference_digest.is_empty():
		if update:
			_write_reference(reference_digest)
		else:
			_compare_reference(reference_digest)

	if not quick:
		_time_large(library)
		_run_real_sectors(library)
		_check_real_sectors_reach_an_attempt(library)

	print("solver check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


## Solves a 24³ grid at seed 0 with restarts and prints attempts and time.
## Only reports the outcome; a solved result must allow every adjacency.
func _time_large(library: TileLibrary) -> void:
	var large := SectorSolver.new(library, LARGE)
	var result := large.solve(0, SECTOR)
	print("  24³ seed 0: %s after %d attempt(s), %d steps, %d propagations, %.1f ms" % [
		SectorSolver.OUTCOME_NAMES[result.outcome], result.attempts, result.steps, result.propagations, result.time_usec / 1000.0,
	])
	if result.outcome == SectorSolver.Outcome.SOLVED:
		_expect(_bad_adjacencies(library, large, result.cells) == 0, "24³ seed 0: every adjacency allowed")


## The entropy heuristic also solves, repeats across instances and gives
## allowed adjacencies.
func _check_entropy(library: TileLibrary) -> void:
	var first := SectorSolver.new(library, SMALL)
	var second := SectorSolver.new(library, SMALL)
	first.use_entropy = true
	second.use_entropy = true
	var result := first.solve(0, SECTOR)
	var again := second.solve(0, SECTOR)
	_expect(result.ok, "entropy: 8³ seed 0 solved%s" % ("" if result.ok else " (%s)" % result.error))
	if result.ok:
		_expect(result.cells == again.cells, "entropy: second solver instance identical")
		_expect(_bad_adjacencies(library, first, result.cells) == 0, "entropy: every adjacency allowed")
		print("  entropy seed 0: %d steps, %.1f ms" % [result.steps, result.time_usec / 1000.0])


## A cell restricted to solid holds solid, and a floor restricted to sit
## directly on air (a floor needs solid below) fails.
func _check_domains(library: TileLibrary) -> void:
	var solver := SectorSolver.new(library, SMALL)
	var solid := _tile_named(library, "solid")
	var air := _tile_named(library, "air")
	var floor := _tile_named(library, "floor")
	var words := library.word_count
	var domains := PackedInt64Array()
	domains.resize(solver.cell_count() * words)
	domains.fill(-1)
	var centre := solver.index(Vector3i(4, 4, 4))
	_restrict(domains, words, centre, solid)
	var result := solver.solve(0, SECTOR, domains)
	_expect(result.ok and result.cells[centre] == solid, "domains: a cell restricted to solid holds solid")
	_expect(result.precollapsed == PackedInt32Array([centre]), "domains: the restricted cell is reported pre-collapsed")

	_restrict(domains, words, solver.index(Vector3i(4, 3, 4)), air)
	_restrict(domains, words, centre, floor)
	result = solver.solve(0, SECTOR, domains)
	_expect(not result.ok and result.outcome == SectorSolver.Outcome.FAILED and result.attempts == 0 and result.contradiction_cell >= 0, "domains: floor above air fails without an attempt (%s)" % result.error)


## Seed RESTART_SEED degrades with fewer than RESTART_ATTEMPTS attempts and
## solves at attempt RESTART_ATTEMPTS; a second instance repeats every outcome.
func _check_restarts(library: TileLibrary) -> void:
	var solver := SectorSolver.new(library, SMALL)
	var twin := SectorSolver.new(library, SMALL)
	for limit in range(1, RESTART_ATTEMPTS):
		solver.max_attempts = limit
		twin.max_attempts = limit
		var result := solver.solve(RESTART_SEED, SECTOR)
		var all_solid := result.cells.size() == solver.cell_count()
		for tile in result.cells:
			all_solid = all_solid and tile == library.solid_tile
		_expect(
			result.ok and result.degraded and result.outcome == SectorSolver.Outcome.DEGRADED
			and result.attempts == limit and result.restarts == limit and all_solid and result.error.is_empty(),
			"restarts: seed %d with %d attempt(s) degrades to all solid after %d restart(s)" % [RESTART_SEED, limit, result.restarts],
		)
		_expect(twin.solve(RESTART_SEED, SECTOR).cells == result.cells, "restarts: degraded result repeats on a second instance")
	solver.max_attempts = SectorSolver.DEFAULT_MAX_ATTEMPTS
	twin.max_attempts = SectorSolver.DEFAULT_MAX_ATTEMPTS
	var result := solver.solve(RESTART_SEED, SECTOR)
	var again := twin.solve(RESTART_SEED, SECTOR)
	_expect(
		result.outcome == SectorSolver.Outcome.SOLVED and not result.degraded and result.attempts == RESTART_ATTEMPTS and result.restarts == RESTART_ATTEMPTS - 1,
		"restarts: seed %d solves at attempt %d of %d" % [RESTART_SEED, result.attempts, solver.max_attempts],
	)
	_expect(result.cells == again.cells and result.steps == again.steps, "restarts: restarted solve repeats on a second instance")
	_expect(_bad_adjacencies(library, solver, result.cells) == 0, "restarts: every adjacency allowed after restarts")


## Records that cannot hold fail fast with an error naming the problem.
func _check_inconsistent(library: TileLibrary) -> void:
	var family := EdgeRasteriser.TileFamily
	var cases := [
		["two records at one cell", [_record(Vector3i(1, 1, 1), family.FLOOR, 0), _record(Vector3i(1, 1, 1), family.FLOOR, 0)], "a second record at the same cell"],
		["a record outside the grid", [_record(Vector3i(8, 1, 1), family.FLOOR, 0)], "cell outside the"],
		["a stair without a yaw", [_record(Vector3i(1, 1, 1), family.STAIR, EdgeRasteriser.ORIENTATION_UP)], "a stair needs a yaw"],
		["a tunnel directly over a bridge", [_record(Vector3i(2, 2, 2), family.BRIDGE, 0), _record(Vector3i(2, 3, 2), family.TUNNEL, 0)], "cannot touch across +y"],
	]
	for case in cases:
		var records: Array[EdgeRasteriser.Record] = []
		records.assign(case[1])
		var started := Time.get_ticks_usec()
		var built := SectorDomains.build(library, SMALL, Skeleton.SectorType.STRATUM, records)
		var usec := Time.get_ticks_usec() - started
		_expect(built.error.contains(case[2]) and built.words.is_empty(), "inconsistent: %s is rejected in %.1f ms: %s" % [case[0], usec / 1000.0, built.error])

	# A tunnel needs rock below and a bridge open space above, and no tile has
	# open space below and rock above: a cell of that column is empty once the
	# records propagate, before any attempt.
	var records: Array[EdgeRasteriser.Record] = [_record(Vector3i(4, 2, 4), family.BRIDGE, 0), _record(Vector3i(4, 4, 4), family.TUNNEL, 0)]
	var built := SectorDomains.build(library, SMALL, Skeleton.SectorType.STRATUM, records)
	_expect(built.error.is_empty(), "inconsistent: a bridge two cells under a tunnel passes the record checks")
	var solver := SectorSolver.new(library, SMALL)
	var result := solver.solve(0, SECTOR, built.words)
	_expect(
		result.outcome == SectorSolver.Outcome.FAILED and result.attempts == 0 and result.cells.is_empty()
		and solver.position(result.contradiction_cell) in [Vector3i(4, 2, 4), Vector3i(4, 3, 4), Vector3i(4, 4, 4)]
		and result.error.begins_with("inconsistent starting domains"),
		"inconsistent: the solver fails without an attempt in %.1f ms: %s" % [result.time_usec / 1000.0, result.error],
	)


## A floor walk, a stair run climbing +x and a portal opening on the +x face,
## with the headroom the rasteriser gives them (one cell over floor and
## portal, two over a stair), consistent on the placeholder tileset, hold in
## every solved 8³ result.
func _check_consistent(library: TileLibrary) -> void:
	var family := EdgeRasteriser.TileFamily
	var headroom := PackedStringArray()
	for tile in library.tiles:
		if tile.headroom:
			headroom.append(tile.label())
	var expected := PackedStringArray(["air@0", "wall_doorway@0", "wall_doorway@1"])
	for tile in library.tiles:
		if tile.prototype.name.begins_with("vault") or tile.prototype.name.begins_with("stairwell"):
			expected.append(tile.label())
	_expect(headroom == expected, "consistent: the headroom tiles are air, the wall doorway, the vaults and the stairwells: %s" % ", ".join(headroom))
	var records: Array[EdgeRasteriser.Record] = []
	for x in range(1, 4):
		records.append(_record(Vector3i(x, 2, 4), family.FLOOR, 0))
		records.append(_record(Vector3i(x, 3, 4), family.HEADROOM, 0))
	for k in 3:
		records.append(_record(Vector3i(4 + k, 2 + k, 4), family.STAIR, 0))
		records.append(_record(Vector3i(4 + k, 3 + k, 4), family.HEADROOM, 0))
		records.append(_record(Vector3i(4 + k, 4 + k, 4), family.HEADROOM, 0))
	records.append(_record(Vector3i(7, 5, 4), family.PORTAL_OPENING, 0))
	records.append(_record(Vector3i(7, 6, 4), family.HEADROOM, 0))
	var built := SectorDomains.build(library, SMALL, Skeleton.SectorType.STRATUM, records)
	_expect(built.error.is_empty(), "consistent: records build%s" % ("" if built.error.is_empty() else " (%s)" % built.error))
	if not built.error.is_empty():
		return
	_expect(built.record_cells.size() == records.size(), "consistent: %d record cells" % built.record_cells.size())
	var solver := SectorSolver.new(library, SMALL)
	var outcomes := PackedInt32Array([0, 0, 0])
	var broken := 0
	var bad := 0
	var outside := 0
	for seed in 10:
		var result := solver.solve(seed, SECTOR, built.words)
		outcomes[result.outcome] += 1
		if result.outcome != SectorSolver.Outcome.SOLVED:
			continue
		for record in records:
			if not SectorDomains.tile_matches(library.tiles[result.cells[solver.index(record.cell)]], record.family, record.orientation):
				broken += 1
		bad += _bad_adjacencies(library, solver, result.cells)
		outside += SolverSectorRun.count_walk_tiles_outside(library, SMALL, records, result.cells)
	_expect(outcomes[SectorSolver.Outcome.FAILED] == 0, "consistent: no solve fails (%d solved, %d degraded)" % [outcomes[0], outcomes[1]])
	_expect(outcomes[SectorSolver.Outcome.SOLVED] > 0, "consistent: at least one of seeds 0..9 solves")
	_expect(broken == 0 and bad == 0, "consistent: every solved result keeps all %d records and its adjacencies, %d broken, %d forbidden" % [records.size(), broken, bad])
	_expect(outside == 0, "consistent: no walk-family tile outside a record cell, %d found" % outside)


## A +y face of solid neighbours ANDed into free domains leaves only tiles
## with rock on top in the top layer; -1 entries stay free; the same face on
## an empty stratum, all air (#180), is an error, and so is a face of the
## wrong size.
func _check_faces(library: TileLibrary) -> void:
	var faces: Array[PackedInt32Array] = []
	for dir in TilePrototype.FACE_COUNT:
		faces.append(PackedInt32Array())
	var top := PackedInt32Array()
	top.resize(SMALL.x * SMALL.z)
	top.fill(library.solid_tile)
	top[0] = -1
	faces[TilePrototype.FACE_POS_Y] = top
	var solver := SectorSolver.new(library, SMALL)
	var words := PackedInt64Array()
	words.resize(solver.cell_count() * library.word_count)
	words.fill(-1)
	var error := SectorDomains.apply_faces(library, SMALL, words, faces)
	_expect(error.is_empty(), "faces: a solid +y face applies to free domains")
	var result := solver.solve(0, SECTOR, words)
	var rock_on_top := result.outcome == SectorSolver.Outcome.SOLVED
	for x in SMALL.x:
		for z in SMALL.z:
			if x == 0 and z == 0:
				continue
			var tile := result.cells[solver.index(Vector3i(x, SMALL.y - 1, z))] if rock_on_top else -1
			rock_on_top = rock_on_top and library.is_allowed(TilePrototype.FACE_POS_Y, tile, library.solid_tile)
	_expect(rock_on_top, "faces: every top cell but the free one allows solid above (%s)" % SectorSolver.OUTCOME_NAMES[result.outcome])
	_expect(result.precollapsed.size() == SMALL.x * SMALL.z - 1, "faces: %d fixed boundary cells pre-collapsed" % result.precollapsed.size())

	var built := SectorDomains.build(library, SMALL, Skeleton.SectorType.STRATUM, [], faces)
	_expect(built.error.contains("no tile fits next to solid@0") and built.words.is_empty(), "faces: a solid +y face over an empty stratum is an error: %s" % built.error)

	faces[TilePrototype.FACE_POS_Y] = PackedInt32Array([library.solid_tile])
	built = SectorDomains.build(library, SMALL, Skeleton.SectorType.STRATUM, [], faces)
	_expect(built.error.contains("expected 64"), "faces: a face of the wrong size is an error: %s" % built.error)


## Runs REAL_SECTORS stratum sectors with records through the pipeline at
## seed 0 and prints the outcome counts; solved ones must keep their records
## and hold walk-family tiles only in record cells. Then the same for
## REAL_VOID_SECTORS sectors of each void type.
func _run_real_sectors(library: TileLibrary) -> void:
	var rasteriser := EdgeRasteriser.new(WalkableGraph.new(0))
	var solver := SectorSolver.new(library, LARGE)
	var counts := {"solved": 0, "degraded": 0, "failed": 0, "rejected": 0}
	var attempts := 0
	var ran := 0
	var broken := 0
	var outside := 0
	var usec := 0
	var i := 0
	while ran < REAL_SECTORS and i < 10000:
		var sector := Vector3i(_sample(i, 0), _sample(i, 1), _sample(i, 2))
		i += 1
		if rasteriser.graph.skeleton.sector_type(0, sector) != Skeleton.SectorType.STRATUM:
			continue
		if rasteriser.records_for_sector(sector).is_empty():
			continue
		ran += 1
		var run := SolverSectorRun.run(library, rasteriser, sector, 0, solver)
		var outcome := "rejected"
		if run.error.is_empty():
			outcome = SectorSolver.OUTCOME_NAMES[run.result.outcome]
			usec += run.result.time_usec
			if run.result.outcome != SectorSolver.Outcome.FAILED:
				attempts += run.result.attempts
			if run.result.outcome == SectorSolver.Outcome.SOLVED:
				broken += run.broken_records(library) + SolverSectorRun.bad_adjacencies(library, LARGE, run.result.cells)
				outside += run.walk_tiles_outside_records(library)
		counts[outcome] += 1
		print("  real %s: %d records, %s%s" % [
			sector, run.records.size(), outcome,
			" after %d attempt(s), %.0f ms" % [run.result.attempts, run.result.time_usec / 1000.0] if run.result != null and run.result.outcome != SectorSolver.Outcome.FAILED else ": %s" % (run.error if not run.error.is_empty() else run.result.error),
		])
	_expect(ran == REAL_SECTORS, "real sectors: %d stratum sectors with records at seed 0" % ran)
	_expect(broken == 0, "real sectors: every solved sector keeps its records and adjacencies, %d broken" % broken)
	_expect(outside == 0, "real sectors: no walk-family tile outside a record cell in any solved sector, %d found" % outside)
	var searched: int = counts.solved + counts.degraded
	print("  real sectors: %d solved, %d degraded, %d inconsistent in the solver, %d rejected by the record checks; mean attempts %.2f over %d searched, %.0f ms total solve time" % [
		counts.solved, counts.degraded, counts.failed, counts.rejected, float(attempts) / maxi(searched, 1), searched, usec / 1000.0,
	])

	for type: Skeleton.SectorType in [Skeleton.SectorType.SHAFT, Skeleton.SectorType.CAVITY, Skeleton.SectorType.CHASM]:
		var type_name := Skeleton.type_name(type)
		var sectors := SolverSectorRun.real_sectors(rasteriser, REAL_VOID_SECTORS, type)
		var solved := 0
		var bad := 0
		for sector in sectors:
			var run := SolverSectorRun.run(library, rasteriser, sector, 0, solver)
			var outcome := run.error if not run.error.is_empty() else SectorSolver.OUTCOME_NAMES[run.result.outcome]
			if run.error.is_empty() and run.result.outcome == SectorSolver.Outcome.SOLVED:
				solved += 1
				bad += run.broken_records(library) + SolverSectorRun.bad_adjacencies(library, LARGE, run.result.cells) + run.walk_tiles_outside_records(library)
			print("  real %s %s: %d records, %s" % [type_name, sector, run.records.size(), outcome])
		_expect(sectors.size() == REAL_VOID_SECTORS and solved > 0 and bad == 0, "real sectors: %d of %d %s sectors solve, keeping records and adjacencies with walk-family tiles only in record cells, %d wrong" % [solved, sectors.size(), type_name, bad])


static func _sample(i: int, axis: int) -> int:
	return Hash.hash3_u(0, Vector3i(i, axis, 0), SALT_TEST_SOLVER) % (2 * REAL_RANGE + 1) - REAL_RANGE


static func _record(cell: Vector3i, family: EdgeRasteriser.TileFamily, orientation: int) -> EdgeRasteriser.Record:
	return EdgeRasteriser.Record.make(cell, family, orientation, Vector4i.ZERO)


static func _restrict(domains: PackedInt64Array, words: int, cell: int, tile: int) -> void:
	for w in words:
		domains[cell * words + w] = 0
	domains[cell * words + (tile >> 6)] = 1 << (tile & 63)


static func _tile_named(library: TileLibrary, tile_name: String) -> int:
	for tile in library.tiles:
		if tile.label() == tile_name + "@0":
			return tile.index
	return -1


## Face-neighbour pairs of the result that the adjacency table forbids.
static func _bad_adjacencies(library: TileLibrary, solver: SectorSolver, cells: PackedInt32Array) -> int:
	return SolverSectorRun.bad_adjacencies(library, solver.size, cells)


static func _digest(cells: PackedInt32Array) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(cells.to_byte_array())
	return context.finish().hex_encode()


static func _print_histogram(library: TileLibrary, cells: PackedInt32Array) -> void:
	var counts := PackedInt32Array()
	counts.resize(library.tile_count())
	for tile in cells:
		counts[tile] += 1
	var parts := PackedStringArray()
	for tile in library.tiles:
		if counts[tile.index] > 0:
			parts.append("%s %d" % [tile.label(), counts[tile.index]])
	print("    %s" % ", ".join(parts))


func _compare_reference(digest: String) -> void:
	if not FileAccess.file_exists(REFERENCE_PATH):
		_expect(false, "reference: %s missing, run: mise run solver-check --update" % REFERENCE_PATH)
		return
	var expected := ""
	for line in FileAccess.get_file_as_string(REFERENCE_PATH).split("\n"):
		if line.begins_with("sha256: "):
			expected = line.trim_prefix("sha256: ").strip_edges()
	_expect(expected == digest, "reference: seed 0 cells match %s" % REFERENCE_PATH.trim_prefix("res://"))
	if expected != digest:
		printerr("  expected sha256 %s, got %s" % [expected, digest])


func _write_reference(digest: String) -> void:
	var text := """---
tags:
  - solver
  - reference
status: current
---

# Solver Reference, Seed 0

> [!summary]
> The SHA-256 of the tiles `SectorSolver` places in an unconstrained 8 × 8 × 8
> grid with the placeholder tileset at seed 0, sector (0, 0, 0), with the
> default minimum remaining values heuristic. `mise run solver-check`
> recomputes it and fails if it differs, so any change to the solver, the
> hash, the tileset or the adjacency table that changes the output shows up
> here. After an intended change, regenerate this file with
> `mise run solver-check --update` and commit it.

The digest covers `Result.cells` as little-endian int32 tile indices in cell
order `x + 8 * (y + 8 * z)`. Generated file: only the `sha256:` line is
compared.

```
sha256: %s
```

## References

- [[sector-solver]]: the solver and its salts.
- [[tools-and-tasks]]: the task and its script.
""" % digest
	var file := FileAccess.open(REFERENCE_PATH, FileAccess.WRITE)
	if file == null:
		_expect(false, "reference: cannot write %s" % REFERENCE_PATH)
		return
	file.store_string(text)
	file.close()
	print("  ok    wrote %s" % REFERENCE_PATH.trim_prefix("res://"))


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)


## Tileability (#161): the REAL_SECTORS real stratum sectors of each of
## world seeds 1 to 4 (seed 0 is solved above) build their starting domains
## and propagate them without emptying a cell, so every one reaches an
## attempt. Only the starting domains are propagated
## (`SolverSectorRun.empty_cell`); nothing is solved.
func _check_real_sectors_reach_an_attempt(library: TileLibrary) -> void:
	for seed in [1, 2, 3, 4]:
		var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed))
		var sectors := SolverSectorRun.real_sectors(rasteriser, REAL_SECTORS)
		var failed := PackedStringArray()
		for sector in sectors:
			var built := SectorDomains.for_sector(library, rasteriser, sector)
			if not built.error.is_empty():
				failed.append("%s: %s" % [sector, built.error])
				continue
			var n := rasteriser.graph.cells_per_sector()
			var empty := SolverSectorRun.empty_cell(library, Vector3i(n, n, n), built.words)
			if empty >= 0:
				failed.append("%s: cell %s empties" % [sector, SolverSectorRun.position(Vector3i(n, n, n), empty)])
		_expect(sectors.size() == REAL_SECTORS and failed.is_empty(), "real sectors: seed %d, %d stratum sectors reach an attempt, %d fail before%s" % [
			seed, sectors.size() - failed.size(), failed.size(), "" if failed.is_empty() else " (%s)" % "; ".join(failed),
		])
