class_name SectorSolver
extends RefCounted
## Fills a grid of cells with tiles of a `TileLibrary` so that every pair of
## face neighbours is allowed by the adjacency table: simple-tiled Wave
## Function Collapse without backtracking.
##
##     var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
##     var solver := SectorSolver.new(library, Vector3i(8, 8, 8))
##     var result := solver.solve(0, Vector3i.ZERO)
##     if result.ok:
##         print(library.tiles[result.cells[0]].label(), " ", result.steps, " ", result.time_usec)
##
## Cells are indexed `x + size.x * (y + size.y * z)`; `Result.cells` holds
## one tile index per cell in that order. The wave is one `PackedInt64Array`
## of `cell_count * word_count` words, bit t of a cell's words set while tile
## t is still possible there.
##
## Each observation takes the open cell (more than one tile left) with the
## fewest tiles (minimum remaining values), ties broken by a per-cell hashed
## priority, kept in an indexed min-heap; with `use_entropy` the Shannon
## entropy of the tile weights replaces the tile count. The cell's tile is drawn by weight with
## `Hash.hash3_u` salted with the observation counter. Propagation is bitset
## AC-3: a changed cell ANDs, per direction, the union of its tiles' allowed
## sets into the neighbour, and a neighbour that shrank is queued. The union
## is read from byte-sliced tables, so it costs a few lookups per word
## whatever the domain size. An empty domain is a contradiction and ends the
## solve with `ok` false. Nothing is random but the hash, and no `Dictionary`
## is iterated.
##
## `solve` first ANDs the optional starting `domains` (from `SectorDomains`)
## into the wave and propagates them; since that does not depend on the seed,
## an empty domain there fails at once with `Outcome.FAILED`. Each attempt
## then starts from that propagated wave with its own attempt seed; a
## contradiction restarts with the next attempt, up to `max_attempts`, after
## which the result is the all-solid degradation: every cell the solid tile,
## `Outcome.DEGRADED`. Steps, a worked example, complexity and salts are in
## docs/algorithms/sector-solver.md.

## Base salt of the per-attempt seed drawn from the solve seed and the
## sector; the attempt number (below `ATTEMPT_LIMIT`) is added.
const ATTEMPT_SALT := 9100
## Default of `max_attempts`.
const DEFAULT_MAX_ATTEMPTS := 8
## Largest `max_attempts`: the attempt salts stay below `TIE_SALT`.
const ATTEMPT_LIMIT := 100
## Salt of the per-cell tie-break priority.
const TIE_SALT := 9200
## Base salt of the weighted tile choice; the observation counter is added.
const CHOICE_SALT := 9300
## Fixed-point scale of tile weights: a weight of 1.0 counts as 1000.
const WEIGHT_SCALE := 1000
## Largest summed integer weight of one domain, so `hash * total` stays
## below 2^63.
const MAX_TOTAL_WEIGHT := 0x7FFFFFFF
## Fixed-point scale of the Shannon entropy key.
const ENTROPY_SCALE := 16777216.0
## Bytes per bitset word.
const SLICES := 8


## How a solve ended.
enum Outcome {
	## An attempt filled every cell.
	SOLVED,
	## Every attempt hit a contradiction; every cell holds the solid tile.
	DEGRADED,
	## Invalid arguments or inconsistent starting domains; no cells.
	FAILED,
}

const OUTCOME_NAMES: Array[String] = ["solved", "degraded", "failed"]


## Outcome of one solve.
class Result:
	extends RefCounted
	## Whether every cell holds exactly one tile: solved or degraded.
	var ok := false
	var outcome := Outcome.FAILED
	## True when the cells are the all-solid degradation.
	var degraded := false
	## Tile index per cell, `x + size.x * (y + size.y * z)`; empty unless ok.
	var cells := PackedInt32Array()
	## Attempts run, 1 to `max_attempts`; 0 when the starting domains failed.
	var attempts := 0
	## Attempts that ended in a contradiction and were restarted or degraded.
	var restarts := 0
	## Cells whose starting domain `domains` narrowed, ascending.
	var precollapsed := PackedInt32Array()
	## Observations made over all attempts (cells collapsed by a weighted draw).
	var steps := 0
	## Cells taken off the propagation queue over all attempts.
	var propagations := 0
	## Wall time of the solve in microseconds, all attempts included.
	var time_usec := 0
	## Cell whose domain became empty in the last contradiction, or -1.
	var contradiction_cell := -1
	## Why the solve failed, empty unless the outcome is FAILED.
	var error := ""


## Cells per axis.
var size: Vector3i
## Choose cells by Shannon entropy of the tile weights instead of tile count.
var use_entropy := false
## Attempts before the all-solid degradation, clamped to 1..ATTEMPT_LIMIT.
var max_attempts := DEFAULT_MAX_ATTEMPTS

var _library: TileLibrary
var _tile_count := 0
var _words := 0
var _cell_count := 0
## Index offset per direction, +x, -x, +y, -y, +z, -z.
var _offsets := PackedInt32Array()
## Per cell, bit d set when the neighbour in direction d is inside the grid.
var _borders := PackedByteArray()
## Words of the domain holding every tile.
var _full := PackedInt64Array()
## Integer weight per tile.
var _weights := PackedInt64Array()
## Union of the allowed sets of the tiles in one byte of a domain word:
## `_union[(((dir * words + word) * SLICES + slice) * 256 + byte) * words + out_word]`.
var _union := PackedInt64Array()
## Bytes of each word that hold tiles (the rest are always zero).
var _slices_used := PackedInt32Array()
## Set bits per byte value.
var _popcount := PackedInt32Array()
## Summed integer weight of the tiles in one byte: `[(word * SLICES + slice) * 256 + byte]`.
var _byte_weight := PackedInt64Array()
## Summed w * log(w) of the tiles in one byte, same layout.
var _byte_wlogw := PackedFloat64Array()

# Per-solve state, reused between solves.
var _wave := PackedInt64Array()
var _counts := PackedInt32Array()
## Current cell selection key without the priority: tile count or entropy.
var _primary := PackedInt64Array()
var _priority := PackedInt64Array()
var _stack := PackedInt32Array()
var _queued := PackedByteArray()
var _heap_keys := PackedInt64Array()
var _heap_cells := PackedInt32Array()
var _heap_size := 0
var _heap_pos := PackedInt32Array()
## False while the starting domains propagate, before the heap exists.
var _heap_ready := false
var _mask := PackedInt64Array()
## Wave, counts and keys after the starting domains propagated.
var _start_wave := PackedInt64Array()
var _start_counts := PackedInt32Array()
var _start_primary := PackedInt64Array()


## A solver for grids of `grid_size` cells over the tiles of `library`, which
## must have no errors.
func _init(library: TileLibrary, grid_size := Vector3i(24, 24, 24)) -> void:
	_library = library
	size = grid_size
	_tile_count = library.tile_count()
	_words = library.word_count
	_cell_count = size.x * size.y * size.z
	_offsets = PackedInt32Array([1, -1, size.x, -size.x, size.x * size.y, -size.x * size.y])
	_build_borders()
	_build_tables()


## Fills the grid for `seed` and `sector`. `domains`, when not empty, holds
## `cell_count * word_count` words ANDed into the starting wave (pre-collapsed
## cells and fixed faces, see `SectorDomains`); it is propagated once before
## the first attempt, and a contradiction there fails without restarting.
## Each attempt restarts from the propagated wave; after `max_attempts`
## contradictions every cell becomes the solid tile.
func solve(seed: int, sector: Vector3i, domains := PackedInt64Array()) -> Result:
	var started := Time.get_ticks_usec()
	var result := Result.new()
	if _tile_count == 0 or not _library.errors.is_empty():
		result.error = "tile library is empty or invalid"
		return _finish(result, started)
	if size.x < 1 or size.y < 1 or size.z < 1:
		result.error = "grid size %s is not positive" % size
		return _finish(result, started)
	if not domains.is_empty() and domains.size() != _cell_count * _words:
		result.error = "domains has %d words, expected %d" % [domains.size(), _cell_count * _words]
		return _finish(result, started)

	_reset(domains)
	if not domains.is_empty():
		for cell in _cell_count:
			if _counts[cell] < _tile_count:
				result.precollapsed.append(cell)
			if _counts[cell] == 0:
				return _inconsistent(result, cell, "starts empty", started)
			if _counts[cell] < _tile_count:
				_queued[cell] = 1
				_stack.append(cell)
		var bad := _propagate(result)
		if bad >= 0:
			return _inconsistent(result, bad, "is left empty by propagating them", started)
	_start_wave = _wave.duplicate()
	_start_counts = _counts.duplicate()
	_start_primary = _primary.duplicate()

	var attempts := clampi(max_attempts, 1, ATTEMPT_LIMIT)
	for attempt in attempts:
		result.attempts = attempt + 1
		if attempt > 0:
			_wave = _start_wave.duplicate()
			_counts = _start_counts.duplicate()
			_primary = _start_primary.duplicate()
		var attempt_seed := Hash.hash3_u(seed, sector, ATTEMPT_SALT + attempt)
		if _attempt(result, attempt_seed):
			result.cells = _collapsed_cells()
			result.ok = true
			result.outcome = Outcome.SOLVED
			return _finish(result, started)
		result.restarts += 1

	result.cells.resize(_cell_count)
	result.cells.fill(_library.solid_tile)
	result.ok = true
	result.degraded = true
	result.outcome = Outcome.DEGRADED
	return _finish(result, started)


func cell_count() -> int:
	return _cell_count


## Grid position of a cell index.
func position(cell: int) -> Vector3i:
	return Vector3i(cell % size.x, (cell / size.x) % size.y, cell / (size.x * size.y))


## Cell index of a grid position.
func index(cell_position: Vector3i) -> int:
	return cell_position.x + size.x * (cell_position.y + size.y * cell_position.z)


## Direction bits of neighbours inside the grid, per cell.
func _build_borders() -> void:
	_borders.resize(_cell_count)
	for z in size.z:
		for y in size.y:
			for x in size.x:
				var bits := 0
				if x + 1 < size.x:
					bits |= 1
				if x > 0:
					bits |= 2
				if y + 1 < size.y:
					bits |= 4
				if y > 0:
					bits |= 8
				if z + 1 < size.z:
					bits |= 16
				if z > 0:
					bits |= 32
				_borders[x + size.x * (y + size.y * z)] = bits


## The full domain, integer weights, and the byte-sliced union, popcount,
## weight and w log w tables.
func _build_tables() -> void:
	_full.resize(_words)
	_full.fill(0)
	_weights.resize(_tile_count)
	var wlogw := PackedFloat64Array()
	wlogw.resize(_tile_count)
	for tile in _tile_count:
		_full[tile >> 6] |= 1 << (tile & 63)
		_weights[tile] = maxi(1, roundi(_library.tiles[tile].weight * WEIGHT_SCALE))
		wlogw[tile] = float(_weights[tile]) * log(float(_weights[tile]))
	_slices_used.resize(_words)
	for w in _words:
		var tiles_in_word := mini(_tile_count - w * 64, 64)
		_slices_used[w] = (tiles_in_word + 7) / 8
	_mask.resize(_words)

	_popcount.resize(256)
	for v in 256:
		_popcount[v] = (v & 1) + _popcount[v >> 1]

	var allowed: Array[PackedInt64Array] = []
	for dir in TilePrototype.FACE_COUNT:
		allowed.append(PackedInt64Array())
		for tile in _tile_count:
			allowed[dir].append_array(_library.allowed(dir, tile))

	_union.resize(TilePrototype.FACE_COUNT * _words * SLICES * 256 * _words)
	_union.fill(0)
	_byte_weight.resize(_words * SLICES * 256)
	_byte_weight.fill(0)
	_byte_wlogw.resize(_words * SLICES * 256)
	_byte_wlogw.fill(0.0)
	for w in _words:
		for s in SLICES:
			var slice_base := (w * SLICES + s) * 256
			# Each byte value extends the value without its lowest set bit.
			for v in range(1, 256):
				var low := 0
				while (v >> low) & 1 == 0:
					low += 1
				var rest := v & (v - 1)
				var tile := w * 64 + s * 8 + low
				if tile >= _tile_count:
					continue
				_byte_weight[slice_base + v] = _byte_weight[slice_base + rest] + _weights[tile]
				_byte_wlogw[slice_base + v] = _byte_wlogw[slice_base + rest] + wlogw[tile]
				for dir in TilePrototype.FACE_COUNT:
					var base := ((dir * _words + w) * SLICES + s) * 256
					for o in _words:
						_union[(base + v) * _words + o] = _union[(base + rest) * _words + o] | allowed[dir][tile * _words + o]


## The starting wave, counts and keys, before any propagation.
func _reset(domains: PackedInt64Array) -> void:
	_wave.resize(_cell_count * _words)
	if _words == 1:
		_wave.fill(_full[0])
	else:
		for cell in _cell_count:
			for w in _words:
				_wave[cell * _words + w] = _full[w]
	if not domains.is_empty():
		for i in _wave.size():
			_wave[i] &= domains[i]
	_counts.resize(_cell_count)
	_primary.resize(_cell_count)
	_priority.resize(_cell_count)
	_queued.resize(_cell_count)
	_queued.fill(0)
	_stack.clear()
	_heap_ready = false
	for cell in _cell_count:
		_update_cell(cell)


## One attempt from the propagated starting wave: priorities, heap, then
## observe and propagate until every cell holds one tile (true) or a
## contradiction (false, `contradiction_cell` set).
func _attempt(result: Result, attempt_seed: int) -> bool:
	_heap_ready = false
	for cell in _cell_count:
		_priority[cell] = Hash.hash3_u(attempt_seed, position(cell), TIE_SALT)
	_build_heap()
	var step := 0
	while _heap_size > 0:
		var cell := _heap_cells[0]
		_heap_remove(0)
		_observe(cell, attempt_seed, step)
		step += 1
		result.steps += 1
		_queued[cell] = 1
		_stack.append(cell)
		var bad := _propagate(result)
		if bad >= 0:
			_queued.fill(0)
			_stack.clear()
			result.contradiction_cell = bad
			return false
	return true


## Recomputes the tile count and selection key of a cell from its words.
func _update_cell(cell: int) -> void:
	var base := cell * _words
	var count := 0
	var weight := 0
	var wlogw := 0.0
	for w in _words:
		var word := _wave[base + w]
		for s in _slices_used[w]:
			var v := (word >> (s * 8)) & 255
			if v == 0:
				continue
			count += _popcount[v]
			if use_entropy:
				var t := (w * SLICES + s) * 256 + v
				weight += _byte_weight[t]
				wlogw += _byte_wlogw[t]
	_counts[cell] = count
	if not use_entropy:
		_primary[cell] = count
	elif count <= 1:
		_primary[cell] = 0
	else:
		var entropy := log(float(weight)) - wlogw / float(weight)
		_primary[cell] = clampi(int(entropy * ENTROPY_SCALE), 0, 0x7FFFFFFF)


## Collapses an open cell to one tile drawn by weight.
func _observe(cell: int, attempt_seed: int, step: int) -> void:
	var base := cell * _words
	var total := 0
	for w in _words:
		var word := _wave[base + w]
		for s in _slices_used[w]:
			total += _byte_weight[(w * SLICES + s) * 256 + ((word >> (s * 8)) & 255)]
	if total > MAX_TOTAL_WEIGHT:
		push_error("SectorSolver: summed tile weight %d above %d" % [total, MAX_TOTAL_WEIGHT])
	var draw := (Hash.hash3_u(attempt_seed, position(cell), CHOICE_SALT + step) * total) >> 32
	var chosen := -1
	for w in _words:
		var word := _wave[base + w]
		for s in _slices_used[w]:
			var v := (word >> (s * 8)) & 255
			var byte_weight := _byte_weight[(w * SLICES + s) * 256 + v]
			if draw >= byte_weight:
				draw -= byte_weight
				continue
			for b in 8:
				if (v >> b) & 1 == 0:
					continue
				var tile := w * 64 + s * 8 + b
				if draw < _weights[tile]:
					chosen = tile
					break
				draw -= _weights[tile]
			break
		if chosen >= 0:
			break
	for w in _words:
		_wave[base + w] = 0
	_wave[base + (chosen >> 6)] = 1 << (chosen & 63)
	_counts[cell] = 1
	_primary[cell] = 1 if not use_entropy else 0


## Bitset AC-3 over the queued cells. Returns the first cell whose domain
## became empty, or -1.
func _propagate(result: Result) -> int:
	var words := _words
	var slices := _slices_used[0]
	var propagations := 0
	var top := _stack.size()
	while top > 0:
		top -= 1
		var cell := _stack[top]
		_queued[cell] = 0
		propagations += 1
		var base := cell * words
		var borders := _borders[cell]
		for dir in TilePrototype.FACE_COUNT:
			if (borders >> dir) & 1 == 0:
				continue
			var neighbour := cell + _offsets[dir]
			var neighbour_base := neighbour * words
			var changed := false
			var empty := true
			if words == 1:
				var word := _wave[base]
				var mask := 0
				var table := dir * SLICES * 256
				for s in slices:
					mask |= _union[table + ((word >> (s * 8)) & 255)]
					table += 256
				var old := _wave[neighbour_base]
				var narrowed := old & mask
				if narrowed == old:
					continue
				if narrowed == 0:
					_stack.resize(top)
					result.propagations += propagations
					return neighbour
				changed = true
				empty = false
				_wave[neighbour_base] = narrowed
			else:
				_mask.fill(0)
				for w in words:
					var word := _wave[base + w]
					for s in _slices_used[w]:
						var t := ((((dir * words + w) * SLICES + s) * 256) + ((word >> (s * 8)) & 255)) * words
						for o in words:
							_mask[o] |= _union[t + o]
				for o in words:
					var old := _wave[neighbour_base + o]
					var narrowed := old & _mask[o]
					if narrowed != old:
						_wave[neighbour_base + o] = narrowed
						changed = true
					if narrowed != 0:
						empty = false
			if empty:
				_stack.resize(top)
				result.propagations += propagations
				return neighbour
			if not changed:
				continue
			if words == 1 and not use_entropy:
				var narrowed_word := _wave[neighbour_base]
				var count := 0
				for s in slices:
					count += _popcount[(narrowed_word >> (s * 8)) & 255]
				_counts[neighbour] = count
				_primary[neighbour] = count
			else:
				_update_cell(neighbour)
			if _heap_ready:
				_heap_update(neighbour)
			if _queued[neighbour] == 0:
				_queued[neighbour] = 1
				if top == _stack.size():
					_stack.resize(top * 2 + 16)
				_stack[top] = neighbour
				top += 1
	_stack.resize(0)
	result.propagations += propagations
	return -1


## Fails a solve whose starting domains cannot hold, whatever the seed.
func _inconsistent(result: Result, cell: int, what: String, started: int) -> Result:
	result.contradiction_cell = cell
	result.error = "inconsistent starting domains: cell %s %s; the records or fixed faces contradict each other" % [position(cell), what]
	return _finish(result, started)


func _finish(result: Result, started: int) -> Result:
	result.time_usec = Time.get_ticks_usec() - started
	return result


## Tile index per cell of a fully collapsed wave.
func _collapsed_cells() -> PackedInt32Array:
	var cells := PackedInt32Array()
	cells.resize(_cell_count)
	for cell in _cell_count:
		var base := cell * _words
		for w in _words:
			var word := _wave[base + w]
			if word == 0:
				continue
			var bit := 0
			while (word >> bit) & 1 == 0:
				bit += 1
			cells[cell] = w * 64 + bit
			break
	return cells


# Indexed binary min-heap of the open cells, ordered by key
# (`primary << 32 | priority`) then cell index. `_heap_pos[cell]` is the
# cell's slot or -1, so a changed key moves the entry in place and the heap
# never holds more than one entry per cell.

func _build_heap() -> void:
	_heap_keys.resize(_cell_count)
	_heap_cells.resize(_cell_count)
	_heap_pos.resize(_cell_count)
	_heap_pos.fill(-1)
	_heap_size = 0
	_heap_ready = true
	for cell in _cell_count:
		if _counts[cell] > 1:
			_heap_keys[_heap_size] = _primary[cell] << 32 | _priority[cell]
			_heap_cells[_heap_size] = cell
			_heap_pos[cell] = _heap_size
			_heap_size += 1
	var i := _heap_size / 2 - 1
	while i >= 0:
		_sift_down(i)
		i -= 1


## Moves, inserts or removes a cell after its count or key changed.
func _heap_update(cell: int) -> void:
	var slot := _heap_pos[cell]
	if _counts[cell] <= 1:
		if slot >= 0:
			_heap_remove(slot)
		return
	var key := _primary[cell] << 32 | _priority[cell]
	if slot < 0:
		slot = _heap_size
		_heap_size += 1
		_heap_keys[slot] = key
		_heap_cells[slot] = cell
		_heap_pos[cell] = slot
		_sift_up(slot)
		return
	var old := _heap_keys[slot]
	_heap_keys[slot] = key
	if key < old:
		_sift_up(slot)
	elif key > old:
		_sift_down(slot)


func _heap_remove(slot: int) -> void:
	_heap_pos[_heap_cells[slot]] = -1
	_heap_size -= 1
	if slot == _heap_size:
		return
	_heap_keys[slot] = _heap_keys[_heap_size]
	_heap_cells[slot] = _heap_cells[_heap_size]
	var moved := _heap_cells[slot]
	_heap_pos[moved] = slot
	_sift_down(slot)
	if _heap_pos[moved] == slot:
		_sift_up(slot)


func _sift_up(start: int) -> void:
	var i := start
	var key := _heap_keys[i]
	var cell := _heap_cells[i]
	while i > 0:
		var parent := (i - 1) >> 1
		var parent_key := _heap_keys[parent]
		if parent_key < key or (parent_key == key and _heap_cells[parent] < cell):
			break
		_heap_keys[i] = parent_key
		_heap_cells[i] = _heap_cells[parent]
		_heap_pos[_heap_cells[i]] = i
		i = parent
	_heap_keys[i] = key
	_heap_cells[i] = cell
	_heap_pos[cell] = i


func _sift_down(start: int) -> void:
	var i := start
	var key := _heap_keys[i]
	var cell := _heap_cells[i]
	while true:
		var child := 2 * i + 1
		if child >= _heap_size:
			break
		var child_key := _heap_keys[child]
		var child_cell := _heap_cells[child]
		if child + 1 < _heap_size:
			var right_key := _heap_keys[child + 1]
			if right_key < child_key or (right_key == child_key and _heap_cells[child + 1] < child_cell):
				child += 1
				child_key = right_key
				child_cell = _heap_cells[child]
		if key < child_key or (key == child_key and cell < child_cell):
			break
		_heap_keys[i] = child_key
		_heap_cells[i] = child_cell
		_heap_pos[child_cell] = i
		i = child
	_heap_keys[i] = key
	_heap_cells[i] = cell
	_heap_pos[cell] = i
