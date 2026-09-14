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
