extends SceneTree
## Checks the edges of `WalkableGraph` for seeds 0..9 over a 15^3 sample of
## sectors (5^3 regions at a hashed offset per seed).
##
## Every edge joins two face-adjacent sectors in order, has the kind
## `edge_kind` gives for their types, a portal on their face (equal to
## `portal` for open pairs) and is computed identically by a fresh graph;
## `edges_for_sector` returns exactly the region and boundary edges touching
## the sector; a region whose open sectors are connected through open
## sectors and that has no solid terminal has no tunnel.
##
## Connectivity, with union-find over all sectors of a window using only the
## edges whose both endpoints lie in the window, counting the components
## that hold a non-solid sector:
##   - every region-aligned window of 1^3 and 2^3 regions (3^3 and 6^3
##     sectors) must have exactly one; the task fails otherwise;
##   - every 5^3 window at every offset is counted and reported, next to the
##     count a graph with every open-open adjacency and no tunnels would
##     reach. Windows that cut a region cannot be guaranteed one component
##     (docs/decisions/0017).
## Also reports the fraction of tunnel edges, the edge kinds and the mean
## vertical edge run (stacked stair or ladder edges in one column).
## Run headless with `mise run graph-connectivity`.

const SEEDS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
const SAMPLE_REGIONS := 5
const WINDOW := 5
## Sample origins lie within +-RANGE regions on each axis.
const RANGE := 10000
## Salt for picking the sample origin; outside the grammar's salt range.
const SALT_TEST_SAMPLE := 903
## Sectors per seed whose edges_for_sector is compared.
const SECTOR_SAMPLES := 40

var _failures := 0
var _n := 0
var _types := PackedInt32Array()
## For every sample sector, the sample indices it has an edge to.
var _neighbours: Array[PackedInt32Array] = []
## For every sample sector, its face-adjacent open sectors when it is open:
## the edges a graph without tunnels could have at most.
var _open_neighbours: Array[PackedInt32Array] = []


func _init() -> void:
	_n = SAMPLE_REGIONS * WalkableGraph.REGION_SECTORS
	var totals := {"edges": 0, "tunnel": 0, "strict": 0, "strict_ok": 0, "open_ok": 0, "runs": 0, "run_sectors": 0}
	var kinds := PackedInt32Array()
	kinds.resize(WalkableGraph.EDGE_KIND_NAMES.size())
	for seed_value in SEEDS:
		_check_seed(seed_value, totals, kinds)
	print("all seeds:")
	print("  %d edges, %.1f %% tunnels (%s)" % [totals.edges, 100.0 * totals.tunnel / maxi(totals.edges, 1), _kind_list(kinds, totals.edges)])
	print("  mean vertical edge run %.2f sectors over %d runs" % [float(totals.run_sectors) / maxi(totals.runs, 1), totals.runs])
	print("  strict 5^3 windows with one component: %d of %d (%.1f %%); with every open-open adjacency as an edge and no tunnels: %d (%.1f %%)" % [totals.strict_ok, totals.strict, 100.0 * totals.strict_ok / maxi(totals.strict, 1), totals.open_ok, 100.0 * totals.open_ok / maxi(totals.strict, 1)])
	print("graph connectivity check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_seed(seed_value: int, totals: Dictionary, kinds: PackedInt32Array) -> void:
	var graph := WalkableGraph.new(seed_value)
	var fresh := WalkableGraph.new(seed_value)
	var r := WalkableGraph.REGION_SECTORS
	var base := Vector3i(_random(seed_value, 0), _random(seed_value, 1), _random(seed_value, 2))
	var origin := base * r
	var label := "seed %d:" % seed_value

	_types.resize(_n * _n * _n)
	for i in _types.size():
		_types[i] = graph.skeleton.sector_type(seed_value, origin + _cell(i))
	_neighbours.clear()
	_neighbours.resize(_types.size())
	_open_neighbours.clear()
	_open_neighbours.resize(_types.size())
	for i in _neighbours.size():
		_neighbours[i] = PackedInt32Array()
		_open_neighbours[i] = PackedInt32Array()
	for i in _types.size():
		var local := _cell(i)
		for axis in 3:
			if local[axis] + 1 >= _n:
				continue
			var step := [_n * _n, _n, 1][axis] as int
			if _types[i] != Skeleton.SectorType.SOLID and _types[i + step] != Skeleton.SectorType.SOLID:
				_open_neighbours[i].append(i + step)
				_open_neighbours[i + step].append(i)

	var bad := {"shape": 0, "kind": 0, "portal": 0, "fresh": 0, "tunnel": 0, "sector": 0}
	var edges := 0
	var tunnels := 0
	var seed_kinds := PackedInt32Array()
	seed_kinds.resize(kinds.size())
	# Vertical edges by lower sector index, for the runs.
	var vertical := {}
	var region_edges := {}
	var boundary := {}
	for rx in SAMPLE_REGIONS:
		for ry in SAMPLE_REGIONS:
			for rz in SAMPLE_REGIONS:
				var region := base + Vector3i(rx, ry, rz)
				var list := graph.edges_in_region(region)
				region_edges[region] = list
				_compare(list, fresh.edges_in_region(region), bad)
				if _has_open_path_only(graph, region, list):
					bad.tunnel += 1
				var all: Array[WalkableGraph.Edge] = list.duplicate()
				for axis in 3:
					var faces := graph.boundary_edges(region, axis)
					boundary[[region, axis]] = faces
					if Vector3i(rx, ry, rz)[axis] + 1 < SAMPLE_REGIONS:
						all.append_array(faces)
				for edge in all:
					edges += 1
					seed_kinds[edge.kind] += 1
					if edge.kind == WalkableGraph.EdgeKind.TUNNEL:
						tunnels += 1
					_check_edge(graph, edge, bad)
					var i := _index(edge.a - origin)
					var j := _index(edge.b - origin)
					_neighbours[i].append(j)
					_neighbours[j].append(i)
					if edge.axis == Vector3i.AXIS_Y and edge.kind != WalkableGraph.EdgeKind.TUNNEL:
						vertical[i] = true

	for s in SECTOR_SAMPLES:
		var cell := origin + Vector3i(_random_in(seed_value, s, 0), _random_in(seed_value, s, 1), _random_in(seed_value, s, 2))
		if not _same_edges(graph.edges_for_sector(cell), _expected_for_sector(graph, cell, region_edges, boundary)):
			bad.sector += 1

	var runs := 0
	var run_sectors := 0
	for i: int in vertical:
		var local := _cell(i)
		if local.y > 0 and vertical.has(i - _n):
			continue
		var length := 1
		while local.y + length < _n - 1 and vertical.has(i + length * _n):
			length += 1
		runs += 1
		run_sectors += length

	_expect(bad.shape == 0, "%s %d edges join face-adjacent sectors in order, %d do not" % [label, edges, bad.shape])
	_expect(bad.kind == 0 and bad.portal == 0, "%s edge kinds match the sector types and portals lie on the face, %d wrong kinds, %d wrong portals" % [label, bad.kind, bad.portal])
	_expect(bad.fresh == 0, "%s a fresh graph computes the same edges for all %d regions, %d differ" % [label, SAMPLE_REGIONS ** 3, bad.fresh])
	_expect(bad.tunnel == 0, "%s regions open-connected without solid terminals have no tunnels, %d do" % [label, bad.tunnel])
	_expect(bad.sector == 0, "%s edges_for_sector matches region and boundary edges for %d sectors, %d differ" % [label, SECTOR_SAMPLES, bad.sector])

	for size in [1, 2]:
		var width: int = size * r
		var windows := 0
		var split := 0
		for x in range(0, _n - width + 1, r):
			for y in range(0, _n - width + 1, r):
				for z in range(0, _n - width + 1, r):
					windows += 1
					if _components(Vector3i(x, y, z), width, _neighbours) > 1:
						split += 1
		_expect(split == 0, "%s %d region-aligned %d^3 windows have one non-solid component, %d have more" % [label, windows, width, split])

	var strict := 0
	var strict_ok := 0
	var open_ok := 0
	var max_components := 0
	for x in _n - WINDOW + 1:
		for y in _n - WINDOW + 1:
			for z in _n - WINDOW + 1:
				var components := _components(Vector3i(x, y, z), WINDOW, _neighbours)
				strict += 1
				if components <= 1:
					strict_ok += 1
				if _components(Vector3i(x, y, z), WINDOW, _open_neighbours) <= 1:
					open_ok += 1
				max_components = maxi(max_components, components)
	print("  info  %s strict %d^3 windows with one component: %d of %d (all open adjacencies, no tunnels: %d), at most %d components; %.1f %% tunnel edges; mean vertical run %.2f sectors (%d runs)" % [label, WINDOW, strict_ok, strict, open_ok, max_components, 100.0 * tunnels / maxi(edges, 1), float(run_sectors) / maxi(runs, 1), runs])

	totals.edges += edges
	totals.tunnel += tunnels
	totals.strict += strict
	totals.strict_ok += strict_ok
	totals.open_ok += open_ok
	totals.runs += runs
	totals.run_sectors += run_sectors
	for k in kinds.size():
		kinds[k] += seed_kinds[k]


## Components of the window that hold a non-solid sector, joined only by
## links in `neighbours` with both endpoints in the window.
func _components(lo: Vector3i, width: int, neighbours: Array[PackedInt32Array]) -> int:
	var parent := {}
	for x in width:
		for y in width:
			for z in width:
				var i := _index(lo + Vector3i(x, y, z))
				parent[i] = i
	for i: int in parent:
		for j in neighbours[i]:
			if parent.has(j):
				var ri: int = _find(parent, i)
				var rj: int = _find(parent, j)
				if ri != rj:
					parent[ri] = rj
	var roots := {}
	for i: int in parent:
		if _types[i] != Skeleton.SectorType.SOLID:
			roots[_find(parent, i)] = true
	return roots.size()


func _check_edge(graph: WalkableGraph, edge: WalkableGraph.Edge, bad: Dictionary) -> void:
	var unit := Vector3i.ZERO
	unit[edge.axis] = 1
	if edge.b - edge.a != unit:
		bad.shape += 1
		return
	var type_a := graph.skeleton.sector_type(graph.world_seed, edge.a)
	var type_b := graph.skeleton.sector_type(graph.world_seed, edge.b)
	if edge.kind != WalkableGraph.edge_kind(type_a, type_b, edge.axis):
		bad.kind += 1
	var p := edge.portal
	if p == null or p.a != edge.a or p.b != edge.b or p.axis != edge.axis:
		bad.portal += 1
	elif edge.kind != WalkableGraph.EdgeKind.TUNNEL and not p.equals(graph.portal(edge.b, edge.a)):
		bad.portal += 1


## True when the region has a tunnel although its open sectors are connected
## through open sectors inside it and no boundary edge lands on a solid one.
func _has_open_path_only(graph: WalkableGraph, region: Vector3i, edges: Array[WalkableGraph.Edge]) -> bool:
	var has_tunnel := false
	for edge in edges:
		has_tunnel = has_tunnel or edge.kind == WalkableGraph.EdgeKind.TUNNEL
	if not has_tunnel:
		return false
	var r := WalkableGraph.REGION_SECTORS
	var lo := region * r
	for axis in 3:
		var unit := Vector3i.ZERO
		unit[axis] = 1
		for edge in graph.boundary_edges(region, axis):
			if _solid(graph, edge.a):
				return false
		for edge in graph.boundary_edges(region - unit, axis):
			if _solid(graph, edge.b):
				return false
	var parent := {}
	for x in r:
		for y in r:
			for z in r:
				var cell := lo + Vector3i(x, y, z)
				if not _solid(graph, cell):
					parent[cell] = cell
	for cell: Vector3i in parent:
		for axis in 3:
			var other := cell
			other[axis] += 1
			if parent.has(other):
				var ra: Vector3i = _find(parent, cell)
				var rb: Vector3i = _find(parent, other)
				if ra != rb:
					parent[ra] = rb
	var roots := {}
	for cell: Vector3i in parent:
		roots[_find(parent, cell)] = true
	return roots.size() <= 1


func _expected_for_sector(graph: WalkableGraph, cell: Vector3i, region_edges: Dictionary, boundary: Dictionary) -> Array[WalkableGraph.Edge]:
	var region := WalkableGraph.region_of(cell)
	var result: Array[WalkableGraph.Edge] = []
	var lists: Array = [region_edges[region] if region_edges.has(region) else graph.edges_in_region(region)]
	for axis in 3:
		var unit := Vector3i.ZERO
		unit[axis] = 1
		for key in [[region, axis], [region - unit, axis]]:
			lists.append(boundary[key] if boundary.has(key) else graph.boundary_edges(key[0], axis))
	for list: Array[WalkableGraph.Edge] in lists:
		for edge in list:
			if (edge.a == cell or edge.b == cell) and not _contains(result, edge):
				result.append(edge)
	return result


func _compare(a: Array[WalkableGraph.Edge], b: Array[WalkableGraph.Edge], bad: Dictionary) -> void:
	if a.size() != b.size():
		bad.fresh += 1
		return
	for i in a.size():
		if not a[i].equals(b[i]):
			bad.fresh += 1
			return


static func _same_edges(a: Array[WalkableGraph.Edge], b: Array[WalkableGraph.Edge]) -> bool:
	if a.size() != b.size():
		return false
	for edge in a:
		if not _contains(b, edge):
			return false
	return true


static func _contains(list: Array[WalkableGraph.Edge], edge: WalkableGraph.Edge) -> bool:
	for other in list:
		if other.equals(edge):
			return true
	return false


static func _solid(graph: WalkableGraph, cell: Vector3i) -> bool:
	return graph.skeleton.sector_type(graph.world_seed, cell) == Skeleton.SectorType.SOLID


static func _find(parent: Dictionary, i: Variant) -> Variant:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _index(local: Vector3i) -> int:
	return (local.x * _n + local.y) * _n + local.z


func _cell(i: int) -> Vector3i:
	return Vector3i(i / (_n * _n), (i / _n) % _n, i % _n)


static func _kind_list(kinds: PackedInt32Array, total: int) -> String:
	var parts := PackedStringArray()
	for k in kinds.size():
		parts.append("%s %.1f %%" % [WalkableGraph.EDGE_KIND_NAMES[k], 100.0 * kinds[k] / maxi(total, 1)])
	return ", ".join(parts)


static func _random(seed_value: int, axis: int) -> int:
	return Hash.hash3_u(seed_value, Vector3i(axis, 0, 0), SALT_TEST_SAMPLE) % (2 * RANGE + 1) - RANGE


func _random_in(seed_value: int, i: int, axis: int) -> int:
	return Hash.hash3_u(seed_value, Vector3i(i, axis, 1), SALT_TEST_SAMPLE) % _n


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
