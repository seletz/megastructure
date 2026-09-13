class_name Skeleton
extends RefCounted
## The skeleton layer: one type per 48 m sector from the hashed grammar.
##
##     var skeleton := Skeleton.new()              # default SectorGrammar
##     var t := skeleton.sector_type(seed, Vector3i(ix, iy, iz))
##
## `sector_type()` is a pure function of (seed, cell) and the grammar: it never
## looks at neighbouring sectors. It still reads structured because every rule
## is decided on a cell coarser than one sector, so a single hash covers a
## shaft run, a cavity box, a solid wall or a chasm. Rules are tested in order
## of precedence and the first that claims the sector wins:
##     chasm > cavity > shaft > solid > stratum
## Each decision uses its own salt (SALT_* below; the table is in
## docs/algorithms/sector-skeleton-and-walkable-graph.md).

enum SectorType { STRATUM, SHAFT, CAVITY, SOLID, CHASM }

const TYPE_NAMES: Array[String] = ["stratum", "shaft", "cavity", "solid", "chasm"]

const SALT_SHAFT_CHANCE := 100
const SALT_SHAFT_LENGTH := 101
const SALT_SHAFT_START := 102
const SALT_CAVITY_CHANCE := 110
const SALT_CAVITY_SIZE_X := 111
const SALT_CAVITY_SIZE_Y := 112
const SALT_CAVITY_SIZE_Z := 113
const SALT_CAVITY_OFFSET_X := 114
const SALT_CAVITY_OFFSET_Y := 115
const SALT_CAVITY_OFFSET_Z := 116
const SALT_SOLID_WALL_X_PLANE := 120
const SALT_SOLID_WALL_Z_PLANE := 121
const SALT_SOLID_FLOOR_PLANE := 122
const SALT_SOLID_WALL_X := 123
const SALT_SOLID_WALL_Z := 124
const SALT_SOLID_FLOOR := 125
const SALT_CHASM_CHANCE := 130
const SALT_CHASM_OFFSET_X := 131
const SALT_CHASM_HEIGHT := 132
const SALT_CHASM_OFFSET_Y := 133

var grammar: SectorGrammar


func _init(sector_grammar: SectorGrammar = null) -> void:
	grammar = sector_grammar if sector_grammar != null else SectorGrammar.new()


func sector_type(seed: int, cell: Vector3i) -> SectorType:
	if _is_chasm(seed, cell):
		return SectorType.CHASM
	if _is_cavity(seed, cell):
		return SectorType.CAVITY
	if _is_shaft(seed, cell):
		return SectorType.SHAFT
	if _is_solid(seed, cell):
		return SectorType.SOLID
	return SectorType.STRATUM


static func type_name(type: SectorType) -> String:
	return TYPE_NAMES[type]


## Chasm: a band `chasm_band` sectors wide in x and `chasm_band_height` tall
## in y holds, with chasm_probability, one canyon `chasm_width` wide at a
## hashed x offset and a hashed height and y offset. It runs without end in z.
func _is_chasm(seed: int, cell: Vector3i) -> bool:
	var band_x := maxi(grammar.chasm_band, 1)
	var band_y := maxi(grammar.chasm_band_height, 1)
	var key := Vector3i(_floor_div(cell.x, band_x), _floor_div(cell.y, band_y), 0)
	if Hash.hash3(seed, key, SALT_CHASM_CHANCE) >= grammar.chasm_probability:
		return false
	var width := clampi(grammar.chasm_width, 1, band_x)
	var x0 := _pick(seed, key, SALT_CHASM_OFFSET_X, 0, band_x - width)
	var max_height := clampi(grammar.chasm_max_height, 1, band_y)
	var height := _pick(seed, key, SALT_CHASM_HEIGHT, clampi(grammar.chasm_min_height, 1, max_height), max_height)
	var y0 := _pick(seed, key, SALT_CHASM_OFFSET_Y, 0, band_y - height)
	return _within(posmod(cell.x, band_x), x0, width) and _within(posmod(cell.y, band_y), y0, height)


## Cavity: a cubic cell of `cavity_cell` sectors holds, with
## cavity_probability, one box of hashed size and offset inside it.
func _is_cavity(seed: int, cell: Vector3i) -> bool:
	var size := maxi(grammar.cavity_cell, 1)
	var key := Vector3i(_floor_div(cell.x, size), _floor_div(cell.y, size), _floor_div(cell.z, size))
	if Hash.hash3(seed, key, SALT_CAVITY_CHANCE) >= grammar.cavity_probability:
		return false
	return (
		_in_box_axis(seed, key, posmod(cell.x, size), size, SALT_CAVITY_SIZE_X, SALT_CAVITY_OFFSET_X)
		and _in_box_axis(seed, key, posmod(cell.y, size), size, SALT_CAVITY_SIZE_Y, SALT_CAVITY_OFFSET_Y)
		and _in_box_axis(seed, key, posmod(cell.z, size), size, SALT_CAVITY_SIZE_Z, SALT_CAVITY_OFFSET_Z)
	)


func _in_box_axis(seed: int, key: Vector3i, local: int, size: int, size_salt: int, offset_salt: int) -> bool:
	var max_extent := clampi(grammar.cavity_max_size, 1, size)
	var extent := _pick(seed, key, size_salt, clampi(grammar.cavity_min_size, 1, max_extent), max_extent)
	return _within(local, _pick(seed, key, offset_salt, 0, size - extent), extent)


## Shaft: the column (ix, iz) is cut into vertical segments of
## `shaft_segment` sectors; each holds, with shaft_probability, one run of
## hashed length and start, so a shaft continues through several sectors.
func _is_shaft(seed: int, cell: Vector3i) -> bool:
	var segment := maxi(grammar.shaft_segment, 1)
	var key := Vector3i(cell.x, _floor_div(cell.y, segment), cell.z)
	if Hash.hash3(seed, key, SALT_SHAFT_CHANCE) >= grammar.shaft_probability:
		return false
	var max_len := clampi(grammar.shaft_max_len, 1, segment)
	var length := _pick(seed, key, SALT_SHAFT_LENGTH, clampi(grammar.shaft_min_len, 1, max_len), max_len)
	return _within(posmod(cell.y, segment), _pick(seed, key, SALT_SHAFT_START, 0, segment - length), length)


## Solid: space is cut into cubic blocks of `solid_grid` sectors. Each band of
## blocks along x has one wall plane at a hashed x offset shared by the whole
## band (so walls of neighbouring blocks line up), likewise along z, and one
## floor plane along y. Each block closes its x wall and z wall with
## solid_wall_probability and its floor with solid_floor_probability.
func _is_solid(seed: int, cell: Vector3i) -> bool:
	var grid := maxi(grammar.solid_grid, 1)
	var block := Vector3i(_floor_div(cell.x, grid), _floor_div(cell.y, grid), _floor_div(cell.z, grid))
	if (
		posmod(cell.x, grid) == _pick(seed, Vector3i(block.x, 0, 0), SALT_SOLID_WALL_X_PLANE, 0, grid - 1)
		and Hash.hash3(seed, block, SALT_SOLID_WALL_X) < grammar.solid_wall_probability
	):
		return true
	if (
		posmod(cell.z, grid) == _pick(seed, Vector3i(block.z, 0, 0), SALT_SOLID_WALL_Z_PLANE, 0, grid - 1)
		and Hash.hash3(seed, block, SALT_SOLID_WALL_Z) < grammar.solid_wall_probability
	):
		return true
	return (
		posmod(cell.y, grid) == _pick(seed, Vector3i(block.y, 0, 0), SALT_SOLID_FLOOR_PLANE, 0, grid - 1)
		and Hash.hash3(seed, block, SALT_SOLID_FLOOR) < grammar.solid_floor_probability
	)


## Integer in lo..hi (inclusive) from the 32-bit hash; lo when hi <= lo.
static func _pick(seed: int, key: Vector3i, salt: int, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + Hash.hash3_u(seed, key, salt) % (hi - lo + 1)


static func _within(value: int, start: int, length: int) -> bool:
	return value >= start and value < start + length


## Division rounding towards negative infinity, so cells below zero land in
## the coarse cell below instead of sharing cell 0.
static func _floor_div(a: int, b: int) -> int:
	return (a - posmod(a, b)) / b
