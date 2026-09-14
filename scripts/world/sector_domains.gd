class_name SectorDomains
extends RefCounted
## The starting domains of one sector solve: turns `EdgeRasteriser` records,
## the sector type and optional fixed boundary faces into the `domains` words
## `SectorSolver.solve` takes.
##
##     var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
##     var rasteriser := EdgeRasteriser.new(WalkableGraph.new(seed))
##     var built := SectorDomains.for_sector(library, rasteriser, sector)
##     if built.error.is_empty():
##         var result := SectorSolver.new(library).solve(seed, sector, built.words)
##
## Each record restricts its cell to the tiles whose prototype family is the
## record's family and whose rotation matches its orientation
## (`tile_matches`): a stair's rotation is the yaw of the way up, a portal
## opening on a side face is turned so its passage points out of the sector,
## every other family (and a portal opening in the floor or ceiling) takes any
## rotation. A headroom record takes every tile that leaves a walker's head
## room (`TileLibrary.Tile.headroom`: air, and on the placeholder tileset the
## wall doorway under its lintel). A floor record also drops the tiles that
## block a side face (`TileLibrary.Tile.blocked_faces`, a parapet) towards a
## face-neighbour record a walker may step to: any record but headroom at the
## same height, or a stair one lower climbing into the floor. Cells without a
## record take the sector's fill tile, solid in a solid sector and air in
## every other (#180), except the support cells: a cell across a face of a
## record where no tile of the record allows the fill tile (on the placeholder
## tileset the rock face a catwalk or ladder hangs on) keeps the free tiles,
## those of no family, that every such record allows there. So walk-family
## tiles stand only in record cells (decision 0018). A fixed
## face lists, per boundary cell, the tile of the neighbour sector across the
## face or -1; the boundary cell keeps only the tiles allowed next to it.
## Records that cannot hold (outside the grid, two at one cell, an orientation
## the family does not take, no tile of the family, two face-neighbour records
## with no allowed tile pair, nothing left next to a fixed face tile) set
## `error` instead. Steps and a worked example are in
## docs/algorithms/sector-solver.md.

## Grid step of each face index, +x, -x, +y, -y, +z, -z.
const STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## Yaw of the forward direction of a prototype at rotation 0, per family
## whose rotation follows the record's orientation: a stair climbs towards
## +x (yaw 0), a portal opening's passage runs along z (yaw 3).
const AUTHORED_YAW := {
	EdgeRasteriser.TileFamily.STAIR: 0,
	EdgeRasteriser.TileFamily.PORTAL_OPENING: 3,
}

## `cell_count * word_count` words, bit t of a cell's words set while tile t
## may start there; empty when `error` is set.
var words := PackedInt64Array()
## Cell index of every record, ascending.
var record_cells := PackedInt32Array()
## Cell index of every support cell, ascending.
var support_cells := PackedInt32Array()
## Why the domains could not be built, empty when they could.
var error := ""


## The domains of a real sector: its type from the graph's skeleton and its
## records from the rasteriser, on a 24³ grid (the graph's cells per sector).
static func for_sector(library: TileLibrary, rasteriser: EdgeRasteriser, sector: Vector3i, faces: Array[PackedInt32Array] = []) -> SectorDomains:
	var graph := rasteriser.graph
	var n := graph.cells_per_sector()
	var type := graph.skeleton.sector_type(graph.world_seed, sector)
	return build(library, Vector3i(n, n, n), type, rasteriser.records_for_sector(sector), faces)


## The domains of a grid of `size` cells of sector type `type` holding
## `records`. `faces` is empty (every face free) or six arrays in face order
## +x, -x, +y, -y, +z, -z, each empty (free) or one entry per boundary cell,
## indexed `u + size_u * v` with u and v the two other axes in xyz order: the
## tile index of the neighbour cell across the face, or -1 for free.
static func build(library: TileLibrary, size: Vector3i, type: Skeleton.SectorType, records: Array[EdgeRasteriser.Record], faces: Array[PackedInt32Array] = []) -> SectorDomains:
	var built := SectorDomains.new()
	var tile_count := library.tile_count()
	if tile_count == 0 or not library.errors.is_empty():
		built.error = "tile library is empty or invalid"
		return built
	var word_count := library.word_count
	var cell_count := size.x * size.y * size.z

	var fill := _single(word_count, library.solid_tile if type == Skeleton.SectorType.SOLID else library.air_tile)
	var free := _single(word_count, -1)
	for tile in library.tiles:
		if tile.prototype.family == TilePrototype.FAMILY_NONE:
			free[tile.index >> 6] |= 1 << (tile.index & 63)

	# Records and their masks by cell.
	var by_cell := {}
	var masks := {}
	for record in records:
		var cell := record.cell
		if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= size.x or cell.y >= size.y or cell.z >= size.z:
			built.error = "%s: cell outside the %s grid" % [record, size]
			return built
		if masks.has(cell):
			built.error = "%s: a second record at the same cell" % record
			return built
		var problem := orientation_error(record.family, record.orientation)
		if not problem.is_empty():
			built.error = "%s: %s" % [record, problem]
			return built
		var mask := family_mask(library, record.family, record.orientation)
		if _is_empty(mask):
			built.error = "%s: no tile of the library matches the family and orientation" % record
			return built
		masks[cell] = mask
		by_cell[cell] = record

	# A floor keeps its faces towards walkable neighbours open.
	for record in records:
		if record.family != EdgeRasteriser.TileFamily.FLOOR:
			continue
		for dir in TilePrototype.FACE_COUNT:
			if TilePrototype.is_vertical(dir):
				continue
			var next: Vector3i = record.cell + STEPS[dir]
			var level: EdgeRasteriser.Record = by_cell.get(next)
			var below: EdgeRasteriser.Record = by_cell.get(next + Vector3i.DOWN)
			var steps_to := level != null and level.family != EdgeRasteriser.TileFamily.HEADROOM
			steps_to = steps_to or (below != null and below.family == EdgeRasteriser.TileFamily.STAIR)
			if steps_to:
				masks[record.cell] = _without_blocked(library, masks[record.cell], dir)
		if _is_empty(masks[record.cell]):
			built.error = "%s: every floor tile blocks a face a walk crosses" % record
			return built

	# Face-neighbour records must admit at least one allowed tile pair.
	for record in records:
		for dir in TilePrototype.FACE_COUNT:
			var next: Vector3i = record.cell + STEPS[dir]
			var other: EdgeRasteriser.Record = by_cell.get(next)
			if other == null or not _before(record.cell, next):
				continue
			if not _any_allowed(library, dir, masks[record.cell], masks[next]):
				built.error = "%s and %s cannot touch across %s: no tile of the first allows a tile of the second there" % [record, other, TilePrototype.FACE_NAMES[dir]]
				return built

	# A cell beside a record also takes the free tiles a tile of the record
	# needs there: what it allows across a face where it does not allow fill.
	var supports := {}
	for record in records:
		for dir in TilePrototype.FACE_COUNT:
			var next: Vector3i = record.cell + STEPS[dir]
			if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= size.x or next.y >= size.y or next.z >= size.z:
				continue
			if masks.has(next):
				continue
			var needed := _needed(library, dir, masks[record.cell], fill)
			var added := false
			for w in word_count:
				needed[w] &= free[w]
				added = added or needed[w] != 0
			if not added:
				continue
			var domain: PackedInt64Array = supports.get(next, fill).duplicate()
			for w in word_count:
				domain[w] |= needed[w]
			supports[next] = domain

	built.words.resize(cell_count * word_count)
	for z in size.z:
		for y in size.y:
			for x in size.x:
				var cell := x + size.x * (y + size.y * z)
				var position := Vector3i(x, y, z)
				var domain: PackedInt64Array = fill
				if masks.has(position):
					domain = masks[position]
					built.record_cells.append(cell)
				elif supports.has(position):
					domain = supports[position]
					built.support_cells.append(cell)
				for w in word_count:
					built.words[cell * word_count + w] = domain[w]

	if not faces.is_empty():
		built.error = apply_faces(library, size, built.words, faces)
		if not built.error.is_empty():
			built.words.clear()
	return built


## ANDs fixed faces into `domains` (see `build`). Returns an error message, or
## "" when every boundary cell keeps at least one tile.
static func apply_faces(library: TileLibrary, size: Vector3i, domains: PackedInt64Array, faces: Array[PackedInt32Array]) -> String:
	var word_count := library.word_count
	if faces.size() != TilePrototype.FACE_COUNT:
		return "faces has %d entries, expected %d" % [faces.size(), TilePrototype.FACE_COUNT]
	for dir in TilePrototype.FACE_COUNT:
		var face := faces[dir]
		if face.is_empty():
			continue
		var axis := dir >> 1
		var u_axis := 1 if axis == 0 else 0
		var v_axis := 1 if axis == 2 else 2
		var size_u := size[u_axis]
		var size_v := size[v_axis]
		if face.size() != size_u * size_v:
			return "face %s has %d entries, expected %d" % [TilePrototype.FACE_NAMES[dir], face.size(), size_u * size_v]
		for v in size_v:
			for u in size_u:
				var neighbour := face[u + size_u * v]
				if neighbour < 0:
					continue
				if neighbour >= library.tile_count():
					return "face %s entry (%d, %d): tile %d outside the library" % [TilePrototype.FACE_NAMES[dir], u, v, neighbour]
				var position := Vector3i.ZERO
				position[axis] = size[axis] - 1 if dir & 1 == 0 else 0
				position[u_axis] = u
				position[v_axis] = v
				var cell := position.x + size.x * (position.y + size.y * position.z)
				# Tile t fits when the neighbour allows t from the opposite side.
				var allowed := library.allowed(dir ^ 1, neighbour)
				var left := false
				for w in word_count:
					domains[cell * word_count + w] &= allowed[w]
					left = left or domains[cell * word_count + w] != 0
				if not left:
					return "cell %s: no tile fits next to %s across face %s" % [position, library.tiles[neighbour].label(), TilePrototype.FACE_NAMES[dir]]
	return ""


## Why `orientation` is not valid for `family`, or "".
static func orientation_error(family: EdgeRasteriser.TileFamily, orientation: int) -> String:
	match family:
		EdgeRasteriser.TileFamily.STAIR:
			if orientation < 0 or orientation > 3:
				return "a stair needs a yaw 0..3, not %d" % orientation
		EdgeRasteriser.TileFamily.LADDER:
			if orientation != EdgeRasteriser.ORIENTATION_UP:
				return "a ladder needs orientation up (%d), not %d" % [EdgeRasteriser.ORIENTATION_UP, orientation]
		EdgeRasteriser.TileFamily.PORTAL_OPENING:
			if orientation < 0 or orientation > EdgeRasteriser.ORIENTATION_DOWN:
				return "a portal opening needs a yaw 0..3, up or down, not %d" % orientation
		_:
			if orientation != 0:
				return "an unoriented family needs orientation 0, not %d" % orientation
	return ""


## Whether a tile may stand in a cell holding a record of `family` and
## `orientation`: same family, and for a stair or a portal opening on a side
## face a rotation that turns the prototype's forward yaw onto the record's.
## For HEADROOM: any tile with head room, whatever its family.
static func tile_matches(tile: TileLibrary.Tile, family: EdgeRasteriser.TileFamily, orientation: int) -> bool:
	if family == EdgeRasteriser.TileFamily.HEADROOM:
		return tile.headroom
	if tile.prototype.family != family:
		return false
	if not AUTHORED_YAW.has(family) or orientation >= EdgeRasteriser.ORIENTATION_UP:
		return true
	return posmod(tile.rotation - (orientation - AUTHORED_YAW[family]), tile.prototype.rotations) == 0


## The tiles `tile_matches` accepts, as `word_count` words.
static func family_mask(library: TileLibrary, family: EdgeRasteriser.TileFamily, orientation: int) -> PackedInt64Array:
	var mask := _single(library.word_count, -1)
	for tile in library.tiles:
		if tile_matches(tile, family, orientation):
			mask[tile.index >> 6] |= 1 << (tile.index & 63)
	return mask


## Whether some tile of `from` allows some tile of `to` in direction `dir`.
static func _any_allowed(library: TileLibrary, dir: int, from: PackedInt64Array, to: PackedInt64Array) -> bool:
	for tile in library.tile_count():
		if (from[tile >> 6] >> (tile & 63)) & 1 == 0:
			continue
		var allowed := library.allowed(dir, tile)
		for w in library.word_count:
			if allowed[w] & to[w] != 0:
				return true
	return false


## The tiles the tiles of `from` need in direction `dir`: the union of what
## each allows there, over those that do not allow a tile of `fill` there.
static func _needed(library: TileLibrary, dir: int, from: PackedInt64Array, fill: PackedInt64Array) -> PackedInt64Array:
	var result := _single(library.word_count, -1)
	for tile in library.tile_count():
		if (from[tile >> 6] >> (tile & 63)) & 1 == 0:
			continue
		var allowed := library.allowed(dir, tile)
		var takes_fill := false
		for w in library.word_count:
			takes_fill = takes_fill or allowed[w] & fill[w] != 0
		if takes_fill:
			continue
		for w in library.word_count:
			result[w] |= allowed[w]
	return result


## Whether `p` comes before `q` in cell index order, so each pair is checked once.
static func _before(p: Vector3i, q: Vector3i) -> bool:
	if p.z != q.z:
		return p.z < q.z
	if p.y != q.y:
		return p.y < q.y
	return p.x < q.x


## `mask` without the tiles that block side face `dir`.
static func _without_blocked(library: TileLibrary, mask: PackedInt64Array, dir: int) -> PackedInt64Array:
	var result := mask.duplicate()
	for tile in library.tiles:
		if tile.blocked_faces & (1 << dir) != 0:
			result[tile.index >> 6] &= ~(1 << (tile.index & 63))
	return result


## `word_count` words with only `tile` set (none for -1).
static func _single(word_count: int, tile: int) -> PackedInt64Array:
	var mask := PackedInt64Array()
	mask.resize(word_count)
	mask.fill(0)
	if tile >= 0:
		mask[tile >> 6] = 1 << (tile & 63)
	return mask


static func _is_empty(mask: PackedInt64Array) -> bool:
	for word in mask:
		if word != 0:
			return false
	return true
