class_name WalkableGraph
extends RefCounted
## The walkable graph: portals on the faces between adjacent sectors, one
## interior node per non-solid sector and the edges that connect them.
##
##     var graph := WalkableGraph.new(seed)          # default Skeleton
##     var p := graph.portal(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
##     var n := graph.interior_node(Vector3i(0, 0, 0))
##     var edges := graph.edges_for_sector(Vector3i(0, 0, 0))
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
## Edges are decided per region of REGION_SECTORS^3 sectors: Kruskal over all
## sectors of the region with hashed weights, pruned to the tree that joins
## its terminals (the non-solid sectors and the sectors the boundary edges
## land on), plus hashed loops. Edges through solid sectors are tunnels.
## Between face-adjacent regions, `boundary_edges` keyed on the lower region
## adds at least one edge per shared face. A region's edges read the sector
## types of the region and of the sector layers across its six faces, never
## another region's edges (docs/decisions/0017).
##
## Sector i spans cells i * n to (i + 1) * n with n = cells_per_sector, so the
## sector edge is taken as n * CELL_SIZE (48 m by default). Positions in
## metres are exact on the grid as long as they fit a float32, about
## +-2^25 m; `face_cell` and `local_cell` stay exact everywhere.

## What the fill layer builds along an edge.
enum EdgeKind { CORRIDOR, STAIR, LADDER, BRIDGE, CATWALK, TUNNEL }

const EDGE_KIND_NAMES: Array[String] = ["corridor", "stair", "ladder", "bridge", "catwalk", "tunnel"]

## Edge of one fill cell in metres.
const CELL_SIZE := 2.0
## Floor levels are this many cells apart (6 m).
const STRATUM_PITCH_CELLS := 3
## Distance of every point from the edges of its face or sector, in cells.
const MARGIN_CELLS := 1
## Smallest sector the margin and one floor level fit into, in cells.
const MIN_CELLS_PER_SECTOR := 4
## Sectors along each axis of a region, the unit the edges are decided on.
const REGION_SECTORS := 3
## Vertical edge weights are shared by a column over this many sectors, so
## Kruskal takes a whole run of stacked vertical edges at once.
const VERTICAL_RUN_SECTORS := 9
## Chance that an open-open pair outside the tree still gets an edge.
const LOOP_PROBABILITY_HORIZONTAL := 0.08
const LOOP_PROBABILITY_VERTICAL := 0.02

## Weight classes, lightest first. Kruskal takes every open-open edge before
## any tunnel, so a tunnel is only built where no open path in the region
## exists. The hash only orders edges inside one class.
const WEIGHT_OPEN_HORIZONTAL := 0
const WEIGHT_VOID_VERTICAL := 1
const WEIGHT_OPEN_VERTICAL := 2
const WEIGHT_TUNNEL_HORIZONTAL := 3
const WEIGHT_TUNNEL_HORIZONTAL_SOLID := 4
const WEIGHT_TUNNEL_VERTICAL := 5
const WEIGHT_TUNNEL_VERTICAL_SOLID := 6

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
## Edge weight salts per axis; the y weight is keyed on the column run.
const SALT_EDGE_WEIGHT_X := 153
const SALT_EDGE_WEIGHT_Y := 154
const SALT_EDGE_WEIGHT_Z := 155
## Loop edge salts per axis, keyed on the lower sector of the pair.
const SALT_EDGE_LOOP_X := 156
const SALT_EDGE_LOOP_Y := 157
const SALT_EDGE_LOOP_Z := 158

const _PORTAL_SALTS: Array[PackedInt32Array] = [
	[SALT_PORTAL_X_U, SALT_PORTAL_X_V],
	[SALT_PORTAL_Y_U, SALT_PORTAL_Y_V],
	[SALT_PORTAL_Z_U, SALT_PORTAL_Z_V],
]
const _WEIGHT_SALTS: PackedInt32Array = [SALT_EDGE_WEIGHT_X, SALT_EDGE_WEIGHT_Y, SALT_EDGE_WEIGHT_Z]
const _LOOP_SALTS: PackedInt32Array = [SALT_EDGE_LOOP_X, SALT_EDGE_LOOP_Y, SALT_EDGE_LOOP_Z]
const _UNITS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]


## A point on the face between two adjacent sectors.
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


## An edge between two face-adjacent sectors.
class Edge:
	extends RefCounted
	## The lower sector of the pair (smaller coordinate along `axis`).
	var a: Vector3i
	## The upper sector, `a` plus one along `axis`.
	var b: Vector3i
	## Vector3i.AXIS_X, AXIS_Y or AXIS_Z.
	var axis: int
	var kind: EdgeKind
	## Where the edge crosses the shared face. Tunnels get a point from the
	## same salts as `portal`, which returns null for them.
	var portal: Portal

	func equals(other: Edge) -> bool:
		return (
			other != null and a == other.a and b == other.b and axis == other.axis
			and kind == other.kind and portal.equals(other.portal)
		)

	func _to_string() -> String:
		return "Edge(%s-%s %s)" % [a, b, EDGE_KIND_NAMES[kind]]


var world_seed: int
var skeleton: Skeleton


func _init(seed_value: int, sector_skeleton: Skeleton = null) -> void:
	world_seed = seed_value
	skeleton = sector_skeleton if sector_skeleton != null else Skeleton.new()


static func edge_kind_name(kind: EdgeKind) -> String:
	return EDGE_KIND_NAMES[kind]


## The region a sector belongs to.
static func region_of(cell: Vector3i) -> Vector3i:
	return Vector3i(
		_floor_div(cell.x, REGION_SECTORS),
		_floor_div(cell.y, REGION_SECTORS),
		_floor_div(cell.z, REGION_SECTORS),
	)


## The kind of edge between two face-adjacent sectors of the given types:
## tunnel if either is solid; along y a ladder when both are shaft or chasm,
## else a stair; across a cavity or chasm a bridge, next to a shaft a catwalk,
## else a corridor.
static func edge_kind(type_a: Skeleton.SectorType, type_b: Skeleton.SectorType, axis: int) -> EdgeKind:
	if type_a == Skeleton.SectorType.SOLID or type_b == Skeleton.SectorType.SOLID:
		return EdgeKind.TUNNEL
	if axis == Vector3i.AXIS_Y:
		return EdgeKind.LADDER if _vertical_void(type_a) and _vertical_void(type_b) else EdgeKind.STAIR
	for type in [type_a, type_b]:
		if type == Skeleton.SectorType.CAVITY or type == Skeleton.SectorType.CHASM:
			return EdgeKind.BRIDGE
	if type_a == Skeleton.SectorType.SHAFT or type_b == Skeleton.SectorType.SHAFT:
		return EdgeKind.CATWALK
	return EdgeKind.CORRIDOR


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
	return _face_point(a if d[axis] > 0 else b, axis)


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


## The edges inside a region: the pruned Kruskal tree over its terminals plus
## hashed loops between open sectors, ordered by `a`, then axis. Every
## non-solid sector of the region, and every sector of it a boundary edge
## lands on, is connected by these edges alone.
func edges_in_region(region: Vector3i) -> Array[Edge]:
	var origin := region * REGION_SECTORS
	var count := REGION_SECTORS * REGION_SECTORS * REGION_SECTORS
	var types: Array[Skeleton.SectorType] = []
	types.resize(count)
	var terminal := PackedByteArray()
	terminal.resize(count)
	for i in count:
		types[i] = skeleton.sector_type(world_seed, origin + _local(i))
		terminal[i] = 1 if types[i] != Skeleton.SectorType.SOLID else 0
	# Sectors the boundary edges of the six faces land on must join the tree.
	for axis in 3:
		for edge in boundary_edges(region, axis):
			terminal[_index(edge.a - origin)] = 1
		for edge in boundary_edges(region - _UNITS[axis], axis):
			terminal[_index(edge.b - origin)] = 1

	# Candidate pairs as [weight, lower index, axis], sorted by weight, then
	# by index and axis so equal weights resolve the same way everywhere.
	var candidates: Array[PackedInt64Array] = []
	for i in count:
		var local := _local(i)
		for axis in 3:
			if local[axis] + 1 >= REGION_SECTORS:
				continue
			var j := _index(local + _UNITS[axis])
			candidates.append(PackedInt64Array([_weight(origin + local, types[i], types[j], axis), i, axis]))
	candidates.sort_custom(_lighter)

	var parent := PackedInt32Array()
	parent.resize(count)
	for i in count:
		parent[i] = i
	var degree := PackedInt32Array()
	degree.resize(count)
	# Chosen tree edges as (lower index, axis); `in_tree` marks them.
	var tree: Array[Vector2i] = []
	var in_tree := {}
	for candidate in candidates:
		var i := int(candidate[1])
		var axis := int(candidate[2])
		var j := _index(_local(i) + _UNITS[axis])
		var ri := _find(parent, i)
		var rj := _find(parent, j)
		if ri == rj:
			continue
		parent[ri] = rj
		tree.append(Vector2i(i, axis))
		in_tree[Vector2i(i, axis)] = true
		degree[i] += 1
		degree[j] += 1

	# Prune leaves that are not terminals until none is left: what stays is
	# the subtree joining the terminals, so no tunnel ends in the rock.
	var pruned := true
	while pruned:
		pruned = false
		for key in tree:
			if not in_tree[key]:
				continue
			var i := key.x
			var j := _index(_local(i) + _UNITS[key.y])
			if (degree[i] == 1 and terminal[i] == 0) or (degree[j] == 1 and terminal[j] == 0):
				in_tree[key] = false
				degree[i] -= 1
				degree[j] -= 1
				pruned = true

	var edges: Array[Edge] = []
	for i in count:
		var local := _local(i)
		for axis in 3:
			if local[axis] + 1 >= REGION_SECTORS:
				continue
			var j := _index(local + _UNITS[axis])
			# Pruned edges always touch a solid sector, so only unchosen
			# open-open pairs can come back as loops.
			if in_tree.get(Vector2i(i, axis), false) or _is_loop(origin + local, types[i], types[j], axis):
				edges.append(_make_edge(origin + local, axis, types[i], types[j]))
	return edges


## The edges across the face between `region` and the region above it along
## `axis`, keyed on `region`: the lightest pair of the face (open-open before
## tunnels, same weights as inside a region) plus hashed loops between the
## other open-open pairs, ordered by `a`. Never empty.
func boundary_edges(region: Vector3i, axis: int) -> Array[Edge]:
	var origin := region * REGION_SECTORS
	var others := _other_axes(axis)
	var best := -1
	var best_weight := 0
	var pairs: Array[Vector3i] = []
	var pair_types: Array[PackedInt32Array] = []
	for u in REGION_SECTORS:
		for v in REGION_SECTORS:
			var local := Vector3i.ZERO
			local[axis] = REGION_SECTORS - 1
			local[others[0]] = u
			local[others[1]] = v
			var a := origin + local
			var type_a := skeleton.sector_type(world_seed, a)
			var type_b := skeleton.sector_type(world_seed, a + _UNITS[axis])
			var weight := _weight(a, type_a, type_b, axis)
			if best < 0 or weight < best_weight:
				best = pairs.size()
				best_weight = weight
			pairs.append(a)
			pair_types.append(PackedInt32Array([type_a, type_b]))
	var edges: Array[Edge] = []
	for p in pairs.size():
		var type_a := pair_types[p][0] as Skeleton.SectorType
		var type_b := pair_types[p][1] as Skeleton.SectorType
		if p == best or _is_loop(pairs[p], type_a, type_b, axis):
			edges.append(_make_edge(pairs[p], axis, type_a, type_b))
	return edges


## Every edge touching a sector: the edges of its region and the boundary
## edges of the region's six faces that have the sector as an endpoint.
func edges_for_sector(cell: Vector3i) -> Array[Edge]:
	var region := region_of(cell)
	var edges: Array[Edge] = []
	for edge in edges_in_region(region):
		if edge.a == cell or edge.b == cell:
			edges.append(edge)
	var local := cell - region * REGION_SECTORS
	for axis in 3:
		if local[axis] == 0:
			for edge in boundary_edges(region - _UNITS[axis], axis):
				if edge.b == cell:
					edges.append(edge)
		if local[axis] == REGION_SECTORS - 1:
			for edge in boundary_edges(region, axis):
				if edge.a == cell:
					edges.append(edge)
	return edges


func _is_solid(cell: Vector3i) -> bool:
	return skeleton.sector_type(world_seed, cell) == Skeleton.SectorType.SOLID


## The point on the face between `lower` and `lower` plus one along `axis`.
func _face_point(lower: Vector3i, axis: int) -> Portal:
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


func _make_edge(lower: Vector3i, axis: int, type_a: Skeleton.SectorType, type_b: Skeleton.SectorType) -> Edge:
	var edge := Edge.new()
	edge.a = lower
	edge.b = lower + _UNITS[axis]
	edge.axis = axis
	edge.kind = edge_kind(type_a, type_b, axis)
	edge.portal = _face_point(lower, axis)
	return edge


## Weight class in the top bits, the 32-bit hash below. A vertical pair is
## keyed on its column and run of VERTICAL_RUN_SECTORS, so stacked vertical
## pairs weigh the same and one column carries the vertical travel.
func _weight(lower: Vector3i, type_a: Skeleton.SectorType, type_b: Skeleton.SectorType, axis: int) -> int:
	var solid := int(type_a == Skeleton.SectorType.SOLID) + int(type_b == Skeleton.SectorType.SOLID)
	var weight_class: int
	var key := lower
	if axis == Vector3i.AXIS_Y:
		key = Vector3i(lower.x, _floor_div(lower.y, VERTICAL_RUN_SECTORS), lower.z)
		if solid == 0:
			weight_class = WEIGHT_VOID_VERTICAL if _vertical_void(type_a) and _vertical_void(type_b) else WEIGHT_OPEN_VERTICAL
		else:
			weight_class = WEIGHT_TUNNEL_VERTICAL if solid == 1 else WEIGHT_TUNNEL_VERTICAL_SOLID
	elif solid == 0:
		weight_class = WEIGHT_OPEN_HORIZONTAL
	else:
		weight_class = WEIGHT_TUNNEL_HORIZONTAL if solid == 1 else WEIGHT_TUNNEL_HORIZONTAL_SOLID
	return (weight_class << 32) | Hash.hash3_u(world_seed, key, _WEIGHT_SALTS[axis])


## An open-open pair outside the tree that still gets an edge.
func _is_loop(lower: Vector3i, type_a: Skeleton.SectorType, type_b: Skeleton.SectorType, axis: int) -> bool:
	if type_a == Skeleton.SectorType.SOLID or type_b == Skeleton.SectorType.SOLID:
		return false
	var chance := LOOP_PROBABILITY_VERTICAL if axis == Vector3i.AXIS_Y else LOOP_PROBABILITY_HORIZONTAL
	return Hash.hash3(world_seed, lower, _LOOP_SALTS[axis]) < chance


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


static func _vertical_void(type: Skeleton.SectorType) -> bool:
	return type == Skeleton.SectorType.SHAFT or type == Skeleton.SectorType.CHASM


static func _lighter(p: PackedInt64Array, q: PackedInt64Array) -> bool:
	if p[0] != q[0]:
		return p[0] < q[0]
	if p[1] != q[1]:
		return p[1] < q[1]
	return p[2] < q[2]


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


## Index of a sector inside its region, x slowest; and back.
static func _index(local: Vector3i) -> int:
	return (local.x * REGION_SECTORS + local.y) * REGION_SECTORS + local.z


static func _local(i: int) -> Vector3i:
	return Vector3i(i / (REGION_SECTORS * REGION_SECTORS), (i / REGION_SECTORS) % REGION_SECTORS, i % REGION_SECTORS)


## Division rounding towards negative infinity.
static func _floor_div(a: int, b: int) -> int:
	return (a - posmod(a, b)) / b


static func _other_axes(axis: int) -> PackedInt32Array:
	match axis:
		Vector3i.AXIS_X:
			return [Vector3i.AXIS_Y, Vector3i.AXIS_Z]
		Vector3i.AXIS_Y:
			return [Vector3i.AXIS_X, Vector3i.AXIS_Z]
	return [Vector3i.AXIS_X, Vector3i.AXIS_Y]
