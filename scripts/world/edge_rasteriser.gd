class_name EdgeRasteriser
extends RefCounted
## The fill contract: turns the walkable graph edges of one sector into
## records on its cell grid, the only input the solver takes from the graph.
##
##     var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed))
##     for record in rasteriser.records_for_sector(Vector3i(0, 0, 0)):
##         print(record.cell, EdgeRasteriser.family_name(record.family), record.orientation)
##
## Every edge of `WalkableGraph.edges_for_sector` becomes a walk from the
## sector's hub (its interior node, or the centre of a solid sector) to the
## edge's portal cell on the face, ending in the portal cell itself. Flat
## cells are in the family of the sector type (FLOOR in stratum, CATWALK in
## shaft, BRIDGE in cavity and chasm, TUNNEL in solid), so the walks of one
## sector share one family and meet at the hub. Flat cells never change
## level: a walk goes flat at the hub's level, climbs to the portal's level by
## an oriented stair run (3 cells of run per stratum, turning only at flat
## landings) or, in shaft and chasm sectors, by a ladder, and reaches the
## portal flat. All portal cells are placed first; records at the same cell
## merge by `merge`, and an edge whose walk would conflict with the records
## before it tries its next routing. When none fits it keeps only its portal
## cell and is listed as rejected. Every walking surface of a routing
## (flat cells, stairs and side portal openings) also reserves the cells above
## it as HEADROOM records, `headroom_cells` of them (one more over a stair),
## which merge only with each other. Rules and a worked example are in
## docs/algorithms/edge-rasteriser.md.

## Tile families a record restricts its cell to. HEADROOM is the last and
## belongs to no prototype: it asks for any tile that leaves a walker's head
## room (`TileLibrary.Tile.headroom`).
enum TileFamily { FLOOR, STAIR, BRIDGE, CATWALK, LADDER, TUNNEL, PORTAL_OPENING, HEADROOM }

const FAMILY_NAMES: Array[String] = ["floor", "stair", "bridge", "catwalk", "ladder", "tunnel", "portal_opening", "headroom"]
## Families a tile prototype may belong to: every family before HEADROOM.
const PROTOTYPE_FAMILIES := TileFamily.HEADROOM

## Orientation of a record. 0 to 3 are yaw quarter turns: the forward
## direction is +x turned that many quarter turns about +y (0 +x, 1 -z, 2 -x,
## 3 +z), so a stair's forward is the way up and a portal opening's forward
## points out of the sector. UP and DOWN mark a vertical record: a ladder
## (always UP) or an opening in the ceiling (UP) or floor (DOWN). Floor,
## bridge, catwalk, tunnel and headroom records are unoriented and carry 0.
const ORIENTATION_UP := 4
const ORIENTATION_DOWN := 5

## Flights a stair run search may lay before it gives up on one start.
const RUN_SEARCH_LIMIT := 64
## Default `headroom_cells`: one clear cell above a walking surface
## (decision #171).
const HEADROOM_CELLS := 1

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
	## merging with the other edges (only the portal cell when rejected), in
	## walking order and without its headroom (`headroom_for`).
	var edge_records: Dictionary = {}
	## Edge refs whose every routing conflicted, in rasterising order.
	var rejected: Array[Vector4i] = []
	## Edges that kept a routing other than their first.
	var fallbacks := 0


var graph: WalkableGraph
## Clear cells reserved above every flat cell and side portal opening; a
## stair reserves one more, as its top tread rises to the floor of the cell
## above. 0 turns headroom records off.
var headroom_cells := HEADROOM_CELLS


func _init(walkable_graph: WalkableGraph, headroom := HEADROOM_CELLS) -> void:
	graph = walkable_graph
	headroom_cells = headroom


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
	var hub := hub_cell(sector)
	var surface := surface_family(graph.skeleton.sector_type(graph.world_seed, sector))
	# Accepted records by cell.
	var cells := {}
	# Portal cells are fixed by the graph, so they go in before any path:
	# a path that would run through another edge's portal takes its next
	# routing instead of pushing the portal out.
	var portal_ok := {}
	for edge in edges:
		var portal: Array[Record] = [_portal_record(sector, edge, n)]
		var merged: Variant = _merge_all(cells, portal)
		if merged != null:
			cells = merged
			portal_ok[edge_ref(edge)] = true
	# Then the room above them, where it fits; a portal whose room does not
	# fit leaves every routing of its edge to conflict.
	for edge in edges:
		if portal_ok.has(edge_ref(edge)):
			var merged: Variant = _merge_all(cells, headroom_for([_portal_record(sector, edge, n)]))
			if merged != null:
				cells = merged
	for edge in edges:
		var ref := edge_ref(edge)
		var chosen: Array[Record] = []
		if portal_ok.has(ref):
			chosen = [_portal_record(sector, edge, n)]
			var found := false
			var candidates := _candidates(sector, edge, hub, surface, n, cells)
			for i in candidates.size():
				var with_room: Array[Record] = []
				with_room.assign(candidates[i])
				with_room.append_array(headroom_for(with_room))
				var merged: Variant = _merge_all(cells, with_room)
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
## family and orientation merge. Headroom merges only with headroom: a cell
## one walk needs for its head is no cell another walk may stand in. A ladder
## wins over the surface families (floor, bridge, catwalk, tunnel): its rungs
## stand off one face. A stair or portal opening does not: a flat walk
## through a stair's slope or between a portal's jambs cannot be walked, so
## those pairs conflict (#173). Two portal openings with different yaws merge
## into a corner opening with the smaller yaw. Every other pair conflicts: two
## surface families, stairs of different orientation, a stair and a ladder, a
## portal opening and a stair or ladder. On a tie the smaller edge_ref stays,
## so merge(p, q) equals merge(q, p).
static func merge(p: Record, q: Record) -> Record:
	var rank_p := _rank(p.family)
	var rank_q := _rank(q.family)
	if p.family == q.family and p.orientation == q.orientation:
		return p if _ref_before(p.edge_ref, q.edge_ref) or p.edge_ref == q.edge_ref else q
	if p.family == TileFamily.HEADROOM or q.family == TileFamily.HEADROOM:
		return null
	if rank_p != rank_q:
		if (rank_p == 0 and q.family == TileFamily.LADDER) or (rank_q == 0 and p.family == TileFamily.LADDER):
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


## The HEADROOM records above the walking surfaces among `records`, in
## order, inside the grid: `headroom_cells` cells above a flat cell (floor,
## bridge, catwalk, tunnel) or a portal opening on a side face, one more above
## a stair. Ladders and openings in a floor or ceiling are passages, not
## surfaces, and reserve nothing. A cell above two records is listed twice.
func headroom_for(records: Array[Record]) -> Array[Record]:
	var result: Array[Record] = []
	var n := graph.cells_per_sector()
	for record in records:
		for y in _room_heights(record, headroom_cells):
			if y < n:
				result.append(Record.make(Vector3i(record.cell.x, y, record.cell.z), TileFamily.HEADROOM, 0, record.edge_ref))
	return result


## Heights of the cells a record's walker needs clear above it.
static func _room_heights(record: Record, room: int) -> Array[int]:
	var cells := 0
	match record.family:
		TileFamily.FLOOR, TileFamily.BRIDGE, TileFamily.CATWALK, TileFamily.TUNNEL:
			cells = room
		TileFamily.STAIR:
			cells = room + 1 if room > 0 else 0
		TileFamily.PORTAL_OPENING:
			cells = room if record.orientation < ORIENTATION_UP else 0
	var heights: Array[int] = []
	for k in range(1, cells + 1):
		heights.append(record.cell.y + k)
	return heights


## The yaw 0..3 of a horizontal unit direction.
static func yaw_of(dir: Vector3i) -> int:
	return _YAW_DIRS.find(dir)


## The point every path of the sector meets at: the interior node, or for a
## solid sector the centre cell at the floor level nearest below it.
func hub_cell(sector: Vector3i) -> Vector3i:
	var n := graph.cells_per_sector()
	var node := graph.interior_node(sector)
	if node != null:
		return node.local_cell
	return Vector3i(n / 2, graph.centre_level(), n / 2)


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


## The routings of an edge, most preferred first. Each lists its records in
## walking order, from the hub to the portal cell, and is consistent on its
## own. Every level change is explicit: the path walks flat at the hub's
## level, climbs a stair run (a ladder in shaft and chasm sectors) and walks
## flat again at the other level; no flat cell ever changes level.
func _candidates(sector: Vector3i, edge: WalkableGraph.Edge, hub: Vector3i, surface: TileFamily, n: int, cells: Dictionary) -> Array[Array]:
	var result: Array[Array] = []
	var portal := _portal_record(sector, edge, n)
	var type := graph.skeleton.sector_type(graph.world_seed, sector)
	var by_ladder := type == Skeleton.SectorType.SHAFT or type == Skeleton.SectorType.CHASM
	if edge.axis == Vector3i.AXIS_Y:
		_vertical_candidates(sector, edge, hub, surface, n, portal, by_ladder, cells, result)
	else:
		_horizontal_candidates(edge, hub, surface, n, portal, by_ladder, cells, result)
	return result


## Horizontal edges: the path reaches the portal `p` along the edge axis
## (across the face) or along the face wall; catwalks prefer the wall. Either
## way the last step is across the face, from the door cell `p` + inward,
## because a portal's jambs close its sides: along the wall the path runs to
## the door cell, not to `p`, and a level walk ends in the door cell either
## way (a route through `p` itself conflicts with the portal). A level change sits next to the portal: a stair
## run leaving `p` inwards or leaving the door cell along the wall, or in a
## shaft or chasm a ladder in the cell before `p` or beside the door cell. A
## level walk last tries detours: along the edge axis to the line `d` cells in
## from the face (d = 1 to n - 1), along the face to the portal's column, then
## across to `p`.
func _horizontal_candidates(edge: WalkableGraph.Edge, hub: Vector3i, surface: TileFamily, n: int, portal: Record, by_ladder: bool, cells: Dictionary, result: Array[Array]) -> void:
	var ref := portal.edge_ref
	var p := portal.cell
	var face_axis := Vector3i.AXIS_Z if edge.axis == Vector3i.AXIS_X else Vector3i.AXIS_X
	var inward := _unit(edge.axis, -1 if p[edge.axis] == n - 1 else 1)
	var door := p + inward
	var last_axes: Array[int] = [edge.axis, face_axis]
	if edge.kind == WalkableGraph.EdgeKind.CATWALK:
		last_axes = [face_axis, edge.axis]
	for last_axis in last_axes:
		var other_axis := face_axis if last_axis == edge.axis else edge.axis
		# Along the wall the run ends at the door cell, then steps into `p`.
		var end := p if last_axis == edge.axis else door
		# Directions leaving `end` into the sector, preferred first.
		var dirs: Array[Vector3i] = []
		if last_axis == edge.axis:
			dirs.append(inward)
		else:
			var toward_hub := signi(hub[last_axis] - p[last_axis])
			if toward_hub == 0:
				toward_hub = 1
			dirs.append(_unit(last_axis, toward_hub))
			dirs.append(_unit(last_axis, -toward_hub))
		var tail: Array[Record] = [portal]
		if end != p:
			tail.push_front(Record.make(door, surface, 0, ref))
		if p.y == hub.y:
			# Level walks always end door, portal, even across the face: a hub
			# on the face row would otherwise reach `p` along the wall.
			var plain: Array[Record] = []
			_append_route(plain, hub, door, other_axis, surface, ref, true)
			plain.append(portal)
			result.append(plain)
			continue
		if by_ladder:
			var foot := end + dirs[0]
			if not _inside(foot, n):
				continue
			var ladder: Array[Record] = []
			_append_route(ladder, hub, Vector3i(foot.x, hub.y, foot.z), other_axis, surface, ref, false)
			_append_ladder(ladder, foot, hub.y, p.y, ref)
			ladder.append_array(tail)
			result.append(ladder)
			continue
		for dir in dirs:
			var stair := _stair_run(end, hub, dir, surface, ref, n, cells)
			if not stair.is_empty():
				stair.append_array(tail)
				result.append(stair)
	if p.y != hub.y:
		return
	# Detours, last: across the face along a line `d` cells in from the face,
	# so a level walk can step around the column of another edge's stair.
	var inward_sign := inward[edge.axis]
	for d in range(1, n):
		var line := p[edge.axis] + inward_sign * d
		var first := hub
		first[edge.axis] = line
		var second := first
		second[face_axis] = p[face_axis]
		var detour: Array[Record] = []
		_append_route(detour, hub, first, edge.axis, surface, ref, false)
		_append_route(detour, first, second, face_axis, surface, ref, false)
		_append_route(detour, second, p, edge.axis, surface, ref, false)
		detour.append(portal)
		result.append(detour)


## Vertical edges: the portal cell is at the top of the lower sector
## (y = n - 1) or the bottom of the upper one (y = 0), and the run joins it to
## the hub's level. Outside shafts and chasms a stair run leaves the portal
## column in each of the four directions in turn; in a shaft or chasm a ladder
## stands in the portal column, or failing that in a column beside it and
## reaching the portal's height, so the climber steps across into it.
func _vertical_candidates(sector: Vector3i, edge: WalkableGraph.Edge, hub: Vector3i, surface: TileFamily, n: int, portal: Record, by_ladder: bool, cells: Dictionary, result: Array[Array]) -> void:
	var ref := portal.edge_ref
	var column := portal.cell
	var lower := sector == edge.a
	if not by_ladder:
		for dir in _YAW_DIRS:
			var stair := _stair_run(column, hub, dir, surface, ref, n, cells)
			if not stair.is_empty():
				stair.append(portal)
				result.append(stair)
		return
	var offsets: Array[Vector3i] = [Vector3i.ZERO]
	offsets.append_array(_YAW_DIRS)
	for offset in offsets:
		var foot := column + offset
		if not _inside(foot, n):
			continue
		var top := n - 2 if offset == Vector3i.ZERO else n - 1
		var bottom := 1 if offset == Vector3i.ZERO else 0
		for first_axis in [Vector3i.AXIS_X, Vector3i.AXIS_Z]:
			var ladder: Array[Record] = []
			_append_route(ladder, hub, Vector3i(foot.x, hub.y, foot.z), first_axis, surface, ref, false)
			_append_ladder(ladder, foot, hub.y, top if lower else bottom, ref)
			ladder.append(portal)
			result.append(ladder)


## A stair run from the hub's level to the flat cell `end` (the portal),
## in walking order from the hub, without `end`; empty when none fits.
##
## The run is built backwards from `end`: it leaves `end` in `first_dir`, one
## stair cell per level cell, in flights that end on floor levels (3 steps
## per stratum). After each flight it goes straight on, turns at a flat
## landing towards the sector centre, turns the other way, or turns back, in
## that order, taking the first choice whose flight and following cell fit in
## the sector and whose cells are free in `cells` (a cell holding a record of
## the same surface family counts as free). A choice that leads nowhere is
## undone and the next one tried, at most RUN_SEARCH_LIMIT flights per run.
## The last flat cell at the hub's level is the landing the route from the
## hub reaches, along the stair when the hub lies behind it, else across it.
func _stair_run(end: Vector3i, hub: Vector3i, first_dir: Vector3i, surface: TileFamily, ref: Vector4i, n: int, cells: Dictionary) -> Array[Record]:
	var outward: Array[Record] = []
	var budget: Array[int] = [RUN_SEARCH_LIMIT]
	var up := 1 if hub.y > end.y else -1
	if not _flights(end, end.y, Vector3i.ZERO, first_dir, up, absi(hub.y - end.y), surface, ref, n, cells, outward, budget):
		return []
	# The walk ends with the landing at the hub's level, stored last.
	var landing: Record = outward.pop_back()
	var last_stair: Record = outward[-1]
	var dir := Vector3i(landing.cell.x - last_stair.cell.x, 0, landing.cell.z - last_stair.cell.z)
	var result: Array[Record] = []
	var behind := _dot(hub - landing.cell, dir) < 0
	var dir_axis := Vector3i.AXIS_X if dir.x != 0 else Vector3i.AXIS_Z
	var cross_axis := Vector3i.AXIS_X + Vector3i.AXIS_Z - dir_axis
	_append_route(result, hub, landing.cell, dir_axis if behind else cross_axis, surface, ref, true)
	outward.reverse()
	result.append_array(outward)
	return result


## One step of the stair run search: from `cursor`, where the last flight
## ended (or `end`) at floor height `h` heading `dir`, lays the next flight
## and recurses; appends to `outward` and returns true once `remaining` is 0.
func _flights(cursor: Vector3i, h: int, dir: Vector3i, first_dir: Vector3i, up: int, remaining: int, surface: TileFamily, ref: Vector4i, n: int, cells: Dictionary, outward: Array[Record], budget: Array[int]) -> bool:
	if remaining == 0:
		var landing := Record.make(Vector3i(cursor.x + dir.x, h, cursor.z + dir.z), surface, 0, ref)
		if not _free(cells, landing) or not _stair_clear(cells, outward, landing) or not _room(cells, outward, landing):
			return false
		outward.append(landing)
		return true
	if budget[0] <= 0:
		return false
	budget[0] -= 1
	var pitch := WalkableGraph.STRATUM_PITCH_CELLS
	var to_level := pitch - posmod(h, pitch) if up > 0 else (posmod(h, pitch) if posmod(h, pitch) != 0 else pitch)
	var flight := mini(to_level, remaining)
	var options: Array[Vector3i] = [first_dir]
	if dir != Vector3i.ZERO:
		var side := _unit(Vector3i.AXIS_Z if dir.x != 0 else Vector3i.AXIS_X, 1)
		var toward := signi(n / 2 - _dot(cursor, side))
		if toward == 0:
			toward = 1
		options = [dir, side * toward, side * -toward, -dir]
	for d in options:
		var turning := dir != Vector3i.ZERO and d != dir
		var start := cursor + dir if turning else cursor
		if not _inside(start, n) or not _inside(start + d * (flight + 1), n):
			continue
		var laid: Array[Record] = []
		if turning:
			laid.append(Record.make(Vector3i(start.x, h, start.z), surface, 0, ref))
		for k in range(1, flight + 1):
			var cell := start + d * k
			cell.y = h + k - 1 if up > 0 else h - k
			laid.append(Record.make(cell, TileFamily.STAIR, yaw_of(d if up > 0 else -d), ref))
		var free := true
		var pending: Array[Record] = outward.duplicate()
		pending.append_array(laid)
		for record in laid:
			free = free and _free(cells, record) and _stair_clear(cells, pending, record) and _room(cells, pending, record)
		if not free:
			continue
		var mark := outward.size()
		outward.append_array(laid)
		if _flights(start + d * flight, h + up * flight, d, first_dir, up, remaining - flight, surface, ref, n, cells, outward, budget):
			return true
		outward.resize(mark)
	return false


## True when `record` can take its cell without overriding anything: the cell
## is empty or holds the same family and orientation.
static func _free(cells: Dictionary, record: Record) -> bool:
	var existing: Record = cells.get(record.cell)
	return existing == null or (existing.family == record.family and existing.orientation == record.orientation)


## True when `record` keeps the stair rule against the records in `cells`
## and in `pending`: nothing but headroom directly above or below a stair
## cell. Headroom records themselves are never checked.
static func _stair_clear(cells: Dictionary, pending: Array[Record], record: Record) -> bool:
	if record.family == TileFamily.HEADROOM:
		return true
	for step in [_UP, -_UP]:
		var next: Vector3i = record.cell + step
		var other: Record = cells.get(next)
		for candidate in pending:
			if candidate.cell == next:
				other = candidate
		if other != null and other.family != TileFamily.HEADROOM and (record.family == TileFamily.STAIR or other.family == TileFamily.STAIR):
			return false
	return true


## True when the headroom of `record` is free (empty or headroom in `cells`,
## no record of `pending`) and `record` is in no headroom of `pending`.
func _room(cells: Dictionary, pending: Array[Record], record: Record) -> bool:
	for y in _room_heights(record, headroom_cells):
		var above := Vector3i(record.cell.x, y, record.cell.z)
		var existing: Record = cells.get(above)
		if existing != null and existing.family != TileFamily.HEADROOM:
			return false
		for candidate in pending:
			if candidate.cell == above:
				return false
	for candidate in pending:
		if candidate.cell.x == record.cell.x and candidate.cell.z == record.cell.z and record.cell.y in _room_heights(candidate, headroom_cells):
			return false
	return true


## Surface cells from `from` to `to` (same height), along `first_axis`, then
## along the other horizontal axis, in walking order; `to` only when
## `include_end`.
static func _append_route(out: Array[Record], from: Vector3i, to: Vector3i, first_axis: int, family: TileFamily, ref: Vector4i, include_end: bool) -> void:
	var cell := from
	var cells: Array[Vector3i] = [cell]
	for axis in [first_axis, Vector3i.AXIS_X + Vector3i.AXIS_Z - first_axis]:
		var step := signi(to[axis] - cell[axis])
		while cell[axis] != to[axis]:
			cell[axis] += step
			cells.append(cell)
	if not include_end:
		cells.pop_back()
	for c in cells:
		out.append(Record.make(c, family, 0, ref))


## Ladder cells in one column from height `from_y` to `to_y`, both included,
## in climbing order.
static func _append_ladder(out: Array[Record], column: Vector3i, from_y: int, to_y: int, ref: Vector4i) -> void:
	var step := 1 if to_y >= from_y else -1
	for y in range(from_y, to_y + step, step):
		out.append(Record.make(Vector3i(column.x, y, column.z), TileFamily.LADDER, ORIENTATION_UP, ref))


## Merges records into a copy of `cells`; null on the first conflict or when
## the result breaks the stair rule at one of the records' cells (a stair
## cell with a record other than headroom directly above or below it).
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
	for record in records:
		if not _stair_clear(result, [], result[record.cell]):
			return null
	return result


static func _inside(cell: Vector3i, n: int) -> bool:
	return cell.x >= 0 and cell.x < n and cell.y >= 0 and cell.y < n and cell.z >= 0 and cell.z < n


static func _dot(p: Vector3i, q: Vector3i) -> int:
	return p.x * q.x + p.y * q.y + p.z * q.z


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
