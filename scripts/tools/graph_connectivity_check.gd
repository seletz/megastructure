extends SceneTree
## Checks the edges of `WalkableGraph` for seeds 0..9 over two 15^3 samples
## of sectors per seed (5^3 regions): one at a hashed offset, one centred on
## a chasm wall.
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
##   - every region-aligned window of 1^3, 2^3 and 3^3 regions (3^3, 6^3
##     and 9^3 sectors) must have exactly one; the task fails otherwise;
##   - every 5^3 window at every offset is counted and reported, next to the
##     count a graph with every open-open adjacency and no tunnels would
##     reach. Windows that cut a region cannot be guaranteed one component
##     (docs/decisions/0017).
## Also reports the fraction of tunnel edges, the tunnels with a chasm or
## cavity end, the boundary faces left without an edge, the edge kinds and
## the mean vertical edge run (stacked stair or ladder edges in one column).
##
## Every check runs for each graph variant in VARIANTS (boundary scheme and
## tunnel weights, docs/decisions/0017), and a table compares them.
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
## Sample placements per seed: at a hashed offset, and centred on the lower
## x wall of the first chasm along +x (chasms are too rare for the first).
const SAMPLES: Array[String] = ["random", "chasm"]
## Graph variants measured, the default first: [name, boundary scheme,
## void_wall_tunnels_last].
const VARIANTS: Array = [
	["per_face", WalkableGraph.BoundaryScheme.PER_FACE, false],
	["per_region_pair", WalkableGraph.BoundaryScheme.PER_REGION_PAIR, false],
	["skip_solid_faces", WalkableGraph.BoundaryScheme.SKIP_SOLID_FACES, false],
	["void_walls_last", WalkableGraph.BoundaryScheme.PER_FACE, true],
	["region_pair_void_walls_last", WalkableGraph.BoundaryScheme.PER_REGION_PAIR, true],
]
## With `--quick` (the `check` tier): only the default variant, the first
## QUICK_SEEDS seeds, and strict 5^3 windows at every QUICK_STRIDE-th offset.
const QUICK_SEEDS := 3
const QUICK_STRIDE := 2

var _failures := 0
var _n := 0
## Names of the variants to run, from `--variants=a,b` after `--`; all when empty.
var _only := PackedStringArray()
var _quick := false
var _seeds: Array[int] = SEEDS
var _stride := 1


## Remembers sector types, as regions read their neighbours' face layers again
## and again. Each graph gets its own, so the fresh graph shares nothing.
class CachingSkeleton:
	extends Skeleton
	var _types := {}

	func sector_type(seed_value: int, cell: Vector3i) -> Skeleton.SectorType:
		var type: int = _types.get(cell, -1)
		if type < 0:
			type = super.sector_type(seed_value, cell)
			_types[cell] = type
		return type as Skeleton.SectorType
var _types := PackedInt32Array()
## For every sample sector, the sample indices it has an edge to.
var _neighbours: Array[PackedInt32Array] = []
## For every sample sector, its face-adjacent open sectors when it is open:
## the edges a graph without tunnels could have at most.
var _open_neighbours: Array[PackedInt32Array] = []


func _init() -> void:
	_n = SAMPLE_REGIONS * WalkableGraph.REGION_SECTORS
	var defaults := WalkableGraph.new(0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variants="):
			_only = arg.trim_prefix("--variants=").split(",", false)
		if arg == "--quick":
			_quick = true
			_seeds = SEEDS.slice(0, QUICK_SEEDS)
			_stride = QUICK_STRIDE
	var summaries := PackedStringArray()
	var open_ok := 0
	var strict := 0
	for v in VARIANTS.size():
		var variant: Array = VARIANTS[v]
		var name: String = variant[0]
		var is_default: bool = variant[1] == defaults.boundary_scheme and variant[2] == defaults.void_wall_tunnels_last
		if not _only.is_empty() and not _only.has(name):
			continue
		if _quick and not is_default:
			continue
		var start := Time.get_ticks_msec()
		for sample in SAMPLES:
			print("variant %s%s, %s samples:" % [name, " (default)" if is_default else "", sample])
			var totals := {
				"edges": 0, "tunnel": 0, "boundary_tunnel": 0, "void_wall": 0, "boundary_void_wall": 0, "chasm": 0, "cavity": 0, "strict": 0, "strict_ok": 0, "open_ok": 0,
				"runs": 0, "run_sectors": 0, "windows": 0, "split": 0, "skipped": 0, "faces": 0,
			}
			var bad := {"shape": 0, "kind": 0, "portal": 0, "fresh": 0, "tunnel": 0, "sector": 0}
			var kinds := PackedInt32Array()
			kinds.resize(WalkableGraph.EDGE_KIND_NAMES.size())
			var random := sample == "random"
			for seed_value in _seeds:
				var graph := WalkableGraph.new(seed_value, CachingSkeleton.new(), variant[1], variant[2])
				var fresh := WalkableGraph.new(seed_value, CachingSkeleton.new(), variant[1], variant[2])
				var base := _random_base(seed_value) if random else _chasm_base(graph)
				_check_seed(graph, fresh, "%s %s" % [name, sample], base, totals, bad, kinds, random, random and open_ok == 0)
			if random and open_ok == 0:
				open_ok = totals.open_ok
				strict = totals.strict
			var label := "%s, %s:" % [name, sample]
			_expect(bad.shape == 0, "%s %d edges join face-adjacent sectors in order, %d do not" % [label, totals.edges, bad.shape])
			_expect(bad.kind == 0 and bad.portal == 0, "%s edge kinds match the sector types and portals lie on the face, %d wrong kinds, %d wrong portals" % [label, bad.kind, bad.portal])
			_expect(bad.fresh == 0, "%s a fresh graph computes the same region and boundary edges for all %d regions of every seed, %d differ" % [label, SAMPLE_REGIONS ** 3, bad.fresh])
			_expect(bad.tunnel == 0, "%s regions open-connected without solid terminals have no tunnels, %d do" % [label, bad.tunnel])
			_expect(bad.sector == 0, "%s edges_for_sector matches region and boundary edges for %d sectors per seed, %d differ" % [label, SECTOR_SAMPLES, bad.sector])
			_expect(totals.split == 0, "%s %d region-aligned 3^3, 6^3 and 9^3 windows have one non-solid component, %d have more" % [label, totals.windows, totals.split])
			var tunnel_pct: float = 100.0 * totals.tunnel / maxi(totals.edges, 1)
			var void_pct: float = 100.0 * totals.void_wall / maxi(totals.edges, 1)
			var run := float(totals.run_sectors) / maxi(totals.runs, 1)
			print("  %d edges, %.1f %% tunnels (%s)" % [totals.edges, tunnel_pct, _kind_list(kinds, totals.edges)])
			print("  tunnels with a chasm or cavity end: %d, %.1f %% of edges, %.1f %% of tunnels (chasm %d, cavity %d)" % [totals.void_wall, void_pct, 100.0 * totals.void_wall / maxi(totals.tunnel, 1), totals.chasm, totals.cavity])
			print("  on boundary faces: %d tunnels, %d with a chasm or cavity end" % [totals.boundary_tunnel, totals.boundary_void_wall])
			print("  boundary faces without an edge: %d of %d (%.1f %%)" % [totals.skipped, totals.faces, 100.0 * totals.skipped / maxi(totals.faces, 1)])
			print("  mean vertical edge run %.2f sectors over %d runs" % [run, totals.runs])
			var strict_text := "-"
			if random:
				strict_text = "%.1f %%" % [100.0 * totals.strict_ok / maxi(totals.strict, 1)]
				print("  strict 5^3 windows with one component: %d of %d (%s)" % [totals.strict_ok, totals.strict, strict_text])
			summaries.append("  %-27s %-6s %6d edges  tunnels %5.1f %%  chasm %4d  cavity %4d  (%4.1f %%)  aligned split %d of %d  vertical run %.2f  strict 5^3 %s" % [
				name + ("*" if is_default else ""), sample, totals.edges, tunnel_pct, totals.chasm, totals.cavity, void_pct,
				totals.split, totals.windows, run, strict_text,
			])
		print("  %.1f s" % [(Time.get_ticks_msec() - start) / 1000.0])
	print("all variants (* default; tunnel shares of all edges; chasm and cavity count tunnels with such an end):")
	for line in summaries:
		print(line)
	print("  strict 5^3 windows with every open-open adjacency as an edge and no tunnels: %d of %d (%.1f %%)" % [open_ok, strict, 100.0 * open_ok / maxi(strict, 1)])
	print("graph connectivity check: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


## Checks one seed of one variant over the sample at region `base` and adds
## its counts to `totals`, `bad` and `kinds`. `with_strict` counts the strict
## 5^3 windows; `with_open` also the windows every open-open adjacency joins,
## which does not depend on the variant.
func _check_seed(graph: WalkableGraph, fresh: WalkableGraph, name: String, base: Vector3i, totals: Dictionary, bad: Dictionary, kinds: PackedInt32Array, with_strict: bool, with_open: bool) -> void:
	var seed_value := graph.world_seed
	var r := WalkableGraph.REGION_SECTORS
	var origin := base * r

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
	if with_open:
		for i in _types.size():
			var local := _cell(i)
			for axis in 3:
				if local[axis] + 1 >= _n:
					continue
				var step := [_n * _n, _n, 1][axis] as int
				if _types[i] != Skeleton.SectorType.SOLID and _types[i + step] != Skeleton.SectorType.SOLID:
					_open_neighbours[i].append(i + step)
					_open_neighbours[i + step].append(i)

	var edges := 0
	var tunnels := 0
	var void_walls := 0
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
					_compare(faces, fresh.boundary_edges(region, axis), bad)
					if Vector3i(rx, ry, rz)[axis] + 1 < SAMPLE_REGIONS:
						all.append_array(faces)
						totals.faces += 1
						if not graph.boundary_face_kept(region, axis):
							totals.skipped += 1
				for e in all.size():
					var edge := all[e]
					var on_boundary := e >= list.size()
					edges += 1
					kinds[edge.kind] += 1
					if edge.kind == WalkableGraph.EdgeKind.TUNNEL:
						tunnels += 1
						totals.boundary_tunnel += int(on_boundary)
						var type_a := graph.skeleton.sector_type(seed_value, edge.a)
						var type_b := graph.skeleton.sector_type(seed_value, edge.b)
						if WalkableGraph.is_void_wall(type_a) or WalkableGraph.is_void_wall(type_b):
							void_walls += 1
							totals.boundary_void_wall += int(on_boundary)
							if type_a == Skeleton.SectorType.CHASM or type_b == Skeleton.SectorType.CHASM:
								totals.chasm += 1
							else:
								totals.cavity += 1
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

	var split := 0
	for size in [1, 2, 3]:
		var width: int = size * r
		for x in range(0, _n - width + 1, r):
			for y in range(0, _n - width + 1, r):
				for z in range(0, _n - width + 1, r):
					totals.windows += 1
					if _components(Vector3i(x, y, z), width, _neighbours) > 1:
						split += 1

	var strict := 0
	var strict_ok := 0
	var max_components := 0
	if with_strict:
		for x in range(0, _n - WINDOW + 1, _stride):
			for y in range(0, _n - WINDOW + 1, _stride):
				for z in range(0, _n - WINDOW + 1, _stride):
					var components := _components(Vector3i(x, y, z), WINDOW, _neighbours)
					strict += 1
					if components <= 1:
						strict_ok += 1
					if with_open and _components(Vector3i(x, y, z), WINDOW, _open_neighbours) <= 1:
						totals.open_ok += 1
					max_components = maxi(max_components, components)
	var strict_text := "strict %d^3 windows with one component %d of %d, at most %d components; " % [WINDOW, strict_ok, strict, max_components] if with_strict else ""
	print("  info  %s seed %d: %.1f %% tunnel edges, %d with a chasm or cavity end; %d split region-aligned windows; %smean vertical run %.2f sectors (%d runs)" % [name, seed_value, 100.0 * tunnels / maxi(edges, 1), void_walls, split, strict_text, float(run_sectors) / maxi(runs, 1), runs])

	totals.edges += edges
	totals.tunnel += tunnels
	totals.void_wall += void_walls
	totals.split += split
	totals.strict += strict
	totals.strict_ok += strict_ok
	totals.runs += runs
	totals.run_sectors += run_sectors


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


static func _random_base(seed_value: int) -> Vector3i:
	return Vector3i(_random(seed_value, 0), _random(seed_value, 1), _random(seed_value, 2))


## The sample region whose centre sits on the lower x wall of the first chasm
## met stepping along +x at z 0. Steps of chasm_width sectors and heights
## chasm_min_height apart cannot miss one.
func _chasm_base(graph: WalkableGraph) -> Vector3i:
	var grammar := graph.skeleton.grammar
	var step := maxi(grammar.chasm_width, 1)
	var rise := maxi(grammar.chasm_min_height, 1)
	var half := _n / 2
	for i in 100000:
		for y in range(0, maxi(grammar.chasm_band_height, 1), rise):
			var cell := Vector3i(i * step, y, 0)
			if graph.skeleton.sector_type(graph.world_seed, cell) != Skeleton.SectorType.CHASM:
				continue
			while graph.skeleton.sector_type(graph.world_seed, cell - Vector3i(1, 0, 0)) == Skeleton.SectorType.CHASM:
				cell.x -= 1
			return WalkableGraph.region_of(cell - Vector3i(half, half, half))
	return _random_base(graph.world_seed)


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
