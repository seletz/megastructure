extends SceneTree
## Checks `EdgeRasteriser` over 1 000 random sectors, 200 per seed 0..4,
## within +-RANGE sectors of the origin.
##
## For every sample sector: two rasterisers (one on a caching skeleton, one
## on a fresh graph) return identical records; every record cell lies inside
## 0..23; no two records share a cell; every record an edge's routing
## produced is kept or merged away without conflict by `merge`, and no two
## raw records at one cell conflict; every edge of the sector has a portal
## opening at its portal cell in both of its endpoint sectors, so each
## endpoint has at least one record; no edge is rejected; the records of a
## sector form one 26-connected group; every edge's routing is a walk from
## the hub to its portal cell in which flat cells never change level and
## every level change is a stair run or a ladder. `merge` is also checked to be
## commutative over every pair of families and orientations.
## Prints the family counts, the mean records per sector and the stair,
## ladder and landing cells that level changes produce.
## Run headless with `mise run raster-check`.

const SEEDS: Array[int] = [0, 1, 2, 3, 4]
const SECTORS_PER_SEED := 200
const RANGE := 100000
const CELLS := 24
## Salt for picking the sample sectors; outside the grammar's salt range.
const SALT_TEST_RASTER := 904

var _failures := 0


## Remembers sector types, as neighbouring sample sectors share regions.
class CachingSkeleton:
	extends Skeleton
	var _types := {}

	func sector_type(seed_value: int, cell: Vector3i) -> Skeleton.SectorType:
		var type: int = _types.get(cell, -1)
		if type < 0:
			type = super.sector_type(seed_value, cell)
			_types[cell] = type
		return type as Skeleton.SectorType


func _init() -> void:
	_check_merge()
	var families := PackedInt32Array()
	families.resize(EdgeRasteriser.TileFamily.size())
	var totals := {"sectors": 0, "with_edges": 0, "records": 0, "edges": 0, "rejected": 0, "fallbacks": 0, "level_edges": 0, "horizontal_stairs": 0, "vertical_stairs": 0, "ladders": 0, "landings": 0}
	for seed_value in SEEDS:
		_check_seed(seed_value, families, totals)
	var parts := PackedStringArray()
	for f in families.size():
		parts.append("%s %d" % [EdgeRasteriser.FAMILY_NAMES[f], families[f]])
	_expect(totals.sectors == SEEDS.size() * SECTORS_PER_SEED, "%d sectors checked" % totals.sectors)
	print("all seeds:")
	print("  %d sectors, %d with edges, %d edges, %d on a fallback routing, %d rejected" % [totals.sectors, totals.with_edges, totals.edges, totals.fallbacks, totals.rejected])
	print("  families: %s" % ", ".join(parts))
	print("  level changes: %d horizontal edge ends change level; %d stair cells on horizontal edges, %d on vertical edges, %d ladder cells, %d landing cells" % [totals.level_edges, totals.horizontal_stairs, totals.vertical_stairs, totals.ladders, totals.landings])
	print("  mean records per sector %.1f (%.1f per sector with edges)" % [float(totals.records) / maxi(totals.sectors, 1), float(totals.records) / maxi(totals.with_edges, 1)])
	print("raster check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_seed(seed_value: int, families: PackedInt32Array, totals: Dictionary) -> void:
	var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed_value, CachingSkeleton.new()))
	var fresh := EdgeRasteriser.new(WalkableGraph.new(seed_value))
	var label := "seed %d:" % seed_value
	_expect(rasteriser.graph.cells_per_sector() == CELLS, "%s %d cells per sector" % [label, CELLS])
	# Rasters by sector, so endpoint sectors are computed once.
	var rasters := {}
	var bad := {"fresh": 0, "bounds": 0, "duplicate": 0, "conflict": 0, "endpoint": 0, "rejected": 0, "split": 0, "walk": 0}
	var with_edges := 0
	var records := 0
	var edges := 0
	for i in SECTORS_PER_SEED:
		var sector := Vector3i(_random(seed_value, i, 0), _random(seed_value, i, 1), _random(seed_value, i, 2))
		var raster := _raster(rasteriser, rasters, sector)
		if not _same(raster, fresh.rasterise(sector)):
			bad.fresh += 1
		var sector_edges := rasteriser.graph.edges_for_sector(sector)
		edges += sector_edges.size()
		if not sector_edges.is_empty():
			with_edges += 1
		records += raster.records.size()
		bad.rejected += raster.rejected.size()
		totals.fallbacks += raster.fallbacks
		for record in raster.records:
			families[record.family] += 1
		_check_cells(raster, bad)
		_check_walks(rasteriser, raster, sector_edges, bad, totals)
		for edge in sector_edges:
			for end in [edge.a, edge.b]:
				if not _has_portal(_raster(rasteriser, rasters, end), end, edge):
					bad.endpoint += 1
		if _components(raster) > 1:
			bad.split += 1

	_expect(bad.fresh == 0, "%s a fresh graph rasterises all %d sectors identically, %d differ" % [label, SECTORS_PER_SEED, bad.fresh])
	_expect(bad.bounds == 0 and bad.duplicate == 0, "%s %d records inside 0..%d with one record per cell, %d outside, %d duplicate cells" % [label, records, CELLS - 1, bad.bounds, bad.duplicate])
	_expect(bad.conflict == 0, "%s no conflicting records in %d sectors, %d conflicts" % [label, SECTORS_PER_SEED, bad.conflict])
	_expect(bad.endpoint == 0, "%s both endpoint sectors of all %d edges have the portal opening, %d miss it" % [label, edges, bad.endpoint])
	_expect(bad.rejected == 0, "%s no edge rejected, %d are" % [label, bad.rejected])
	_expect(bad.walk == 0, "%s every routing walks from the hub to its portal with explicit stairs and ladders, %d do not" % [label, bad.walk])
	_expect(bad.split == 0, "%s the records of every sector are one 26-connected group, %d sectors are split" % [label, bad.split])
	print("  info  %s %d of %d sectors have edges, %.1f records per sector with edges, %.2f %% of their cells" % [label, with_edges, SECTORS_PER_SEED, float(records) / maxi(with_edges, 1), 100.0 * records / maxi(with_edges * CELLS ** 3, 1)])
	totals.sectors += SECTORS_PER_SEED
	totals.with_edges += with_edges
	totals.records += records
	totals.edges += edges
	totals.rejected += bad.rejected


func _raster(rasteriser: EdgeRasteriser, rasters: Dictionary, sector: Vector3i) -> EdgeRasteriser.SectorRaster:
	if not rasters.has(sector):
		rasters[sector] = rasteriser.rasterise(sector)
	return rasters[sector]


## Bounds, one record per cell, and every raw routing record kept or merged
## into the final record without conflict.
func _check_cells(raster: EdgeRasteriser.SectorRaster, bad: Dictionary) -> void:
	var by_cell := {}
	for record in raster.records:
		var c := record.cell
		if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= CELLS or c.y >= CELLS or c.z >= CELLS:
			bad.bounds += 1
		if by_cell.has(c):
			bad.duplicate += 1
		by_cell[c] = record
	var raw := {}
	for ref: Vector4i in raster.edge_records:
		for record: EdgeRasteriser.Record in raster.edge_records[ref]:
			var final: EdgeRasteriser.Record = by_cell.get(record.cell)
			if final == null or not final.equals(EdgeRasteriser.merge(final, record)):
				bad.conflict += 1
			for other: EdgeRasteriser.Record in raw.get(record.cell, []):
				if EdgeRasteriser.merge(other, record) == null:
					bad.conflict += 1
			if not raw.has(record.cell):
				raw[record.cell] = []
			raw[record.cell].append(record)


## Each edge's routing, in walking order, starts at the hub, ends at the
## portal cell and only takes steps a walker can: flat to flat at one level,
## onto, along and off a stair in its orientation, or on and off a ladder.
## Also counts what level changes produced.
func _check_walks(rasteriser: EdgeRasteriser, raster: EdgeRasteriser.SectorRaster, edges: Array[WalkableGraph.Edge], bad: Dictionary, totals: Dictionary) -> void:
	var hub := rasteriser.hub_cell(raster.sector)
	for edge in edges:
		var ref := EdgeRasteriser.edge_ref(edge)
		var walk: Array = raster.edge_records.get(ref, [])
		var portal := EdgeRasteriser.portal_cell(raster.sector, edge, CELLS)
		if edge.axis != Vector3i.AXIS_Y and portal.y != hub.y:
			totals.level_edges += 1
		if walk.is_empty() or walk[0].cell != hub or walk[-1].cell != portal:
			bad.walk += 1
			continue
		for i in walk.size():
			var record: EdgeRasteriser.Record = walk[i]
			match record.family:
				EdgeRasteriser.TileFamily.STAIR:
					if edge.axis == Vector3i.AXIS_Y:
						totals.vertical_stairs += 1
					else:
						totals.horizontal_stairs += 1
				EdgeRasteriser.TileFamily.LADDER:
					totals.ladders += 1
				EdgeRasteriser.TileFamily.PORTAL_OPENING:
					pass
				_:
					if record.cell.y != hub.y:
						totals.landings += 1
			if i > 0 and not _step_ok(walk[i - 1], record):
				bad.walk += 1
				break


static func _step_ok(p: EdgeRasteriser.Record, q: EdgeRasteriser.Record) -> bool:
	var d := q.cell - p.cell
	var flat := absi(d.x) + absi(d.z)
	var stair := EdgeRasteriser.TileFamily.STAIR
	var ladder := EdgeRasteriser.TileFamily.LADDER
	if p.family == ladder or q.family == ladder:
		return (flat == 1 and d.y == 0) or (flat == 0 and absi(d.y) == 1)
	if flat != 1:
		return false
	var dir := Vector3i(d.x, 0, d.z)
	if p.family != stair and q.family != stair:
		return d.y == 0
	if p.family != stair:
		# Onto the bottom step going up, or onto the top step going down.
		var forward := _forward(q)
		return (d.y == 0 and dir == forward) or (d.y == -1 and dir == -forward)
	if q.family != stair:
		var forward := _forward(p)
		return (d.y == 1 and dir == forward) or (d.y == 0 and dir == -forward)
	if p.orientation != q.orientation:
		return false
	return (d.y == 1 and dir == _forward(p)) or (d.y == -1 and dir == -_forward(p))


static func _forward(record: EdgeRasteriser.Record) -> Vector3i:
	return [Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 1)][record.orientation]


func _has_portal(raster: EdgeRasteriser.SectorRaster, sector: Vector3i, edge: WalkableGraph.Edge) -> bool:
	var cell := EdgeRasteriser.portal_cell(sector, edge, CELLS)
	for record in raster.records:
		if record.cell == cell:
			return record.family == EdgeRasteriser.TileFamily.PORTAL_OPENING
	return false


## Groups of record cells joined through their 26 neighbours.
static func _components(raster: EdgeRasteriser.SectorRaster) -> int:
	var unseen := {}
	for record in raster.records:
		unseen[record.cell] = true
	var groups := 0
	while not unseen.is_empty():
		groups += 1
		var stack: Array[Vector3i] = [unseen.keys()[0]]
		unseen.erase(stack[0])
		while not stack.is_empty():
			var cell: Vector3i = stack.pop_back()
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var next := cell + Vector3i(dx, dy, dz)
						if unseen.has(next):
							unseen.erase(next)
							stack.append(next)
	return groups


static func _same(p: EdgeRasteriser.SectorRaster, q: EdgeRasteriser.SectorRaster) -> bool:
	if p.records.size() != q.records.size() or p.rejected != q.rejected:
		return false
	for i in p.records.size():
		if not p.records[i].equals(q.records[i]):
			return false
	return true


## merge(p, q) and merge(q, p) agree for every pair of families and valid
## orientations, and a record merges with itself.
func _check_merge() -> void:
	var samples: Array[EdgeRasteriser.Record] = []
	for family in EdgeRasteriser.TileFamily.size():
		var orientations: Array[int] = [0]
		match family:
			EdgeRasteriser.TileFamily.STAIR:
				orientations = [0, 1, 2, 3]
			EdgeRasteriser.TileFamily.LADDER:
				orientations = [EdgeRasteriser.ORIENTATION_UP]
			EdgeRasteriser.TileFamily.PORTAL_OPENING:
				orientations = [0, 1, 2, 3, EdgeRasteriser.ORIENTATION_UP, EdgeRasteriser.ORIENTATION_DOWN]
		for orientation in orientations:
			for ref in [Vector4i(0, 0, 0, 0), Vector4i(0, 0, 0, 2)]:
				samples.append(EdgeRasteriser.Record.make(Vector3i.ZERO, family, orientation, ref))
	var asymmetric := 0
	for p in samples:
		if not p.equals(EdgeRasteriser.merge(p, p)):
			asymmetric += 1
		for q in samples:
			var pq := EdgeRasteriser.merge(p, q)
			var qp := EdgeRasteriser.merge(q, p)
			if (pq == null) != (qp == null) or (pq != null and not pq.equals(qp)):
				asymmetric += 1
	_expect(asymmetric == 0, "merge is commutative and idempotent over %d record pairs, %d are not" % [samples.size() ** 2, asymmetric])


static func _random(seed_value: int, i: int, axis: int) -> int:
	return Hash.hash3_u(seed_value, Vector3i(i, axis, 0), SALT_TEST_RASTER) % (2 * RANGE + 1) - RANGE


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
