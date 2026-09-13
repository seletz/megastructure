class_name WalkableGraph
extends RefCounted
## Nodes of the walkable graph: portals on the faces between adjacent
## non-solid sectors and one interior node per non-solid sector.
##
##     var graph := WalkableGraph.new(seed)          # default Skeleton
##     var p := graph.portal(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
##     var n := graph.interior_node(Vector3i(0, 0, 0))
##
## Every point is a pure function of (seed, sector) and the skeleton, so any
## sector computes the same points as its neighbours without asking them:
## a portal is keyed on the lower sector of its pair and the face axis, with
## one salt per axis and face coordinate. Points are snapped to the 2 m cell
## grid of the fill layer and kept at least MARGIN_CELLS cells inside the
## face or sector; on vertical faces and for interior nodes the height is a
## floor level on the 6 m stratum pitch. Salts and rules are in
## docs/algorithms/sector-skeleton-and-walkable-graph.md.
##
## Sector i spans cells i * n to (i + 1) * n with n = cells_per_sector, so the
## sector edge is taken as n * CELL_SIZE (48 m by default). Positions in
## metres are exact on the grid as long as they fit a float32, about
## +-2^25 m; `face_cell` and `local_cell` stay exact everywhere.

## Edge of one fill cell in metres.
const CELL_SIZE := 2.0
## Floor levels are this many cells apart (6 m).
const STRATUM_PITCH_CELLS := 3
## Distance of every point from the edges of its face or sector, in cells.
const MARGIN_CELLS := 1
## Smallest sector the margin and one floor level fit into, in cells.
const MIN_CELLS_PER_SECTOR := 4

## Portal salts: the first and second face coordinate of an x, y and z face.
const SALT_PORTAL_X_U := 140
const SALT_PORTAL_X_V := 141
const SALT_PORTAL_Y_U := 142
const SALT_PORTAL_Y_V := 143
const SALT_PORTAL_Z_U := 144
const SALT_PORTAL_Z_V := 145
## Interior node salts: local x, floor level, local z.
const SALT_NODE_X := 150
const SALT_NODE_LEVEL := 151
const SALT_NODE_Z := 152

const _PORTAL_SALTS: Array[PackedInt32Array] = [
	[SALT_PORTAL_X_U, SALT_PORTAL_X_V],
	[SALT_PORTAL_Y_U, SALT_PORTAL_Y_V],
	[SALT_PORTAL_Z_U, SALT_PORTAL_Z_V],
]


## A point on the face between two adjacent non-solid sectors.
class Portal:
	extends RefCounted
	## The lower sector of the pair (smaller coordinate along `axis`).
	var a: Vector3i
	## The upper sector, `a` plus one along `axis`.
	var b: Vector3i
	## Vector3i.AXIS_X, AXIS_Y or AXIS_Z: the axis the face is normal to.
	var axis: int
	## Cells from the face's lower corner along the two other axes in xyz
	## order: (y, z) on an x face, (x, z) on a y face, (x, y) on a z face.
	var face_cell: Vector2i
	## World position in metres.
	var position: Vector3

	func equals(other: Portal) -> bool:
		return (
			other != null and a == other.a and b == other.b and axis == other.axis
			and face_cell == other.face_cell and position == other.position
		)

	func _to_string() -> String:
		return "Portal(%s-%s axis %d at %s)" % [a, b, axis, position]


## The interior node of one non-solid sector.
class InteriorNode:
	extends RefCounted
	var cell: Vector3i
	## The sector type. Stratum nodes are walked through; shaft, cavity and
	## chasm nodes mark vertical travel or open space for the edge rules.
	var type: Skeleton.SectorType
	## Cells from the sector's lower corner.
	var local_cell: Vector3i
	## World position in metres.
	var position: Vector3

	func _to_string() -> String:
		return "InteriorNode(%s %s at %s)" % [cell, Skeleton.type_name(type), position]


var world_seed: int
var skeleton: Skeleton


func _init(seed_value: int, sector_skeleton: Skeleton = null) -> void:
	world_seed = seed_value
	skeleton = sector_skeleton if sector_skeleton != null else Skeleton.new()


## Fill cells along one edge of a sector.
func cells_per_sector() -> int:
	return maxi(int(skeleton.grammar.sector_size / CELL_SIZE), MIN_CELLS_PER_SECTOR)


## The portal between two face-adjacent sectors, in either order; null when
## they are not adjacent or either is solid.
func portal(a: Vector3i, b: Vector3i) -> Portal:
	var d := b - a
	if absi(d.x) + absi(d.y) + absi(d.z) != 1:
		return null
	if _is_solid(a) or _is_solid(b):
		return null
	var axis := Vector3i.AXIS_X if d.x != 0 else (Vector3i.AXIS_Y if d.y != 0 else Vector3i.AXIS_Z)
	var lower := a if d[axis] > 0 else b
	var n := cells_per_sector()
	var salts := _PORTAL_SALTS[axis]
	var others := _other_axes(axis)

	var upper := lower
	upper[axis] += 1
	var result := Portal.new()
	result.a = lower
	result.b = upper
	result.axis = axis
	var face := Vector2i.ZERO
	for i in 2:
		# The height on a vertical face is a floor level, like interior nodes.
		if others[i] == Vector3i.AXIS_Y:
			face[i] = _pick_level(lower, salts[i], n)
		else:
			face[i] = _pick(lower, salts[i], MARGIN_CELLS, n - MARGIN_CELLS)
	result.face_cell = face

	# Cell coordinates as 64-bit ints: sector times n can exceed int32.
	var world: Array[int] = [0, 0, 0]
	world[axis] = (lower[axis] + 1) * n
	for i in 2:
		world[others[i]] = lower[others[i]] * n + face[i]
	result.position = Vector3(world[0], world[1], world[2]) * CELL_SIZE
	return result


## The interior node of a sector; null when it is solid.
func interior_node(cell: Vector3i) -> InteriorNode:
	var type := skeleton.sector_type(world_seed, cell)
	if type == Skeleton.SectorType.SOLID:
		return null
	var n := cells_per_sector()
	var node := InteriorNode.new()
	node.cell = cell
	node.type = type
	node.local_cell = Vector3i(
		_pick(cell, SALT_NODE_X, MARGIN_CELLS, n - MARGIN_CELLS),
		_pick_level(cell, SALT_NODE_LEVEL, n),
		_pick(cell, SALT_NODE_Z, MARGIN_CELLS, n - MARGIN_CELLS),
	)
	node.position = Vector3(
		cell.x * n + node.local_cell.x,
		cell.y * n + node.local_cell.y,
		cell.z * n + node.local_cell.z,
	) * CELL_SIZE
	return node


## Interior nodes of every non-solid sector in the box, bounds inclusive,
## ordered by x, then y, then z.
func nodes_in_region(min_cell: Vector3i, max_cell: Vector3i) -> Array[InteriorNode]:
	var nodes: Array[InteriorNode] = []
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				var node := interior_node(Vector3i(x, y, z))
				if node != null:
					nodes.append(node)
	return nodes


func _is_solid(cell: Vector3i) -> bool:
	return skeleton.sector_type(world_seed, cell) == Skeleton.SectorType.SOLID


## A floor level in cells: a multiple of STRATUM_PITCH_CELLS inside the margin.
func _pick_level(key: Vector3i, salt: int, n: int) -> int:
	var lo := ceili(float(MARGIN_CELLS) / STRATUM_PITCH_CELLS)
	var hi := floori(float(n - MARGIN_CELLS) / STRATUM_PITCH_CELLS)
	return _pick(key, salt, lo, hi) * STRATUM_PITCH_CELLS


## Integer in lo..hi (inclusive) from the 32-bit hash; lo when hi <= lo.
func _pick(key: Vector3i, salt: int, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + Hash.hash3_u(world_seed, key, salt) % (hi - lo + 1)


static func _other_axes(axis: int) -> PackedInt32Array:
	match axis:
		Vector3i.AXIS_X:
			return [Vector3i.AXIS_Y, Vector3i.AXIS_Z]
		Vector3i.AXIS_Y:
			return [Vector3i.AXIS_X, Vector3i.AXIS_Z]
	return [Vector3i.AXIS_X, Vector3i.AXIS_Y]
