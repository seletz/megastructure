class_name SectorMultiMesh
extends Node3D
## One solved sector placed as one `MultiMeshInstance3D` per tile mesh and
## one `StaticBody3D` with a merged `ConcavePolygonShape3D`, from plain data a
## worker thread builds.
##
##     var library := TileLibrary.build(load("res://resources/tilesets/placeholder.tres"))
##     var faces := SectorMultiMesh.prototype_faces(library)        # main thread, once
##     var meshes := SectorMultiMesh.build_meshes(library)          # main thread, once
##     # on any thread:
##     var placement := SectorMultiMesh.build(library, faces, result.cells)
##     # on the main thread:
##     var node := SectorMultiMesh.new()
##     add_child(node)
##     node.place(meshes, Vector3i(-1, 1, -1), placement)
##
## `build` touches only its arguments and returns a `Dictionary`:
##
## - `buffers` (Array of PackedFloat32Array, by prototype index): the
##   `MultiMesh.buffer` of that prototype's instances, 12 floats each
##   (`FLOATS_PER_INSTANCE`); empty for a prototype with no mesh or no cell.
## - `faces` (PackedVector3Array): the collision triangles of every tile.
## - `cells_per_sector` (int), `instances` (int), `triangles` (int),
##   `culled_triangles` (int) and `build_usec` (int).
##
## Frame: every transform and every face is in sector-local metres, cell
## (i, j, k) the box from `(i, j, k) * 2` to two metres further with the tile
## mesh's origin at its centre, the frame `SectorGridMap` uses. The sector
## offset, `sector * 48` m, is not baked in: `place` puts this node at the
## sector's corner, so buffers and faces stay small numbers whatever the
## sector and one sector's data could be placed anywhere.
##
## Buffer layout (`TRANSFORM_3D`, no colour, no custom data), per instance
## the three basis rows, each followed by that row's origin component:
##
##     x.x  y.x  z.x  origin.x   x.y  y.y  z.y  origin.y   x.z  y.z  z.z  origin.z
##
## where x, y, z are the basis columns. The class reference does not document
## it; `mise run multimesh-check` pins it by hand for a known tile and cell,
## and `mise run multimesh-draw-calls` compares it with what the OpenGL
## renderer writes for `set_instance_transform`. A tile turned r quarter
## turns uses `Basis(Vector3.UP, r * PI / 2)` (+x goes to -z), taken from the
## exact table `YAW_BASES` rather than sin and cos, so the floats are exactly
## 0 and ±1.
##
## Collision: `prototype_faces` reads each prototype mesh's `get_faces()` once
## and sorts its triangles into the six cell faces they lie on (all three
## corners on that face's plane) and the rest. `build` transforms each tile's
## triangles by its turn and cell centre. A triangle on a cell face whose
## tile and neighbour across that face are both the tileset's solid tile is
## dropped: two solid boxes hide it from both sides. Neighbours outside the
## sector are unknown, so border faces always stay.

## Floats per instance in `MultiMesh.buffer` with `TRANSFORM_3D`.
const FLOATS_PER_INSTANCE := 12
## Basis of 0..3 quarter turns about +y, exact.
const YAW_BASES: Array[Basis] = [
	Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)),
	Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)),
	Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)),
	Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)),
]
## Index of the interior group in a prototype's face groups; 0..5 are the
## cell faces in `TilePrototype` face order.
const INTERIOR := 6
## A corner this close to a cell face's plane lies on it, in metres.
const PLANE_EPSILON := 0.001
## Cell steps by face index, +x, -x, +y, -y, +z, -z.
const STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## Sector of the last `place`.
var sector := Vector3i.ZERO
## MultiMeshInstance3D children made by the last `place`.
var multimesh_count := 0
## Instances and collision triangles of the last `place`.
var instance_count := 0
var triangle_count := 0


## Per prototype index, seven `PackedVector3Array` triangle lists of its mesh
## in its own frame: the triangles on cell faces +x, -x, +y, -y, +z, -z, then
## the rest (`INTERIOR`). An empty Array for a prototype without a mesh.
## Reads meshes, so call it on the main thread.
static func prototype_faces(library: TileLibrary) -> Array:
	var faces := []
	var half := WalkableGraph.CELL_SIZE * 0.5
	for tile in library.tiles:
		if tile.prototype_index < faces.size():
			continue
		faces.resize(tile.prototype_index + 1)
		faces[tile.prototype_index] = []
		if tile.prototype.mesh == null:
			continue
		var all := tile.prototype.mesh.get_faces()
		var groups := []
		for group in INTERIOR + 1:
			var triangles := PackedVector3Array()
			for t in range(0, all.size() - 2, 3):
				if _face_of(all[t], all[t + 1], all[t + 2], half) == group:
					triangles.append_array([all[t], all[t + 1], all[t + 2]])
			groups.append(triangles)
		faces[tile.prototype_index] = groups
	return faces


## One mesh per prototype index, null without a mesh; with `family_colours`
## coloured copies as `SectorGridMap.build_mesh_library` makes them.
static func build_meshes(library: TileLibrary, family_colours := true) -> Array[Mesh]:
	var meshes: Array[Mesh] = []
	for tile in library.tiles:
		if tile.prototype_index < meshes.size():
			continue
		meshes.resize(tile.prototype_index + 1)
		var mesh := tile.prototype.mesh
		if mesh != null and family_colours:
			mesh = SectorGridMap.coloured_mesh(mesh, SectorGridMap.family_colour(tile.prototype.family))
		meshes[tile.prototype_index] = mesh
	return meshes


## The exact basis of `quarter_turns` about +y (wrapped modulo 4).
static func yaw_basis(quarter_turns: int) -> Basis:
	return YAW_BASES[posmod(quarter_turns, 4)]


## Sector-local transform of a tile turned `quarter_turns` in local cell `cell`.
static func cell_transform(cell: Vector3i, quarter_turns: int) -> Transform3D:
	return Transform3D(yaw_basis(quarter_turns), (Vector3(cell) + Vector3.ONE * 0.5) * WalkableGraph.CELL_SIZE)


## Writes `transform` into `buffer` at instance `instance` in the
## `MultiMesh.buffer` layout.
static func write_instance(buffer: PackedFloat32Array, instance: int, transform: Transform3D) -> void:
	var o := instance * FLOATS_PER_INSTANCE
	var b := transform.basis
	buffer[o] = b.x.x
	buffer[o + 1] = b.y.x
	buffer[o + 2] = b.z.x
	buffer[o + 3] = transform.origin.x
	buffer[o + 4] = b.x.y
	buffer[o + 5] = b.y.y
	buffer[o + 6] = b.z.y
	buffer[o + 7] = transform.origin.y
	buffer[o + 8] = b.x.z
	buffer[o + 9] = b.y.z
	buffer[o + 10] = b.z.z
	buffer[o + 11] = transform.origin.z


## Instance `instance` of `buffer` read back as a transform.
static func read_instance(buffer: PackedFloat32Array, instance: int) -> Transform3D:
	var o := instance * FLOATS_PER_INSTANCE
	return Transform3D(
		Vector3(buffer[o], buffer[o + 4], buffer[o + 8]),
		Vector3(buffer[o + 1], buffer[o + 5], buffer[o + 9]),
		Vector3(buffer[o + 2], buffer[o + 6], buffer[o + 10]),
		Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11]))


## The placement data of `cells` (n³ tile indices of `library`, cell
## `x + n * (y + n * z)`), with `faces` from `prototype_faces`. Safe on any
## thread: reads its arguments only. See the class comment for the fields.
static func build(library: TileLibrary, faces: Array, cells: PackedInt32Array) -> Dictionary:
	var started := Time.get_ticks_usec()
	var n := roundi(pow(cells.size(), 1.0 / 3.0))
	var prototype_count := faces.size()
	var solid := library.tiles[library.solid_tile].prototype_index if library.solid_tile >= 0 else -1

	# Per tile and per cell lookups in packed arrays: object property reads in
	# the cell loop cost several times more.
	var tile_prototype := PackedInt32Array()
	var tile_rotation := PackedInt32Array()
	for tile in library.tiles:
		tile_prototype.append(tile.prototype_index)
		tile_rotation.append(tile.rotation)
	var cell_prototype := PackedInt32Array()
	cell_prototype.resize(cells.size())
	var counts := PackedInt32Array()
	counts.resize(prototype_count)
	counts.fill(0)
	for i in cells.size():
		var p := tile_prototype[cells[i]]
		cell_prototype[i] = p
		if not (faces[p] as Array).is_empty():
			counts[p] += 1
	# One flat buffer, prototype after prototype, sliced at the end: a packed
	# array written through while an Array also holds it is copied per write.
	var starts := PackedInt32Array()
	starts.resize(prototype_count + 1)
	starts[0] = 0
	for p in prototype_count:
		starts[p + 1] = starts[p] + counts[p]
	var all := PackedFloat32Array()
	all.resize(starts[prototype_count] * FLOATS_PER_INSTANCE)
	counts.fill(0)
	# World face of prototype face `group` after r turns: turned[r * 6 + group].
	var turned := PackedInt32Array()
	for r in 4:
		for group in INTERIOR:
			turned.append(TileLibrary.rotate_face(group, r))
	var stride := PackedInt32Array([1, -1, n, -n, n * n, -n * n])

	var collision := PackedVector3Array()
	var instances := 0
	var culled := 0
	var i := 0
	for z in n:
		for y in n:
			for x in n:
				var p := cell_prototype[i]
				var rotation := tile_rotation[cells[i]]
				i += 1
				var groups: Array = faces[p]
				if groups.is_empty():
					continue
				var transform := cell_transform(Vector3i(x, y, z), rotation)
				write_instance(all, starts[p] + counts[p], transform)
				counts[p] += 1
				instances += 1
				for group in INTERIOR + 1:
					var triangles: PackedVector3Array = groups[group]
					if triangles.is_empty():
						continue
					if group < INTERIOR and p == solid:
						var face := turned[rotation * INTERIOR + group]
						var along := x if face < 2 else y if face < 4 else z
						var inside := along < n - 1 if face & 1 == 0 else along > 0
						if inside and cell_prototype[i - 1 + stride[face]] == solid:
							culled += triangles.size() / 3
							continue
					collision.append_array(transform * triangles)

	var buffers := []
	buffers.resize(prototype_count)
	for p in prototype_count:
		buffers[p] = all.slice(starts[p] * FLOATS_PER_INSTANCE, starts[p + 1] * FLOATS_PER_INSTANCE)
	return {
		"buffers": buffers,
		"faces": collision,
		"cells_per_sector": n,
		"instances": instances,
		"triangles": collision.size() / 3,
		"culled_triangles": culled,
		"build_usec": Time.get_ticks_usec() - started,
	}


## The cell face (0..5) all three corners lie on, or `INTERIOR`.
static func _face_of(a: Vector3, b: Vector3, c: Vector3, half: float) -> int:
	for face in INTERIOR:
		var axis := face >> 1
		var plane := half if face & 1 == 0 else -half
		if absf(a[axis] - plane) < PLANE_EPSILON and absf(b[axis] - plane) < PLANE_EPSILON and absf(c[axis] - plane) < PLANE_EPSILON:
			return face
	return INTERIOR


## Removes the children of an earlier `place`, moves this node to the corner
## of `sector_cell` and adds one `MultiMeshInstance3D` per prototype with
## instances (mesh from `meshes`, by prototype index) and one `StaticBody3D`
## holding a `ConcavePolygonShape3D` of the faces. Main thread only. Returns
## the MultiMeshInstance3D count.
func place(meshes: Array[Mesh], sector_cell: Vector3i, placement: Dictionary) -> int:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	sector = sector_cell
	var n: int = placement.cells_per_sector
	position = SectorGridMap.sector_origin(sector_cell, n)
	var bounds := AABB(Vector3.ZERO, Vector3.ONE * n * WalkableGraph.CELL_SIZE)
	multimesh_count = 0
	var buffers: Array = placement.buffers
	for p in buffers.size():
		var buffer: PackedFloat32Array = buffers[p]
		if buffer.is_empty() or p >= meshes.size() or meshes[p] == null:
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = meshes[p]
		multimesh.instance_count = buffer.size() / FLOATS_PER_INSTANCE
		multimesh.custom_aabb = bounds
		multimesh.buffer = buffer
		var instance := MultiMeshInstance3D.new()
		instance.name = "Mesh_%d" % p
		instance.multimesh = multimesh
		add_child(instance)
		multimesh_count += 1
	instance_count = placement.instances
	triangle_count = placement.triangles
	var faces: PackedVector3Array = placement.faces
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.add_child(collision)
		add_child(body)
	return multimesh_count
