class_name GraphLines
extends Node3D
## Debug lines of the walkable graph: every edge of the regions overlapping a
## box of sectors, drawn from the node of sector `a` to the portal and on to
## the node of sector `b`, so a path reads node -> portal -> node.
##
## One MeshInstance3D per EdgeKind holds an ArrayMesh with one PRIMITIVE_LINES
## surface: the edge segments and a short cross at every portal, all in the
## kind's colour. A further mesh holds grey crosses at the interior nodes.
## Solid sectors have no interior node, so tunnels bend at the sector centre;
## those crosses go into the tunnel mesh. Every material is unshaded,
## translucent at full alpha, without depth write and with a render priority
## above the viewer's boxes, so the lines are blended last and stay crisp.
##
## `rebuild` is called by the owner (the SkeletonViewer refresh); the node
## never redraws on its own. Edges per region, boundary edges per face and
## node positions are cached, so a rebuild after the box moves only computes
## the regions it newly overlaps, and the graph reads sector types through a
## CachedSkeleton, since edges_in_region asks for the boundary layers of its
## neighbours again and again; `invalidate` clears every cache after a seed or
## grammar change. The per-kind toggles only hide a mesh; `show_graph` and
## `marker_size` emit `changed` so the owner refreshes.

signal changed

## Line colours per WalkableGraph.EdgeKind.
const KIND_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.9, 0.2),
	Color(1.0, 0.9, 0.2),
	Color(0.2, 0.95, 1.0),
	Color(0.35, 1.0, 0.35),
	Color(1.0, 0.25, 1.0),
]
const NODE_COLOR := Color(0.75, 0.75, 0.75)
## Above the viewer's box priorities (0 to 2).
const RENDER_PRIORITY := 10

## The type cache is dropped when it grows past this many sectors.
const MAX_CACHED_TYPES := 200000

const _UNITS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]

@export var show_graph := true:
	set(value):
		show_graph = value
		visible = value
		changed.emit()
## Edge of a marker cross in metres; 0 hides the markers.
@export_range(0.0, 12.0, 0.5) var marker_size := 3.0:
	set(value):
		marker_size = maxf(value, 0.0)
		changed.emit()

## Edges of each kind drawn by the last rebuild.
var counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
## Duration of the last rebuild in microseconds.
var last_rebuild_usec := 0

var _kind_visible: Array[bool] = [true, true, true, true, true, true]
var _kind_instances: Array[MeshInstance3D] = []
var _node_instance: MeshInstance3D
var _graph: WalkableGraph
## The viewer's skeleton the cached one reads through.
var _skeleton: Skeleton
## Region -> Array[Edge] from edges_in_region.
var _region_cache := {}
## Vector4i(region, axis) -> Array[Edge] from boundary_edges.
var _boundary_cache := {}
## Sector -> [position, is_solid].
var _node_cache := {}


## A Skeleton that remembers sector types per cell for one seed.
class CachedSkeleton:
	extends Skeleton
	var _types := {}

	func sector_type(seed: int, cell: Vector3i) -> Skeleton.SectorType:
		var type: int = _types.get(cell, -1)
		if type < 0:
			if _types.size() >= MAX_CACHED_TYPES:
				_types.clear()
			type = super.sector_type(seed, cell)
			_types[cell] = type
		return type as Skeleton.SectorType


func _ready() -> void:
	for kind in WalkableGraph.EdgeKind.size():
		_kind_instances.append(_add_instance(WalkableGraph.edge_kind_name(kind).capitalize(), KIND_COLORS[kind]))
		_kind_instances[kind].visible = _kind_visible[kind]
	_node_instance = _add_instance("Nodes", NODE_COLOR)
	visible = show_graph


static func kind_param_name(kind: int) -> String:
	return "show_" + WalkableGraph.edge_kind_name(kind)


func is_kind_visible(kind: int) -> bool:
	return _kind_visible[kind]


## Shows or hides the lines and portal markers of one edge kind without a rebuild.
func set_kind_visible(kind: int, value: bool) -> void:
	_kind_visible[kind] = value
	if kind < _kind_instances.size():
		_kind_instances[kind].visible = value


## Forgets every cached edge and node (after a seed or grammar change).
func invalidate() -> void:
	_graph = null
	_skeleton = null
	_region_cache.clear()
	_boundary_cache.clear()
	_node_cache.clear()


## Redraws the edges of every region overlapping min_cell..max_cell (bounds
## inclusive) for `skeleton` and `world_seed`.
func rebuild(skeleton: Skeleton, world_seed: int, min_cell: Vector3i, max_cell: Vector3i) -> void:
	var start := Time.get_ticks_usec()
	counts = PackedInt32Array([0, 0, 0, 0, 0, 0])
	if not show_graph:
		for instance in _kind_instances:
			(instance.mesh as ArrayMesh).clear_surfaces()
		(_node_instance.mesh as ArrayMesh).clear_surfaces()
		last_rebuild_usec = Time.get_ticks_usec() - start
		return
	if _graph == null or _graph.world_seed != world_seed or _skeleton != skeleton:
		invalidate()
		_skeleton = skeleton
		_graph = WalkableGraph.new(world_seed, CachedSkeleton.new(skeleton.grammar))

	var region_min := WalkableGraph.region_of(min_cell)
	var region_max := WalkableGraph.region_of(max_cell)
	var regions := {}
	var boundaries := {}
	var nodes := {}
	var edges: Array[WalkableGraph.Edge] = []
	# Region edges of every overlapped region, and the boundary edges of every
	# face with an overlapped region on either side (keyed on the lower one).
	for rx in range(region_min.x - 1, region_max.x + 1):
		for ry in range(region_min.y - 1, region_max.y + 1):
			for rz in range(region_min.z - 1, region_max.z + 1):
				var region := Vector3i(rx, ry, rz)
				var inside := rx >= region_min.x and ry >= region_min.y and rz >= region_min.z
				if inside:
					var region_edges: Array = _region_cache.get(region, [])
					if not _region_cache.has(region):
						region_edges = _graph.edges_in_region(region)
					regions[region] = region_edges
					edges.append_array(region_edges)
				for axis in 3:
					var upper := region + _UNITS[axis]
					if not inside and not _in_box(upper, region_min, region_max):
						continue
					var key := Vector4i(rx, ry, rz, axis)
					var face_edges: Array = _boundary_cache.get(key, [])
					if not _boundary_cache.has(key):
						face_edges = _graph.boundary_edges(region, axis)
					boundaries[key] = face_edges
					edges.append_array(face_edges)
	_region_cache = regions
	_boundary_cache = boundaries

	var lines: Array[PackedVector3Array] = []
	for kind in WalkableGraph.EdgeKind.size():
		lines.append(PackedVector3Array())
	var node_lines := PackedVector3Array()
	var half := marker_size * 0.5
	for edge in edges:
		var kind := edge.kind as int
		counts[kind] += 1
		var portal := edge.portal.position
		for cell in [edge.a, edge.b]:
			var node: Array = _node_cache.get(cell, [])
			if not _node_cache.has(cell):
				node = _node_point(cell)
			if not nodes.has(cell):
				nodes[cell] = node
				if half > 0.0:
					_cross(lines[WalkableGraph.EdgeKind.TUNNEL] if node[1] else node_lines, node[0], half)
			lines[kind].append(node[0])
			lines[kind].append(portal)
		if half > 0.0:
			_cross(lines[kind], portal, half)
	_node_cache = nodes

	for kind in WalkableGraph.EdgeKind.size():
		_set_lines(_kind_instances[kind], lines[kind])
	_set_lines(_node_instance, node_lines)
	last_rebuild_usec = Time.get_ticks_usec() - start


## [position, is_solid]: the interior node, or the centre of a solid sector.
func _node_point(cell: Vector3i) -> Array:
	var node := _graph.interior_node(cell)
	if node != null:
		return [node.position, false]
	var n := _graph.cells_per_sector()
	return [(Vector3(cell) * n + Vector3.ONE * floorf(n * 0.5)) * WalkableGraph.CELL_SIZE, true]


func _add_instance(instance_name: String, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.mesh = ArrayMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = RENDER_PRIORITY
	instance.material_override = material
	add_child(instance)
	return instance


static func _set_lines(instance: MeshInstance3D, vertices: PackedVector3Array) -> void:
	var mesh := instance.mesh as ArrayMesh
	mesh.clear_surfaces()
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)


## Three axis-aligned segments of length 2 * half through `point`.
static func _cross(vertices: PackedVector3Array, point: Vector3, half: float) -> void:
	for axis in 3:
		var offset := Vector3.ZERO
		offset[axis] = half
		vertices.append(point - offset)
		vertices.append(point + offset)


static func _in_box(cell: Vector3i, lo: Vector3i, hi: Vector3i) -> bool:
	return (
		cell.x >= lo.x and cell.y >= lo.y and cell.z >= lo.z
		and cell.x <= hi.x and cell.y <= hi.y and cell.z <= hi.z
	)
