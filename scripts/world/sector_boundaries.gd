class_name SectorBoundaries
extends RefCounted
## Face-first, order-independent sector boundaries: solves the cells sectors
## share at their borders from keys of their own, before any sector interior,
## so two neighbouring sectors compute the same border without reading each
## other.
##
##     var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
##     var boundaries := SectorBoundaries.new(library, seed, EdgeRasteriser.new(WalkableGraph.new(seed)))
##     var sector := boundaries.solve_sector(seed, Vector3i(3, 0, 7))
##     print(sector.solved, " ", sector.cells.size())             # true 13824
##     print(boundaries.face(Vector3i(3, 0, 7), TilePrototype.FACE_POS_X)
##         == boundaries.face(Vector3i(4, 0, 7), TilePrototype.FACE_NEG_X))   # true
##
## With `n` cells per axis and `m = n - 1`, the boundary cells of a sector are
## the cells of its outermost layer on the positive side of each axis, owned
## by that sector, the canonical lower sector of every border (decision
## #162). They form four levels, each solved with `SectorSolver` from its own
## hash key:
##
## - **corner** of owner `s`: cell `(m, m, m)`, one cell.
## - **edge** of `s` along axis `a`: the cells with coordinate `a` in
##   `0..m-1` and the other two at `m`, a line of `m` cells; with the corner it
##   is the `n`-cell line `edge(s, a)`.
## - **face** of `s` across axis `a`: the cells with coordinate `a` at `m` and
##   the other two in `0..m-1`, an `m x m` square; with its two own edges and
##   the corner it is the `n x n` layer `face(s, dir)`.
## - **interior** of `s`: the `m³` cells with every coordinate below `m`.
##
## A piece's cells start from the owner's `SectorDomains` (records and sector
## type; free without a rasteriser). A boundary cell without a record also
## keeps only the tiles that accept air on every side facing a cell of a
## higher level, so filling everything above with air is always possible
## (decision #163). The cells are then constrained, through the fixed
## faces of `SectorDomains.apply_faces`, by every neighbouring cell of a lower
## level, in its own sector or across a border: an edge by its two corners, a
## face by its four edges, an interior by its six faces. Cells of the same
## level never touch unless they belong to one piece, so the order is a fixed
## tree and every piece is a pure function of the seed, its owner and its
## kind. A piece whose starting domains fail is filled with the solid tile,
## as is the interior of a sector whose records are inconsistent; the
## boundary pieces of such a sector use its type's default domains instead.
## Pieces are cached until `clear_cache` or a seed change. Steps, a worked
## example and complexity are in docs/algorithms/face-first-boundaries.md.

## Base salt of a piece's solve seed; the piece kind (`Kind`) is added.
const PIECE_SALT := 9000
## Grid step of each face index, +x, -x, +y, -y, +z, -z.
const STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## What a piece is; also its salt offset from `PIECE_SALT`.
enum Kind {
	CORNER,
	EDGE_X,
	EDGE_Y,
	EDGE_Z,
	FACE_X,
	FACE_Y,
	FACE_Z,
	INTERIOR,
}

## Level of each piece kind: solved after every lower level it touches.
enum Level { CORNER, EDGE, FACE, INTERIOR }

const LEVEL_NAMES: Array[String] = ["corner", "edge", "face", "interior"]


## One solved piece.
class Piece:
	extends RefCounted
	var kind := Kind.CORNER
	var owner := Vector3i.ZERO
	## First owner-local cell and cells per axis of the piece.
	var origin := Vector3i.ZERO
	var size := Vector3i.ONE
	## Tile per piece cell, `x + size.x * (y + size.y * z)` from `origin`.
	var cells := PackedInt32Array()
	var outcome := SectorSolver.Outcome.FAILED
	var attempts := 0
	## Observations and propagation queue pops of the piece's solve.
	var steps := 0
	var propagations := 0
	## Why the piece failed (its cells are solid), or "".
	var error := ""
	var time_usec := 0


## A sector composed from its 8 corners, 12 edges, 6 faces and interior.
class SectorResult:
	extends RefCounted
	var sector := Vector3i.ZERO
	## Tile per cell of the `n³` sector, `x + n * (y + n * z)`.
	var cells := PackedInt32Array()
	## True when every piece the sector uses was solved (none degraded or failed).
	var solved := false
	## Pieces the sector uses that degraded to solid or failed.
	var degraded := 0
	var failed := 0
	## Errors of the failed pieces.
	var errors := PackedStringArray()
	## Every piece the sector uses: corners, edges, faces, then the interior.
	var pieces: Array[Piece] = []
	var interior: Piece
	## Wall time of this call per level (corner, edge, face, interior); pieces
	## already cached cost nothing.
	var level_usec := PackedInt64Array([0, 0, 0, 0])


## Seed of every piece solve; `solve_sector` sets it.
var seed := 0
## Cells per sector axis.
var cells_per_sector := 24
## Solves per level (corner, edge, face, interior) since construction.
var level_solves := PackedInt32Array([0, 0, 0, 0])
## Microseconds spent solving per level since construction.
var level_usec := PackedInt64Array([0, 0, 0, 0])
## Outcome counts per level: `[level * 3 + outcome]`.
var level_outcomes := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

var _library: TileLibrary
var _rasteriser: EdgeRasteriser
## Kind -> owner -> Piece.
var _pieces: Array[Dictionary] = []
## Owner -> domain words of its n³ grid (records and type).
var _domains := {}
## Owner -> why its records could not be turned into domains.
var _domain_errors := {}
## Grid size -> SectorSolver.
var _solvers := {}
## Owner -> Dictionary of its record cell indices.
var _record_cells := {}
var _full := PackedInt64Array()
## Per direction, the tiles that accept the air tile next to them there.
var _open: Array[PackedInt64Array] = []


## Boundaries over `library` for world seed `world_seed`. With a
## `rasteriser`, pieces honour the records and sector types of its graph and
## `cells` is its cells per sector; without one every cell starts free.
func _init(library: TileLibrary, world_seed := 0, rasteriser: EdgeRasteriser = null, cells := 24) -> void:
	_library = library
	_rasteriser = rasteriser
	seed = world_seed
	cells_per_sector = rasteriser.graph.cells_per_sector() if rasteriser != null else cells
	_full.resize(library.word_count)
	_full.fill(0)
	for tile in library.tile_count():
		_full[tile >> 6] |= 1 << (tile & 63)
	for dir in TilePrototype.FACE_COUNT:
		var open := PackedInt64Array()
		open.resize(library.word_count)
		open.fill(0)
		for tile in library.tile_count():
			if library.is_allowed(dir, tile, library.air_tile):
				open[tile >> 6] |= 1 << (tile & 63)
		_open.append(open)
	clear_cache()


## Forgets every solved piece and domain.
func clear_cache() -> void:
	_pieces.clear()
	for kind in Kind.size():
		_pieces.append({})
	_domains.clear()
	_domain_errors.clear()
	_record_cells.clear()


## The tile of the corner cell `(m, m, m)` of `sector`.
func corner(sector: Vector3i) -> int:
	return _piece(Kind.CORNER, sector).cells[0]


## The `n` cells of `sector` along `axis` (0 x, 1 y, 2 z) whose other two
## coordinates are `m`, by coordinate on `axis`; the last is `corner(sector)`.
func edge(sector: Vector3i, axis: int) -> PackedInt32Array:
	var line := _piece(Kind.EDGE_X + axis, sector).cells.duplicate()
	line.append(corner(sector))
	return line


## The `n x n` boundary layer between `sector` and its neighbour across face
## `dir` (+x, -x, +y, -y, +z, -z), indexed `u + n * v` with u and v the other
## two axes in xyz order, as `SectorDomains` fixed faces are. The layer is the
## lower sector's outermost layer, so `face(s, +x) == face(s + x, -x)`.
func face(sector: Vector3i, dir: int) -> PackedInt32Array:
	var axis := dir >> 1
	var owner := sector if dir & 1 == 0 else sector + STEPS[dir]
	var n := cells_per_sector
	var m := n - 1
	var u_axis := 1 if axis == 0 else 0
	var v_axis := 1 if axis == 2 else 2
	var layer := PackedInt32Array()
	layer.resize(n * n)
	var inner := _piece(Kind.FACE_X + axis, owner)
	var u_edge := edge(owner, u_axis)
	var v_edge := edge(owner, v_axis)
	for v in n:
		for u in n:
			if u == m:
				layer[u + n * v] = v_edge[v]
			elif v == m:
				layer[u + n * v] = u_edge[u]
			else:
				layer[u + n * v] = inner.cells[u + m * v]
	return layer


## Solves (or reads from the cache) every piece of `sector` at solve seed
## `solve_seed` and composes its `n³` cells.
func solve_sector(solve_seed: int, sector: Vector3i) -> SectorResult:
	if solve_seed != seed:
		seed = solve_seed
		clear_cache()
	var result := SectorResult.new()
	result.sector = sector
	var n := cells_per_sector
	var m := n - 1
	var used: Array[Piece] = []
	for level in Level.size():
		var started := Time.get_ticks_usec()
		for kind in _kinds_of_level(level):
			for offset in _owner_offsets(kind):
				used.append(_piece(kind, sector + offset))
		result.level_usec[level] = Time.get_ticks_usec() - started
	result.pieces = used
	result.interior = used[used.size() - 1]
	result.solved = true
	for piece in used:
		if piece.outcome == SectorSolver.Outcome.SOLVED:
			continue
		result.solved = false
		if piece.outcome == SectorSolver.Outcome.DEGRADED:
			result.degraded += 1
		else:
			result.failed += 1
			result.errors.append("%s of %s: %s" % [Kind.keys()[piece.kind].to_lower(), piece.owner, piece.error])

	result.cells.resize(n * n * n)
	for z in n:
		for y in n:
			for x in n:
				var cell := Vector3i(x, y, z)
				var index := x + n * (y + n * z)
				if x < m and y < m and z < m:
					result.cells[index] = result.interior.cells[x + m * (y + m * z)]
				else:
					result.cells[index] = _boundary_tile(sector, cell)
	return result


## Level of an owner-local cell: corner 0 (three coordinates at m), edge 1,
## face 2, interior 3.
func level_of(cell: Vector3i) -> int:
	var m := cells_per_sector - 1
	return 3 - int(cell.x == m) - int(cell.y == m) - int(cell.z == m)


static func level_of_kind(kind: int) -> int:
	if kind == Kind.CORNER:
		return Level.CORNER
	if kind <= Kind.EDGE_Z:
		return Level.EDGE
	if kind <= Kind.FACE_Z:
		return Level.FACE
	return Level.INTERIOR


static func _kinds_of_level(level: int) -> Array[int]:
	match level:
		Level.CORNER:
			return [Kind.CORNER]
		Level.EDGE:
			return [Kind.EDGE_X, Kind.EDGE_Y, Kind.EDGE_Z]
		Level.FACE:
			return [Kind.FACE_X, Kind.FACE_Y, Kind.FACE_Z]
	return [Kind.INTERIOR]


## Offsets from a sector to the owners of the pieces of `kind` it uses: the
## pieces on its own positive side and those its negative neighbours own.
static func _owner_offsets(kind: int) -> Array[Vector3i]:
	var free := _free_axes(kind)
	var offsets: Array[Vector3i] = []
	for z: int in [-1, 0]:
		for y: int in [-1, 0]:
			for x: int in [-1, 0]:
				var offset := Vector3i(x, y, z)
				var keep := true
				for axis in 3:
					if (free >> axis) & 1 == 1 and offset[axis] != 0:
						keep = false
				if keep:
					offsets.append(offset)
	return offsets


## Bit a set for each axis a the piece spans.
static func _free_axes(kind: int) -> int:
	if kind == Kind.CORNER:
		return 0
	if kind <= Kind.EDGE_Z:
		return 1 << (kind - Kind.EDGE_X)
	if kind <= Kind.FACE_Z:
		return 7 & ~(1 << (kind - Kind.FACE_X))
	return 7


## The cached piece, solved on first use.
func _piece(kind: int, owner: Vector3i) -> Piece:
	var cached: Piece = _pieces[kind].get(owner)
	if cached != null:
		return cached
	var piece := _solve_piece(kind, owner)
	_pieces[kind][owner] = piece
	return piece


func _solve_piece(kind: int, owner: Vector3i) -> Piece:
	var started := Time.get_ticks_usec()
	var n := cells_per_sector
	var m := n - 1
	var word_count := _library.word_count
	var piece := Piece.new()
	piece.kind = kind
	piece.owner = owner
	var free := _free_axes(kind)
	var level := level_of_kind(kind)
	for axis in 3:
		piece.origin[axis] = 0 if (free >> axis) & 1 == 1 else m
		piece.size[axis] = m if (free >> axis) & 1 == 1 else 1
	var size := piece.size
	var count := size.x * size.y * size.z

	# Starting domains: the owner's domains restricted to the piece's cells.
	# Starting domains: the owner's domains restricted to the piece's cells;
	# a boundary cell without a record keeps only open sockets towards the
	# cells of higher levels.
	var owner_words := _owner_words(owner)
	var records: Dictionary = _record_cells.get(owner, {})
	var domains := PackedInt64Array()
	domains.resize(count * word_count)
	for z in size.z:
		for y in size.y:
			for x in size.x:
				var cell := x + size.x * (y + size.y * z)
				var local := piece.origin + Vector3i(x, y, z)
				var source := local.x + n * (local.y + n * local.z)
				for w in word_count:
					domains[cell * word_count + w] = _full[w] if owner_words.is_empty() else owner_words[source * word_count + w]
				if level == Level.INTERIOR or records.has(source):
					continue
				for dir in TilePrototype.FACE_COUNT:
					var next := _normalise(owner, local + STEPS[dir])
					if level_of(next[1]) <= level:
						continue
					for w in word_count:
						domains[cell * word_count + w] &= _open[dir][w]

	# Fixed faces: every neighbouring cell of a lower level.
	var faces: Array[PackedInt32Array] = []
	var any_fixed := false
	for dir in TilePrototype.FACE_COUNT:
		var axis := dir >> 1
		var u_axis := 1 if axis == 0 else 0
		var v_axis := 1 if axis == 2 else 2
		var fixed := PackedInt32Array()
		for v in size[v_axis]:
			for u in size[u_axis]:
				var local := piece.origin
				local[axis] += size[axis] - 1 if dir & 1 == 0 else 0
				local[u_axis] += u
				local[v_axis] += v
				var next := _normalise(owner, local + STEPS[dir])
				var neighbour_level := level_of(next[1])
				if neighbour_level > level:
					continue
				if neighbour_level == level:
					push_error("SectorBoundaries: %s of %s touches a piece of its own level at %s" % [Kind.keys()[kind], owner, next])
					continue
				if fixed.is_empty():
					fixed.resize(size[u_axis] * size[v_axis])
					fixed.fill(-1)
				fixed[u + size[u_axis] * v] = _boundary_tile(next[0], next[1])
				any_fixed = true
		faces.append(fixed)

	if kind == Kind.INTERIOR and _domain_errors.has(owner):
		piece.error = _domain_errors[owner]
	elif any_fixed:
		piece.error = SectorDomains.apply_faces(_library, size, domains, faces)
	if piece.error.is_empty():
		var result := _solver(size).solve(Hash.hash3_u(seed, owner, PIECE_SALT + kind), owner, domains)
		piece.outcome = result.outcome
		piece.attempts = result.attempts
		piece.steps = result.steps
		piece.propagations = result.propagations
		piece.error = result.error
		piece.cells = result.cells
	if piece.outcome == SectorSolver.Outcome.FAILED:
		piece.cells.resize(count)
		piece.cells.fill(_library.solid_tile)
	piece.time_usec = Time.get_ticks_usec() - started
	level_solves[level] += 1
	level_outcomes[level * 3 + piece.outcome] += 1
	return piece


## The tile of boundary cell `cell` of `sector` (not an interior cell).
func _boundary_tile(sector: Vector3i, cell: Vector3i) -> int:
	var m := cells_per_sector - 1
	match level_of(cell):
		Level.CORNER:
			return corner(sector)
		Level.EDGE:
			var axis := 0 if cell.x != m else 1 if cell.y != m else 2
			return _piece(Kind.EDGE_X + axis, sector).cells[cell[axis]]
		Level.FACE:
			var axis := 0 if cell.x == m else 1 if cell.y == m else 2
			var piece := _piece(Kind.FACE_X + axis, sector)
			var local := cell - piece.origin
			return piece.cells[local.x + piece.size.x * (local.y + piece.size.y * local.z)]
	push_error("SectorBoundaries: %s of %s is not a boundary cell" % [cell, sector])
	return -1


## `[sector, cell]` of an owner-local cell that may lie one step outside the
## grid.
func _normalise(sector: Vector3i, cell: Vector3i) -> Array[Vector3i]:
	var n := cells_per_sector
	for axis in 3:
		if cell[axis] < 0:
			cell[axis] += n
			sector[axis] -= 1
		elif cell[axis] >= n:
			cell[axis] -= n
			sector[axis] += 1
	return [sector, cell]


## The owner's `n³` domain words, or empty (every tile) without a rasteriser.
func _owner_words(owner: Vector3i) -> PackedInt64Array:
	if _rasteriser == null:
		return PackedInt64Array()
	if _domains.has(owner):
		return _domains[owner]
	var built := SectorDomains.for_sector(_library, _rasteriser, owner)
	var records := {}
	for cell in built.record_cells:
		records[cell] = true
	_record_cells[owner] = records
	if not built.error.is_empty():
		_domain_errors[owner] = built.error
		var graph := _rasteriser.graph
		var n := cells_per_sector
		var no_records: Array[EdgeRasteriser.Record] = []
		built = SectorDomains.build(_library, Vector3i(n, n, n), graph.skeleton.sector_type(graph.world_seed, owner), no_records)
	_domains[owner] = built.words
	return built.words


func _solver(size: Vector3i) -> SectorSolver:
	var solver: SectorSolver = _solvers.get(size)
	if solver == null:
		solver = SectorSolver.new(_library, size)
		_solvers[size] = solver
	return solver
