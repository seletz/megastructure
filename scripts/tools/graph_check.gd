extends SceneTree
## Checks the portals and interior nodes of `WalkableGraph` for seeds 0..4.
## For 100 random adjacent pairs of non-solid sectors per seed, along all
## three axes: `portal(a, b)` equals `portal(b, a)` exactly and on a fresh
## graph, the portal lies on the shared face at least MARGIN_CELLS inside its
## edges, on the 2 m grid and, on a vertical face, at the floor level of the
## lower sector's interior node. Pairs with a solid sector and non-adjacent
## pairs return null. The edges around EDGE_SECTORS sectors per seed, tunnels
## included, have their x and z portals at `hub_level` of the lower sector,
## which is `centre_level` for a solid one. Interior nodes lie
## inside their sector on the grid at a floor level, carry the sector type,
## are null for solid sectors, and `nodes_in_region` returns one per
## non-solid sector of a 3^3 region.
## Run headless with `mise run graph-check`.

const SEEDS: Array[int] = [0, 1, 2, 3, 4]
const OPEN_PAIRS := 100
const SOLID_PAIRS := 20
## Sample sectors per seed whose edges are checked against the level rule.
const EDGE_SECTORS := 20
## Upper bound of random pairs tried per seed before giving up.
const MAX_TRIES := 2000
## Random sectors lie within +-RANGE on each axis, where metres stay exact.
const RANGE := 100000
## Salt for picking the random test pairs; outside the grammar's salt range.
const SALT_TEST_PAIR := 902

const _OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1),
	Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, -1),
]
const _NOT_ADJACENT: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 0, 1),
	Vector3i(1, 1, 1), Vector3i(2, 0, 0), Vector3i(0, -2, 0), Vector3i(0, 0, 3),
]

var _failures := 0


func _init() -> void:
	for seed_value in SEEDS:
		_check_seed(seed_value)
	print("graph check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_seed(seed_value: int) -> void:
	var graph := WalkableGraph.new(seed_value)
	var fresh := WalkableGraph.new(seed_value)
	var n := graph.cells_per_sector()
	var open := 0
	var solid := 0
	var not_adjacent := 0
	var per_axis := PackedInt32Array([0, 0, 0])
	var bad := {"symmetry": 0, "face": 0, "grid": 0, "level": 0, "solid": 0, "adjacent": 0, "node": 0}

	var i := 0
	while (open < OPEN_PAIRS or solid < SOLID_PAIRS) and i < MAX_TRIES:
		var a := _random_cell(seed_value, i)
		var b := a + _OFFSETS[Hash.hash3_u(seed_value, Vector3i(i, 3, 0), SALT_TEST_PAIR) % _OFFSETS.size()]
		var far := a + _NOT_ADJACENT[i % _NOT_ADJACENT.size()]
		i += 1

		if graph.portal(a, far) != null or graph.portal(far, a) != null:
			bad.adjacent += 1
		not_adjacent += 1

		var either_solid := _solid(graph, a) or _solid(graph, b)
		var forward := graph.portal(a, b)
		var backward := graph.portal(b, a)
		if either_solid:
			if solid < SOLID_PAIRS:
				solid += 1
				if forward != null or backward != null:
					bad.solid += 1
			continue
		if open >= OPEN_PAIRS:
			continue
		open += 1
		if forward == null or not forward.equals(backward) or not forward.equals(fresh.portal(b, a)):
			bad.symmetry += 1
			continue
		per_axis[forward.axis] += 1
		if not _on_face(forward, n):
			bad.face += 1
		if not _on_grid(forward.position):
			bad.grid += 1
		if forward.axis != Vector3i.AXIS_Y and _face_height(forward) != graph.interior_node(forward.a).local_cell.y:
			bad.level += 1
		for cell in [a, b]:
			if not _node_ok(graph, cell, n):
				bad.node += 1

	var label := "seed %d:" % seed_value
	_expect(open == OPEN_PAIRS and bad.symmetry == 0, "%s portal(a, b) == portal(b, a) for %d open pairs (x %d, y %d, z %d), %d mismatches" % [label, open, per_axis[0], per_axis[1], per_axis[2], bad.symmetry])
	_expect(bad.face == 0, "%s portals on the shared face inside a %d cell margin, %d outside" % [label, WalkableGraph.MARGIN_CELLS, bad.face])
	_expect(bad.grid == 0, "%s portal positions on the %.0f m grid, %d off it" % [label, WalkableGraph.CELL_SIZE, bad.grid])
	_expect(bad.level == 0, "%s portals on vertical faces at the floor level of the lower sector's interior node, %d not" % [label, bad.level])
	_expect(solid == SOLID_PAIRS and bad.solid == 0, "%s %d pairs with a solid sector return null, %d did not" % [label, solid, bad.solid])
	_expect(bad.adjacent == 0, "%s %d non-adjacent pairs return null, %d did not" % [label, not_adjacent, bad.adjacent])
	_expect(bad.node == 0, "%s interior nodes of %d open sectors inside the sector on the grid at a floor level, %d not" % [label, open * 2, bad.node])
	_check_region(graph, seed_value, label)
	_check_edge_levels(graph, seed_value, label)


## Every x and z edge portal around EDGE_SECTORS sample sectors, tunnels
## included, lies at the hub level of the edge's lower sector.
func _check_edge_levels(graph: WalkableGraph, seed_value: int, label: String) -> void:
	var edges := 0
	var tunnels := 0
	var mismatches := 0
	for i in EDGE_SECTORS:
		for edge in graph.edges_for_sector(_random_cell(seed_value, MAX_TRIES + 1 + i)):
			if edge.axis == Vector3i.AXIS_Y:
				continue
			edges += 1
			var expected := graph.hub_level(edge.a)
			if _solid(graph, edge.a):
				tunnels += 1
				if expected != graph.centre_level():
					mismatches += 1
			if _face_height(edge.portal) != expected:
				mismatches += 1
	_expect(mismatches == 0, "%s %d horizontal edges (%d from a solid sector) have their portal at the lower sector's hub level, %d not" % [label, edges, tunnels, mismatches])


## nodes_in_region returns exactly the non-solid sectors of a 3^3 region, in
## order, and every one matches interior_node.
func _check_region(graph: WalkableGraph, seed_value: int, label: String) -> void:
	var lo := _random_cell(seed_value, MAX_TRIES)
	var hi := lo + Vector3i(2, 2, 2)
	var nodes := graph.nodes_in_region(lo, hi)
	var expected := 0
	var mismatches := 0
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var cell := Vector3i(x, y, z)
				var node := graph.interior_node(cell)
				if _solid(graph, cell):
					if node != null:
						mismatches += 1
					continue
				if expected >= nodes.size() or nodes[expected].cell != cell or node == null or nodes[expected].position != node.position:
					mismatches += 1
				expected += 1
	_expect(nodes.size() == expected and mismatches == 0, "%s nodes_in_region of a 3^3 region: %d nodes for %d open sectors, %d mismatches" % [label, nodes.size(), expected, mismatches])


static func _solid(graph: WalkableGraph, cell: Vector3i) -> bool:
	return graph.skeleton.sector_type(graph.world_seed, cell) == Skeleton.SectorType.SOLID


## On the plane between a and b, and at least MARGIN_CELLS from the face edges.
static func _on_face(p: WalkableGraph.Portal, n: int) -> bool:
	if p.b - p.a != _unit(p.axis):
		return false
	var cell_size := WalkableGraph.CELL_SIZE
	var margin := WalkableGraph.MARGIN_CELLS
	for axis in 3:
		var value := p.position[axis]
		if axis == p.axis:
			if value != float(p.b[axis] * n) * cell_size:
				return false
		elif value < float(p.a[axis] * n + margin) * cell_size or value > float((p.a[axis] + 1) * n - margin) * cell_size:
			return false
	return true


## Inside its sector with the margin, on the grid, at a floor level, typed.
static func _node_ok(graph: WalkableGraph, cell: Vector3i, n: int) -> bool:
	var node := graph.interior_node(cell)
	if node == null or node.cell != cell or node.type != graph.skeleton.sector_type(graph.world_seed, cell):
		return false
	if not _on_grid(node.position) or node.local_cell.y % WalkableGraph.STRATUM_PITCH_CELLS != 0:
		return false
	var margin := WalkableGraph.MARGIN_CELLS
	for axis in 3:
		var local := node.local_cell[axis]
		if local < margin or local > n - margin:
			return false
		if node.position[axis] != float(cell[axis] * n + local) * WalkableGraph.CELL_SIZE:
			return false
	return true


static func _on_grid(position: Vector3) -> bool:
	for axis in 3:
		if fmod(position[axis], WalkableGraph.CELL_SIZE) != 0.0:
			return false
	return true


## The face coordinate along y of a portal on an x face (y, z) or z face (x, y).
static func _face_height(p: WalkableGraph.Portal) -> int:
	return p.face_cell[0] if p.axis == Vector3i.AXIS_X else p.face_cell[1]


static func _unit(axis: int) -> Vector3i:
	var v := Vector3i.ZERO
	v[axis] = 1
	return v


## A sector within +-RANGE on each axis, drawn from the hash.
static func _random_cell(seed_value: int, i: int) -> Vector3i:
	var axis := func(a: int) -> int: return Hash.hash3_u(seed_value, Vector3i(i, a, 0), SALT_TEST_PAIR) % (2 * RANGE + 1) - RANGE
	return Vector3i(axis.call(0), axis.call(1), axis.call(2))


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
