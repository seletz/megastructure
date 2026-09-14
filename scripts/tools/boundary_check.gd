extends SceneTree
## Checks `SectorBoundaries` on the placeholder tileset.
##
## Faces: at seeds 0 to 4, `FACES_PER_SEED` random faces with real records
## are computed from sector S on one instance and from its neighbour S + dir
## on a second, fresh instance that first solves another face of that
## neighbour, so the caches and the solve order differ; the two layers must
## be identical. Two instances also compose the same sector byte for byte.
##
## Pairs: `PAIRS` random adjacent sector pairs are solved on two instances,
## the neighbour first, once with unconstrained domains and once with real
## records where both sectors' records build into domains. For every pair
## whose pieces all solved, no tile pair across the shared face and no pair
## inside either sector may be forbidden, and every record must hold. The
## counts of solved, degraded and failed pairs are printed, then the time per
## level (corners, edges, faces, interior) of one unconstrained and one real
## 24³ sector. Run headless with `mise run boundary-check`.

const TILESET := "res://resources/tilesets/placeholder.tres"
const SEEDS: Array[int] = [0, 1, 2, 3, 4]
const FACES_PER_SEED := 20
const PAIRS := 50
## Unconstrained pairs also solved at 24³ (the 50 unconstrained pairs are 8³).
const PAIRS_LARGE := 2
const RANGE := 1000
## Candidate sectors searched for real pairs with buildable domains.
const SEARCH_LIMIT := 20000
## Salt for picking test sectors and faces; outside the grammar's salt range.
const SALT_TEST_BOUNDARY := 906

var _failures := 0


func _init() -> void:
	var library := TileLibrary.build(load(TILESET) as TileSet3D)
	if not library.errors.is_empty():
		_expect(false, "%s: %s" % [TILESET, library.errors])
		quit(1)
		return
	print("boundary check: %s, %d tiles" % [TILESET.trim_prefix("res://"), library.tile_count()])

	_check_faces(library)
	_check_determinism(library)
	_check_pairs(library, false, 8, PAIRS)
	_check_pairs(library, false, 24, PAIRS_LARGE)
	_check_pairs(library, true, 24, PAIRS)
	_print_timings(library)

	if _failures > 0:
		printerr("boundary check: %d failure(s)" % _failures)
		quit(1)
	else:
		print("boundary check: ok")
		quit(0)


## The same face from both sides, on separate instances.
func _check_faces(library: TileLibrary) -> void:
	var same := 0
	var total := 0
	var outcomes := PackedInt32Array([0, 0, 0])
	var usec := 0
	for seed in SEEDS:
		var from_sector := SectorBoundaries.new(library, seed, EdgeRasteriser.new(WalkableGraph.new(seed)))
		var from_neighbour := SectorBoundaries.new(library, seed, EdgeRasteriser.new(WalkableGraph.new(seed)))
		for i in FACES_PER_SEED:
			var sector := _sample_sector(seed, i)
			var dir := Hash.hash3_u(seed, Vector3i(i, 3, 0), SALT_TEST_BOUNDARY) % TilePrototype.FACE_COUNT
			var neighbour := sector + SectorBoundaries.STEPS[dir]
			var started := Time.get_ticks_usec()
			var layer := from_sector.face(sector, dir)
			usec += Time.get_ticks_usec() - started
			from_neighbour.face(neighbour, (dir + 2) % TilePrototype.FACE_COUNT)
			var other := from_neighbour.face(neighbour, dir ^ 1)
			total += 1
			if layer == other and layer.size() == 24 * 24:
				same += 1
			else:
				printerr("  face %s %s differs from %s %s at seed %d" % [sector, TilePrototype.FACE_NAMES[dir], neighbour, TilePrototype.FACE_NAMES[dir ^ 1], seed])
		for outcome in 3:
			outcomes[outcome] += from_sector.level_outcomes[SectorBoundaries.Level.FACE * 3 + outcome]
	_expect(same == total and total == SEEDS.size() * FACES_PER_SEED, "faces: %d of %d random faces identical from the sector and from its neighbour (seeds 0..4, real records)" % [same, total])
	print("  faces: %d solved, %d degraded, %d failed face pieces; %.1f ms mean per face from a cold cache" % [outcomes[0], outcomes[1], outcomes[2], usec / 1000.0 / maxi(total, 1)])


## Two instances compose the same sector.
func _check_determinism(library: TileLibrary) -> void:
	var first := SectorBoundaries.new(library, 0, null, 8).solve_sector(3, Vector3i(5, -2, 9))
	var second := SectorBoundaries.new(library, 7, null, 8)
	second.face(Vector3i(5, -2, 9), TilePrototype.FACE_NEG_Y)
	var again := second.solve_sector(3, Vector3i(5, -2, 9))
	_expect(first.cells == again.cells and first.cells.size() == 512, "determinism: an 8³ sector is identical on a second instance after a seed change and another face")


## Adjacent pairs have no socket mismatch across the shared face.
func _check_pairs(library: TileLibrary, real: bool, n: int, wanted: int) -> void:
	var label := "%d³ %s" % [n, "real records" if real else "unconstrained"]
	var both_solved := 0
	var one_not := 0
	var mismatches := 0
	var inner := 0
	var broken := 0
	var usec := 0
	var pairs := 0
	var rasterisers: Array[EdgeRasteriser] = []
	for seed in SEEDS:
		rasterisers.append(EdgeRasteriser.new(WalkableGraph.new(seed)) if real else null)
	var instances: Array[SectorBoundaries] = []
	for seed in SEEDS:
		instances.append(SectorBoundaries.new(library, seed, rasterisers[seed], n))
		instances.append(SectorBoundaries.new(library, seed, rasterisers[seed], n))
	var i := 0
	while pairs < wanted and i < SEARCH_LIMIT:
		var seed := SEEDS[i % SEEDS.size()]
		var sector := _sample_sector(seed, 1000 + i)
		var dir := Hash.hash3_u(seed, Vector3i(1000 + i, 3, 0), SALT_TEST_BOUNDARY) % TilePrototype.FACE_COUNT
		var neighbour := sector + SectorBoundaries.STEPS[dir]
		i += 1
		if real and not (_tileable(library, rasterisers[seed], sector) and _tileable(library, rasterisers[seed], neighbour)):
			continue
		pairs += 1
		var started := Time.get_ticks_usec()
		var b := instances[seed * 2 + 1].solve_sector(seed, neighbour)
		var a := instances[seed * 2].solve_sector(seed, sector)
		usec += Time.get_ticks_usec() - started
		if not (a.solved and b.solved):
			one_not += 1
			continue
		both_solved += 1
		mismatches += _mismatches(library, n, a.cells, b.cells, dir)
		inner += SolverSectorRun.bad_adjacencies(library, Vector3i(n, n, n), a.cells) + SolverSectorRun.bad_adjacencies(library, Vector3i(n, n, n), b.cells)
		if real:
			broken += _broken_records(library, rasterisers[seed], a) + _broken_records(library, rasterisers[seed], b)
	_expect(pairs == wanted, "pairs, %s: %d adjacent pairs%s" % [label, pairs, " whose records build into domains" if real else ""])
	_expect(mismatches == 0 and inner == 0 and broken == 0, "pairs, %s: no socket mismatch across the shared face (%d) or inside (%d), no broken record (%d) in the %d pairs where both sectors solved" % [label, mismatches, inner, broken, both_solved])
	if not real:
		_expect(both_solved == pairs, "pairs, %s: every pair solved" % label)
	print("  pairs, %s: %d both solved, %d with a degraded or failed piece; %.0f ms mean per sector" % [label, both_solved, one_not, usec / 1000.0 / maxi(pairs * 2, 1)])


## Time per level of one cold 24³ sector, unconstrained and with records.
func _print_timings(library: TileLibrary) -> void:
	for real in [false, true]:
		var boundaries := SectorBoundaries.new(library, 0, EdgeRasteriser.new(WalkableGraph.new(0)) if real else null)
		var sector := Vector3i.ZERO
		if real:
			var i := 0
			while i < SEARCH_LIMIT and not _tileable(library, EdgeRasteriser.new(WalkableGraph.new(0)), _sample_sector(0, 5000 + i)):
				i += 1
			sector = _sample_sector(0, 5000 + i)
		var result := boundaries.solve_sector(0, sector)
		var parts := PackedStringArray()
		for level in SectorBoundaries.Level.size():
			parts.append("%d %s%s %.1f ms" % [
				boundaries.level_solves[level], SectorBoundaries.LEVEL_NAMES[level], "s" if boundaries.level_solves[level] != 1 else "", result.level_usec[level] / 1000.0,
			])
		print("  timing 24³ %s %s: %s; %s" % [
			"real" if real else "unconstrained", sector, ", ".join(parts),
			"solved" if result.solved else "%d degraded, %d failed pieces" % [result.degraded, result.failed],
		])


## Whether a real sector's records build into domains.
static func _tileable(library: TileLibrary, rasteriser: EdgeRasteriser, sector: Vector3i) -> bool:
	return SectorDomains.for_sector(library, rasteriser, sector).error.is_empty()


## Forbidden tile pairs between sector `a` and its neighbour `b` across `dir`.
static func _mismatches(library: TileLibrary, n: int, a: PackedInt32Array, b: PackedInt32Array, dir: int) -> int:
	var axis := dir >> 1
	var u_axis := 1 if axis == 0 else 0
	var v_axis := 1 if axis == 2 else 2
	var bad := 0
	for v in n:
		for u in n:
			var p := Vector3i.ZERO
			p[u_axis] = u
			p[v_axis] = v
			var q := p
			p[axis] = n - 1 if dir & 1 == 0 else 0
			q[axis] = 0 if dir & 1 == 0 else n - 1
			if not library.is_allowed(dir, a[p.x + n * (p.y + n * p.z)], b[q.x + n * (q.y + n * q.z)]):
				bad += 1
	return bad


static func _broken_records(library: TileLibrary, rasteriser: EdgeRasteriser, result: SectorBoundaries.SectorResult) -> int:
	var n := 24
	var broken := 0
	for record in rasteriser.records_for_sector(result.sector):
		var tile := library.tiles[result.cells[record.cell.x + n * (record.cell.y + n * record.cell.z)]]
		if not SectorDomains.tile_matches(tile, record.family, record.orientation):
			broken += 1
	return broken


static func _sample_sector(seed: int, i: int) -> Vector3i:
	var sector := Vector3i.ZERO
	for axis in 3:
		sector[axis] = Hash.hash3_u(seed, Vector3i(i, axis, 0), SALT_TEST_BOUNDARY) % (2 * RANGE + 1) - RANGE
	return sector


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
