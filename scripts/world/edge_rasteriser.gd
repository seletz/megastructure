class_name EdgeRasteriser
extends RefCounted
## The fill contract: turns the walkable graph edges of one sector into
## records on its cell grid, the only input the solver takes from the graph.
##
##     var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed))
##     for record in rasteriser.records_for_sector(Vector3i(0, 0, 0)):
##         print(record.cell, EdgeRasteriser.family_name(record.family), record.orientation)
##
## Every edge of `WalkableGraph.edges_for_sector` becomes a path from the
## sector's hub (its interior node, or the centre of a solid sector) to the
## edge's portal cell on the face, plus the portal cell itself. Horizontal
## travel is an L of cells at the hub's floor level in the family of the
## sector type (FLOOR in stratum, CATWALK in shaft, BRIDGE in cavity and
## chasm, TUNNEL in solid), so the paths of one sector share one family and
## meet at the hub. Level changes are stairs (one cell up per cell of run, so
## one stratum in 3 cells) or ladders (one column). All portal cells are
## placed first; records at the same cell merge by `merge`, and an edge whose
## path would conflict with the records before it tries its next routing.
## When none fits it keeps only its portal cell and is listed as rejected. Rules and a worked example are in
## docs/algorithms/edge-rasteriser.md.

## Tile families a record restricts its cell to.
enum TileFamily { FLOOR, STAIR, BRIDGE, CATWALK, LADDER, TUNNEL, PORTAL_OPENING }

const FAMILY_NAMES: Array[String] = ["floor", "stair", "bridge", "catwalk", "ladder", "tunnel", "portal_opening"]

## Orientation of a record. 0 to 3 are yaw quarter turns: the forward
## direction is +x turned that many quarter turns about +y (0 +x, 1 -z, 2 -x,
## 3 +z), so a stair's forward is the way up and a portal opening's forward
## points out of the sector. UP and DOWN mark a vertical record: a ladder
## (always UP) or an opening in the ceiling (UP) or floor (DOWN). Floor,
## bridge, catwalk and tunnel records are unoriented and carry 0.
const ORIENTATION_UP := 4
const ORIENTATION_DOWN := 5

const _YAW_DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 1)]
const _UP := Vector3i(0, 1, 0)


## One cell of the contract.
class Record:
	extends RefCounted
	## Cell inside the sector, 0 to cells_per_sector - 1 on each axis.
	var cell: Vector3i
	var family: TileFamily
	## A yaw 0..3, ORIENTATION_UP or ORIENTATION_DOWN; 0 when unoriented.
	var orientation: int
	## The edge the record came from: (a.x, a.y, a.z, axis) of the edge.
	## Both sectors of an edge use the same key.
	var edge_ref: Vector4i

	static func make(record_cell: Vector3i, record_family: TileFamily, record_orientation: int, ref: Vector4i) -> Record:
		var record := Record.new()
		record.cell = record_cell
		record.family = record_family
		record.orientation = record_orientation
		record.edge_ref = ref
		return record

	func equals(other: Record) -> bool:
		return (
			other != null and cell == other.cell and family == other.family
			and orientation == other.orientation and edge_ref == other.edge_ref
		)

	func _to_string() -> String:
		return "Record(%s %s %d %s)" % [cell, FAMILY_NAMES[family], orientation, edge_ref]


## The raster of one sector with what the check needs to verify it.
class SectorRaster:
	extends RefCounted
	var sector: Vector3i
	## Merged records, one per cell, ordered by cell x, then y, then z.
	var records: Array[Record] = []
	## For every edge, by edge_ref, the records of the routing it kept before
	## merging with the other edges (only the portal cell when rejected).
	var edge_records: Dictionary = {}
	## Edge refs whose every routing conflicted, in rasterising order.
	var rejected: Array[Vector4i] = []
	## Edges that kept a routing other than their first.
	var fallbacks := 0


var graph: WalkableGraph


func _init(walkable_graph: WalkableGraph) -> void:
	graph = walkable_graph


static func family_name(family: TileFamily) -> String:
	return FAMILY_NAMES[family]


## The key of an edge as stored in `Record.edge_ref`.
static func edge_ref(edge: WalkableGraph.Edge) -> Vector4i:
	return Vector4i(edge.a.x, edge.a.y, edge.a.z, edge.axis)


## The records of a sector, merged, one per cell, ordered by cell.
func records_for_sector(sector: Vector3i) -> Array[Record]:
	return rasterise(sector).records


## Rasterises every edge of the sector. Vertical edges go first, as they
## have the fewest routings, then horizontal ones; each group by edge_ref.
func rasterise(sector: Vector3i) -> SectorRaster:
	var raster := SectorRaster.new()
	raster.sector = sector
	var edges := graph.edges_for_sector(sector)
	edges.sort_custom(_edge_before)

	var n := graph.cells_per_sector()
	var hub := _hub(sector, n)
	var surface := surface_family(graph.skeleton.sector_type(graph.world_seed, sector))
	# Accepted records by cell.
	var cells := {}
	# Portal cells are fixed by the graph, so they go in before any path:
	# a path that would run through another edge's portal takes its next
	# routing instead of pushing the portal out.
	var portal_ok := {}
	for edge in edges:
		var merged: Variant = _merge_all(cells, [_portal_record(sector, edge, n)])
		if merged != null:
			cells = merged
			portal_ok[edge_ref(edge)] = true
	for edge in edges:
		var ref := edge_ref(edge)
		var chosen: Array[Record] = []
		if portal_ok.has(ref):
			chosen = [_portal_record(sector, edge, n)]
			var found := false
			var candidates := _candidates(sector, edge, hub, surface, n)
			for i in candidates.size():
				var merged: Variant = _merge_all(cells, candidates[i])
				if merged != null:
					cells = merged
					chosen.assign(candidates[i])
					found = true
					if i > 0:
						raster.fallbacks += 1
					break
			if not found:
				raster.rejected.append(ref)
		else:
			raster.rejected.append(ref)
		raster.edge_records[ref] = chosen

	var keys: Array = cells.keys()
	keys.sort_custom(_cell_before)
	for key: Vector3i in keys:
		raster.records.append(cells[key])
	return raster


## The family of horizontal travel inside a sector of the given type.
static func surface_family(type: Skeleton.SectorType) -> TileFamily:
	match type:
		Skeleton.SectorType.SHAFT:
			return TileFamily.CATWALK
		Skeleton.SectorType.CAVITY, Skeleton.SectorType.CHASM:
			return TileFamily.BRIDGE
		Skeleton.SectorType.SOLID:
			return TileFamily.TUNNEL
	return TileFamily.FLOOR


## Merges two records at the same cell; null when they conflict. The same
## family and orientation merge. Stairs, ladders and portal openings win over
## the surface families (floor, bridge, catwalk, tunnel). Two portal openings
## with different yaws merge into a corner opening with the smaller yaw.
## Every other pair conflicts: two surface families, stairs of different
## orientation, a stair and a ladder, a portal opening and a stair or ladder.
## On a tie the smaller edge_ref stays, so merge(p, q) equals merge(q, p).
static func merge(p: Record, q: Record) -> Record:
	var rank_p := _rank(p.family)
	var rank_q := _rank(q.family)
	if p.family == q.family and p.orientation == q.orientation:
		return p if _ref_before(p.edge_ref, q.edge_ref) or p.edge_ref == q.edge_ref else q
	if rank_p != rank_q:
		if rank_p == 0 or rank_q == 0:
			return p if rank_p > rank_q else q
		return null
	if p.family == TileFamily.PORTAL_OPENING and q.family == TileFamily.PORTAL_OPENING:
		if p.orientation < ORIENTATION_UP and q.orientation < ORIENTATION_UP:
			return p if p.orientation < q.orientation else q
	return null


## 0 for surface families, 1 for stairs and ladders, 2 for portal openings.
static func _rank(family: TileFamily) -> int:
	match family:
		TileFamily.STAIR, TileFamily.LADDER:
			return 1
		TileFamily.PORTAL_OPENING:
			return 2
	return 0


## The yaw 0..3 of a horizontal unit direction.
static func yaw_of(dir: Vector3i) -> int:
	return _YAW_DIRS.find(dir)


## The point every path of the sector meets at: the interior node, or for a
## solid sector the centre cell at the floor level nearest below it.
func _hub(sector: Vector3i, n: int) -> Vector3i:
	var node := graph.interior_node(sector)
	if node != null:
		return node.local_cell
	var level := (n / 2) / WalkableGraph.STRATUM_PITCH_CELLS * WalkableGraph.STRATUM_PITCH_CELLS
	return Vector3i(n / 2, level, n / 2)


## The portal cell of an edge inside the sector.
static func portal_cell(sector: Vector3i, edge: WalkableGraph.Edge, n: int) -> Vector3i:
	var cell := Vector3i.ZERO
	cell[edge.axis] = n - 1 if sector == edge.a else 0
	# face_cell holds the two other axes in xyz order.
	var i := 0
	for axis in 3:
		if axis != edge.axis:
			cell[axis] = edge.portal.face_cell[i]
			i += 1
	return cell


func _portal_record(sector: Vector3i, edge: WalkableGraph.Edge, n: int) -> Record:
	var cell := portal_cell(sector, edge, n)
	var orientation: int
	if edge.axis == Vector3i.AXIS_Y:
		orientation = ORIENTATION_UP if sector == edge.a else ORIENTATION_DOWN
	else:
		var out := Vector3i.ZERO
		out[edge.axis] = 1 if sector == edge.a else -1
		orientation = yaw_of(out)
	return Record.make(cell, TileFamily.PORTAL_OPENING, orientation, edge_ref(edge))


## The routings of an edge, most preferred first. Each is a record list that
## is consistent on its own.
func _candidates(sector: Vector3i, edge: WalkableGraph.Edge, hub: Vector3i, surface: TileFamily, n: int) -> Array[Array]:
	var result: Array[Array] = []
	var portal := _portal_record(sector, edge, n)
	if edge.axis == Vector3i.AXIS_Y:
		_vertical_candidates(sector, edge, hub, surface, n, portal, result)
	else:
		_horizontal_candidates(edge, hub, surface, n, portal, result)
	return result


## Horizontal edges: the last leg of the L runs into the portal either across
## the face (along the edge axis) or along the face wall; catwalks prefer the
## wall. A level change sits on the last leg next to the portal: a stair when
## its run fits, else a ladder in the cell before the portal.
func _horizontal_candidates(edge: WalkableGraph.Edge, hub: Vector3i, surface: TileFamily, n: int, portal: Record, result: Array[Array]) -> void:
	var ref := portal.edge_ref
	var p := portal.cell
	var face_axis := Vector3i.AXIS_Z if edge.axis == Vector3i.AXIS_X else Vector3i.AXIS_X
	var last_axes: Array[int] = [edge.axis, face_axis]
	if edge.kind == WalkableGraph.EdgeKind.CATWALK:
		last_axes = [face_axis, edge.axis]
	var rise := p.y - hub.y
	for last_axis in last_axes:
		# Directions along the last leg towards the portal, preferred first.
		var dirs: Array[Vector3i] = []
		if last_axis == edge.axis:
			dirs.append(_unit(last_axis, 1 if p[last_axis] == n - 1 else -1))
		else:
			var toward := signi(p[last_axis] - hub[last_axis])
			if toward == 0:
				toward = 1
			dirs.append(_unit(last_axis, toward))
			dirs.append(_unit(last_axis, -toward))
		var other_axis := face_axis if last_axis == edge.axis else edge.axis
		if rise == 0:
			var plain: Array[Record] = [portal]
			_append_route(plain, hub, p, other_axis, surface, ref)
			result.append(plain)
			continue
		for dir in dirs:
			var steps := absi(rise)
			var landing := p - dir * (steps + 1)
			landing.y = hub.y
			if not _inside(landing, n):
				continue
			var stair: Array[Record] = [portal]
			if rise > 0:
				_append_stair(stair, landing, dir, steps, ref)
			else:
				_append_stair(stair, p, -dir, steps, ref)
			_append_route(stair, hub, landing, _first_axis(hub, landing, p, last_axis, other_axis), surface, ref)
			result.append(stair)
		var before := p - dirs[0]
		if _inside(before, n):
			var ladder: Array[Record] = [portal]
			_append_ladder(ladder, before, mini(p.y, hub.y), maxi(p.y, hub.y), ref)
			_append_route(ladder, hub, Vector3i(before.x, hub.y, before.z), other_axis, surface, ref)
			result.append(ladder)


## Vertical edges: the run climbs from the hub's level to the portal cell at
## the top of the sector (lower sector) or from the portal cell at the bottom
## (upper sector) to the hub's level. Stair edges try a straight stair in the
## four directions, then a ladder; ladder and tunnel edges only a ladder. A
## ladder stands in the portal column or, failing that, in a column beside
## it. The route to the stair's landing ends along the stair.
func _vertical_candidates(sector: Vector3i, edge: WalkableGraph.Edge, hub: Vector3i, surface: TileFamily, n: int, portal: Record, result: Array[Array]) -> void:
	var ref := portal.edge_ref
	var column := portal.cell
	var lower := sector == edge.a
	if edge.kind == WalkableGraph.EdgeKind.STAIR:
		for dir in _YAW_DIRS:
			var stair: Array[Record] = [portal]
			var landing: Vector3i
			if lower:
				var steps := n - 1 - hub.y
				landing = column - dir * (steps + 1)
				landing.y = hub.y
				if not _inside(landing, n):
					continue
				_append_stair(stair, landing, dir, steps, ref)
			else:
				var steps := hub.y
				landing = column + dir * (steps + 1)
				landing.y = hub.y
				if not _inside(landing, n):
					continue
				_append_stair(stair, column, dir, steps, ref)
			var stair_axis := Vector3i.AXIS_X if dir.x != 0 else Vector3i.AXIS_Z
			var cross_axis := Vector3i.AXIS_Z if stair_axis == Vector3i.AXIS_X else Vector3i.AXIS_X
			_append_route(stair, hub, landing, cross_axis, surface, ref)
			result.append(stair)
	# A ladder in the portal column, then in each column beside it, reaching
	# the portal cell's height so the climber steps across into it.
	var offsets: Array[Vector3i] = [Vector3i.ZERO]
	offsets.append_array(_YAW_DIRS)
	for offset in offsets:
		var foot := column + offset
		if not _inside(foot, n):
			continue
		for first_axis in [Vector3i.AXIS_X, Vector3i.AXIS_Z]:
			var ladder: Array[Record] = [portal]
			if offset == Vector3i.ZERO:
				_append_ladder(ladder, foot, hub.y if lower else 1, n - 2 if lower else hub.y, ref)
			else:
				_append_ladder(ladder, foot, hub.y if lower else 0, n - 1 if lower else hub.y, ref)
			_append_route(ladder, hub, Vector3i(foot.x, hub.y, foot.z), first_axis, surface, ref)
			result.append(ladder)


## The first leg of the route to a stair landing: across the stair line, so
## the route meets the landing from outside the stair, unless the hub lies
## between the landing and the portal, where walking along first keeps the
## route off the stair line.
static func _first_axis(hub: Vector3i, landing: Vector3i, p: Vector3i, last_axis: int, other_axis: int) -> int:
	var h := hub[last_axis]
	if (h > landing[last_axis] and h <= p[last_axis]) or (h < landing[last_axis] and h >= p[last_axis]):
		return last_axis
	return other_axis


## Surface cells from `from` to `to` (same height), along `first_axis`, then
## along the other horizontal axis, both ends included.
static func _append_route(out: Array[Record], from: Vector3i, to: Vector3i, first_axis: int, family: TileFamily, ref: Vector4i) -> void:
	var cell := from
	out.append(Record.make(cell, family, 0, ref))
	for axis in [first_axis, Vector3i.AXIS_X + Vector3i.AXIS_Z - first_axis]:
		var step := signi(to[axis] - cell[axis])
		while cell[axis] != to[axis]:
			cell[axis] += step
			out.append(Record.make(cell, family, 0, ref))


## Stair cells climbing from a landing at `low` in direction `dir`: cell k
## (1..steps) is `low + dir * k` at height `low.y + k - 1`, ramping to the
## next level; the upper landing is `low + dir * (steps + 1)` at `low.y + steps`.
static func _append_stair(out: Array[Record], low: Vector3i, dir: Vector3i, steps: int, ref: Vector4i) -> void:
	var yaw := yaw_of(dir)
	for k in range(1, steps + 1):
		out.append(Record.make(low + dir * k + _UP * (k - 1), TileFamily.STAIR, yaw, ref))


## Ladder cells in one column from height `lo` to `hi`, both included.
static func _append_ladder(out: Array[Record], column: Vector3i, lo: int, hi: int, ref: Vector4i) -> void:
	for y in range(lo, hi + 1):
		out.append(Record.make(Vector3i(column.x, y, column.z), TileFamily.LADDER, ORIENTATION_UP, ref))


## Merges records into a copy of `cells`; null on the first conflict.
static func _merge_all(cells: Dictionary, records: Array[Record]) -> Variant:
	var result := cells.duplicate()
	for record in records:
		var existing: Record = result.get(record.cell)
		if existing == null:
			result[record.cell] = record
			continue
		var merged := merge(existing, record)
		if merged == null:
			return null
		result[record.cell] = merged
	return result


static func _inside(cell: Vector3i, n: int) -> bool:
	return cell.x >= 0 and cell.x < n and cell.y >= 0 and cell.y < n and cell.z >= 0 and cell.z < n


static func _unit(axis: int, sign_value: int) -> Vector3i:
	var v := Vector3i.ZERO
	v[axis] = sign_value
	return v


static func _edge_before(p: WalkableGraph.Edge, q: WalkableGraph.Edge) -> bool:
	var vp := p.axis == Vector3i.AXIS_Y
	var vq := q.axis == Vector3i.AXIS_Y
	if vp != vq:
		return vp
	return _ref_before(edge_ref(p), edge_ref(q))


static func _ref_before(p: Vector4i, q: Vector4i) -> bool:
	for i in 4:
		if p[i] != q[i]:
			return p[i] < q[i]
	return false


static func _cell_before(p: Vector3i, q: Vector3i) -> bool:
	if p.x != q.x:
		return p.x < q.x
	if p.y != q.y:
		return p.y < q.y
	return p.z < q.z
