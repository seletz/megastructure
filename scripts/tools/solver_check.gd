extends SceneTree
## Checks `SectorSolver` on the placeholder tileset. Solves an unconstrained
## 8³ grid at seeds 0 to 4 and fails unless every solve succeeds, a second
## solver instance returns byte-identical cells, every face adjacency in the
## result is allowed, and the seed 0 cells hash to the SHA-256 recorded in
## docs/solver_reference_seed0.md. Also checks the Shannon entropy flag the
## same way, that a `domains` restriction holds in the result and that an
## unsatisfiable one fails, then prints the tile histogram, steps and time
## per seed and the time of the first 24³ solve that succeeds.
## Run headless with `mise run solver-check`; pass `--update` to rewrite the
## reference file instead of comparing against it.

const TILESET := "res://resources/tilesets/placeholder.tres"
const REFERENCE_PATH := "res://docs/solver_reference_seed0.md"
const SMALL := Vector3i(8, 8, 8)
const LARGE := Vector3i(24, 24, 24)
const SEEDS: Array[int] = [0, 1, 2, 3, 4]
const SECTOR := Vector3i.ZERO

## Grid step of each face index, +x, -x, +y, -y, +z, -z.
const STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var _failures := 0


func _init() -> void:
	var update := "--update" in OS.get_cmdline_user_args()
	var library := TileLibrary.build(load(TILESET) as TileSet3D)
	if not library.errors.is_empty():
		_expect(false, "%s: %s" % [TILESET, library.errors])
		quit(1)
		return
	print("solver check: %s, %d tiles, %d word(s)" % [TILESET.trim_prefix("res://"), library.tile_count(), library.word_count])

	var first := SectorSolver.new(library, SMALL)
	var second := SectorSolver.new(library, SMALL)
	var reference_digest := ""
	for seed in SEEDS:
		var result := first.solve(seed, SECTOR)
		var again := second.solve(seed, SECTOR)
		_expect(result.ok, "seed %d: 8³ solved%s" % [seed, "" if result.ok else " (%s)" % result.error])
		if not result.ok:
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

	if not reference_digest.is_empty():
		if update:
			_write_reference(reference_digest)
		else:
			_compare_reference(reference_digest)

	_time_large(library)

	print("solver check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


## Solves 24³ grids from seed 0 until one succeeds (at most `SEEDS.size()`
## seeds, since there are no restarts yet) and prints each time. Only
## reports: a contradiction is not a failure of the check.
func _time_large(library: TileLibrary) -> void:
	var large := SectorSolver.new(library, LARGE)
	for seed in SEEDS:
		var result := large.solve(seed, SECTOR)
		print("  24³ seed %d: %s, %d steps, %d propagations, %.1f ms" % [
			seed, "ok" if result.ok else result.error, result.steps, result.propagations, result.time_usec / 1000.0,
		])
		if result.ok:
			_expect(_bad_adjacencies(library, large, result.cells) == 0, "24³ seed %d: every adjacency allowed" % seed)
			return


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

	_restrict(domains, words, solver.index(Vector3i(4, 3, 4)), air)
	_restrict(domains, words, centre, floor)
	result = solver.solve(0, SECTOR, domains)
	_expect(not result.ok and result.contradiction_cell >= 0, "domains: floor above air fails (%s)" % result.error)


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
	var bad := 0
	for cell in cells.size():
		var position := solver.position(cell)
		for dir in TilePrototype.FACE_COUNT:
			var next := position + STEPS[dir]
			if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= solver.size.x or next.y >= solver.size.y or next.z >= solver.size.z:
				continue
			if not library.is_allowed(dir, cells[cell], cells[solver.index(next)]):
				bad += 1
	return bad


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
