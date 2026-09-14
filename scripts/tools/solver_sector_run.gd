class_name SolverSectorRun
extends RefCounted
## One pass of the fill pipeline for a real sector, shared by `solver-sector`
## and `solver-check`: sector type, records, `SectorDomains`, solve; plus the
## checks both tools apply to the result.

## Grid step of each face index, +x, -x, +y, -y, +z, -z.
const STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## Real sectors are sampled within this many sectors of the origin.
const REAL_RANGE := 1000
## Samples `real_sectors` looks at before it gives up.
const REAL_SEARCH_LIMIT := 10000
## Salt of the real sector sample, the one `solver-check` uses; outside the
## grammar's salt range.
const SALT_REAL_SECTORS := 905

var sector: Vector3i
var type: Skeleton.SectorType
var size: Vector3i
var records: Array[EdgeRasteriser.Record] = []
## Why the domains could not be built, or "".
var error := ""
var domains_usec := 0
var result: SectorSolver.Result


## Rasterises, builds the domains and solves `sector` with solve seed `seed`.
static func run(library: TileLibrary, rasteriser: EdgeRasteriser, sector_cell: Vector3i, seed: int, solver: SectorSolver = null) -> SolverSectorRun:
	var pass_run := SolverSectorRun.new()
	var graph := rasteriser.graph
	var n := graph.cells_per_sector()
	pass_run.sector = sector_cell
	pass_run.size = Vector3i(n, n, n)
	pass_run.type = graph.skeleton.sector_type(graph.world_seed, sector_cell)
	pass_run.records = rasteriser.records_for_sector(sector_cell)
	var started := Time.get_ticks_usec()
	var built := SectorDomains.build(library, pass_run.size, pass_run.type, pass_run.records)
	pass_run.domains_usec = Time.get_ticks_usec() - started
	if not built.error.is_empty():
		pass_run.error = built.error
		return pass_run
	if solver == null or solver.size != pass_run.size:
		solver = SectorSolver.new(library, pass_run.size)
	pass_run.result = solver.solve(seed, sector_cell, built.words)
	return pass_run


## Records whose cell holds a tile `SectorDomains.tile_matches` rejects.
func broken_records(library: TileLibrary) -> int:
	var broken := 0
	for record in records:
		var tile := library.tiles[result.cells[record.cell.x + size.x * (record.cell.y + size.y * record.cell.z)]]
		if not SectorDomains.tile_matches(tile, record.family, record.orientation):
			broken += 1
	return broken


## Cells outside every record that hold a tile of a walk family (any family
## but none): 0 when walk tiles stand only in record cells (#180).
func walk_tiles_outside_records(library: TileLibrary) -> int:
	return count_walk_tiles_outside(library, size, records, result.cells)


## `walk_tiles_outside_records` for any grid, records and cells.
static func count_walk_tiles_outside(library: TileLibrary, grid: Vector3i, cell_records: Array[EdgeRasteriser.Record], cells: PackedInt32Array) -> int:
	var in_record := PackedByteArray()
	in_record.resize(cells.size())
	in_record.fill(0)
	for record in cell_records:
		in_record[record.cell.x + grid.x * (record.cell.y + grid.y * record.cell.z)] = 1
	var outside := 0
	for cell in cells.size():
		if in_record[cell] == 0 and library.tiles[cells[cell]].prototype.family != TilePrototype.FAMILY_NONE:
			outside += 1
	return outside


## Face-neighbour pairs of `cells` that the adjacency table forbids.
static func bad_adjacencies(library: TileLibrary, grid: Vector3i, cells: PackedInt32Array) -> int:
	var bad := 0
	for cell in cells.size():
		var position := Vector3i(cell % grid.x, (cell / grid.x) % grid.y, cell / (grid.x * grid.y))
		for dir in TilePrototype.FACE_COUNT:
			var next := position + STEPS[dir]
			if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= grid.x or next.y >= grid.y or next.z >= grid.z:
				continue
			if not library.is_allowed(dir, cells[cell], cells[next.x + grid.x * (next.y + grid.y * next.z)]):
				bad += 1
	return bad


## Tile counts by family name; tiles of no family by prototype name.
static func histogram(library: TileLibrary, cells: PackedInt32Array) -> String:
	var counts := {}
	var order := PackedStringArray()
	for tile_index in cells:
		var tile := library.tiles[tile_index]
		var key := tile.prototype.name if tile.prototype.family == TilePrototype.FAMILY_NONE else EdgeRasteriser.FAMILY_NAMES[tile.prototype.family]
		if not counts.has(key):
			order.append(key)
			counts[key] = 0
		counts[key] += 1
	order.sort()
	var parts := PackedStringArray()
	for key in order:
		parts.append("%s %d" % [key, counts[key]])
	return ", ".join(parts)


## The `index`-th real sector candidate `solver-check` samples: a sector
## within +-`REAL_RANGE` of the origin, hashed with `SALT_REAL_SECTORS`.
static func real_sector(index: int) -> Vector3i:
	var axes := Vector3i.ZERO
	for axis in 3:
		axes[axis] = Hash.hash3_u(0, Vector3i(index, axis, 0), SALT_REAL_SECTORS) % (2 * REAL_RANGE + 1) - REAL_RANGE
	return axes


## The first `count` sampled sectors of `type` (stratum by default) with
## records at the rasteriser's world seed (fewer when `REAL_SEARCH_LIMIT` runs
## out).
static func real_sectors(rasteriser: EdgeRasteriser, count: int, type := Skeleton.SectorType.STRATUM) -> Array[Vector3i]:
	var graph := rasteriser.graph
	var found: Array[Vector3i] = []
	var i := 0
	while found.size() < count and i < REAL_SEARCH_LIMIT:
		var sector := real_sector(i)
		i += 1
		if graph.skeleton.sector_type(graph.world_seed, sector) != type:
			continue
		if rasteriser.records_for_sector(sector).is_empty():
			continue
		found.append(sector)
	return found


## Propagates `words` (as `SectorDomains` builds them) to arc consistency
## and returns the first cell left without a tile, or -1 when none is.
static func empty_cell(library: TileLibrary, grid: Vector3i, words: PackedInt64Array) -> int:
	var wc := library.word_count
	var tiles := library.tile_count()
	var domains := words.duplicate()
	var cell_count := grid.x * grid.y * grid.z
	var tables: Array[PackedInt64Array] = []
	for dir in TilePrototype.FACE_COUNT:
		var table := PackedInt64Array()
		for tile in tiles:
			table.append_array(library.allowed(dir, tile))
		tables.append(table)
	var full := PackedInt64Array()
	full.resize(wc)
	full.fill(0)
	for tile in tiles:
		full[tile >> 6] |= 1 << (tile & 63)
	# A cell that may still hold every tile restricts nothing, so only the
	# restricted cells start in the queue.
	var queued := PackedByteArray()
	queued.resize(cell_count)
	queued.fill(0)
	var stack := PackedInt32Array()
	for cell in range(cell_count - 1, -1, -1):
		for w in wc:
			if domains[cell * wc + w] != full[w]:
				queued[cell] = 1
				stack.append(cell)
				break
	# Union of the allowed tiles by domain and direction; domains repeat.
	var supports := {}
	var support := PackedInt64Array()
	while not stack.is_empty():
		var cell := stack[-1]
		stack.remove_at(stack.size() - 1)
		queued[cell] = 0
		var position := Vector3i(cell % grid.x, (cell / grid.x) % grid.y, cell / (grid.x * grid.y))
		for dir in TilePrototype.FACE_COUNT:
			var next := position + STEPS[dir]
			if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= grid.x or next.y >= grid.y or next.z >= grid.z:
				continue
			var key: Variant = domains[cell * wc] * 6 + dir if wc == 1 else [domains.slice(cell * wc, (cell + 1) * wc), dir]
			if supports.has(key):
				support = supports[key]
			else:
				support = PackedInt64Array()
				support.resize(wc)
				support.fill(0)
				for tile in tiles:
					if (domains[cell * wc + (tile >> 6)] >> (tile & 63)) & 1 == 1:
						for w in wc:
							support[w] |= tables[dir][tile * wc + w]
				supports[key] = support
			var other := next.x + grid.x * (next.y + grid.y * next.z)
			var changed := false
			var left := false
			for w in wc:
				var before := domains[other * wc + w]
				var after := before & support[w]
				domains[other * wc + w] = after
				changed = changed or after != before
				left = left or after != 0
			if not left:
				return other
			if changed and queued[other] == 0:
				queued[other] = 1
				stack.append(other)
	return -1


## A cell index as a grid position.
static func position(grid: Vector3i, cell: int) -> Vector3i:
	return Vector3i(cell % grid.x, (cell / grid.x) % grid.y, cell / (grid.x * grid.y))
