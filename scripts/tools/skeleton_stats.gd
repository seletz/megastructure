extends SceneTree
## Structure statistics of the sector grammar. Samples REGIONS_PER_SEED
## random 5x5x5 sector regions for each of the seeds 0..SEEDS-1 and reports:
##     mean vertical shaft run length (whole runs, followed past the region)
##     connected non-solid components per region (6-connectivity union-find)
##     sector type fractions
##     cavity clusters per region (6-connected cavity sectors)
##     mean stratum run length along x, z and y inside the region
## Fails unless shafts run at least MIN_SHAFT_RUN sectors on average and
## solid mass splits a region into at least MIN_COMPONENTS components on
## average. Run headless with `mise run skeleton-stats`.

const SEEDS := 5
const REGIONS_PER_SEED := 20
const SIDE := 5
## Region origins lie in -REGION_SPREAD..REGION_SPREAD - 1 on each axis.
const REGION_SPREAD := 4096
## Longest shaft run followed outside the region, in sectors.
const MAX_RUN := 512
## Salt for picking the region origins; outside the grammar's salt range.
const SALT_REGION := 901
const MIN_SHAFT_RUN := 3.0
const MIN_COMPONENTS := 2.0

var _failures := 0


func _init() -> void:
	var stats := measure(Skeleton.new())
	print_stats(stats)
	_expect(stats.shaft_run >= MIN_SHAFT_RUN,
		"mean vertical shaft run %.2f sectors (at least %.1f)" % [stats.shaft_run, MIN_SHAFT_RUN])
	_expect(stats.components >= MIN_COMPONENTS,
		"mean non-solid components per 5^3 region %.2f (at least %.1f)" % [stats.components, MIN_COMPONENTS])
	print("skeleton stats: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


## Every statistic over all sampled regions of all seeds.
static func measure(skeleton: Skeleton) -> Dictionary:
	var type_count := Skeleton.TYPE_NAMES.size()
	var type_totals := PackedInt32Array()
	type_totals.resize(type_count)
	var run_sum := 0
	var run_count := 0
	var component_sum := 0
	var single_region := 0
	var cavity_cluster_sum := 0
	var cavity_cluster_cells := 0
	var stratum_runs := [0, 0, 0, 0, 0, 0]
	for world_seed in SEEDS:
		for r in REGIONS_PER_SEED:
			var origin := _region_origin(world_seed, r)
			var types := PackedByteArray()
			types.resize(SIDE * SIDE * SIDE)
			for x in SIDE:
				for y in SIDE:
					for z in SIDE:
						var type := skeleton.sector_type(world_seed, origin + Vector3i(x, y, z))
						types[_index(x, y, z)] = type
						type_totals[type] += 1
			var runs := _shaft_runs(skeleton, world_seed, origin, types)
			run_sum += runs[0]
			run_count += runs[1]
			var components := _components(types, func(t: int) -> bool: return t != Skeleton.SectorType.SOLID)
			component_sum += components
			if components < 2:
				single_region += 1
			var clusters := _components(types, func(t: int) -> bool: return t == Skeleton.SectorType.CAVITY)
			cavity_cluster_sum += clusters
			cavity_cluster_cells += types.count(Skeleton.SectorType.CAVITY)
			for axis in 3:
				var axis_runs := _runs_in_region(types, Skeleton.SectorType.STRATUM, axis)
				stratum_runs[axis * 2] += axis_runs[0]
				stratum_runs[axis * 2 + 1] += axis_runs[1]
	var regions := SEEDS * REGIONS_PER_SEED
	var cells := regions * SIDE * SIDE * SIDE
	var fractions := PackedFloat32Array()
	for count in type_totals:
		fractions.append(float(count) / cells)
	var stratum_mean := PackedFloat32Array()
	for axis in 3:
		stratum_mean.append(float(stratum_runs[axis * 2]) / maxi(stratum_runs[axis * 2 + 1], 1))
	return {
		"regions": regions,
		"shaft_run": float(run_sum) / maxi(run_count, 1),
		"shaft_runs": run_count,
		"components": float(component_sum) / regions,
		"single_component_regions": single_region,
		"fractions": fractions,
		"cavity_clusters": float(cavity_cluster_sum) / regions,
		"cavity_cluster_size": float(cavity_cluster_cells) / maxi(cavity_cluster_sum, 1),
		"stratum_run": stratum_mean,
	}


static func print_stats(stats: Dictionary) -> void:
	print("skeleton stats: %d random %d^3 regions, seeds 0..%d" % [stats.regions, SIDE, SEEDS - 1])
	var fractions: PackedFloat32Array = stats.fractions
	var parts := PackedStringArray()
	for type in fractions.size():
		parts.append("%s %.1f %%" % [Skeleton.TYPE_NAMES[type], fractions[type] * 100.0])
	print("  types               %s" % ", ".join(parts))
	print("  shaft run           %.2f sectors (%d runs)" % [stats.shaft_run, stats.shaft_runs])
	print("  components/region   %.2f non-solid (%d regions with one)" % [stats.components, stats.single_component_regions])
	print("  cavity clusters     %.2f per region, %.1f sectors each" % [stats.cavity_clusters, stats.cavity_cluster_size])
	var stratum: PackedFloat32Array = stats.stratum_run
	print("  stratum run         x %.2f, z %.2f, y %.2f sectors (inside the region)" % [stratum[0], stratum[2], stratum[1]])


static func _region_origin(world_seed: int, region: int) -> Vector3i:
	var axis := func(a: int) -> int:
		return Hash.hash3_u(world_seed, Vector3i(region, a, 0), SALT_REGION) % (2 * REGION_SPREAD) - REGION_SPREAD
	return Vector3i(axis.call(0), axis.call(1), axis.call(2))


static func _index(x: int, y: int, z: int) -> int:
	return (x * SIDE + y) * SIDE + z


## [sum of lengths, number of runs] of the vertical shaft runs that touch the
## region, each followed up and down past the region to its real length.
static func _shaft_runs(skeleton: Skeleton, world_seed: int, origin: Vector3i, types: PackedByteArray) -> PackedInt32Array:
	var shaft := Skeleton.SectorType.SHAFT
	var result := PackedInt32Array([0, 0])
	for x in SIDE:
		for z in SIDE:
			var y := 0
			while y < SIDE:
				if types[_index(x, y, z)] != shaft:
					y += 1
					continue
				var top := y
				while top + 1 < SIDE and types[_index(x, top + 1, z)] == shaft:
					top += 1
				var length := top - y + 1
				var column := origin + Vector3i(x, 0, z)
				if y == 0:
					var below := origin.y - 1
					while length < MAX_RUN and skeleton.sector_type(world_seed, Vector3i(column.x, below, column.z)) == shaft:
						length += 1
						below -= 1
				if top == SIDE - 1:
					var above := origin.y + SIDE
					while length < MAX_RUN and skeleton.sector_type(world_seed, Vector3i(column.x, above, column.z)) == shaft:
						length += 1
						above += 1
				result[0] += length
				result[1] += 1
				y = top + 1
	return result


## Number of 6-connected components of the cells whose type passes `member`.
static func _components(types: PackedByteArray, member: Callable) -> int:
	var parent := PackedInt32Array()
	parent.resize(types.size())
	for i in types.size():
		parent[i] = i if member.call(types[i]) else -1
	for x in SIDE:
		for y in SIDE:
			for z in SIDE:
				var i := _index(x, y, z)
				if parent[i] < 0:
					continue
				if x + 1 < SIDE and parent[_index(x + 1, y, z)] >= 0:
					_union(parent, i, _index(x + 1, y, z))
				if y + 1 < SIDE and parent[_index(x, y + 1, z)] >= 0:
					_union(parent, i, _index(x, y + 1, z))
				if z + 1 < SIDE and parent[_index(x, y, z + 1)] >= 0:
					_union(parent, i, _index(x, y, z + 1))
	var roots := 0
	for i in parent.size():
		if parent[i] == i:
			roots += 1
	return roots


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var root_a := _find(parent, a)
	var root_b := _find(parent, b)
	if root_a != root_b:
		parent[maxi(root_a, root_b)] = mini(root_a, root_b)


## [sum of lengths, number of runs] of maximal runs of `type` along `axis`
## (0 x, 1 y, 2 z), clipped to the region.
static func _runs_in_region(types: PackedByteArray, type: int, axis: int) -> PackedInt32Array:
	var result := PackedInt32Array([0, 0])
	for a in SIDE:
		for b in SIDE:
			var length := 0
			for c in SIDE + 1:
				var inside := false
				if c < SIDE:
					var cell := [a, b, c]
					match axis:
						0: cell = [c, a, b]
						1: cell = [a, c, b]
					inside = types[_index(cell[0], cell[1], cell[2])] == type
				if inside:
					length += 1
				elif length > 0:
					result[0] += length
					result[1] += 1
					length = 0
	return result


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)
